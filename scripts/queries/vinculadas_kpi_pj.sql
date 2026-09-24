-- Mismo filtro de Mónica (16/09/2026) aplicado a PERSONAS JURÍDICAS: de los
-- grupos de CUIT duplicado, cuáles tienen registros vinculados a una matrícula.
--
-- Base: pj_kpi_sin_placeholder.sql (CUIT normalizado, se excluyen SIN_CUIT,
-- longitud <> 11 y el placeholder '30999078040'). Resultado de ese corte al
-- 16/09/2026: 5.814 grupos / 12.787 registros redundantes (CLAUDE.md §3).
--
-- Importa más que en PF: ~42% de las PJ no tiene CUIT utilizable y no es
-- deduplicable automáticamente (§3). Saber cuántas de esas realmente sostienen
-- una titularidad dice si esa deuda técnica hay que atacarla ahora o queda
-- documentada y listo.
--
-- PENDIENTE DE CORRER.

WITH juridicas AS (
    SELECT p.ID_FORMULARIO,
        NVL(NULLIF(TRIM(TO_CHAR(p.NU_CUIL_CUIT)), ''),
            REGEXP_REPLACE(p.NU_CUIL_CUIT_STR, '[^0-9]', '')) AS CUIT_NORMALIZADO
    FROM DIG_DOC_R62 p
    WHERE p.TP_PERSONA <> 'PF'
),
validas AS (
    SELECT ID_FORMULARIO, CUIT_NORMALIZADO
    FROM juridicas
    WHERE CUIT_NORMALIZADO IS NOT NULL
      AND LENGTH(CUIT_NORMALIZADO) = 11
      AND CUIT_NORMALIZADO <> '30999078040'
),
grupos_dup AS (
    SELECT CUIT_NORMALIZADO
    FROM validas
    GROUP BY CUIT_NORMALIZADO
    HAVING COUNT(*) > 1
),
personas_dup AS (
    SELECT v.CUIT_NORMALIZADO, v.ID_FORMULARIO
    FROM validas v
    JOIN grupos_dup g ON g.CUIT_NORMALIZADO = v.CUIT_NORMALIZADO
),
vinculos AS (
    SELECT CD_PERSONA   AS ID_FORMULARIO, 'B2' AS ORIGEN FROM DIG_DOC_R00_B2 WHERE CD_PERSONA   IS NOT NULL GROUP BY CD_PERSONA
    UNION ALL
    SELECT CD_PERSONA_H AS ID_FORMULARIO, 'B4' AS ORIGEN FROM DIG_DOC_R00_B4 WHERE CD_PERSONA_H IS NOT NULL GROUP BY CD_PERSONA_H
    UNION ALL
    SELECT CD_PERSONA_P AS ID_FORMULARIO, 'B5' AS ORIGEN FROM DIG_DOC_R00_B5 WHERE CD_PERSONA_P IS NOT NULL GROUP BY CD_PERSONA_P
),
persona_flag AS (
    SELECT
        pd.CUIT_NORMALIZADO,
        pd.ID_FORMULARIO,
        MAX(CASE WHEN v.ORIGEN = 'B2' THEN 1 ELSE 0 END)      AS EN_B2,
        MAX(CASE WHEN v.ORIGEN IS NOT NULL THEN 1 ELSE 0 END) AS VINCULADA
    FROM personas_dup pd
    LEFT JOIN vinculos v ON v.ID_FORMULARIO = pd.ID_FORMULARIO
    GROUP BY pd.CUIT_NORMALIZADO, pd.ID_FORMULARIO
),
grupo AS (
    SELECT CUIT_NORMALIZADO,
           COUNT(*)       AS CANT_IDS,
           SUM(VINCULADA) AS CANT_VINCULADAS,
           SUM(EN_B2)     AS CANT_EN_B2
    FROM persona_flag
    GROUP BY CUIT_NORMALIZADO
)
SELECT
    CASE
        WHEN CANT_VINCULADAS = 0 THEN '3 - SIN VINCULO A MATRICULA'
        WHEN CANT_VINCULADAS = 1 THEN '2 - UN SOLO VINCULADO'
        ELSE                          '1 - VARIOS VINCULADOS'
    END                                             AS CATEGORIA,
    COUNT(*)                                        AS GRUPOS,
    SUM(CANT_IDS)                                   AS REGISTROS_TOTALES,
    SUM(CANT_IDS - 1)                               AS REGISTROS_REDUNDANTES,
    SUM(CANT_VINCULADAS)                            AS PERSONAS_VINCULADAS,
    SUM(CASE WHEN CANT_EN_B2 > 1 THEN 1 ELSE 0 END) AS GRUPOS_CON_2MAS_ACTIVOS_B2
FROM grupo
GROUP BY
    CASE
        WHEN CANT_VINCULADAS = 0 THEN '3 - SIN VINCULO A MATRICULA'
        WHEN CANT_VINCULADAS = 1 THEN '2 - UN SOLO VINCULADO'
        ELSE                          '1 - VARIOS VINCULADOS'
    END
ORDER BY CATEGORIA;

-- Chequeo: SUM(GRUPOS) = 5.814 y SUM(REGISTROS_REDUNDANTES) = 12.787 si se
-- corre el mismo día que pj_kpi_sin_placeholder.sql. Diferencias chicas son
-- drift de la base de desarrollo entre cortes (§3), no error de la query.
--
-- Para el segmento NO deduplicable (sin CUIT o CUIT inválido), la pregunta
-- equivalente se responde cambiando "validas" por el complemento:
--   WHERE CUIT_NORMALIZADO IS NULL OR LENGTH(CUIT_NORMALIZADO) <> 11
-- y contando cuántos de esos ID_FORMULARIO aparecen en vinculos — dimensiona
-- la deuda técnica de §3 en términos de impacto registral, no de padrón.
