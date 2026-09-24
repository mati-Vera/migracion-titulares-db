import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.text.Normalizer;
import java.time.Duration;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Llama a la API de validación (RENAPER) para una persona física y compara
 * la respuesta contra el registro candidato de DIG_DOC_R62.
 *
 * El parseo del JSON está hecho a mano (sin Jackson/Gson/org.json) porque
 * la respuesta es chica, plana y de forma fija. Si el proyecto ya usa
 * alguna librería JSON, conviene reemplazar RenaperResponse.parse(...) por
 * deserialización con esa librería en vez de esto.
 *
 * La API es la fuente de verdad: si el CUIL calculado no trae datos, se
 * asume que el CUIL está mal (sexo incorrecto o documento inexistente en
 * RENAPER), no que la API falló. Dos formas de error confirmadas:
 *   1) HTTP 200, validado=false, error="El documento o sexo son
 *      incorrectos" -> se reintenta una vez con el prefijo de sexo
 *      contrario antes de concluir que no está en RENAPER (confirmado
 *      con el caso real 6824505/20068245053: CD_SEXO estaba mal cargado
 *      en la base, y con el prefijo correcto la persona sí tiene datos).
 *   2) HTTP 500 con forma distinta ({"timestamp","status","error",
 *      "message"}, sin "nroDoc") -> CUIT mal formado (cantidad de
 *      dígitos incorrecta). Se clasifica aparte, no se reintenta.
 */
public class ValidadorPersonaApi {

    private static final String BASE_URL =
        "https://dev-api-drp.jus.mendoza.gov.ar/gateway/api/v1/persons/renaper/persona";

    private final HttpClient http = HttpClient.newBuilder()
        .connectTimeout(Duration.ofSeconds(10))
        .build();

    // ---------- Respuesta de la API ----------

    public record RenaperResponse(
        String nroDoc,
        String nombres,
        String apellidos,
        String fechaNacimiento,
        String sexo,
        boolean validado,
        boolean fallecido,
        boolean mayorEdad,
        String error,
        String fechaFallecimiento
    ) {
        static RenaperResponse parse(String json) {
            return new RenaperResponse(
                campoString(json, "nroDoc"),
                campoString(json, "nombres"),
                campoString(json, "apellidos"),
                campoString(json, "fechaNacimiento"),
                campoString(json, "sexo"),
                campoBooleano(json, "validado"),
                campoBooleano(json, "fallecido"),
                campoBooleano(json, "mayorEdad"),
                campoString(json, "error"),
                campoString(json, "fecha_fallecimiento")
            );
        }
    }

    private static String campoString(String json, String clave) {
        // matchea "clave":"valor"  o  "clave":null
        Pattern p = Pattern.compile("\"" + clave + "\"\\s*:\\s*(?:\"([^\"]*)\"|null)");
        Matcher m = p.matcher(json);
        if (!m.find()) return null;
        return m.group(1); // null si matcheó la rama "null"
    }

    private static boolean campoBooleano(String json, String clave) {
        Pattern p = Pattern.compile("\"" + clave + "\"\\s*:\\s*(true|false)");
        Matcher m = p.matcher(json);
        return m.find() && Boolean.parseBoolean(m.group(1));
    }

    // ---------- Llamado a la API ----------

    private static final String ERROR_DOC_O_SEXO = "El documento o sexo son incorrectos";

    /**
     * Punto de entrada principal: dado un DNI y el CD_SEXO de la base
     * (puede ser null/0 = desconocido), calcula el CUIL y consulta la
     * API. Si la API responde "El documento o sexo son incorrectos",
     * reintenta automáticamente con el prefijo de sexo contrario antes
     * de darse por vencido — confirmado con el caso real 6824505: el
     * CD_SEXO de la base puede estar mal cargado, y sin este reintento
     * ese caso queda clasificado como "sin datos" incorrectamente.
     */
    public RenaperResponse consultar(String dni, Integer cdSexo) throws Exception {
        Integer prefijoInicial = prefijoDesdeSexo(cdSexo); // null si CD_SEXO es NULL/0

        if (prefijoInicial != null) {
            String cuil = CalculadorCuil.calcularCuil(dni, cdSexo);
            RenaperResponse resp = consultarPorCuil(cuil, prefijoInicial == 27 ? "F" : "M");
            if (!esErrorDocumentoOSexo(resp)) {
                return resp; // encontrado (o un error distinto) al primer intento
            }
            // reintentar con el prefijo contrario
            int prefijoAlterno = (prefijoInicial == 20) ? 27 : 20;
            String cuilAlterno = construirCuilConPrefijo(dni, prefijoAlterno);
            return consultarPorCuil(cuilAlterno, prefijoAlterno == 27 ? "F" : "M");
        }

        // CD_SEXO desconocido: probar masculino primero, después femenino
        for (String cuil : CalculadorCuil.candidatosCuil(dni)) {
            String sexoParam = cuil.startsWith("27") ? "F" : "M";
            RenaperResponse resp = consultarPorCuil(cuil, sexoParam);
            if (!esErrorDocumentoOSexo(resp)) {
                return resp;
            }
        }
        // ninguno de los dos prefijos funcionó: devolvemos el último intento (femenino)
        String ultimoCuil = CalculadorCuil.candidatosCuil(dni).get(1);
        return consultarPorCuil(ultimoCuil, "F");
    }

    private static boolean esErrorDocumentoOSexo(RenaperResponse resp) {
        return resp.error() != null && resp.error().contains(ERROR_DOC_O_SEXO);
    }

    private static Integer prefijoDesdeSexo(Integer cdSexo) {
        if (cdSexo == null) return null;
        return switch (cdSexo) {
            case 1 -> CalculadorCuil.PREFIJO_FEMENINO;
            case 2 -> CalculadorCuil.PREFIJO_MASCULINO;
            default -> null;
        };
    }

    private static String construirCuilConPrefijo(String dni, int prefijo) {
        // reutiliza la lógica de CalculadorCuil armando el CD_SEXO equivalente
        int cdSexoEquivalente = (prefijo == CalculadorCuil.PREFIJO_FEMENINO) ? 1 : 2;
        return CalculadorCuil.calcularCuil(dni, cdSexoEquivalente);
    }

    public RenaperResponse consultarPorCuil(String cuil, String sexoParam) throws Exception {
        String url = BASE_URL + "?tipoDoc=CUIL&nroDoc=" + cuil + "&sexo=" + sexoParam;

        HttpRequest request = HttpRequest.newBuilder()
            .uri(URI.create(url))
            .GET()
            .timeout(Duration.ofSeconds(15))
            .build();

        HttpResponse<String> response = http.send(request, HttpResponse.BodyHandlers.ofString());
        String body = response.body();

        if (response.statusCode() == 500 && body.contains("\"status\"")) {
            // Forma distinta de error (CUIT mal formado, ej. cantidad de
            // dígitos incorrecta): {"timestamp":...,"status":500,"error":...,"message":...}
            // No tiene "nroDoc" ni el resto de los campos habituales.
            String mensaje = campoString(body, "message");
            return new RenaperResponse(cuil, "", "", "", sexoParam, false, false, false,
                "CUIT_MAL_FORMADO: " + (mensaje != null ? mensaje : body), "");
        }
        if (response.statusCode() != 200) {
            throw new RuntimeException(
                "La API respondió HTTP " + response.statusCode() + ": " + body);
        }
        return RenaperResponse.parse(body);
    }

    // ---------- Comparación contra el candidato de DIG_DOC_R62 ----------

    public enum Resultado {
        COINCIDE, DIFERENCIA_NOMBRE, DIFERENCIA_SEXO, FALLECIDO, SIN_DATOS_API, CUIT_MAL_FORMADO
    }

    public record Comparacion(Resultado resultado, String detalle) {}

    /**
     * Compara nombre, apellido y sexo del candidato (tal como están en
     * DIG_DOC_R62) contra lo que devolvió la API. Normaliza mayúsculas y
     * acentos antes de comparar, porque RENAPER devuelve "Angel Mariano"
     * (con mayúscula inicial) y la base suele tener todo en mayúsculas.
     */
    public Comparacion comparar(String nmNombre, String nmApellido, Integer cdSexo,
                                 RenaperResponse api) {
        if (api.error() != null && api.error().startsWith("CUIT_MAL_FORMADO")) {
            return new Comparacion(Resultado.CUIT_MAL_FORMADO, api.error());
        }
        if (api.error() != null) {
            // Llegar acá después del reintento con ambos prefijos significa
            // que el documento realmente no está en RENAPER (o la persona
            // es extranjera) — ya no es un simple problema de sexo mal
            // calculado, porque eso ya se reintentó en consultar(...).
            return new Comparacion(Resultado.SIN_DATOS_API, "La API devolvió error: " + api.error());
        }
        if (api.fallecido()) {
            return new Comparacion(Resultado.FALLECIDO,
                "La persona figura fallecida en RENAPER (" + api.fechaFallecimiento() + ")");
        }

        String sexoEsperado = (cdSexo != null && cdSexo == 1) ? "F"
                             : (cdSexo != null && cdSexo == 2) ? "M" : null;
        if (sexoEsperado != null && api.sexo() != null && !sexoEsperado.equals(api.sexo())) {
            return new Comparacion(Resultado.DIFERENCIA_SEXO,
                "CD_SEXO=" + cdSexo + " (" + sexoEsperado + ") vs API=" + api.sexo());
        }

        boolean nombreOk = normalizar(nmNombre).equals(normalizar(api.nombres()));
        boolean apellidoOk = normalizar(nmApellido).equals(normalizar(api.apellidos()));
        if (!nombreOk || !apellidoOk) {
            return new Comparacion(Resultado.DIFERENCIA_NOMBRE,
                "BD: " + nmNombre + " " + nmApellido
                + " | API: " + api.nombres() + " " + api.apellidos());
        }

        return new Comparacion(Resultado.COINCIDE, "Nombre, apellido y sexo coinciden con RENAPER");
    }

    private static String normalizar(String s) {
        if (s == null) return "";
        String sinAcentos = Normalizer.normalize(s.trim(), Normalizer.Form.NFD)
            .replaceAll("\\p{M}", "");
        return sinAcentos.toUpperCase().replaceAll("\\s+", " ");
    }

    // ---------- Prueba con el ejemplo real que pasaste ----------

    public static void main(String[] args) {
        String ejemploJson = """
            {
                "nroDoc": "23598685",
                "nombres": "Angel Mariano",
                "apellidos": "MIGUEL",
                "fechaNacimiento": "21-10-1973",
                "sexo": "M",
                "validado": true,
                "fallecido": false,
                "mayorEdad": true,
                "error": null,
                "fecha_fallecimiento": ""
            }
            """;

        RenaperResponse resp = RenaperResponse.parse(ejemploJson);
        System.out.println("Parseado: " + resp);

        ValidadorPersonaApi validador = new ValidadorPersonaApi();

        // Simulando un candidato de DIG_DOC_R62 con el mismo nombre (pero en mayúsculas, como en la BD)
        Comparacion c1 = validador.comparar("ANGEL MARIANO", "MIGUEL", 2, resp);
        System.out.println("Caso igual: " + c1.resultado() + " -> " + c1.detalle());

        // Simulando una variante de tipeo típica (como vimos en los casos ELASKAR/MATHUS)
        Comparacion c2 = validador.comparar("ANGEL MARIANO", "MIGUEZ", 2, resp);
        System.out.println("Caso con diferencia: " + c2.resultado() + " -> " + c2.detalle());

        // Caso real: CUIL calculado con el sexo equivocado (6824505 / 20068245053)
        String jsonSexoIncorrecto = """
            {
                "nroDoc": "20068245053",
                "nombres": "",
                "apellidos": "",
                "fechaNacimiento": "",
                "sexo": "M",
                "validado": false,
                "fallecido": false,
                "mayorEdad": false,
                "error": "El documento o sexo son incorrectos",
                "fecha_fallecimiento": ""
            }
            """;
        RenaperResponse respSexoIncorrecto = RenaperResponse.parse(jsonSexoIncorrecto);
        System.out.println("¿Es error de documento/sexo? " + esErrorDocumentoOSexo(respSexoIncorrecto));

        // Caso real: CUIT mal formado (cantidad de dígitos incorrecta) -> HTTP 500
        String jsonCuitMalFormado = """
            {
                "timestamp": "2026-09-15T16:07:58.962766021",
                "status": 500,
                "error": "Internal Server Error",
                "message": "An error occurred processing your request."
            }
            """;
        String mensaje = campoString(jsonCuitMalFormado, "message");
        RenaperResponse respMalFormado = new RenaperResponse("?", "", "", "", "?", false, false, false,
            "CUIT_MAL_FORMADO: " + mensaje, "");
        Comparacion c3 = validador.comparar("X", "Y", 2, respMalFormado);
        System.out.println("Caso CUIT mal formado: " + c3.resultado() + " -> " + c3.detalle());
    }
}
