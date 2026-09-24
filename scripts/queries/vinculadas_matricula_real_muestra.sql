-- Lote de revisión manual sobre el universo vinculado a matrícula REAL.
--
-- Reemplaza a vinculadas_muestra_estratificada.sql: mismo diseño (aleatoria,
-- estratificada por prioridad P1/P2/P3, grupo traído completo) pero contando
-- como "vinculada" SOLO a la persona que cuelga de un inmueble con
-- NU_MATRICULA cargado — ver vinculadas_matricula_real_kpi_pf.sql para el
-- porqué del cambio.
--
-- DOS DIFERENCIAS ÚTILES respecto de la muestra del 16/09:
--
-- 1) MUESTRA REPRODUCIBLE. Se usa ORA_HASH(NU_DOCUMENTO, ...) en vez de
--    DBMS_RANDOM: el orden es pseudo-aleatorio pero DETERMINÍSTICO, así que
--    los bloques 1 y 2 devuelven exactamente el mismo conjunto de documentos y
--    volver a correr la query mañana da el mismo lote. Para sortear otro lote
--    distinto, cambiar la semilla 42 del ORA_HASH.
--
-- 2) TRAE LAS MATRÍCULAS. El bloque 2 lista, para los mismos documentos, qué
--    matrículas reales cuelgan de cada ID_FORMULARIO y en qué tabla — que es
--    lo que hace falta para decidir a mano si son la misma persona o personas
--    distintas compartiendo documento.
--
-- TAMAÑO DEL LOTE: 30 P1 + 20 P2 + 10 P3 = 60 documentos (se expanden a ~150
-- filas de persona). Cambiar los RN <= N del CTE `muestra` para otro tamaño.
--
-- ACTUALIZADO 17/09/2026: filtra ELIMINADO=1 en B2 y B5 (verificado como baja
-- lógica real, CLAUDE.md §10 y §3). RECIENTE se investigó y no se filtra
-- (correlaciona con origen migración/workflow, no con si la titularidad está
-- viva). El lote y sus matrículas ya reflejan el universo corregido.

-- ===========================================================================
-- Bloque 1: el lote, en el formato que consume EvaluadorLote.java
-- (columnas ESTRATO, NU_DOCUMENTO, ID_FORMULARIO, NM_NOMBRE, NM_APELLIDO,
-- CD_SEXO, SCORE_COMPLETITUD, DT_LAST_UPDATE; las demás las ignora).
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
    SELECT t.CD_PERSONA AS ID_FORMULARIO, 'B2' AS ORIGEN, COUNT(*) AS FILAS
    FROM DIG_DOC_R00_B2 t JOIN DIG_DOC_R00 i ON i.ID_MATRICULA = t.ID_MATRICULA
    WHERE t.CD_PERSONA IS NOT NULL AND i.NU_MATRICULA IS NOT NULL
      AND NVL(t.ELIMINADO, 0) = 0
    GROUP BY t.CD_PERSONA
    UNION ALL
    SELECT t.CD_PERSONA_H, 'B4', COUNT(*)
    FROM DIG_DOC_R00_B4 t JOIN DIG_DOC_R00 i ON i.ID_MATRICULA = t.ID_MATRICULA
    WHERE t.CD_PERSONA_H IS NOT NULL AND i.NU_MATRICULA IS NOT NULL
    GROUP BY t.CD_PERSONA_H
    UNION ALL
    SELECT t.CD_PERSONA_P, 'B5', COUNT(*)
    FROM DIG_DOC_R00_B5 t JOIN DIG_DOC_R00 i ON i.ID_MATRICULA = t.ID_MATRICULA
    WHERE t.CD_PERSONA_P IS NOT NULL AND i.NU_MATRICULA IS NOT NULL
      AND NVL(t.ELIMINADO, 0) = 0
    GROUP BY t.CD_PERSONA_P
),
persona_flag AS (
    SELECT pd.NU_DOCUMENTO, pd.ID_FORMULARIO,
           MAX(CASE WHEN v.ORIGEN = 'B2' THEN 1 ELSE 0 END)      AS EN_B2,
           MAX(CASE WHEN v.ORIGEN IS NOT NULL THEN 1 ELSE 0 END) AS VINCULADA,
           NVL(SUM(CASE WHEN v.ORIGEN = 'B2' THEN v.FILAS END), 0) AS FILAS_B2,
           NVL(SUM(CASE WHEN v.ORIGEN = 'B4' THEN v.FILAS END), 0) AS FILAS_B4,
           NVL(SUM(CASE WHEN v.ORIGEN = 'B5' THEN v.FILAS END), 0) AS FILAS_B5
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
),
etiquetado AS (
    SELECT NU_DOCUMENTO, CANT_IDS, CANT_VINCULADAS, CANT_EN_B2,
           CASE WHEN CANT_EN_B2 > 1 THEN 'P1'
                WHEN CANT_EN_B2 = 1 THEN 'P2'
                ELSE                     'P3' END AS PRIORIDAD,
           CASE WHEN CANT_IDS BETWEEN 2 AND 3  THEN 'BAJO'
                WHEN CANT_IDS BETWEEN 4 AND 6  THEN 'MEDIO'
                WHEN CANT_IDS BETWEEN 7 AND 10 THEN 'ALTO'
                ELSE                                'MUY_ALTO' END AS ESTRATO_TAMANIO
    FROM grupo
),
numerado AS (
    SELECT e.*,
           ROW_NUMBER() OVER (PARTITION BY PRIORIDAD
                              ORDER BY ORA_HASH(NU_DOCUMENTO, 4294967295, 42)) AS RN
    FROM etiquetado e
),
muestra AS (
    SELECT * FROM numerado
    WHERE (PRIORIDAD = 'P1' AND RN <= 30)
       OR (PRIORIDAD = 'P2' AND RN <= 20)
       OR (PRIORIDAD = 'P3' AND RN <= 10)
)
SELECT
    m.PRIORIDAD || '-' || m.ESTRATO_TAMANIO AS ESTRATO,
    m.NU_DOCUMENTO,
    p.ID_FORMULARIO,
    p.NM_NOMBRE,
    p.NM_APELLIDO,
    p.CD_SEXO,
    p.NU_CUIL_CUIT,
    p.NU_CUIL_CUIT_STR,
    pf.VINCULADA      AS TIENE_MATRICULA_REAL,
    pf.EN_B2          AS ES_TITULAR_ACTIVO,
    pf.FILAS_B2       AS FILAS_B2,
    pf.FILAS_B4       AS FILAS_B4,
    pf.FILAS_B5       AS FILAS_B5,
    m.CANT_IDS        AS REGISTROS_EN_EL_GRUPO,
    m.CANT_VINCULADAS AS VINCULADAS_EN_EL_GRUPO,
    (
        (CASE WHEN p.DS_CALLE           IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN p.DS_NUMERO          IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN p.CD_LOCALIDAD       IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN p.DT_NACIMIENTO      IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN p.DS_EMAIL           IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN p.NU_CELULAR         IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN p.NU_TELEFONO        IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN p.CD_ESTADO_CIVIL    IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN p.NM_NOMBRE_CONYUGUE IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN p.CD_NACIONALIDAD    IS NOT NULL THEN 1 ELSE 0 END)
    )                 AS SCORE_COMPLETITUD,
    TO_CHAR(p.DT_LAST_UPDATE, 'YYYY-MM-DD HH24:MI:SS') AS DT_LAST_UPDATE
FROM muestra m
JOIN DIG_DOC_R62 p   ON p.NU_DOCUMENTO = m.NU_DOCUMENTO AND p.TP_PERSONA = 'PF'
JOIN persona_flag pf ON pf.ID_FORMULARIO = p.ID_FORMULARIO
ORDER BY m.PRIORIDAD, m.NU_DOCUMENTO, p.ID_FORMULARIO;

-- Ojo al revisar: el grupo viene COMPLETO (vinculados y no vinculados). El
-- filtro de matrícula elige QUÉ GRUPOS entran, no qué filas se miran adentro
-- (CLAUDE.md §5). TIENE_MATRICULA_REAL / ES_TITULAR_ACTIVO marcan cuáles de
-- esas filas arrastran titularidad.

-- ===========================================================================
-- Bloque 2: detalle de matrículas para EXACTAMENTE los mismos documentos del
-- bloque 1 (mismo ORA_HASH => mismo lote). Una fila por
-- (persona, tabla, matrícula). Es la columna que falta para decidir a mano.
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
),
etiquetado AS (
    SELECT NU_DOCUMENTO,
           CASE WHEN CANT_EN_B2 > 1 THEN 'P1'
                WHEN CANT_EN_B2 = 1 THEN 'P2'
                ELSE                     'P3' END AS PRIORIDAD
    FROM grupo
),
numerado AS (
    SELECT e.*,
           ROW_NUMBER() OVER (PARTITION BY PRIORIDAD
                              ORDER BY ORA_HASH(NU_DOCUMENTO, 4294967295, 42)) AS RN
    FROM etiquetado e
),
muestra AS (
    SELECT NU_DOCUMENTO, PRIORIDAD FROM numerado
    WHERE (PRIORIDAD = 'P1' AND RN <= 30)
       OR (PRIORIDAD = 'P2' AND RN <= 20)
       OR (PRIORIDAD = 'P3' AND RN <= 10)
),
personas_muestra AS (
    SELECT m.PRIORIDAD, m.NU_DOCUMENTO, p.ID_FORMULARIO,
           p.NM_NOMBRE, p.NM_APELLIDO
    FROM muestra m
    JOIN DIG_DOC_R62 p ON p.NU_DOCUMENTO = m.NU_DOCUMENTO AND p.TP_PERSONA = 'PF'
),
-- Una tabla "muchos" por rama, unida solo contra DIG_DOC_R00 (§4).
titularidades AS (
    -- Todas las ramas castean a VARCHAR2: el UNION ALL exige el mismo tipo
    -- columna por columna y un NULL pelado no tiene tipo (ORA-01790, ya pisado).
    SELECT t.CD_PERSONA AS ID_FORMULARIO, 'B2 - ACTIVO' AS TABLA,
           TO_CHAR(i.NU_MATRICULA)               AS NU_MATRICULA,
           TO_CHAR(i.CD_ESTADO)                  AS CD_ESTADO,
           SUBSTR(TO_CHAR(i.DS_INMUEBLE), 1, 80) AS DS_INMUEBLE,
           TO_CHAR(t.DS_PORCENTAJE)              AS PORCENTAJE,
           TO_CHAR(t.DT_DESDE, 'YYYY-MM-DD')     AS DESDE,
           CAST(NULL AS VARCHAR2(10))            AS HASTA
    FROM DIG_DOC_R00_B2 t JOIN DIG_DOC_R00 i ON i.ID_MATRICULA = t.ID_MATRICULA
    WHERE i.NU_MATRICULA IS NOT NULL AND NVL(t.ELIMINADO, 0) = 0
    UNION ALL
    SELECT t.CD_PERSONA_H, 'B4 - HISTORICO',
           TO_CHAR(i.NU_MATRICULA),
           TO_CHAR(i.CD_ESTADO),
           SUBSTR(TO_CHAR(i.DS_INMUEBLE), 1, 80),
           TO_CHAR(t.NU_NUMERAD_2) || '/' || TO_CHAR(t.NU_DENOMINAD_2),
           TO_CHAR(t.DT_DES_2, 'YYYY-MM-DD'),
           TO_CHAR(t.DT_HASTA,  'YYYY-MM-DD')
    FROM DIG_DOC_R00_B4 t JOIN DIG_DOC_R00 i ON i.ID_MATRICULA = t.ID_MATRICULA
    WHERE i.NU_MATRICULA IS NOT NULL
    UNION ALL
    SELECT t.CD_PERSONA_P, 'B5 - NO VIGENTE',
           TO_CHAR(i.NU_MATRICULA),
           TO_CHAR(i.CD_ESTADO),
           SUBSTR(TO_CHAR(i.DS_INMUEBLE), 1, 80),
           CAST(NULL AS VARCHAR2(40)),
           CAST(NULL AS VARCHAR2(10)),
           TO_CHAR(t.DT_HAS_2, 'YYYY-MM-DD')
    FROM DIG_DOC_R00_B5 t JOIN DIG_DOC_R00 i ON i.ID_MATRICULA = t.ID_MATRICULA
    WHERE i.NU_MATRICULA IS NOT NULL AND NVL(t.ELIMINADO, 0) = 0
)
SELECT
    pm.PRIORIDAD,
    pm.NU_DOCUMENTO,
    pm.ID_FORMULARIO,
    pm.NM_APELLIDO,
    pm.NM_NOMBRE,
    ti.TABLA,
    ti.NU_MATRICULA,
    ti.CD_ESTADO       AS ESTADO_INMUEBLE,
    ti.PORCENTAJE,
    ti.DESDE,
    ti.HASTA,
    ti.DS_INMUEBLE     AS INMUEBLE
FROM personas_muestra pm
JOIN titularidades ti ON ti.ID_FORMULARIO = pm.ID_FORMULARIO
ORDER BY pm.PRIORIDAD, pm.NU_DOCUMENTO, pm.ID_FORMULARIO, ti.TABLA, ti.NU_MATRICULA;

-- Si un mismo (NU_DOCUMENTO, NU_MATRICULA) aparece con dos ID_FORMULARIO
-- distintos en B2, es un caso de "doble titular en la misma matrícula"
-- (CLAUDE.md §3) — el hallazgo más mostrable, marcarlo en la revisión.
