-- KPI de personas físicas duplicadas RESTRINGIDO A LAS VINCULADAS A UNA MATRÍCULA.
--
-- Origen del cambio de criterio: reunión con Mónica (16/09/2026) — "tenés que
-- vincular las personas con las matrículas, filtralo por ese lado; si están
-- vinculadas a una matrícula entonces tomá esos registros y revisalos".
--
-- Qué cambia respecto de los KPI de CLAUDE.md §3: hasta ahora el universo eran
-- TODOS los grupos de NU_DOCUMENTO duplicado de DIG_DOC_R62 (121.793 grupos /
-- 162.491 registros redundantes). DIG_DOC_R62 es el catálogo de personas de todo
-- el BPM, no solo de titulares (§4), así que una parte de esos duplicados no toca
-- ninguna matrícula y no impacta en el problema registral.
--
-- Esta query parte los grupos en tres categorías:
--   1 - VARIOS VINCULADOS  -> 2+ registros del grupo cuelgan de una matrícula.
--                             Es la fusión "de verdad": hay que reasignar FK en
--                             B2/B4/B5 y es donde pega el riesgo de "personas
--                             mezcladas" (§5, §7).
--   2 - UN SOLO VINCULADO  -> el ganador ya está determinado por los datos: el
--                             único que tiene matrícula. Los demás son copias
--                             sueltas del catálogo, no hay FK que mover.
--   3 - SIN VÍNCULO        -> ningún registro del grupo toca una matrícula.
--                             Fuera del alcance de titulares.
--
-- ⚠️ "Sin vínculo a matrícula" NO significa "borrable": DIG_DOC_R62 lo comparte
-- todo el BPM y esas personas pueden estar referenciadas desde otros formularios.
-- Acá solo se usa para acotar el alcance de ESTE proyecto, no para depurar.
--
-- Mismo criterio de exclusión de placeholders que la Query 14 de
-- docs/Metodologia_Queries_SIRCLAN.md y que distribucion_estratos_pf.sql.
-- PENDIENTE DE CORRER — no hay cifras de esta query todavía.

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
-- Una fila por (persona, tabla de titularidad) — agrupado, NO joineado, para no
-- multiplicar filas (CLAUDE.md §4, principio de queries).
vinculos AS (
    SELECT CD_PERSONA   AS ID_FORMULARIO, 'B2' AS ORIGEN
    FROM DIG_DOC_R00_B2 WHERE CD_PERSONA IS NOT NULL GROUP BY CD_PERSONA
    UNION ALL
    SELECT CD_PERSONA_H AS ID_FORMULARIO, 'B4' AS ORIGEN
    FROM DIG_DOC_R00_B4 WHERE CD_PERSONA_H IS NOT NULL GROUP BY CD_PERSONA_H
    UNION ALL
    SELECT CD_PERSONA_P AS ID_FORMULARIO, 'B5' AS ORIGEN
    FROM DIG_DOC_R00_B5 WHERE CD_PERSONA_P IS NOT NULL GROUP BY CD_PERSONA_P
),
persona_flag AS (
    SELECT
        pd.NU_DOCUMENTO,
        pd.ID_FORMULARIO,
        MAX(CASE WHEN v.ORIGEN = 'B2'    THEN 1 ELSE 0 END) AS EN_B2,
        MAX(CASE WHEN v.ORIGEN = 'B4'    THEN 1 ELSE 0 END) AS EN_B4,
        MAX(CASE WHEN v.ORIGEN = 'B5'    THEN 1 ELSE 0 END) AS EN_B5,
        MAX(CASE WHEN v.ORIGEN IS NOT NULL THEN 1 ELSE 0 END) AS VINCULADA
    FROM personas_dup pd
    LEFT JOIN vinculos v ON v.ID_FORMULARIO = pd.ID_FORMULARIO
    GROUP BY pd.NU_DOCUMENTO, pd.ID_FORMULARIO
),
grupo AS (
    SELECT
        NU_DOCUMENTO,
        COUNT(*)           AS CANT_IDS,
        SUM(VINCULADA)     AS CANT_VINCULADAS,
        SUM(EN_B2)         AS CANT_EN_B2,
        SUM(EN_B4)         AS CANT_EN_B4,
        SUM(EN_B5)         AS CANT_EN_B5
    FROM persona_flag
    GROUP BY NU_DOCUMENTO
),
clasificado AS (
    SELECT
        g.NU_DOCUMENTO, g.CANT_IDS, g.CANT_VINCULADAS,
        g.CANT_EN_B2, g.CANT_EN_B4, g.CANT_EN_B5,
        CASE
            WHEN g.CANT_VINCULADAS = 0 THEN '3 - SIN VINCULO A MATRICULA'
            WHEN g.CANT_VINCULADAS = 1 THEN '2 - UN SOLO VINCULADO'
            ELSE                            '1 - VARIOS VINCULADOS'
        END AS CATEGORIA
    FROM grupo g
)
SELECT
    CATEGORIA,
    COUNT(*)                                             AS GRUPOS,
    SUM(CANT_IDS)                                        AS REGISTROS_TOTALES,
    SUM(CANT_IDS - 1)                                    AS REGISTROS_REDUNDANTES,
    SUM(CANT_VINCULADAS)                                 AS PERSONAS_VINCULADAS,
    SUM(GREATEST(CANT_VINCULADAS - 1, 0))                AS PERSONAS_A_REASIGNAR,
    SUM(CASE WHEN CANT_EN_B2 > 0 THEN 1 ELSE 0 END)      AS GRUPOS_CON_ALGUN_ACTIVO_B2,
    SUM(CASE WHEN CANT_EN_B2 > 1 THEN 1 ELSE 0 END)      AS GRUPOS_CON_2MAS_ACTIVOS_B2,
    SUM(CASE WHEN CANT_EN_B4 > 1 THEN 1 ELSE 0 END)      AS GRUPOS_CON_2MAS_HIST_B4,
    SUM(CASE WHEN CANT_EN_B5 > 1 THEN 1 ELSE 0 END)      AS GRUPOS_CON_2MAS_B5
FROM clasificado
GROUP BY CATEGORIA
ORDER BY CATEGORIA;

-- Chequeo de consistencia: SUM(GRUPOS) de las 3 filas tiene que dar el total de
-- grupos del corte del día (121.793 en el Excel, 121.852 en el corte del 16/09
-- — ver CLAUDE.md §3, nota de drift), y SUM(REGISTROS_REDUNDANTES) = 162.491.
-- Si no cierra, el WHERE de grupos_dup dejó de ser idéntico al de la query que
-- produjo esos totales.
--
-- PERSONAS_A_REASIGNAR cuenta PERSONAS perdedoras con vínculo, no FILAS de FK a
-- mover: un mismo ID_FORMULARIO aparece hasta 60 veces en B4 (§7). El conteo de
-- filas reales está en vinculadas_matriculas_afectadas.sql.
