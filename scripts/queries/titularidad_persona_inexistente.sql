-- Titularidades cuyo CD_PERSONA / CD_PERSONA_H / CD_PERSONA_P NO EXISTE en DIG_DOC_R62.
--
-- Caso INVERSO de titularidad_matricula_inexistente.sql: ahí la matrícula era la
-- referencia rota; acá la matrícula existe (se trae su NU_MATRICULA/CD_ESTADO para
-- contexto) y lo que está colgado es la PERSONA. Origen: al revisar las 519 filas
-- huérfanas de matrícula (18/09) apareció una con CD_PERSONA sin contraparte en
-- DIG_DOC_R62 (plan_etapa2_borrado_titularidades_huerfanas_2026-09-22.md §2) — nunca
-- se midió si hay más casos de este tipo fuera de ese lote. Esta query los busca en
-- todo B2/B4/B5, no solo dentro de las huérfanas de matrícula.
--
-- Mismos principios que la query hermana: nunca se une más de una tabla "muchos" en
-- la misma rama del UNION ALL (CLAUDE.md §4); NO filtra ELIMINADO a propósito (se
-- audita todo, ELIMINADO va como columna); distingue CD_PERSONA NULL (nunca se
-- asignó persona) de CD_PERSONA con valor que no matchea ninguna fila de R62
-- (referencia rota real, el caso que interesa).
--
-- Sin FK declaradas (CLAUDE.md §2) nada impide que B2/B4/B5 apunten a un
-- ID_FORMULARIO que fue borrado de R62 o que nunca existió.

-- ===========================================================================
-- Bloque 1: resumen por tabla.
-- ===========================================================================
SELECT 'B2 - ACTIVOS' AS TABLA,
       COUNT(*) AS FILAS_PERSONA_INEXISTENTE,
       SUM(CASE WHEN b.CD_PERSONA IS NULL THEN 1 ELSE 0 END) AS SIN_CD_PERSONA,
       SUM(CASE WHEN b.CD_PERSONA IS NOT NULL THEN 1 ELSE 0 END) AS CD_PERSONA_INEXISTENTE,
       SUM(CASE WHEN NVL(b.ELIMINADO,0) = 1 THEN 1 ELSE 0 END) AS DE_LAS_CUALES_ELIMINADO_1
FROM DIG_DOC_R00_B2 b
WHERE NOT EXISTS (SELECT 1 FROM DIG_DOC_R62 p WHERE p.ID_FORMULARIO = b.CD_PERSONA)
UNION ALL
SELECT 'B4 - HISTORICOS',
       COUNT(*),
       SUM(CASE WHEN b.CD_PERSONA_H IS NULL THEN 1 ELSE 0 END),
       SUM(CASE WHEN b.CD_PERSONA_H IS NOT NULL THEN 1 ELSE 0 END),
       CAST(NULL AS NUMBER)  -- B4 no tiene columna ELIMINADO
FROM DIG_DOC_R00_B4 b
WHERE NOT EXISTS (SELECT 1 FROM DIG_DOC_R62 p WHERE p.ID_FORMULARIO = b.CD_PERSONA_H)
UNION ALL
SELECT 'B5 - NO VIGENTES',
       COUNT(*),
       SUM(CASE WHEN b.CD_PERSONA_P IS NULL THEN 1 ELSE 0 END),
       SUM(CASE WHEN b.CD_PERSONA_P IS NOT NULL THEN 1 ELSE 0 END),
       SUM(CASE WHEN NVL(b.ELIMINADO,0) = 1 THEN 1 ELSE 0 END)
FROM DIG_DOC_R00_B5 b
WHERE NOT EXISTS (SELECT 1 FROM DIG_DOC_R62 p WHERE p.ID_FORMULARIO = b.CD_PERSONA_P);

-- ===========================================================================
-- Bloque 2: detalle fila por fila — SOLO el caso real (CD_PERSONA con un valor
-- que no matchea ningún ID_FORMULARIO de DIG_DOC_R62), no el caso trivial de
-- "nunca se asignó persona". Por eso el WHERE agrega CD_PERSONA IS NOT NULL
-- explícito, además del NOT EXISTS que ya hace la verificación contra R62.
-- LEFT JOIN a DIG_DOC_R00 (no INNER): en teoría podría combinarse con el
-- problema hermano (matrícula también inexistente), aunque no se espera.
-- Volumen esperado chico (el único caso visto hasta ahora es 1), se trae
-- completo, sin ROWNUM.
-- ===========================================================================
SELECT
    'B2 - ACTIVOS'      AS TABLA,
    b.ID_MATRICULA,
    i.NU_MATRICULA,
    i.CD_ESTADO,
    i.DS_INMUEBLE,
    b.CD_PERSONA        AS ID_FORMULARIO_INEXISTENTE,
    ROUND(b.NU_NUMERADOR / NULLIF(b.NU_DENOMINADOR,0) * 100, 4) AS PORCENTAJE,
    TO_CHAR(b.DT_DESDE, 'YYYY-MM-DD') AS DESDE,
    NVL(b.ELIMINADO, 0) AS ELIMINADO
FROM DIG_DOC_R00_B2 b
LEFT JOIN DIG_DOC_R00 i ON i.ID_MATRICULA = b.ID_MATRICULA
WHERE b.CD_PERSONA IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM DIG_DOC_R62 p WHERE p.ID_FORMULARIO = b.CD_PERSONA)
UNION ALL
SELECT
    'B4 - HISTORICOS',
    b.ID_MATRICULA,
    i.NU_MATRICULA,
    i.CD_ESTADO,
    i.DS_INMUEBLE,
    b.CD_PERSONA_H,
    ROUND(b.NU_NUMERAD_2 / NULLIF(b.NU_DENOMINAD_2,0) * 100, 4),
    TO_CHAR(b.DT_DES_2, 'YYYY-MM-DD'),
    CAST(NULL AS NUMBER)  -- B4 no tiene columna ELIMINADO
FROM DIG_DOC_R00_B4 b
LEFT JOIN DIG_DOC_R00 i ON i.ID_MATRICULA = b.ID_MATRICULA
WHERE b.CD_PERSONA_H IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM DIG_DOC_R62 p WHERE p.ID_FORMULARIO = b.CD_PERSONA_H)
UNION ALL
SELECT
    'B5 - NO VIGENTES',
    b.ID_MATRICULA,
    i.NU_MATRICULA,
    i.CD_ESTADO,
    i.DS_INMUEBLE,
    b.CD_PERSONA_P,
    CAST(NULL AS NUMBER),  -- B5 no lleva porcentaje (CLAUDE.md §4)
    TO_CHAR(b.DT_HAS_2, 'YYYY-MM-DD'),
    NVL(b.ELIMINADO, 0)
FROM DIG_DOC_R00_B5 b
LEFT JOIN DIG_DOC_R00 i ON i.ID_MATRICULA = b.ID_MATRICULA
WHERE b.CD_PERSONA_P IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM DIG_DOC_R62 p WHERE p.ID_FORMULARIO = b.CD_PERSONA_P)
ORDER BY 1, 2;

-- Lectura: toda fila de este bloque tiene un ID_FORMULARIO_INEXISTENTE con
-- valor — ese código no existe en DIG_DOC_R62, es la referencia rota real (el
-- caso "nunca se asignó persona" ya quedó afuera por el CD_PERSONA IS NOT NULL
-- del WHERE, y sigue contado aparte en el bloque 1 como SIN_CD_PERSONA).
-- NU_MATRICULA/CD_ESTADO/DS_INMUEBLE NULOS significan que además la matrícula
-- tampoco existe (los dos problemas juntos en la misma fila) — señal a reportar
-- aparte si aparece.
