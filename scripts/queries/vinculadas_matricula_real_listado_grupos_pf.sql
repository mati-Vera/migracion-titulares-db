-- LISTA DE TRABAJO DEFINITIVA: los grupos PF duplicados que hay que revisar,
-- sobre el universo del corte del 17/09/2026 (matrícula REAL + sin bajas
-- lógicas). Una fila por grupo, ordenada por prioridad — es la hoja Detalle
-- del entregable para Mónica.
--
-- POR QUÉ ESTA QUERY EXISTE: vinculadas_listado_grupos_pf.sql (16/09) prioriza
-- sobre los 60.847 grupos del corte viejo, que contaba como "vinculada" a
-- cualquier persona presente en B2/B4/B5 sin mirar si el inmueble tiene
-- NU_MATRICULA real, y sin filtrar ELIMINADO. Era el pendiente de CLAUDE.md
-- §10 ("Rehacer vinculadas_listado_grupos_pf.sql con el filtro de matrícula
-- real + ELIMINADO: hoy prioriza sobre los 60.847, no sobre los 55.918").
--
-- Los dos filtros salen tal cual de vinculadas_matricula_real_kpi_pf.sql, para
-- que los totales cierren exactos contra CLAUDE.md §3 "Corte con matrícula
-- REAL":
--   1. JOIN contra DIG_DOC_R00 exigiendo NU_MATRICULA IS NOT NULL (cualquier
--      CD_ESTADO; las BAJ quedan dentro del alcance por decisión del usuario
--      del 17/09, CLAUDE.md §5).
--   2. NVL(ELIMINADO,0) = 0 en B2 y B5 (B4 no tiene la columna). Verificado el
--      17/09 como baja lógica real, CLAUDE.md §3.
--
-- CHEQUEO OBLIGATORIO ANTES DE ENTREGAR: el resultado tiene que dar 55.918
-- filas, partidas en 30.136 P1 / 17.449 P2 / 8.333 P3. Si no cierra contra
-- CLAUDE.md §3, el filtro quedó mal y NO se exporta.
--
-- Criterio de prioridad (idéntico al de la query del 16/09, pero contando
-- solo vínculos a matrícula real y vivos):
--   P1 - 2+ registros en B2: la misma persona figura dos veces como titular
--        VIGENTE de una matrícula real. Es el caso que rompe datos hoy.
--   P2 - 1 en B2 + otros en B4/B5: hay un activo claro; los demás vínculos
--        son históricos que igual hay que reasignar al fusionar (§5).
--   P3 - 2+ vinculados pero ninguno activo: todo histórico (B4/B5).
--
-- Corrida 18/09/2026 con RunQuery --csv.

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
-- Cada tabla de titularidad se agrupa por persona ANTES de cruzarse con las
-- demás: nunca se unen dos tablas "muchos" en el mismo SELECT (CLAUDE.md §4).
vinculos AS (
    SELECT t.CD_PERSONA AS ID_FORMULARIO, 'B2' AS ORIGEN,
           COUNT(*) AS FILAS, COUNT(DISTINCT t.ID_MATRICULA) AS MATRICULAS
    FROM DIG_DOC_R00_B2 t
    JOIN DIG_DOC_R00 i ON i.ID_MATRICULA = t.ID_MATRICULA
    WHERE t.CD_PERSONA IS NOT NULL AND i.NU_MATRICULA IS NOT NULL
      AND NVL(t.ELIMINADO, 0) = 0
    GROUP BY t.CD_PERSONA
    UNION ALL
    SELECT t.CD_PERSONA_H AS ID_FORMULARIO, 'B4' AS ORIGEN,
           COUNT(*), COUNT(DISTINCT t.ID_MATRICULA)
    FROM DIG_DOC_R00_B4 t
    JOIN DIG_DOC_R00 i ON i.ID_MATRICULA = t.ID_MATRICULA
    WHERE t.CD_PERSONA_H IS NOT NULL AND i.NU_MATRICULA IS NOT NULL
    GROUP BY t.CD_PERSONA_H
    UNION ALL
    SELECT t.CD_PERSONA_P AS ID_FORMULARIO, 'B5' AS ORIGEN,
           COUNT(*), COUNT(DISTINCT t.ID_MATRICULA)
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
        MAX(CASE WHEN v.ORIGEN IS NOT NULL THEN 1 ELSE 0 END) AS VINCULADA,
        NVL(SUM(v.FILAS), 0)                                  AS FILAS_TITULARIDAD,
        NVL(SUM(v.MATRICULAS), 0)                             AS MATRICULAS_PERSONA
    FROM personas_dup pd
    LEFT JOIN vinculos v ON v.ID_FORMULARIO = pd.ID_FORMULARIO
    GROUP BY pd.NU_DOCUMENTO, pd.ID_FORMULARIO
),
grupo AS (
    SELECT
        NU_DOCUMENTO,
        COUNT(*)                AS CANT_IDS,
        SUM(VINCULADA)          AS CANT_VINCULADAS,
        SUM(EN_B2)              AS CANT_EN_B2,
        SUM(EN_B4)              AS CANT_EN_B4,
        SUM(EN_B5)              AS CANT_EN_B5,
        SUM(FILAS_TITULARIDAD)  AS FILAS_TITULARIDAD_GRUPO,
        SUM(MATRICULAS_PERSONA) AS MATRICULAS_GRUPO
    FROM persona_flag
    GROUP BY NU_DOCUMENTO
    HAVING SUM(VINCULADA) > 1
),
-- IDs vinculados del grupo, acotados a 10 para no reventar LISTAGG
-- (ORA-01489 a los 4000 bytes, CLAUDE.md §4).
ids_num AS (
    SELECT NU_DOCUMENTO, ID_FORMULARIO, FILAS_TITULARIDAD,
           ROW_NUMBER() OVER (PARTITION BY NU_DOCUMENTO
                              ORDER BY EN_B2 DESC, FILAS_TITULARIDAD DESC, ID_FORMULARIO) AS RN
    FROM persona_flag
    WHERE VINCULADA = 1
),
ids_listado AS (
    SELECT NU_DOCUMENTO,
           LISTAGG(ID_FORMULARIO || '(' || FILAS_TITULARIDAD || ')', ' ')
               WITHIN GROUP (ORDER BY RN) AS IDS_VINCULADOS
    FROM ids_num
    WHERE RN <= 10
    GROUP BY NU_DOCUMENTO
)
SELECT
    CASE
        WHEN g.CANT_EN_B2 > 1 THEN 'P1 - DOS O MAS ACTIVOS'
        WHEN g.CANT_EN_B2 = 1 THEN 'P2 - UN ACTIVO + HISTORICOS'
        ELSE                       'P3 - SOLO HISTORICOS'
    END                                 AS PRIORIDAD,
    CASE
        WHEN g.CANT_IDS BETWEEN 2 AND 3  THEN 'BAJO'
        WHEN g.CANT_IDS BETWEEN 4 AND 6  THEN 'MEDIO'
        WHEN g.CANT_IDS BETWEEN 7 AND 10 THEN 'ALTO'
        ELSE                                  'MUY_ALTO'
    END                                 AS ESTRATO,
    g.NU_DOCUMENTO,
    g.CANT_IDS                          AS REGISTROS_EN_R62,
    g.CANT_VINCULADAS                   AS REGISTROS_CON_MATRICULA,
    g.CANT_EN_B2                        AS EN_B2_ACTIVOS,
    g.CANT_EN_B4                        AS EN_B4_HISTORICOS,
    g.CANT_EN_B5                        AS EN_B5_NO_VIGENTES,
    g.FILAS_TITULARIDAD_GRUPO           AS FILAS_FK_A_REVISAR,
    g.MATRICULAS_GRUPO                  AS MATRICULAS_TOCADAS,
    l.IDS_VINCULADOS
FROM grupo g
JOIN ids_listado l ON l.NU_DOCUMENTO = g.NU_DOCUMENTO
ORDER BY PRIORIDAD, g.CANT_EN_B2 DESC, g.FILAS_TITULARIDAD_GRUPO DESC, g.NU_DOCUMENTO;

-- IDS_VINCULADOS trae "ID_FORMULARIO(filas de titularidad)" de los primeros 10
-- vinculados, con los activos primero — para tener a mano el candidato sin
-- abrir otra query. El detalle completo de cada documento sigue saliendo de
-- consultas.sql (queries 1 a 4) pasándole :p_nu_documento.
--
-- MATRICULAS_TOCADAS suma por persona, así que una matrícula compartida por
-- dos registros del mismo grupo se cuenta dos veces: es la cota superior del
-- trabajo de reasignación, no el conteo de inmuebles distintos. Para inmuebles
-- distintos está vinculadas_matriculas_afectadas.sql.
