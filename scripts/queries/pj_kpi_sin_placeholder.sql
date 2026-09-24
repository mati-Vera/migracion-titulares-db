-- Recalcula el KPI de personas jurídicas excluyendo el placeholder
-- '30999078040' ("CUIT cajón de sastre": 563 registros bajo 31 razones
-- sociales distintas, no es una empresa real) — CLAUDE.md §3/§9.7/§10,
-- pendiente "Recalcular el KPI de PJ excluyendo el placeholder
-- 30999078040 (y variantes de typo)".
--
-- El 13.295 actual (informe .docx Y Excel, sin recalcular en ninguno de
-- los dos) todavía lo incluye. Esta query es la Query 4 de
-- docs/Metodologia_Queries_SIRCLAN.md (clasificación final PJ) con el
-- agregado de excluir ese CUIT del conteo de duplicados.
--
-- OJO: revisar primero si hay variantes de typo del mismo placeholder
-- (ej. con espacios, guiones, u otro dígito corrido) antes de dar este
-- número por definitivo — la query solo excluye el valor exacto.

WITH juridicas AS (
    SELECT p.ID_FORMULARIO,
        NVL(NULLIF(TRIM(TO_CHAR(p.NU_CUIL_CUIT)), ''),
            REGEXP_REPLACE(p.NU_CUIL_CUIT_STR, '[^0-9]', '')) AS CUIT_NORMALIZADO
    FROM DIG_DOC_R62 p
    WHERE p.TP_PERSONA <> 'PF'
),
clasificado AS (
    SELECT ID_FORMULARIO, CUIT_NORMALIZADO,
        CASE
            WHEN CUIT_NORMALIZADO IS NULL THEN 'SIN_CUIT'
            WHEN LENGTH(CUIT_NORMALIZADO) <> 11 THEN 'CUIT_INVALIDO'
            WHEN CUIT_NORMALIZADO = '30999078040' THEN 'PLACEHOLDER'
            ELSE 'VALIDO'
        END AS clasificacion
    FROM juridicas
),
conteo_validos AS (
    SELECT CUIT_NORMALIZADO, COUNT(*) AS cant_ids
    FROM clasificado
    WHERE clasificacion = 'VALIDO'
    GROUP BY CUIT_NORMALIZADO
)
SELECT
    (SELECT COUNT(*) FROM clasificado WHERE clasificacion = 'SIN_CUIT')       AS personas_sin_cuit,
    (SELECT COUNT(*) FROM clasificado WHERE clasificacion = 'CUIT_INVALIDO') AS personas_cuit_invalido,
    (SELECT COUNT(*) FROM clasificado WHERE clasificacion = 'PLACEHOLDER')   AS personas_cuit_placeholder_30999078040,
    (SELECT COUNT(*) FROM conteo_validos WHERE cant_ids > 1)                 AS grupos_cuit_duplicado,
    (SELECT NVL(SUM(cant_ids - 1), 0) FROM conteo_validos WHERE cant_ids > 1) AS registros_redundantes_cuit
FROM dual;

-- Comparar contra el 13.295 actual (Excel/informe, sin recalcular):
--   registros_redundantes_cuit de esta query = 13.295 - (563 - 1) = 12.733,
--   si el único cambio es sacar el cluster completo de 563 registros bajo
--   31 razones sociales (563 filas, 1 solo "grupo" que se resta entero de
--   grupos_cuit_duplicado, y 562 registros redundantes que se restan del
--   total). Confirmar contra el resultado real antes de publicarlo — es
--   una cuenta a mano para chequeo, no un valor tomado por cierto.

-- Variantes de typo a revisar aparte si aparecen (no cubiertas acá):
-- SELECT CUIT_NORMALIZADO, COUNT(*) FROM juridicas
-- WHERE CUIT_NORMALIZADO LIKE '%999078040%' OR CUIT_NORMALIZADO LIKE '3099907804_'
-- GROUP BY CUIT_NORMALIZADO ORDER BY 2 DESC;
