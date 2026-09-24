-- Titularidades que apuntan a un ID_MATRICULA que NO EXISTE en DIG_DOC_R00.
--
-- Origen: hallazgo del 17/09/2026 al correr vinculadas_matricula_real_kpi_pf.sql
-- (bloque 3, columna FILAS_SIN_INMUEBLE) — CLAUDE.md §3 "Corte con matrícula REAL":
-- 519 filas en B2 + 38 en B4 + 0 en B5 = 557 filas de titularidad "colgadas de la
-- nada". Como el sistema no tiene FK declaradas (CLAUDE.md §2), nada le impide a
-- una fila de B2/B4/B5 referenciar un ID_MATRICULA que ya no está en R00 (o que
-- nunca estuvo). Pendiente de investigar (§10), esta query es el primer paso:
-- verla en detalle, no solo el número agregado.
--
-- Cubre las tres tablas de titularidad, pero cada una en su propio bloque del
-- UNION ALL (nunca se une más de una tabla "muchos" en la misma rama, CLAUDE.md
-- §4). El join contra DIG_DOC_R62 es 1:1 por la PK ID_FORMULARIO, no multiplica.
--
-- ⚠️ A propósito NO filtra ELIMINADO acá (a diferencia de las queries de KPI):
-- el objetivo es auditar TODAS las filas huérfanas, incluidas las que ya están
-- de baja lógica, para poder separar "huérfana y viva" (más urgente) de "huérfana
-- y ya dada de baja" (curiosidad histórica, menor prioridad). El campo ELIMINADO
-- se muestra como columna en vez de usarse como filtro.
--
-- Distingue dos casos distintos dentro de "sin inmueble":
--   - ID_MATRICULA de la fila es NULL directamente -> no apunta a nada.
--   - ID_MATRICULA tiene un valor, pero ESE valor no existe en DIG_DOC_R00 -> es
--     el caso interesante: una referencia colgada, no un campo vacío.

-- ===========================================================================
-- Bloque 1: resumen por tabla (para contrastar contra 519 / 38 / 0 del 17/09).
-- ===========================================================================
SELECT 'B2 - ACTIVOS' AS TABLA,
       COUNT(*) AS FILAS_HUERFANAS,
       SUM(CASE WHEN b.ID_MATRICULA IS NULL THEN 1 ELSE 0 END) AS SIN_ID_MATRICULA,
       SUM(CASE WHEN b.ID_MATRICULA IS NOT NULL THEN 1 ELSE 0 END) AS ID_MATRICULA_INEXISTENTE,
       SUM(CASE WHEN NVL(b.ELIMINADO,0) = 1 THEN 1 ELSE 0 END) AS DE_LAS_CUALES_ELIMINADO_1
FROM DIG_DOC_R00_B2 b
WHERE NOT EXISTS (SELECT 1 FROM DIG_DOC_R00 i WHERE i.ID_MATRICULA = b.ID_MATRICULA)
UNION ALL
SELECT 'B4 - HISTORICOS',
       COUNT(*),
       SUM(CASE WHEN b.ID_MATRICULA IS NULL THEN 1 ELSE 0 END),
       SUM(CASE WHEN b.ID_MATRICULA IS NOT NULL THEN 1 ELSE 0 END),
       CAST(NULL AS NUMBER)  -- B4 no tiene columna ELIMINADO
FROM DIG_DOC_R00_B4 b
WHERE NOT EXISTS (SELECT 1 FROM DIG_DOC_R00 i WHERE i.ID_MATRICULA = b.ID_MATRICULA)
UNION ALL
SELECT 'B5 - NO VIGENTES',
       COUNT(*),
       SUM(CASE WHEN b.ID_MATRICULA IS NULL THEN 1 ELSE 0 END),
       SUM(CASE WHEN b.ID_MATRICULA IS NOT NULL THEN 1 ELSE 0 END),
       SUM(CASE WHEN NVL(b.ELIMINADO,0) = 1 THEN 1 ELSE 0 END)
FROM DIG_DOC_R00_B5 b
WHERE NOT EXISTS (SELECT 1 FROM DIG_DOC_R00 i WHERE i.ID_MATRICULA = b.ID_MATRICULA);

-- ===========================================================================
-- Bloque 2: detalle fila por fila — quién es el titular, con qué documento,
-- desde cuándo, y a qué ID_MATRICULA inexistente apunta. Volumen chico
-- (~557 filas en total el 17/09), se trae completo, sin ROWNUM.
-- ===========================================================================
SELECT
    'B2 - ACTIVOS'      AS TABLA,
    b.ID_MATRICULA,
    b.CD_PERSONA        AS ID_FORMULARIO,
    p.NU_DOCUMENTO,
    p.NM_APELLIDO,
    p.NM_NOMBRE,
    ROUND(b.NU_NUMERADOR / NULLIF(b.NU_DENOMINADOR,0) * 100, 4) AS PORCENTAJE,
    TO_CHAR(b.DT_DESDE, 'YYYY-MM-DD') AS DESDE,
    NVL(b.ELIMINADO, 0) AS ELIMINADO
FROM DIG_DOC_R00_B2 b
LEFT JOIN DIG_DOC_R62 p ON p.ID_FORMULARIO = b.CD_PERSONA
WHERE NOT EXISTS (SELECT 1 FROM DIG_DOC_R00 i WHERE i.ID_MATRICULA = b.ID_MATRICULA)
UNION ALL
SELECT
    'B4 - HISTORICOS',
    b.ID_MATRICULA,
    b.CD_PERSONA_H,
    p.NU_DOCUMENTO,
    p.NM_APELLIDO,
    p.NM_NOMBRE,
    ROUND(b.NU_NUMERAD_2 / NULLIF(b.NU_DENOMINAD_2,0) * 100, 4),
    TO_CHAR(b.DT_DES_2, 'YYYY-MM-DD'),
    CAST(NULL AS NUMBER)  -- B4 no tiene columna ELIMINADO
FROM DIG_DOC_R00_B4 b
LEFT JOIN DIG_DOC_R62 p ON p.ID_FORMULARIO = b.CD_PERSONA_H
WHERE NOT EXISTS (SELECT 1 FROM DIG_DOC_R00 i WHERE i.ID_MATRICULA = b.ID_MATRICULA)
UNION ALL
SELECT
    'B5 - NO VIGENTES',
    b.ID_MATRICULA,
    b.CD_PERSONA_P,
    p.NU_DOCUMENTO,
    p.NM_APELLIDO,
    p.NM_NOMBRE,
    CAST(NULL AS NUMBER),  -- B5 no lleva porcentaje (CLAUDE.md §4)
    TO_CHAR(b.DT_HAS_2, 'YYYY-MM-DD'),
    NVL(b.ELIMINADO, 0)
FROM DIG_DOC_R00_B5 b
LEFT JOIN DIG_DOC_R62 p ON p.ID_FORMULARIO = b.CD_PERSONA_P
WHERE NOT EXISTS (SELECT 1 FROM DIG_DOC_R00 i WHERE i.ID_MATRICULA = b.ID_MATRICULA)
ORDER BY 1, 3;

-- Lectura: si ID_MATRICULA sale NULL, esa fila nunca tuvo inmueble asignado (no
-- es "colgada", es "vacía"). Si sale con un número, ESE número no existe en
-- DIG_DOC_R00 — es la referencia rota real, la que interesa reportar.
