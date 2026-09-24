-- Universo vinculado a matrícula REAL — recorte del corte del 16/09/2026.
--
-- POR QUÉ ESTA QUERY: las `vinculadas_*.sql` del 16/09 marcan una persona como
-- "vinculada" si su ID_FORMULARIO aparece en DIG_DOC_R00_B2 / _B4 / _B5, pero
-- NUNCA joinean contra DIG_DOC_R00 para ver a qué inmueble apunta esa fila. El
-- 34,6% de DIG_DOC_R00 (277.212 de 800.829, censo del 17/09 — CLAUDE.md §3) es
-- legado Tomo/Folio SIN NU_MATRICULA. O sea: parte de los 60.847 grupos del
-- universo de trabajo puede estar vinculada solo a inmuebles de legado, que no
-- son matrículas usables.
--
-- Criterio de "matrícula real": DIG_DOC_R00.NU_MATRICULA IS NOT NULL, con
-- CUALQUIER CD_ESTADO (MIG/ACT/BAJ/CRE) — mismo criterio del censo, y las BAJ
-- quedan dentro del alcance por decisión del usuario del 17/09 (CLAUDE.md §5).
--
-- ACTUALIZADO 17/09/2026: filtra ELIMINADO=1 en B2 y B5 — verificado como baja
-- lógica real (CLAUDE.md §10 y §3 "Verificación ELIMINADO/RECIENTE"). RECIENTE
-- se investigó y NO se filtra (correlaciona con origen migración/workflow, no
-- con si la titularidad está viva). Impacto sobre este corte: categoría
-- 1 (varios vinculados) 56.135→55.918 grupos, P1 30.376→30.136.

-- ===========================================================================
-- Bloque 1: partición de los grupos PF duplicados, exigiendo matrícula REAL.
-- Comparable fila a fila contra la tabla de CLAUDE.md §3 "Corte del universo
-- vinculado a matrículas" (60.847 / 45.178 / 15.827).
-- ===========================================================================
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
-- ÚNICO cambio respecto de vinculadas_kpi_pf.sql: cada tabla de titularidad se
-- joinea contra DIG_DOC_R00 y se exige NU_MATRICULA IS NOT NULL. Se agrupa por
-- persona (no se joinea "muchos" contra "muchos"), CLAUDE.md §4.
vinculos AS (
    SELECT t.CD_PERSONA AS ID_FORMULARIO, 'B2' AS ORIGEN
    FROM DIG_DOC_R00_B2 t
    JOIN DIG_DOC_R00 i ON i.ID_MATRICULA = t.ID_MATRICULA
    WHERE t.CD_PERSONA IS NOT NULL AND i.NU_MATRICULA IS NOT NULL
      AND NVL(t.ELIMINADO, 0) = 0
    GROUP BY t.CD_PERSONA
    UNION ALL
    SELECT t.CD_PERSONA_H AS ID_FORMULARIO, 'B4' AS ORIGEN
    FROM DIG_DOC_R00_B4 t
    JOIN DIG_DOC_R00 i ON i.ID_MATRICULA = t.ID_MATRICULA
    WHERE t.CD_PERSONA_H IS NOT NULL AND i.NU_MATRICULA IS NOT NULL
    GROUP BY t.CD_PERSONA_H
    UNION ALL
    SELECT t.CD_PERSONA_P AS ID_FORMULARIO, 'B5' AS ORIGEN
    FROM DIG_DOC_R00_B5 t
    JOIN DIG_DOC_R00 i ON i.ID_MATRICULA = t.ID_MATRICULA
    WHERE t.CD_PERSONA_P IS NOT NULL AND i.NU_MATRICULA IS NOT NULL
      AND NVL(t.ELIMINADO, 0) = 0
    GROUP BY t.CD_PERSONA_P
),
persona_flag AS (
    SELECT
        pd.NU_DOCUMENTO,
        pd.ID_FORMULARIO,
        MAX(CASE WHEN v.ORIGEN = 'B2' THEN 1 ELSE 0 END)      AS EN_B2,
        MAX(CASE WHEN v.ORIGEN = 'B4' THEN 1 ELSE 0 END)      AS EN_B4,
        MAX(CASE WHEN v.ORIGEN = 'B5' THEN 1 ELSE 0 END)      AS EN_B5,
        MAX(CASE WHEN v.ORIGEN IS NOT NULL THEN 1 ELSE 0 END) AS VINCULADA
    FROM personas_dup pd
    LEFT JOIN vinculos v ON v.ID_FORMULARIO = pd.ID_FORMULARIO
    GROUP BY pd.NU_DOCUMENTO, pd.ID_FORMULARIO
),
grupo AS (
    SELECT NU_DOCUMENTO,
           COUNT(*)       AS CANT_IDS,
           SUM(VINCULADA) AS CANT_VINCULADAS,
           SUM(EN_B2)     AS CANT_EN_B2,
           SUM(EN_B4)     AS CANT_EN_B4,
           SUM(EN_B5)     AS CANT_EN_B5
    FROM persona_flag
    GROUP BY NU_DOCUMENTO
)
SELECT
    CASE
        WHEN CANT_VINCULADAS = 0 THEN '3 - SIN VINCULO A MATRICULA REAL'
        WHEN CANT_VINCULADAS = 1 THEN '2 - UN SOLO VINCULADO'
        ELSE                          '1 - VARIOS VINCULADOS'
    END                                             AS CATEGORIA,
    COUNT(*)                                        AS GRUPOS,
    SUM(CANT_IDS)                                   AS REGISTROS_TOTALES,
    SUM(CANT_IDS - 1)                               AS REGISTROS_REDUNDANTES,
    SUM(CANT_VINCULADAS)                            AS PERSONAS_VINCULADAS,
    SUM(GREATEST(CANT_VINCULADAS - 1, 0))           AS PERSONAS_A_REASIGNAR,
    SUM(CASE WHEN CANT_EN_B2 > 1 THEN 1 ELSE 0 END) AS GRUPOS_CON_2MAS_ACTIVOS_B2,
    SUM(CASE WHEN CANT_EN_B4 > 1 THEN 1 ELSE 0 END) AS GRUPOS_CON_2MAS_HIST_B4,
    SUM(CASE WHEN CANT_EN_B5 > 1 THEN 1 ELSE 0 END) AS GRUPOS_CON_2MAS_B5
FROM grupo
GROUP BY
    CASE
        WHEN CANT_VINCULADAS = 0 THEN '3 - SIN VINCULO A MATRICULA REAL'
        WHEN CANT_VINCULADAS = 1 THEN '2 - UN SOLO VINCULADO'
        ELSE                          '1 - VARIOS VINCULADOS'
    END
ORDER BY 1;

-- Chequeo: SUM(GRUPOS) tiene que seguir dando 121.852 y SUM(REGISTROS_REDUNDANTES)
-- 162.491 (el filtro mueve grupos ENTRE categorías, no saca grupos del total).
-- La categoría 1 tiene que dar <= 60.847. La diferencia contra 60.847 es
-- exactamente lo que el corte del 16/09 contaba de más por no mirar NU_MATRICULA.

-- ===========================================================================
-- Bloque 2: el universo de trabajo (categoría 1) partido por prioridad,
-- mismo criterio P1/P2/P3 de vinculadas_listado_grupos_pf.sql pero contando
-- solo vínculos a matrícula real. Comparable contra 34.055 / 19.028 / 7.764.
-- ===========================================================================
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
    SELECT t.CD_PERSONA AS ID_FORMULARIO, 'B2' AS ORIGEN
    FROM DIG_DOC_R00_B2 t JOIN DIG_DOC_R00 i ON i.ID_MATRICULA = t.ID_MATRICULA
    WHERE t.CD_PERSONA IS NOT NULL AND i.NU_MATRICULA IS NOT NULL
      AND NVL(t.ELIMINADO, 0) = 0
    GROUP BY t.CD_PERSONA
    UNION ALL
    SELECT t.CD_PERSONA_H, 'B4'
    FROM DIG_DOC_R00_B4 t JOIN DIG_DOC_R00 i ON i.ID_MATRICULA = t.ID_MATRICULA
    WHERE t.CD_PERSONA_H IS NOT NULL AND i.NU_MATRICULA IS NOT NULL
    GROUP BY t.CD_PERSONA_H
    UNION ALL
    SELECT t.CD_PERSONA_P, 'B5'
    FROM DIG_DOC_R00_B5 t JOIN DIG_DOC_R00 i ON i.ID_MATRICULA = t.ID_MATRICULA
    WHERE t.CD_PERSONA_P IS NOT NULL AND i.NU_MATRICULA IS NOT NULL
      AND NVL(t.ELIMINADO, 0) = 0
    GROUP BY t.CD_PERSONA_P
),
persona_flag AS (
    SELECT pd.NU_DOCUMENTO, pd.ID_FORMULARIO,
           MAX(CASE WHEN v.ORIGEN = 'B2' THEN 1 ELSE 0 END)      AS EN_B2,
           MAX(CASE WHEN v.ORIGEN IS NOT NULL THEN 1 ELSE 0 END) AS VINCULADA
    FROM personas_dup pd
    LEFT JOIN vinculos v ON v.ID_FORMULARIO = pd.ID_FORMULARIO
    GROUP BY pd.NU_DOCUMENTO, pd.ID_FORMULARIO
),
grupo AS (
    SELECT NU_DOCUMENTO, COUNT(*) AS CANT_IDS,
           SUM(VINCULADA) AS CANT_VINCULADAS, SUM(EN_B2) AS CANT_EN_B2
    FROM persona_flag
    GROUP BY NU_DOCUMENTO
    HAVING SUM(VINCULADA) > 1
)
SELECT
    CASE WHEN CANT_EN_B2 > 1 THEN 'P1 - DOS O MAS TITULARES ACTIVOS'
         WHEN CANT_EN_B2 = 1 THEN 'P2 - UN ACTIVO + HISTORICOS'
         ELSE                     'P3 - SOLO HISTORICOS' END AS PRIORIDAD,
    CASE WHEN CANT_IDS BETWEEN 2 AND 3  THEN 'BAJO'
         WHEN CANT_IDS BETWEEN 4 AND 6  THEN 'MEDIO'
         WHEN CANT_IDS BETWEEN 7 AND 10 THEN 'ALTO'
         ELSE                                'MUY_ALTO' END   AS ESTRATO_TAMANIO,
    COUNT(*)                  AS GRUPOS,
    SUM(CANT_IDS)             AS REGISTROS_TOTALES,
    SUM(CANT_VINCULADAS)      AS PERSONAS_VINCULADAS
FROM grupo
GROUP BY
    CASE WHEN CANT_EN_B2 > 1 THEN 'P1 - DOS O MAS TITULARES ACTIVOS'
         WHEN CANT_EN_B2 = 1 THEN 'P2 - UN ACTIVO + HISTORICOS'
         ELSE                     'P3 - SOLO HISTORICOS' END,
    CASE WHEN CANT_IDS BETWEEN 2 AND 3  THEN 'BAJO'
         WHEN CANT_IDS BETWEEN 4 AND 6  THEN 'MEDIO'
         WHEN CANT_IDS BETWEEN 7 AND 10 THEN 'ALTO'
         ELSE                                'MUY_ALTO' END
ORDER BY 1, 2;

-- ===========================================================================
-- Bloque 3: cuánto pesa el legado Tomo/Folio dentro de las tablas de
-- titularidad. Responde si el filtro de matrícula real cambia algo o no,
-- sin pasar por los grupos.
-- ===========================================================================
-- Deliberadamente SIN filtrar ELIMINADO acá: esto mide la estructura cruda de
-- cada tabla (legado vs. real, FK huérfana), no un universo de trabajo. La
-- columna FILAS_ELIMINADO se agrega para que el peso de la baja lógica quede
-- visible en la misma foto (B4 no tiene la columna → NULL).
SELECT 'B2 - ACTIVOS' AS TABLA,
       COUNT(*)                                               AS FILAS,
       COUNT(CASE WHEN i.NU_MATRICULA IS NOT NULL THEN 1 END) AS FILAS_MATRICULA_REAL,
       COUNT(CASE WHEN i.NU_MATRICULA IS NULL     THEN 1 END) AS FILAS_LEGADO_TOMO_FOLIO,
       COUNT(CASE WHEN i.ID_MATRICULA IS NULL     THEN 1 END) AS FILAS_SIN_INMUEBLE,
       COUNT(CASE WHEN t.ELIMINADO = 1             THEN 1 END) AS FILAS_ELIMINADO
FROM DIG_DOC_R00_B2 t LEFT JOIN DIG_DOC_R00 i ON i.ID_MATRICULA = t.ID_MATRICULA
UNION ALL
SELECT 'B4 - HISTORICOS', COUNT(*),
       COUNT(CASE WHEN i.NU_MATRICULA IS NOT NULL THEN 1 END),
       COUNT(CASE WHEN i.NU_MATRICULA IS NULL     THEN 1 END),
       COUNT(CASE WHEN i.ID_MATRICULA IS NULL     THEN 1 END),
       CAST(NULL AS NUMBER)
FROM DIG_DOC_R00_B4 t LEFT JOIN DIG_DOC_R00 i ON i.ID_MATRICULA = t.ID_MATRICULA
UNION ALL
SELECT 'B5 - NO VIGENTES', COUNT(*),
       COUNT(CASE WHEN i.NU_MATRICULA IS NOT NULL THEN 1 END),
       COUNT(CASE WHEN i.NU_MATRICULA IS NULL     THEN 1 END),
       COUNT(CASE WHEN i.ID_MATRICULA IS NULL     THEN 1 END),
       COUNT(CASE WHEN t.ELIMINADO = 1             THEN 1 END)
FROM DIG_DOC_R00_B5 t LEFT JOIN DIG_DOC_R00 i ON i.ID_MATRICULA = t.ID_MATRICULA;

-- FILAS_SIN_INMUEBLE > 0 sería un hallazgo aparte: titularidad apuntando a un
-- ID_MATRICULA que no existe en DIG_DOC_R00 (no hay FK declaradas, §2).
