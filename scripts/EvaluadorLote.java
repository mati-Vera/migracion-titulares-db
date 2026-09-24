import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.*;

/**
 * Automatiza el triage de la muestra piloto (CLAUDE.md §10): lee el
 * detalle de DIG_DOC_R62 de varios documentos duplicados (exportado como
 * tabla Markdown desde la query
 * scripts/queries/muestra_detalle_persona_base.sql), agrupa por
 * NU_DOCUMENTO, corre DetectorMezclados sobre cada grupo, elige un
 * candidato dentro del cluster principal (completitud + DT_LAST_UPDATE
 * DESC NULLS LAST, ver CLAUDE.md §5) y calcula su CUIL con
 * CalculadorCuil.
 *
 * OJO — a propósito NO llama a la API de RENAPER (ValidadorPersonaApi):
 * eso queda para una corrida aparte, más chica, después de que el equipo
 * de la API confirme rate/concurrencia (CLAUDE.md §0 y §10). Esta clase
 * solo deja el trabajo de agrupamiento + cálculo hecho para que la
 * revisión manual sea de confirmar/corregir, no de armar todo desde cero.
 *
 * Uso:
 *   java EvaluadorLote <archivo_markdown_de_entrada> [archivo_salida_csv]
 *
 * Columnas esperadas en la tabla Markdown de entrada (por NOMBRE, no por
 * posición — el orden puede variar): ESTRATO, NU_DOCUMENTO, ID_FORMULARIO,
 * NM_NOMBRE, NM_APELLIDO, CD_SEXO, NU_CUIL_CUIT, NU_CUIL_CUIT_STR,
 * SCORE_COMPLETITUD, DT_LAST_UPDATE.
 */
public class EvaluadorLote {

    record Fila(
        String estrato, String nuDocumento, String idFormulario,
        String nombre, String apellido, Integer cdSexo,
        String cuilCargado, int scoreCompletitud, String dtLastUpdate
    ) {}

    record Evaluacion(
        String estrato, String nuDocumento, int cantRegistros,
        int cantPrincipal, int cantSospechosos, String idsSospechosos,
        String candidatoId, String candidatoNombre, String candidatoApellido,
        String cuilYaCargado, String cuilesCalculados, boolean revisionManual,
        String motivoRevision
    ) {}

    public static void main(String[] args) throws IOException {
        if (args.length < 1) {
            System.out.println("Uso: java EvaluadorLote <entrada.md> [salida.csv]");
            System.out.println("(ver javadoc de la clase para el formato esperado)");
            return;
        }
        Path entrada = Path.of(args[0]);
        Path salida = Path.of(args.length > 1 ? args[1] : "out/evaluacion_lote.csv");
        if (salida.getParent() != null) {
            Files.createDirectories(salida.getParent());
        }

        List<Fila> filas = leerMarkdown(entrada);
        System.out.println("Filas leídas: " + filas.size());

        Map<String, List<Fila>> porDocumento = new LinkedHashMap<>();
        for (Fila f : filas) {
            porDocumento.computeIfAbsent(f.nuDocumento(), k -> new ArrayList<>()).add(f);
        }
        System.out.println("Documentos distintos: " + porDocumento.size());

        List<Evaluacion> resultado = new ArrayList<>();
        DetectorMezclados detector = new DetectorMezclados();

        for (Map.Entry<String, List<Fila>> entry : porDocumento.entrySet()) {
            String nuDocumento = entry.getKey();
            List<Fila> grupo = entry.getValue();
            String estrato = grupo.get(0).estrato();

            List<DetectorMezclados.Persona> personas = grupo.stream()
                .map(f -> new DetectorMezclados.Persona(f.idFormulario(), f.nombre(), f.apellido()))
                .toList();
            DetectorMezclados.Grupo clusters = detector.clusterizar(personas);

            Map<String, Fila> porId = new HashMap<>();
            for (Fila f : grupo) porId.put(f.idFormulario(), f);

            Fila candidato = elegirCandidato(clusters.principal(), porId);

            String idsSospechosos = clusters.sospechosos().stream()
                .map(DetectorMezclados.Persona::idFormulario)
                .reduce((a, b) -> a + ";" + b).orElse("");

            String cuilYaCargado = buscarCuilYaCargado(grupo);
            String cuilesCalculados = "";
            List<String> motivos = new ArrayList<>();

            if (!cuilYaCargado.isEmpty()) {
                cuilesCalculados = "(usar el ya cargado: " + cuilYaCargado + ")";
            } else if (candidato != null) {
                if (candidato.cdSexo() != null) {
                    String cuil = CalculadorCuil.calcularCuil(nuDocumento, candidato.cdSexo());
                    if (cuil != null) {
                        cuilesCalculados = cuil;
                    } else {
                        motivos.add("DV=10 con sexo conocido, ni 20/27 ni 23 dieron válido");
                    }
                } else {
                    List<String> candidatos = CalculadorCuil.candidatosCuil(nuDocumento);
                    cuilesCalculados = String.join(" | ", candidatos);
                    if (candidatos.isEmpty()) {
                        motivos.add("sin CD_SEXO y ningún prefijo (20/27/23/24) dio DV válido");
                    } else {
                        motivos.add("CD_SEXO desconocido, probar candidatos contra la API en orden");
                    }
                }
            } else {
                motivos.add("no se pudo elegir candidato (grupo principal vacío)");
            }

            if (!clusters.sospechosos().isEmpty()) {
                motivos.add(clusters.sospechosos().size() + " registro(s) posiblemente mezclado(s)");
            }
            if (grupo.size() >= 11) {
                motivos.add("grupo grande (11+), candidato a colisión — revisar igual aunque no haya sospechosos");
            }

            resultado.add(new Evaluacion(
                estrato, nuDocumento, grupo.size(),
                clusters.principal().size(), clusters.sospechosos().size(), idsSospechosos,
                candidato != null ? candidato.idFormulario() : "",
                candidato != null ? candidato.nombre() : "",
                candidato != null ? candidato.apellido() : "",
                cuilYaCargado, cuilesCalculados,
                !motivos.isEmpty(), String.join(" / ", motivos)
            ));
        }

        escribirCsv(salida, resultado);

        long conSospechosos = resultado.stream().filter(e -> e.cantSospechosos() > 0).count();
        long conCuilCargado = resultado.stream().filter(e -> !e.cuilYaCargado().isEmpty()).count();
        long sinCuilCalculable = resultado.stream()
            .filter(e -> e.cuilYaCargado().isEmpty() && e.cuilesCalculados().isEmpty()).count();

        System.out.println();
        System.out.println("=== Resumen ===");
        System.out.println("Documentos evaluados:            " + resultado.size());
        System.out.println("Con posible mezcla (sospechosos): " + conSospechosos);
        System.out.println("Con CUIL ya cargado en la base:   " + conCuilCargado);
        System.out.println("Sin ningún CUIL calculable:       " + sinCuilCalculable);
        System.out.println("Reporte completo: " + salida.toAbsolutePath());
        System.out.println();
        System.out.println("Recordatorio: esto NO llamó a la API de RENAPER. El paso de");
        System.out.println("validación (ValidadorPersonaApi) queda para una corrida aparte,");
        System.out.println("una vez acordado el rate/concurrencia (CLAUDE.md §0 y §10).");
    }

    /**
     * Candidato dentro del cluster principal: mayor SCORE_COMPLETITUD y,
     * en empate, DT_LAST_UPDATE más reciente (NULLS LAST) — aproximación
     * a la regla de CLAUDE.md §5. Con score/fecha vacíos, elige el primero
     * de la lista sin más criterio (no hay suficiente señal).
     */
    private static Fila elegirCandidato(List<DetectorMezclados.Persona> principal, Map<String, Fila> porId) {
        return principal.stream()
            .map(p -> porId.get(p.idFormulario()))
            .filter(Objects::nonNull)
            .max(Comparator
                .comparingInt(Fila::scoreCompletitud)
                .thenComparing(f -> f.dtLastUpdate() == null ? "" : f.dtLastUpdate()))
            .orElse(null);
    }

    /** Si CUALQUIER registro del grupo ya tiene un CUIL/CUIT usable cargado, no hace falta calcular. */
    private static String buscarCuilYaCargado(List<Fila> grupo) {
        for (Fila f : grupo) {
            String c = normalizarNumero(f.cuilCargado());
            if (c != null && c.length() == 11 && !c.matches("0+") && !c.equals("30999078040")) {
                return c;
            }
        }
        return "";
    }

    /** Convierte "2.0068995699E10" / "20068995699.0" a "20068995699"; null si no hay nada usable. */
    private static String normalizarNumero(String s) {
        if (s == null || s.isBlank()) return null;
        try {
            double d = Double.parseDouble(s.trim());
            if (d <= 0) return null;
            return String.valueOf((long) d);
        } catch (NumberFormatException e) {
            String limpio = s.trim();
            return limpio.isEmpty() ? null : limpio;
        }
    }

    // ---------- Parseo de la tabla Markdown ----------

    private static List<Fila> leerMarkdown(Path archivo) throws IOException {
        List<String> lineas = Files.readAllLines(archivo, StandardCharsets.UTF_8).stream()
            .filter(l -> l.trim().startsWith("|"))
            .toList();
        if (lineas.isEmpty()) {
            throw new IllegalArgumentException("No se encontraron filas de tabla Markdown en " + archivo);
        }
        List<String> encabezado = partirFila(lineas.get(0));
        Map<String, Integer> col = new HashMap<>();
        for (int i = 0; i < encabezado.size(); i++) {
            col.put(encabezado.get(i).trim().toUpperCase(), i);
        }
        for (String requerida : List.of("ESTRATO", "NU_DOCUMENTO", "ID_FORMULARIO", "NM_NOMBRE",
                                         "NM_APELLIDO", "CD_SEXO", "SCORE_COMPLETITUD", "DT_LAST_UPDATE")) {
            if (!col.containsKey(requerida)) {
                throw new IllegalArgumentException("Falta la columna " + requerida + " en " + archivo
                    + " — encabezado encontrado: " + encabezado);
            }
        }
        // La segunda línea suele ser el separador |---|---|...
        int desde = lineas.size() > 1 && lineas.get(1).replaceAll("[|:\\- ]", "").isEmpty() ? 2 : 1;

        List<Fila> filas = new ArrayList<>();
        int descartadas = 0;
        for (int i = desde; i < lineas.size(); i++) {
            List<String> celdas = partirFila(lineas.get(i));
            if (celdas.size() != encabezado.size()) {
                descartadas++;
                System.out.println("AVISO: fila " + (i + 1) + " descartada, tiene " + celdas.size()
                    + " columnas y el encabezado tiene " + encabezado.size() + " -> " + lineas.get(i));
                continue;
            }
            String cdSexoStr = valor(celdas, col, "CD_SEXO");
            Integer cdSexo = null;
            if (cdSexoStr != null && !cdSexoStr.isBlank()) {
                try {
                    cdSexo = (int) Double.parseDouble(cdSexoStr.trim());
                } catch (NumberFormatException ignored) {
                    // queda null: se trata como sexo desconocido
                }
            }
            String cuilCargado = valor(celdas, col, "NU_CUIL_CUIT");
            if (cuilCargado == null || cuilCargado.isBlank()) {
                cuilCargado = valor(celdas, col, "NU_CUIL_CUIT_STR");
            }
            int score = 0;
            String scoreStr = valor(celdas, col, "SCORE_COMPLETITUD");
            if (scoreStr != null && !scoreStr.isBlank()) {
                try {
                    score = (int) Double.parseDouble(scoreStr.trim());
                } catch (NumberFormatException ignored) { }
            }
            String nuDoc = normalizarNumero(valor(celdas, col, "NU_DOCUMENTO"));
            filas.add(new Fila(
                valor(celdas, col, "ESTRATO"),
                nuDoc != null ? nuDoc : valor(celdas, col, "NU_DOCUMENTO"),
                valor(celdas, col, "ID_FORMULARIO"),
                nvl(valor(celdas, col, "NM_NOMBRE")),
                nvl(valor(celdas, col, "NM_APELLIDO")),
                cdSexo,
                cuilCargado,
                score,
                valor(celdas, col, "DT_LAST_UPDATE")
            ));
        }
        if (descartadas > 0) {
            System.out.println("Total de filas descartadas por columnas inconsistentes: " + descartadas);
        }
        return filas;
    }

    private static String valor(List<String> celdas, Map<String, Integer> col, String nombre) {
        Integer idx = col.get(nombre);
        if (idx == null || idx >= celdas.size()) return null;
        String v = celdas.get(idx).trim();
        return v.isEmpty() ? null : v;
    }

    private static String nvl(String s) {
        return s == null ? "" : s;
    }

    private static List<String> partirFila(String linea) {
        String sinBordes = linea.trim();
        if (sinBordes.startsWith("|")) sinBordes = sinBordes.substring(1);
        if (sinBordes.endsWith("|")) sinBordes = sinBordes.substring(0, sinBordes.length() - 1);
        return Arrays.asList(sinBordes.split("\\|", -1));
    }

    // ---------- Salida CSV ----------

    /**
     * CSV con ";" y BOM UTF-8, misma convención que RunQuery --csv: es lo que
     * Excel en español abre con doble clic sin pasar por el asistente de
     * importación ni romper los acentos.
     */
    private static void escribirCsv(Path salida, List<Evaluacion> filas) throws IOException {
        StringBuilder sb = new StringBuilder();
        sb.append("ESTRATO;NU_DOCUMENTO;CANT_REGISTROS;CANT_PRINCIPAL;CANT_SOSPECHOSOS;IDS_SOSPECHOSOS;")
          .append("CANDIDATO_ID;CANDIDATO_NOMBRE;CANDIDATO_APELLIDO;CUIL_YA_CARGADO;CUILES_CALCULADOS;")
          .append("REVISION_MANUAL;MOTIVO\n");
        for (Evaluacion e : filas) {
            sb.append(csv(e.estrato())).append(';')
              .append(csv(e.nuDocumento())).append(';')
              .append(e.cantRegistros()).append(';')
              .append(e.cantPrincipal()).append(';')
              .append(e.cantSospechosos()).append(';')
              .append(csv(e.idsSospechosos())).append(';')
              .append(csv(e.candidatoId())).append(';')
              .append(csv(e.candidatoNombre())).append(';')
              .append(csv(e.candidatoApellido())).append(';')
              .append(csv(e.cuilYaCargado())).append(';')
              .append(csv(e.cuilesCalculados())).append(';')
              .append(e.revisionManual()).append(';')
              .append(csv(e.motivoRevision())).append('\n');
        }
        Files.writeString(salida, "﻿" + sb.toString(), StandardCharsets.UTF_8);
    }

    private static String csv(String s) {
        if (s == null) s = "";
        // IDS_SOSPECHOSOS separa los ID con ";", que ahora es el separador de
        // columnas: sin este comillado esa celda partiría la fila en Excel.
        if (s.contains(";") || s.contains("\"") || s.contains("\n")) {
            return "\"" + s.replace("\"", "\"\"") + "\"";
        }
        return s;
    }
}
