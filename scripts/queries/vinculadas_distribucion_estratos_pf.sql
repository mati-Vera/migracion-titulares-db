-- Distribución por estrato de los grupos PF duplicados, cruzada contra la
-- vinculación a matrícula. Es distribucion_estratos_pf.sql + el filtro que
-- pidió Mónica (16/09/2026): mirar solo las personas vinculadas a matrículas.
--
-- Para qué sirve: poner al lado la distribución "vieja" (todos los grupos:
-- bajo 113.959 / medio 7.545 / alto 328 / muy alto 20, CLAUDE.md §3) y la
-- distribución del universo real de trabajo. Dos cosas a mirar en el resultado:
--
--   (a) Cuánto se achica el trabajo. Si el grueso de los 113.959 grupos del
--       estrato bajo no toca ninguna matrícula, el piloto y las ~122.000
--       llamadas a la API (§10) se redimensionan fuerte.
--   (b) Si el sesgo se invierte. Los grupos grandes son candidatos a "colisión"
--       (documento mal cargado que atrapó varias personas, §5); si además
--       resultan ser los que concentran los vínculos, la muestra tiene que
--       rearmarse sobre el universo vinculado — que es lo que hace
--       vinculadas_muestra_estratificada.sql.
--
-- PENDIENTE DE CORRER.

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
vinculos AS (
    SELECT CD_PERSONA   AS ID_FORMULARIO FROM DIG_DOC_R00_B2 WHERE CD_PERSONA   IS NOT NULL GROUP BY CD_PERSONA
    UNION
    SELECT CD_PERSONA_H AS ID_FORMULARIO FROM DIG_DOC_R00_B4 WHERE CD_PERSONA_H IS NOT NULL GROUP BY CD_PERSONA_H
    UNION
    SELECT CD_PERSONA_P AS ID_FORMULARIO FROM DIG_DOC_R00_B5 WHERE CD_PERSONA_P IS NOT NULL GROUP BY CD_PERSONA_P
),
grupo AS (
    SELECT
        pd.NU_DOCUMENTO,
        COUNT(*)                                            AS CANT_IDS,
        SUM(CASE WHEN v.ID_FORMULARIO IS NULL THEN 0 ELSE 1 END) AS CANT_VINCULADAS
    FROM personas_dup pd
    LEFT JOIN vinculos v ON v.ID_FORMULARIO = pd.ID_FORMULARIO
    GROUP BY pd.NU_DOCUMENTO
)
SELECT
    CASE
        WHEN CANT_IDS BETWEEN 2 AND 3  THEN '1 - BAJO (2-3)'
        WHEN CANT_IDS BETWEEN 4 AND 6  THEN '2 - MEDIO (4-6)'
        WHEN CANT_IDS BETWEEN 7 AND 10 THEN '3 - ALTO (7-10)'
        ELSE                                '4 - MUY ALTO (11+)'
    END AS ESTRATO,
    CASE
        WHEN CANT_VINCULADAS = 0 THEN '3 - SIN VINCULO A MATRICULA'
        WHEN CANT_VINCULADAS = 1 THEN '2 - UN SOLO VINCULADO'
        ELSE                          '1 - VARIOS VINCULADOS'
    END AS CATEGORIA_VINCULO,
    COUNT(*)                              AS GRUPOS,
    SUM(CANT_IDS)                         AS REGISTROS_TOTALES,
    SUM(CANT_IDS - 1)                     AS REGISTROS_REDUNDANTES,
    SUM(CANT_VINCULADAS)                  AS PERSONAS_VINCULADAS,
    MIN(CANT_IDS)                         AS MIN_DUPLICADOS,
    MAX(CANT_IDS)                         AS MAX_DUPLICADOS,
    ROUND(AVG(CANT_IDS), 2)               AS PROMEDIO_DUPLICADOS
FROM grupo
GROUP BY
    CASE
        WHEN CANT_IDS BETWEEN 2 AND 3  THEN '1 - BAJO (2-3)'
        WHEN CANT_IDS BETWEEN 4 AND 6  THEN '2 - MEDIO (4-6)'
        WHEN CANT_IDS BETWEEN 7 AND 10 THEN '3 - ALTO (7-10)'
        ELSE                                '4 - MUY ALTO (11+)'
    END,
    CASE
        WHEN CANT_VINCULADAS = 0 THEN '3 - SIN VINCULO A MATRICULA'
        WHEN CANT_VINCULADAS = 1 THEN '2 - UN SOLO VINCULADO'
        ELSE                          '1 - VARIOS VINCULADOS'
    END
ORDER BY ESTRATO, CATEGORIA_VINCULO;

-- Chequeo: la suma de GRUPOS por ESTRATO (las 3 categorías juntas) tiene que
-- reproducir la tabla de CLAUDE.md §3 — 113.959 / 7.545 / 328 / 20 (total
-- 121.852 en el corte del 16/09). Si difiere, es drift de la base de desarrollo
-- entre cortes, no un error de la query: verificarlo volviendo a correr
-- distribucion_estratos_pf.sql el mismo día que ésta.
