import java.util.ArrayList;
import java.util.List;

/**
 * Calcula el CUIL de una persona física a partir del DNI y el código de
 * sexo tal como está almacenado en DIG_DOC_R62.CD_SEXO, para armar el
 * parámetro "nroDoc" (tipoDoc=CUIL) que pide la API de validación
 * (RENAPER).
 *
 * Verificado contra el ejemplo real provisto:
 *   DNI 23598685 + sexo masculino -> CUIL 20235986850
 *
 * OJO: esto asume que la API acepta un CUIL calculado (no que exija que
 * ya esté cargado en NU_CUIL_CUIT). Falta confirmar con el equipo de la
 * API que esto es correcto antes de usarlo en el script real.
 */
public class CalculadorCuil {

    private static final int[] PESOS = {5, 4, 3, 2, 7, 6, 5, 4, 3, 2};

    // Prefijos CUIL para persona física, según AFIP/ARCA.
    public static final int PREFIJO_MASCULINO = 20;
    public static final int PREFIJO_FEMENINO = 27;

    /**
     * Prefijo de reasignación AFIP/ANSES para el caso borde en que el
     * dígito verificador calculado con 20/27 da 10 (resto=1): el número
     * se reasigna cambiando los dos primeros dígitos a 23 y recalculando
     * el DV con ese nuevo prefijo (no se descarta el caso ni se fuerza
     * un DV inválido). Confirmado con fuentes públicas del algoritmo
     * AFIP/ANSES (15/09/2026) — antes esto tiraba IllegalStateException.
     */
    public static final int PREFIJO_REASIGNADO = 23;

    /**
     * Prefijo visto en un caso real de la base (documento 6903524 ->
     * CUIL 24069035244, ver CLAUDE.md §7 y §9.2). A diferencia del 23,
     * este NO sale de una regla derivable del algoritmo (en ese caso
     * CD_SEXO está NULL y el DV con 20/27 no da 10) — es simplemente un
     * prefijo real que ANSES asigna a algunas personas físicas por fuera
     * del esquema binario 20/27. No hay forma de saber de antemano si a
     * un DNI le corresponde: se ofrece como candidato más para probar
     * contra la API, no como resultado de un cálculo confiable.
     *
     * Antes de usar este candidato conviene revisar si NU_CUIL_CUIT /
     * NU_CUIL_CUIT_STR ya tienen el valor cargado en algún registro del
     * grupo de duplicados — si está cargado, no hace falta adivinar.
     */
    public static final int PREFIJO_ALTERNATIVO = 24;

    /**
     * CD_SEXO en DIG_DOC_R62: 1 = femenino, 2 = masculino, 0 = usado para
     * S.A. (no debería darse en PF), NULL = sin dato.
     * Devuelve null si el sexo es desconocido (sin prefijo de partida) o
     * si ni el prefijo esperado por sexo ni su reasignación a 23 dan un
     * dígito verificador válido (caso extremadamente raro, no visto
     * todavía en la base) — en ese caso conviene probar
     * {@link #candidatosCuil(String)} o revisar el caso a mano.
     */
    public static String calcularCuil(String dni, Integer cdSexo) {
        String dniPad = normalizarDni(dni);
        Integer prefijo = prefijoSegunSexo(cdSexo);
        if (prefijo == null) {
            return null;
        }
        String cuil = intentarConstruirCuil(prefijo, dniPad);
        if (cuil != null) {
            return cuil;
        }
        // DV=10 con el prefijo esperado por sexo -> reasignación AFIP/ANSES a 23.
        return intentarConstruirCuil(PREFIJO_REASIGNADO, dniPad);
    }

    /**
     * Para candidatos con CD_SEXO NULL o 0, o como respaldo cuando
     * {@link #calcularCuil} no pudo resolverlo: devuelve, EN ORDEN, los
     * CUIL candidatos a probar contra la API (masculino, femenino,
     * reasignado 23, alternativo 24 — ver {@link #PREFIJO_ALTERNATIVO}).
     * Un prefijo que da DV=10 se omite de la lista en vez de tirar
     * excepción o cortar el cálculo de los demás.
     *
     * PENDIENTE DE CONFIRMAR: si esto es viable depende de cómo responde
     * la API cuando el CUIL no existe (404 / cuerpo vacío / error) — con
     * el caso 6824505 ya vimos que "no trae info" es una respuesta
     * posible, pero no tenemos el JSON real todavía.
     */
    public static List<String> candidatosCuil(String dni) {
        String dniPad = normalizarDni(dni);
        List<String> candidatos = new ArrayList<>();
        for (int prefijo : List.of(PREFIJO_MASCULINO, PREFIJO_FEMENINO,
                                    PREFIJO_REASIGNADO, PREFIJO_ALTERNATIVO)) {
            String cuil = intentarConstruirCuil(prefijo, dniPad);
            if (cuil != null) {
                candidatos.add(cuil);
            }
        }
        return candidatos;
    }

    private static Integer prefijoSegunSexo(Integer cdSexo) {
        if (cdSexo == null) return null;
        return switch (cdSexo) {
            case 1 -> PREFIJO_FEMENINO;
            case 2 -> PREFIJO_MASCULINO;
            default -> null; // 0 u otro valor no mapeado
        };
    }

    private static String normalizarDni(String dni) {
        if (dni == null) {
            throw new IllegalArgumentException("DNI no puede ser null");
        }
        String limpio = dni.trim();
        if (!limpio.matches("\\d{1,8}")) {
            throw new IllegalArgumentException("DNI inválido: " + dni);
        }
        return String.format("%08d", Long.parseLong(limpio));
    }

    /**
     * Devuelve el CUIL para ese prefijo+DNI, o null si el dígito
     * verificador da 10 (caso borde del algoritmo para ese prefijo
     * puntual — no significa que el DNI no tenga CUIL, sino que ESTE
     * prefijo no es el correcto y hay que probar otro).
     */
    private static String intentarConstruirCuil(int prefijo, String dniPad) {
        String base10 = prefijo + dniPad; // 2 + 8 = 10 dígitos
        int dv = calcularDigitoVerificador(base10);
        if (dv == 10) {
            return null;
        }
        return base10 + dv;
    }

    static int calcularDigitoVerificador(String base10) {
        int suma = 0;
        for (int i = 0; i < 10; i++) {
            suma += Character.getNumericValue(base10.charAt(i)) * PESOS[i];
        }
        int resto = suma % 11;
        int dv = 11 - resto;
        return (dv == 11) ? 0 : dv;
    }

    public static void main(String[] args) {
        String cuil = calcularCuil("23598685", 2);
        System.out.println("CUIL calculado: " + cuil);
        System.out.println("Esperado:        20235986850");
        System.out.println("¿Coincide? " + "20235986850".equals(cuil));
        System.out.println();

        // Caso borde: DNI 20000009 con prefijo 20 da DV=10 -> se reasigna a 23.
        // (DNI de prueba armado a propósito para ejercitar la reasignación;
        // no corresponde a ningún caso real de la base.)
        String cuilReasignado = calcularCuil("20000009", 2);
        System.out.println("CUIL reasignado (caso borde DV=10): " + cuilReasignado);
        System.out.println("Esperado:                            23200000099");
        System.out.println("¿Coincide? " + "23200000099".equals(cuilReasignado));
        System.out.println();

        // Caso real de la base con CD_SEXO NULL (documento 6903524, ver
        // CLAUDE.md §7/§9.2): candidatosCuil debe incluir el 24 real
        // (24069035244) entre las opciones a probar.
        List<String> candidatos = candidatosCuil("6903524");
        System.out.println("Candidatos para 6903524 (CD_SEXO NULL): " + candidatos);
        System.out.println("¿Incluye el real 24069035244? " + candidatos.contains("24069035244"));
    }
}
