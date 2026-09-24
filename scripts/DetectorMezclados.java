import java.text.Normalizer;
import java.util.*;

/**
 * Detecta si un grupo de personas duplicadas por NU_DOCUMENTO en realidad
 * mezcla a varias personas reales distintas, en vez de ser todo variantes
 * de tipeo de una sola persona.
 *
 * Motivación (revisión manual, 15/09/2026): de 7 casos nuevos revisados a
 * mano, 5 tenían esta mezcla — incluyendo 25007077, donde solo 4 de 11
 * registros eran la misma persona (Francisco Gaitán) y el resto eran al
 * menos 5 personas distintas con apellido parecido o igual (hermanos con
 * el mismo apellido, por ejemplo).
 *
 * Estrategia: comparar nombre y apellido normalizados con tolerancia a
 * variantes de tipeo (distancia de Levenshtein por token). El apellido
 * exige que todos sus tokens aparezcan en el otro registro (sin importar
 * el orden). El nombre se acepta si CUALQUIERA de estas dos señales se
 * cumple: el primer token (nombre de pila) es muy similar por sí solo
 * (cubre variantes de segundo nombre, ej. "IBRAHIM ABIB" vs "IBRAHIN
 * ADID"), o todos los tokens aparecen sin importar el orden (cubre
 * nombres reordenados entre cargas, ej. "JUAN CARLOS ERNESTO" vs
 * "ERNESTO JUAN"). Si el apellido coincide pero NINGUNA de las dos
 * señales de nombre se cumple (ej. "FRANCISCO GAITAN TROIANO" vs "RAMON
 * EDUARDO GAITAN TROIANO"), se asume que son personas distintas
 * (hermanos u otro familiar), no una variante de tipeo. También
 * contempla el caso de nombre/apellido invertidos entre registros (visto
 * en el caso ELASKAR: "ELASKAR IBRAHIN" / "ABIB").
 */
public class DetectorMezclados {

    private static final double UMBRAL_SIMILITUD_TOKEN = 0.75; // 0–1, más alto = más estricto

    public record Persona(String idFormulario, String nombre, String apellido) {}

    public record Grupo(List<Persona> principal, List<Persona> sospechosos) {}

    /**
     * Agrupa las personas de un mismo NU_DOCUMENTO en componentes conexas
     * según similitud de nombre. El componente más grande queda como
     * "principal" (sigue el flujo normal: selección de candidato +
     * validación API); el resto queda como "sospechosos" — posibles
     * personas distintas, a cola de revisión manual, NO se fusionan
     * automáticamente.
     */
    public Grupo clusterizar(List<Persona> grupo) {
        int n = grupo.size();
        int[] padre = new int[n];
        for (int i = 0; i < n; i++) padre[i] = i;

        for (int i = 0; i < n; i++) {
            for (int j = i + 1; j < n; j++) {
                if (esMismaPersona(grupo.get(i), grupo.get(j))) {
                    unir(padre, i, j);
                }
            }
        }

        Map<Integer, List<Persona>> componentes = new LinkedHashMap<>();
        for (int i = 0; i < n; i++) {
            int raiz = encontrar(padre, i);
            componentes.computeIfAbsent(raiz, k -> new ArrayList<>()).add(grupo.get(i));
        }

        List<List<Persona>> ordenado = new ArrayList<>(componentes.values());
        ordenado.sort((a, b) -> b.size() - a.size()); // más grande primero

        List<Persona> principal = ordenado.isEmpty() ? List.of() : ordenado.get(0);
        List<Persona> sospechosos = new ArrayList<>();
        for (int i = 1; i < ordenado.size(); i++) {
            sospechosos.addAll(ordenado.get(i));
        }
        return new Grupo(principal, sospechosos);
    }

    public boolean esMismaPersona(Persona a, Persona b) {
        boolean apellidoOk = todosLosTokensCoinciden(a.apellido(), b.apellido());
        // dos señales para el nombre, con OR: o el primer token (nombre de
        // pila) es fuerte por sí solo (cubre "IBRAHIM ABIB" vs "IBRAHIN
        // ADID", donde el segundo nombre difiere bastante pero el primero
        // no deja dudas), o todos los tokens aparecen sin importar el
        // orden (cubre "JUAN CARLOS ERNESTO" vs "ERNESTO JUAN", nombres
        // reordenados entre cargas). Cualquiera de las dos alcanza.
        boolean nombreOk = primerTokenSimilar(a.nombre(), b.nombre())
            || todosLosTokensCoinciden(a.nombre(), b.nombre());
        if (apellidoOk && nombreOk) return true;

        // caso borde: nombre/apellido invertidos entre registros (visto en el caso ELASKAR,
        // donde un registro tiene "ELASKAR IBRAHIN" en apellido y "ABIB" en nombre, y en el
        // caso 23598685 donde "MIGUEL ANGEL"/"MARIANO" y "ANGEL MARIANO"/"MIGUEL" son la misma
        // persona con los tokens repartidos distinto). Acá ya no se puede confiar en cuál
        // token es el "nombre de pila", así que se usa el chequeo laxo por subconjunto en
        // los dos sentidos.
        return todosLosTokensCoinciden(a.nombre(), b.apellido())
            && todosLosTokensCoinciden(a.apellido(), b.nombre());
    }

    /**
     * Compara el PRIMER token de cada campo (el nombre de pila principal),
     * que es la señal más fuerte de identidad — mucho más confiable que
     * exigir que la mitad de todos los tokens coincidan, lo cual dejaba
     * pasar casos como "FRANCO MIGUEL" vs "FRANCISCO MIGUEL" (personas
     * distintas que comparten el segundo nombre) como si fueran la misma
     * persona. Los tokens siguientes (segundo nombre, etc.) no se exigen:
     * suelen omitirse o variar entre cargas sin que cambie la persona.
     */
    private boolean primerTokenSimilar(String x, String y) {
        List<String> tokensX = tokenizar(x);
        List<String> tokensY = tokenizar(y);
        if (tokensX.isEmpty() || tokensY.isEmpty()) return false;
        return similitudToken(tokensX.get(0), tokensY.get(0)) >= UMBRAL_SIMILITUD_TOKEN;
    }

    /**
     * El apellido sí se compara token a token (con subconjuntos, por
     * apellidos compuestos que a veces se cargan truncados) porque ahí
     * el riesgo de "personas distintas con apellido parecido" es menor
     * una vez que YA se exigió que el nombre de pila coincida.
     */
    /**
     * TODOS los tokens del campo más corto deben encontrar una pareja
     * similar en el más largo (sin importar el orden). Se usa tanto para
     * apellido como, junto con primerTokenSimilar, para nombre.
     */
    private boolean todosLosTokensCoinciden(String x, String y) {
        List<String> tokensX = tokenizar(x);
        List<String> tokensY = tokenizar(y);
        if (tokensX.isEmpty() || tokensY.isEmpty()) return false;

        List<String> corto = tokensX.size() <= tokensY.size() ? tokensX : tokensY;
        List<String> largo = tokensX.size() <= tokensY.size() ? tokensY : tokensX;

        for (String t : corto) {
            boolean matcheo = false;
            for (String u : largo) {
                if (similitudToken(t, u) >= UMBRAL_SIMILITUD_TOKEN) {
                    matcheo = true;
                    break;
                }
            }
            if (!matcheo) return false; // TODOS los tokens del apellido más corto deben aparecer
        }
        return true;
    }

    private double similitudToken(String a, String b) {
        if (a.equals(b)) return 1.0;
        int dist = levenshtein(a, b);
        int maxLen = Math.max(a.length(), b.length());
        return maxLen == 0 ? 1.0 : 1.0 - (double) dist / maxLen;
    }

    private List<String> tokenizar(String s) {
        String norm = normalizar(s);
        return norm.isBlank() ? List.of() : Arrays.asList(norm.split("\\s+"));
    }

    private String normalizar(String s) {
        if (s == null) return "";
        String sinAcentos = Normalizer.normalize(s.trim(), Normalizer.Form.NFD)
            .replaceAll("\\p{M}", "");
        return sinAcentos.toUpperCase().replaceAll("\\s+", " ");
    }

    private static int levenshtein(String a, String b) {
        // Damerau-Levenshtein (con transposición de adyacentes) porque varios
        // typos reales del Excel son transposiciones (MIGUEL/MIGULE), que a
        // Levenshtein simple le cuestan 2 ediciones en vez de 1 y subestiman
        // la similitud.
        int[][] dp = new int[a.length() + 1][b.length() + 1];
        for (int i = 0; i <= a.length(); i++) dp[i][0] = i;
        for (int j = 0; j <= b.length(); j++) dp[0][j] = j;
        for (int i = 1; i <= a.length(); i++) {
            for (int j = 1; j <= b.length(); j++) {
                int costo = a.charAt(i - 1) == b.charAt(j - 1) ? 0 : 1;
                dp[i][j] = Math.min(Math.min(dp[i - 1][j] + 1, dp[i][j - 1] + 1), dp[i - 1][j - 1] + costo);
                if (i > 1 && j > 1
                    && a.charAt(i - 1) == b.charAt(j - 2)
                    && a.charAt(i - 2) == b.charAt(j - 1)) {
                    dp[i][j] = Math.min(dp[i][j], dp[i - 2][j - 2] + 1);
                }
            }
        }
        return dp[a.length()][b.length()];
    }

    private static int encontrar(int[] padre, int i) {
        while (padre[i] != i) {
            padre[i] = padre[padre[i]];
            i = padre[i];
        }
        return i;
    }

    private static void unir(int[] padre, int i, int j) {
        int ri = encontrar(padre, i), rj = encontrar(padre, j);
        if (ri != rj) padre[ri] = rj;
    }

    // ---------- Pruebas con los casos reales del Excel ----------

    public static void main(String[] args) {
        probarCaso("23598685 — esperado: solo 5099514 y 1606378 juntos", List.of(
            new Persona("5173055", "ALEJANDRO JOSE", "MORSUCCI"),
            new Persona("5160702", "VICTORIA", "GROTZ"),
            new Persona("5160662", "ALEJANDRO JAVIER", "SANCHEZ"),
            new Persona("5135435", "JUAN", "MANRIQUE"),
            new Persona("5135432", "DOMINGO ROGELIO", "OLIVERA"),
            new Persona("5114199", "GUILLERMO", "CONSOLI OBERDAN"),
            new Persona("5114198", "ARIEL HERNAN", "SCAFI"),
            new Persona("5114197", "ANDRES ANTONIO", "MARTORELL"),
            new Persona("5114223", "ENRIQUE DANIEL", "AGUILAR"),
            new Persona("5099514", "MIGUEL ANGEL", "MARIANO"),
            new Persona("1606378", "ANGEL MARIANO", "MIGUEL")
        ));

        probarCaso("25007077 — esperado: solo 5302372,5302369,5302373,5115894 juntos", List.of(
            new Persona("5302372", "FRANCISCO MIGUEL", "GAITAN"),
            new Persona("5302368", "OMAR ALEJANDRO", "QUIROGA"),
            new Persona("5302369", "FRANCISCO", "GAITAN TROIANO"),
            new Persona("5302370", "FRANCO MIGUEL", "GAITAN TROIANO"),
            new Persona("5302371", "RAMON EDUARDO", "GAITAN TROIANO"),
            new Persona("5302377", "RAMON ALEJANDRO", "TOLEDO VELAZQUEZ"),
            new Persona("5302373", "FRANCISCO MIGUEL", "GAITAN TROIANO"),
            new Persona("5302374", "FRANCO MIGUEL", "GAITAN TROYANO"),
            new Persona("5302375", "RAMON EDUARDO", "GAITAN TROYANO"),
            new Persona("5302376", "RODRIGO FERNANDO", "RAMIREZ"),
            new Persona("5115894", "FRANCISCO MIGUEL", "GAITAN TROIANO")
        ));

        probarCaso("6903524 — esperado: solo 5681889 (Patricia) separada", List.of(
            new Persona("5682021", "CARLOS ALBERTO", "CUERVO"),
            new Persona("5681901", "CARLOS ALBERTO", "CUERVO"),
            new Persona("5681900", "CARLOS ALBERTO", "CUERVO"),
            new Persona("5681897", "CARLOS ALBERTO", "CUERVO"),
            new Persona("5681893", "CARLOS ALBERTO", "CUERVO"),
            new Persona("5681891", "CARLOS ALBERTO", "CUERVO"),
            new Persona("5681889", "PATRICIA DEL CARMEN", "LEAL"),
            new Persona("5585833", "CARLOS ALBERTO", "CUERVO"),
            new Persona("5437444", "CARLOS ALBERTO", "CUERVO FONTANA"),
            new Persona("5279576", "CARLOS ALBERTO", "CUERVO"),
            new Persona("1423051", "CARLOS ALBERTO", "CUERVO")
        ));

        probarCaso("32162858 — esperado: solo 5671495 (Yanina) separada", List.of(
            new Persona("5671513", "LEILA YASMIN", "MUSCARSEL ELASKAR"),
            new Persona("5671509", "LEILA YASMIN", "MUCARSEL ELASKAR"),
            new Persona("5671495", "YANINA LORENA", "MUCARSEL ELASKAR"),
            new Persona("5668475", "LEILA YASMIN", "MUCARSEL ELASKAR"),
            new Persona("5668451", "LEILA YASMIN", "MUCARSEL ELASKAR"),
            new Persona("5668431", "LEILA YASMIN", "MUSCARSEL ELASKAR"),
            new Persona("5668428", "LEILA YASMIN", "MUCARSEL ELASKAR"),
            new Persona("5668421", "LEILA YASMIN", "MUCARSEL ELASKAR"),
            new Persona("5629536", "LEILA YASMIN", "MUCARSEL ELASKAR"),
            new Persona("5542938", "LELIA YASMIN", "MUCARSEL ELASKAR"),
            new Persona("5372395", "LELIA YASMIN", "MUCARSEL")
        ));

        probarCaso("ELASKAR (Anexo I del informe original) — esperado: 1 solo grupo, incluye campos invertidos", List.of(
            new Persona("428409", "IBRAHIM ABIB", "ELASKAR"),
            new Persona("1494698", "IBRAHIN ABIB", "ELASKAR"),
            new Persona("2023617", "IBRAHIM", "ELASKAR"),
            new Persona("2060010", "IBRAHIN ABIB", "ELASKAR"),
            new Persona("5098912", "IBRAHIN ADID", "ELASKAR"),
            new Persona("5158814", "IBRAIN ABIB", "ELASKAR"),
            new Persona("5402125", "ABIB", "ELASKAR IBRAHIN"),
            new Persona("5591706", "ABIB ELASKAR", "IBRAHIM")
        ));

        probarCaso("6880087 (MATHUS) — esperado: 1 solo grupo, incluye el typo MIGUEL/MIGULE", List.of(
            new Persona("5712948", "MIGUEL ALFREDO ATAULFO GUILLERMO", "MATHUS"),
            new Persona("5568790", "MIGUEL ALFREDO ATAULFO GUILLERMO", "MATHUS ESCORIHUELA"),
            new Persona("5568691", "MIGUEL ATAULFO GUILLERMO", "MATHUS ESCORIHUELA"),
            new Persona("5568658", "MIGULE ALFREDO ATAULFO GUILLERMO", "MATHUS ESCORIHUELA"),
            new Persona("5213957", "MIGUEL ALFREDOATAULFOGUILLERMO", "MATHUS ESCORIHUELA")
        ));

        probarCaso("6772336 (GONZALEZ FELTRUP, caso original) — esperado: 1 solo grupo", List.of(
            new Persona("5638314", "RAMON CONRADO", "GONZALEZ FELTRUP"),
            new Persona("5632841", "RAMON CONRADO", "GONZALEZ PELTRUP"),
            new Persona("5547630", " RAMON CONRADO", "GONZALEZ FELTRUP"),
            new Persona("385243", "RAMON CONRADO", "GONZALEZ")
        ));

        probarCaso("8154398 (FERIOZZI) — esperado: 9 juntos, 2 intrusos separados", List.of(
            new Persona("5486162", "JUAN CARLOS ERNESTO", "FERIOZZI"),
            new Persona("5447060", "JOSE RAFAEL", "STRADIOTTO"),
            new Persona("5377673", "ERNESTO J CARLOS", "FERIOZZI"),
            new Persona("5332780", "ERNESTO JUAN", "FERIOZZI"),
            new Persona("5302754", "ERNESTO JUAN", "FERIOZZI"),
            new Persona("5269038", "ADRIANA", "MOYANO MAURE"),
            new Persona("5125619", "ERNESTO JUAN CARLOS", "FERIOZZI VILCHEZ"),
            new Persona("2087016", "ERNESTO JUAN C", "FERIOZZI"),
            new Persona("1452036", "ERNESTO JUAN CARLOS", "FERIOZZI"),
            new Persona("665367", "ERNESTO JUAN CARLOS", "FERIOZZI"),
            new Persona("439685", "ERNESTO JUAN CARLOS", "FERIOZZI")
        ));

        probarCaso("8023173 (GINART) — esperado: 1 solo grupo, sin mezcla", List.of(
            new Persona("5644105", "JOSE", "GINART SANCHEZ"),
            new Persona("5615045", "JOSE", "GINART"),
            new Persona("5614633", "SANCHEZ", "GINART"),
            new Persona("5614603", "JOSË", "GINART"),
            new Persona("5614602", "JOSÉ", "GINART"),
            new Persona("5614601", "JOS E", "GINART"),
            new Persona("5614600", "JOSÉ", "GINART"),
            new Persona("5590795", "JOSE", "GINART SANCHEZ"),
            new Persona("2072656", "JOSE", "GINART"),
            new Persona("2011482", "JOSE", "GINART SANCHEZ"),
            new Persona("1618528", "JOSE", "GINART")
        ));

        // ---- Casos agregados el 16/09/2026 desde las hojas del Excel que
        // quedaban sin test (CLAUDE.md §6, "11 son regresiones baratas de
        // agregar"). El "esperado" es la Observación cargada a mano en cada
        // hoja; donde el resultado real no coincide se deja documentado
        // como limitación conocida en vez de forzar el test.

        probarCaso("6850189 (PERALTA) — esperado: 1 solo grupo, sin mezcla (observación: relacionado a muchas matrículas)", List.of(
            new Persona("5641750", "EDILBERTO MODESTO", "PERALTA"),
            new Persona("5631869", "EDILBERTO MODESTO", "PERALTA"),
            new Persona("5618579", "EDILBERTO MODESTO", "PERALTA"),
            new Persona("5618578", "EDILBERTO MODESTO", "PERALTA"),
            new Persona("5616766", "EDILBERTO MODESTO", "PERALTA"),
            new Persona("5537925", "MODESTO EDILBERTO", "PERALTA"),
            new Persona("1563605", "EDILBERTO MODESTO", "PERALTA"),
            new Persona("5393798", "ELIBERTO MODESTO", "PERALTA"),
            new Persona("5082530", "EDILBERTO MODESTO", "PERALTA"),
            new Persona("2064808", "MODESTO EDILBERTO", "PERALTA"),
            new Persona("2058543", "EDILBERTO MODESTO", "PERALTA"),
            new Persona("2056108", "EDILBERTO MODESTO", "PERALTA"),
            new Persona("1428010", "EDILBERTO MODESTO", "PERALTA"),
            new Persona("460548", "EDILBERTO MODESTO", "PERALTA")
        ));

        probarCaso("6146086 (GROSSO) — esperado: 1 solo grupo, sin mezcla (observación: muchas relaciones con matrículas)", List.of(
            new Persona("5559183", "ROBERTO OSVALDO", "GROSSO MELCHORI"),
            new Persona("5335229", "ROBERTO", "GROSSO MELCHIORI"),
            new Persona("5166682", "OSVALDO BLAS", "GROSSO"),
            new Persona("5119132", "ROBERTO", "GROSSO MELCHIORI"),
            new Persona("5115004", "MELCHIORI ROBERTO", "GROSSO"),
            new Persona("5022753", "ROBERTO", "GROSSO MELCHIORI"),
            new Persona("2026317", "ROBERTO OSVALDO BLAS", "GROSSO MELCHIORI"),
            new Persona("2004462", "ROBERTO OSVALDO", "GROSSO"),
            new Persona("2004461", "ROBERTO OSVALDO BLAS", "GROSSO"),
            new Persona("2004460", "ROBERTO OSVALDO BLAS", "GROSSO MELCHIORI"),
            new Persona("2004464", "ROBERTO BLAS", "GROSSO"),
            new Persona("1562382", "ROBERTO OSVALDO BLAS", "GROSSO"),
            new Persona("342038", "ROBERTO OSVALDO BLAS", "GROSSO")
        ));

        probarCaso("8145732 (LEMOS) — esperado: 1 solo grupo, sin mezcla (observación: el 5038282 está 60 veces en b4)", List.of(
            new Persona("5651279", "RICARDO ALBERTO", "LEMOS GRANTA"),
            new Persona("5593850", "RICARDO", "LEMOS GRANATA"),
            new Persona("5593665", "RICARDO ALBERTO", "LEMOS GRANATA"),
            new Persona("5593623", "RICARDO ALBERTO", "LEMOS GRANATA"),
            new Persona("5586971", "RICARDO ALBERTO", "LEMOS"),
            new Persona("5586603", "RICARDO ALBERTO", "LEMOS"),
            new Persona("5585313", "RICARDO ALBERTO", "LEMOS GRANATA"),
            new Persona("5561309", "RICARDO", "LEMOS GRANATA"),
            new Persona("5550721", "RICARDO ALBERTO", "LEMOS GRANATA"),
            new Persona("5541722", "RICARDO ALBERTO", "LEMOS GRANATA"),
            new Persona("5469526", "RICARDO ALBERTO", "LEMOS GRANATA"),
            new Persona("5447462", "RICARDO ALBERTO", "LEMOS"),
            new Persona("5038282", "RICARDO ALBERTO", "LEMOS")
        ));

        probarCaso("5109377 (COLOMBO/MEDINA) — esperado: 1 solo grupo, sin mezcla (observación: sin CUIT válido, no valida con la API)", List.of(
            new Persona("5495732", "LAURA", "MEDINA BETTANCOURT"),
            new Persona("5471489", "LAURA DEL CARMEN", "COLOMBO"),
            new Persona("5466104", "LAURA DEL CARMEN", "BENTANCOURT DE COLOMBO"),
            new Persona("5454396", "LAURA DEL CARMEN DE", "COLOMBO"),
            new Persona("5437098", "LAURA DEL CARMEN", "MEDINA BETTANCOURT DE COLOMBO"),
            new Persona("5368010", "LAURA DEL CARMEN", "COLOMBO"),
            new Persona("5364203", "LAURA DEL CARMEN DE", "COLOMBO"),
            new Persona("5363896", "LAURA DEL CARMEN", "DE COLOMBO"),
            new Persona("5363897", "LAURA DEL CARMEN DE", "COLOMBO"),
            new Persona("5309355", "LAURA DEL CARMEN DE", "COLOMBO"),
            new Persona("5106435", "LAURA DEL CARMEN", "DE COLOMBO"),
            new Persona("5106409", "LAURA DEL CARMEN", "DE COLOMBO"),
            new Persona("1573484", "LAURA DEL CARMEN", "MEDINA")
        ));

        probarCaso("92833978 (SO KANG YOUNG) — esperado: 1 solo grupo, sin mezcla (observación: aparentemente extranjero, sin registros en b2/b4/b5)", List.of(
            new Persona("5324224", "SO", "KANG YOUNG"),
            new Persona("2085420", "KANG YOUNG", "SO"),
            new Persona("2051662", "YOUNG", "SO KANG"),
            new Persona("2026303", "SO KANG", "YOUNG"),
            new Persona("2026302", "KANG YOUNG", "SO"),
            new Persona("2023158", "KANG YOUNG", "SO"),
            new Persona("2023160", "SO KANG", "YOUNG"),
            new Persona("2023161", "SO", "KANG YOUNG"),
            new Persona("2019318", "KANG", "YOUNG SO"),
            new Persona("2019313", "YOUNG SO", "KANG"),
            new Persona("2019321", "KANG YOUNG", "SO"),
            new Persona("2016480", "YOUNG", "SO KANG"),
            new Persona("2016479", "SO KANG", "YOUNG")
        ));

        probarCaso("6842131 (ELASKAR NAZAR) — esperado: 1 solo grupo, sin mezcla (observación: solo registros en tabla b4)", List.of(
            new Persona("5591705", "JOSE ELASKAR", "NAZAR"),
            new Persona("5477668", "JOSE", "ELASKAR NAZAR"),
            new Persona("5361961", "JOSE", "ELASKAR NAZAR"),
            new Persona("5336565", "JOSE", "NAZAR"),
            new Persona("5334223", "NAZAR JOSE", "ELASKAR"),
            new Persona("5273886", "JOSE", "ELASKAR MAZAR"),
            new Persona("5126904", "JOSE NAZAR", "ELASCAR"),
            new Persona("2070051", "JOSE", "ELASKAR NAZAR"),
            new Persona("2060009", "NAZAR JOSE", "ELASKAR"),
            new Persona("1465040", "NAZAR JOSE", "ELASKAR"),
            new Persona("428408", "NAZAR JOSE", "ELASKAR")
        ));

        probarCaso("6899569 (MARINI / FIRMANI) — esperado: 2 grupos, observación confirma \"dos personas diferentes con el mismo dni\"", List.of(
            new Persona("5694152", "JOSE", "MARINI"),
            new Persona("5694151", "JOSE", "MARINI"),
            new Persona("5694135", "JOSE", "MARINI"),
            new Persona("5648852", "ANTONIO JOSE", "FIRMANI"),
            new Persona("5638275", "JOSE", "MARINI"),
            new Persona("5638274", "JOSE", "MARINI"),
            new Persona("5386019", "JOSE", "MARINI"),
            new Persona("5175873", "ANTONIO JOSE", "FIRMANI"),
            new Persona("5047133", "JOSE ANTONIO", "FIRMANI"),
            new Persona("1645862", "JOSE MARINI", "DE CAROLIS"),
            new Persona("568153", "JOSE", "MARINI")
        ));
    }

    private static void probarCaso(String titulo, List<Persona> grupo) {
        DetectorMezclados detector = new DetectorMezclados();
        Grupo resultado = detector.clusterizar(grupo);
        System.out.println("=== " + titulo + " (" + grupo.size() + " registros) ===");
        System.out.println("Principal (" + resultado.principal().size() + "): " + idsYNombres(resultado.principal()));
        System.out.println("Sospechosos (" + resultado.sospechosos().size() + "): " + idsYNombres(resultado.sospechosos()));
        System.out.println();
    }

    private static String idsYNombres(List<Persona> personas) {
        return personas.stream()
            .map(p -> p.idFormulario() + ":" + p.nombre().trim() + " " + p.apellido().trim())
            .toList().toString();
    }
}
