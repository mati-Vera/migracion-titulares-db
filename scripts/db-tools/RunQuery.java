import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.sql.*;
import java.util.*;

/**
 * Corredor de queries de solo lectura contra la base de desarrollo SIRCLAN,
 * reusando el túnel SSH que ya abre DBeaver (ver README.md de esta carpeta).
 *
 * node-oracledb en modo Thin (JS puro) no soporta la versión del servidor
 * Oracle de esta base (NJS-138); el JDBC Thin driver de Oracle sí, con la
 * misma lógica de negociación de protocolo que usa DBeaver por dentro. Este
 * runner es el equivalente en Java, usando el JDK ya instalado en la
 * máquina y el driver descargado en lib/ojdbc11.jar (no requiere Oracle
 * Instant Client nativo).
 *
 * Uso:
 *   java -cp lib/ojdbc11.jar;. RunQuery <archivo.sql>
 *   java -cp lib/ojdbc11.jar;. RunQuery <archivo.sql> --csv <prefijo_salida>
 *
 * Sin --csv imprime cada bloque como tabla Markdown por stdout (el formato
 * que consume EvaluadorLote.java). Con --csv escribe un CSV por bloque en
 * <prefijo_salida>_bloqueN.csv y por stdout deja solo el conteo de filas.
 *
 * La salida es UTF-8 siempre, por stdout y a archivo. Antes usaba el
 * charset default de Windows, y por eso los acentos de los campos de texto
 * libre (DS_INMUEBLE) salían como "?" en los exports (CLAUDE.md §3).
 *
 * El CSV usa ";" como separador y arranca con BOM: es lo que espera Excel
 * en español para abrirlo con doble clic sin pasar por el asistente de
 * importación. Los valores van comillados según RFC 4180, así que un
 * DS_INMUEBLE con saltos de línea incrustados queda contenido en una celda
 * en vez de partir la fila (el otro artefacto de los exports viejos).
 *
 * Lee la conexión de db-tools/.env (mismo archivo que usaba el intento con
 * Node). Cualquier statement que no empiece con SELECT o WITH se rechaza
 * antes de conectar -- guardrail del script, porque el usuario de Oracle no
 * es una cuenta de solo lectura a nivel de grants (CLAUDE.md §0).
 */
public class RunQuery {

    private static final char CSV_SEP = ';';

    public static void main(String[] args) throws Exception {
        System.setOut(new PrintStream(new FileOutputStream(FileDescriptor.out), true, StandardCharsets.UTF_8));

        if (args.length < 1) {
            System.err.println("Uso: java -cp lib/ojdbc11.jar;. RunQuery <archivo.sql> [--csv <prefijo_salida>]");
            System.exit(1);
        }

        String csvPrefix = null;
        for (int a = 1; a < args.length - 1; a++) {
            if ("--csv".equals(args[a])) csvPrefix = args[a + 1];
        }

        Map<String, String> env = readEnvFile(new File(new File(RunQuery.class.getProtectionDomain()
                .getCodeSource().getLocation().toURI()), ".env"));
        String connectString = env.get("DB_CONNECT_STRING");
        String user = env.get("DB_USER");
        String password = env.get("DB_PASSWORD");
        if (connectString == null || user == null || password == null) {
            System.err.println("Faltan DB_CONNECT_STRING / DB_USER / DB_PASSWORD en .env (ver README.md).");
            System.exit(1);
        }

        String sql = new String(Files.readAllBytes(Paths.get(args[0])), java.nio.charset.StandardCharsets.UTF_8);
        List<String> statements = splitStatements(stripLineComments(sql));
        for (String stmt : statements) {
            assertReadOnly(stmt);
        }

        String url = "jdbc:oracle:thin:@//" + connectString;
        try (Connection conn = DriverManager.getConnection(url, user, password)) {
            int i = 1;
            for (String stmt : statements) {
                System.out.println("\n--- Bloque " + i + " ---");
                try (Statement st = conn.createStatement();
                     ResultSet rs = st.executeQuery(stmt)) {
                    if (csvPrefix == null) {
                        printAsMarkdown(rs);
                    } else {
                        Path destino = Paths.get(csvPrefix + "_bloque" + i + ".csv");
                        System.out.println(writeCsv(rs, destino) + " filas -> " + destino.toAbsolutePath());
                    }
                }
                i++;
            }
        }
    }

    /**
     * Saca todo lo que sigue a "--" en cada línea, sin importar si esa línea
     * es un comentario propio o tiene código antes. No contempla "--" dentro
     * de un literal de string (no hace falta para las queries de este
     * proyecto). Necesario porque los comentarios en prosa de este repo usan
     * "--" como guion (ej. "según el informe -- el bloque 2..."), y eso
     * rompería un split por ";" que no ignore comentarios primero.
     */
    private static String stripLineComments(String sql) {
        StringBuilder out = new StringBuilder();
        for (String line : sql.split("\n")) {
            int idx = line.indexOf("--");
            out.append(idx >= 0 ? line.substring(0, idx) : line).append('\n');
        }
        return out.toString();
    }

    private static List<String> splitStatements(String sqlWithoutComments) {
        List<String> out = new ArrayList<>();
        for (String part : sqlWithoutComments.split(";")) {
            String trimmed = part.trim();
            if (!trimmed.isEmpty()) out.add(trimmed);
        }
        return out;
    }

    private static void assertReadOnly(String stmt) {
        String upper = stmt.trim().toUpperCase();
        if (!upper.startsWith("SELECT") && !upper.startsWith("WITH")) {
            throw new IllegalArgumentException("Statement rechazado (no es SELECT/WITH): "
                    + stmt.substring(0, Math.min(80, stmt.length())) + "...");
        }
    }

    private static void printAsMarkdown(ResultSet rs) throws SQLException {
        ResultSetMetaData meta = rs.getMetaData();
        int cols = meta.getColumnCount();
        StringBuilder header = new StringBuilder("|");
        StringBuilder sep = new StringBuilder("|");
        for (int c = 1; c <= cols; c++) {
            header.append(' ').append(meta.getColumnLabel(c)).append(" |");
            sep.append("---|");
        }
        System.out.println(header);
        System.out.println(sep);
        int rows = 0;
        while (rs.next()) {
            StringBuilder row = new StringBuilder("|");
            for (int c = 1; c <= cols; c++) {
                row.append(' ').append(rs.getString(c)).append(" |");
            }
            System.out.println(row);
            rows++;
        }
        if (rows == 0) System.out.println("(sin filas)");
    }

    /**
     * Escribe el ResultSet como CSV UTF-8 con BOM y devuelve la cantidad de
     * filas de datos (sin contar el encabezado), para poder chequear el
     * total contra las cifras de CLAUDE.md §3 sin abrir el archivo.
     */
    private static int writeCsv(ResultSet rs, Path destino) throws SQLException, IOException {
        if (destino.getParent() != null) Files.createDirectories(destino.getParent());
        ResultSetMetaData meta = rs.getMetaData();
        int cols = meta.getColumnCount();
        int rows = 0;
        try (BufferedWriter w = Files.newBufferedWriter(destino, StandardCharsets.UTF_8)) {
            w.write('﻿');
            for (int c = 1; c <= cols; c++) {
                if (c > 1) w.write(CSV_SEP);
                w.write(csv(meta.getColumnLabel(c)));
            }
            w.write("\r\n");
            while (rs.next()) {
                for (int c = 1; c <= cols; c++) {
                    if (c > 1) w.write(CSV_SEP);
                    w.write(csv(rs.getString(c)));
                }
                w.write("\r\n");
                rows++;
            }
        }
        return rows;
    }

    /**
     * Comillado RFC 4180. Un NULL de la base sale como celda vacía, no como
     * el literal "null" que imprime el modo Markdown: en Excel esa celda se
     * lee de un vistazo como "falta el dato".
     */
    private static String csv(String valor) {
        if (valor == null) return "";
        boolean necesitaComillas = valor.indexOf(CSV_SEP) >= 0 || valor.indexOf('"') >= 0
                || valor.indexOf('\n') >= 0 || valor.indexOf('\r') >= 0;
        if (!necesitaComillas) return valor;
        return '"' + valor.replace("\"", "\"\"") + '"';
    }

    private static Map<String, String> readEnvFile(File file) throws IOException {
        Map<String, String> env = new HashMap<>();
        if (!file.exists()) return env;
        for (String line : Files.readAllLines(file.toPath())) {
            String trimmed = line.trim();
            if (trimmed.isEmpty() || trimmed.startsWith("#")) continue;
            int eq = trimmed.indexOf('=');
            if (eq < 0) continue;
            env.put(trimmed.substring(0, eq).trim(), trimmed.substring(eq + 1).trim());
        }
        return env;
    }
}
