-- LA PREGUNTA QUE ABRE EL CORTE DEL 16/09/2026: de los 34.055 grupos con dos o
-- más titulares ACTIVOS duplicados (P1), ¿en cuántos los dos registros están
-- colgados de la MISMA matrícula?
--
-- La diferencia importa y mucho:
--   * Si están en matrículas distintas, es una persona con varios inmuebles
--     cargada dos veces. Molesto, pero el dato registral de cada matrícula está
--     bien.
--   * Si están en la MISMA matrícula, esa matrícula tiene a la misma persona
--     contada dos veces como titular vigente. Ahí el porcentaje de titularidad
--     está repartido entre dos registros que son la misma persona — se conecta
--     directo con las 309 matrículas con suma de porcentajes <> 100% del
--     informe (CLAUDE.md §3) y es el caso más mostrable de todos: no es "la
--     base está desprolija", es "este inmueble tiene mal los titulares".
--
-- Devuelve primero el resumen (una fila) y después el detalle para el Excel.
--
-- ✅ VERIFICADO 17/09/2026 (CLAUDE.md §10): DIG_DOC_R00_B2 (y B5, no solo B2)
-- tiene columnas ELIMINADO y RECIENTE. ELIMINADO=1 confirmado como baja
-- lógica real: hay matrículas donde TODAS las filas de B2 están en
-- ELIMINADO=1 (quedan sin titular vivo si no se excluyen) y filas ELIMINADO=1
-- cargadas tanto por la migración (CD_USER_STORE null / RPI_RV_MIG) como por
-- usuarios de WORKFLOW corrigiendo errores ya en producción. La query de
-- abajo YA filtra `WHERE NVL(b.ELIMINADO,0) = 0`.
-- RECIENTE se investigó y NO se filtra: correlaciona con el origen del
-- registro (NULL = migración pre-17/08/2017, 0/1 = WORKFLOW post-migración),
-- no con si la titularidad sigue vigente — no es un flag de baja.
--
-- Impacto medido (16/09 sin filtrar → 17/09 filtrando ELIMINADO):
-- casos 3.537→3.362, matrículas afectadas 3.006→2.868 (−4,6%), documentos
-- 3.082→2.947, registros de persona 7.194→6.842, filas B2 7.741→7.365. El
-- máximo de personas en una matrícula no cambió (9). Ver CLAUDE.md §3.
--
-- Nota aparte (17/09/2026): el alias REGISTROS_DE_PERSONA_INVOLUCRADOS tenía
-- 33 caracteres y excede el límite de 30 de esta versión de Oracle
-- (ORA-00972) — no había reventado antes porque el 16/09 se corrió desde
-- DBeaver, no desde RunQuery. Corregido a REGISTROS_PERSONA_INVOLUC.
--
-- ---------------------------------------------------------------------------
-- 0) CHEQUEO PREVIO (ya corrido, resultado documentado arriba y en CLAUDE.md):
-- ---------------------------------------------------------------------------
-- SELECT ELIMINADO, RECIENTE, COUNT(*) AS FILAS
-- FROM DIG_DOC_R00_B2
-- GROUP BY ELIMINADO, RECIENTE
-- ORDER BY FILAS DESC;
--
-- Resultado (B2): (null,null)=761039 (null,0)=208540 (null,1)=3524
-- (0,null)=3365 (1,null)=2822 (1,0)=896 (0,0)=745. Total ELIMINADO=1: 3.718
-- filas (0,38% de 980.931) — chico en volumen pero concentrado justo en los
-- casos de "doble titular" que este archivo mide, de ahí el −4,6%.

-- ---------------------------------------------------------------------------
-- 1) RESUMEN
-- ---------------------------------------------------------------------------
WITH grupos_dup AS (
    SELECT NU_DOCUMENTO
    FROM DIG_DOC_R62
    WHERE TP_PERSONA = 'PF'
      AND NU_DOCUMENTO IS NOT NULL
      AND NOT REGEXP_LIKE(NU_DOCUMENTO, '^0+$')
      AND NU_DOCUMENTO NOT IN ('99907804', '1')
    GROUP BY NU_DOCUMENTO
    HAVING COUNT(*) > 1
),
personas_dup AS (
    SELECT p.NU_DOCUMENTO, p.ID_FORMULARIO
    FROM DIG_DOC_R62 p
    JOIN grupos_dup g ON g.NU_DOCUMENTO = p.NU_DOCUMENTO
    WHERE p.TP_PERSONA = 'PF'
),
-- Una sola tabla "muchos" (B2) contra el set de personas duplicadas.
colision AS (
    SELECT
        b.ID_MATRICULA,
        pd.NU_DOCUMENTO,
        COUNT(DISTINCT b.CD_PERSONA) AS PERSONAS_DISTINTAS,
        COUNT(*)                     AS FILAS_B2,
        SUM(b.NU_NUMERADOR / NULLIF(b.NU_DENOMINADOR, 0)) AS SUMA_PORCENTAJE_DEL_GRUPO
    FROM DIG_DOC_R00_B2 b
    JOIN personas_dup pd ON pd.ID_FORMULARIO = b.CD_PERSONA
    WHERE NVL(b.ELIMINADO, 0) = 0
    GROUP BY b.ID_MATRICULA, pd.NU_DOCUMENTO
    HAVING COUNT(DISTINCT b.CD_PERSONA) > 1
)
SELECT
    COUNT(*)                            AS CASOS_MATRICULA_MAS_DOCUMENTO,
    COUNT(DISTINCT ID_MATRICULA)        AS MATRICULAS_AFECTADAS,
    COUNT(DISTINCT NU_DOCUMENTO)        AS DOCUMENTOS_AFECTADOS,
    SUM(PERSONAS_DISTINTAS)             AS REGISTROS_PERSONA_INVOLUC,
    SUM(FILAS_B2)                       AS FILAS_B2_INVOLUCRADAS,
    MAX(PERSONAS_DISTINTAS)             AS MAX_PERSONAS_EN_UNA_MATRICULA
FROM colision;

-- ---------------------------------------------------------------------------
-- 2) DETALLE (para la hoja del Excel) — misma lógica, con datos del inmueble.
--    Correr por separado; reemplaza al SELECT de arriba.
-- ---------------------------------------------------------------------------
-- WITH grupos_dup AS ( ... igual que arriba ... ),
--      personas_dup AS ( ... igual que arriba ... ),
--      colision AS ( ... igual que arriba ... )
-- SELECT
--     c.NU_DOCUMENTO,
--     c.ID_MATRICULA,
--     i.NU_MATRICULA,
--     i.CD_ESTADO,
--     i.DS_INMUEBLE,
--     c.PERSONAS_DISTINTAS,
--     c.FILAS_B2,
--     ROUND(c.SUMA_PORCENTAJE_DEL_GRUPO, 4) AS SUMA_PORCENTAJE_DEL_GRUPO
-- FROM colision c
-- LEFT JOIN DIG_DOC_R00 i ON i.ID_MATRICULA = c.ID_MATRICULA
-- ORDER BY c.PERSONAS_DISTINTAS DESC, c.FILAS_B2 DESC, c.NU_DOCUMENTO;

-- Lectura de SUMA_PORCENTAJE_DEL_GRUPO: es cuánto de la titularidad de esa
-- matrícula está en manos de registros que son la MISMA persona. Si da 1
-- (=100%), el inmueble entero pertenece a una sola persona cargada N veces:
-- fusionar esos registros es sumar las partes, no elegir una.
