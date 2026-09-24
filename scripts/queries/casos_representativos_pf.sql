-- CASOS REPRESENTATIVOS de personas físicas duplicadas — hoja de detalle del
-- entregable del 18/09/2026 para Mónica.
--
-- QUÉ TRAE: registro por registro de DIG_DOC_R62, para dos conjuntos de
-- documentos que se complementan:
--
--   a) MUESTRA ALEATORIA — los 60 documentos ya sorteados el 17/09 por
--      vinculadas_matricula_real_muestra.sql (30 P1 / 20 P2 / 10 P3, con el
--      mismo ORA_HASH semilla 42, así que el lote es EL MISMO). Es la parte
--      defendible: permite decir "de una muestra aleatoria del universo de
--      trabajo, tantos casos se comportan así".
--
--   b) EMBLEMÁTICOS — 8 documentos elegidos a mano, uno por cada patrón ya
--      documentado en el informe del 17/09 (Anexos I y II) y en el Excel de
--      revisión manual. Es la parte mostrable: cada uno ilustra una causa
--      distinta del mismo problema.
--
-- La columna CASO dice de cuál de los dos viene cada fila, para que no se
-- mezclen al leer: los emblemáticos NO son una muestra y no sirven para
-- estimar proporciones (CLAUDE.md §7, "corrección metodológica sobre la
-- muestra").
--
-- COLUMNAS PEDIDAS POR EL USUARIO (18/09): CD_SEXO, CD_USER_STORE (origen
-- migración vs. WORKFLOW) y una columna vacía de fecha de fallecimiento —
-- ese dato NO existe en ninguna tabla de SIRCLAN (se verificó el catálogo
-- completo de DIG_DOC_R62), lo trae la API de RENAPER y es uno de los campos
-- a agregar en el modelo PostgreSQL. Las columnas VALIDADO_RENAPER /
-- FECHA_FALLECIMIENTO / SEXO_RENAPER / NOMBRE_RENAPER_OK / OBSERVACIONES
-- salen VACÍAS a propósito: las completa el usuario a mano. Esta query no
-- llama a la API (CLAUDE.md §0).
--
-- DT_NACIMIENTO se agrega aunque no estaba pedida: es el desempate más fuerte
-- para decidir si dos registros con el mismo documento son la misma persona o
-- personas distintas (CLAUDE.md §7, "personas mezcladas").
--
-- Corrida 18/09/2026 con RunQuery --csv.

-- ===========================================================================
-- Bloque 1: un registro de DIG_DOC_R62 por fila. Mantiene los nombres de
-- columna que EvaluadorLote.java busca (ESTRATO, NU_DOCUMENTO, ID_FORMULARIO,
-- NM_NOMBRE, NM_APELLIDO, CD_SEXO, NU_CUIL_CUIT, NU_CUIL_CUIT_STR,
-- SCORE_COMPLETITUD, DT_LAST_UPDATE); las demás las ignora sin romperse.
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
           MAX(CASE WHEN v.ORIGEN = 'B2' THEN 1 ELSE 0 END)        AS EN_B2,
           MAX(CASE WHEN v.ORIGEN IS NOT NULL THEN 1 ELSE 0 END)   AS VINCULADA,
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
    SELECT NU_DOCUMENTO FROM numerado
    WHERE (PRIORIDAD = 'P1' AND RN <= 30)
       OR (PRIORIDAD = 'P2' AND RN <= 20)
       OR (PRIORIDAD = 'P3' AND RN <= 10)
),
-- Los 8 emblemáticos. Cada uno referenciado a dónde ya está documentado, para
-- que cualquiera pueda rastrear de dónde salió y por qué está elegido.
-- OJO con los literales: RunQuery corta todo lo que sigue a "--" antes de
-- partir por ";", así que estas etiquetas no pueden contener ninguno de los dos.
emblematicos AS (
    SELECT CAST('24506089' AS VARCHAR2(20)) AS NU_DOCUMENTO,
           CAST('EMBLEMATICO 1 - DOBLE SUBMIT (9 cargas identicas en una matricula vigente)' AS VARCHAR2(120)) AS CASO FROM DUAL
    UNION ALL SELECT '14041005', 'EMBLEMATICO 2 - COPROPIEDAD GRANDE (la misma persona con dos porcentajes)' FROM DUAL
    UNION ALL SELECT '26557033', 'EMBLEMATICO 3 - VARIANTE DE TIPEO EN EL APELLIDO (BOURGET / BOURGUET)' FROM DUAL
    UNION ALL SELECT '21949584', 'EMBLEMATICO 4 - POSIBLES DOS PERSONAS DISTINTAS (NO fusionar)' FROM DUAL
    UNION ALL SELECT '6899569',  'EMBLEMATICO 5 - DOS PERSONAS REALES BAJO UN MISMO DOCUMENTO' FROM DUAL
    UNION ALL SELECT '8145732',  'EMBLEMATICO 6 - REDUNDANCIA MASIVA DE FK (un ID_FORMULARIO 61 veces en B4)' FROM DUAL
    UNION ALL SELECT '6903524',  'EMBLEMATICO 7 - CUIL CON PREFIJO 24 (falso negativo contra la API)' FROM DUAL
    UNION ALL SELECT '25007077', 'EMBLEMATICO 8 - MEZCLADOS EXTREMO (fuera del universo, sin titularidad)' FROM DUAL
),
-- Si un emblemático cayera además en la muestra sorteada, el MIN() se queda
-- con la etiqueta del emblemático y el documento no se duplica.
documentos_caso AS (
    SELECT NU_DOCUMENTO, MIN(CASO) AS CASO
    FROM (
        SELECT NU_DOCUMENTO, CAST('MUESTRA ALEATORIA' AS VARCHAR2(120)) AS CASO FROM muestra
        UNION ALL
        SELECT NU_DOCUMENTO, CASO FROM emblematicos
    )
    GROUP BY NU_DOCUMENTO
)
SELECT
    dc.CASO,
    NVL(e.PRIORIDAD, 'FUERA') || '-' || NVL(e.ESTRATO_TAMANIO, 'ALCANCE') AS ESTRATO,
    dc.NU_DOCUMENTO,
    p.ID_FORMULARIO,
    p.NM_APELLIDO,
    p.NM_NOMBRE,
    p.CD_SEXO,
    CASE p.CD_SEXO WHEN 1 THEN 'FEMENINO'
                   WHEN 2 THEN 'MASCULINO'
                   WHEN 0 THEN 'CERO (anomalo en persona fisica)'
                   ELSE        'SIN DATO' END                  AS SEXO_EN_LA_BASE,
    TO_CHAR(p.DT_NACIMIENTO, 'YYYY-MM-DD')                     AS DT_NACIMIENTO,
    p.TP_DOCUMENTO,
    p.NU_DOCUMENTO_STR,
    p.NU_CUIL_CUIT,
    p.NU_CUIL_CUIT_STR,
    p.CD_NACIONALIDAD,
    p.CD_ESTADO_CIVIL,
    p.IN_BAJA_LOGICA,
    p.CD_USER_STORE,
    CASE WHEN p.CD_USER_STORE = 'WORKFLOW' THEN 'WORKFLOW (cargado en el sistema)'
         ELSE 'MIGRACION (' || p.CD_USER_STORE || ')' END      AS ORIGEN_DEL_REGISTRO,
    TO_CHAR(p.DT_STORE, 'YYYY-MM-DD HH24:MI:SS')               AS DT_STORE,
    p.CD_USER_LAST_UPDATE,
    TO_CHAR(p.DT_LAST_UPDATE, 'YYYY-MM-DD HH24:MI:SS')         AS DT_LAST_UPDATE,
    p.MIG_ID_PERSONA,
    NVL(pf.VINCULADA, 0)                                       AS TIENE_MATRICULA_REAL,
    NVL(pf.EN_B2, 0)                                           AS ES_TITULAR_ACTIVO,
    NVL(pf.FILAS_B2, 0)                                        AS FILAS_B2,
    NVL(pf.FILAS_B4, 0)                                        AS FILAS_B4,
    NVL(pf.FILAS_B5, 0)                                        AS FILAS_B5,
    e.CANT_IDS                                                 AS REGISTROS_EN_EL_GRUPO,
    e.CANT_VINCULADAS                                          AS VINCULADAS_EN_EL_GRUPO,
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
    )                                                          AS SCORE_COMPLETITUD,
    -- Columnas a completar A MANO contra RENAPER. Van vacías desde la base.
    CAST(NULL AS VARCHAR2(20))  AS VALIDADO_RENAPER,
    CAST(NULL AS VARCHAR2(20))  AS FECHA_FALLECIMIENTO,
    CAST(NULL AS VARCHAR2(20))  AS SEXO_RENAPER,
    CAST(NULL AS VARCHAR2(20))  AS NOMBRE_RENAPER_OK,
    CAST(NULL AS VARCHAR2(200)) AS OBSERVACIONES
FROM documentos_caso dc
JOIN DIG_DOC_R62 p    ON p.NU_DOCUMENTO = dc.NU_DOCUMENTO AND p.TP_PERSONA = 'PF'
LEFT JOIN etiquetado e   ON e.NU_DOCUMENTO = dc.NU_DOCUMENTO
LEFT JOIN persona_flag pf ON pf.ID_FORMULARIO = p.ID_FORMULARIO
ORDER BY dc.CASO, dc.NU_DOCUMENTO, p.ID_FORMULARIO;

-- Ojo al revisar: el grupo viene COMPLETO (vinculados y no vinculados). El
-- filtro de matrícula elige QUÉ GRUPOS entran, no qué filas se miran adentro
-- (CLAUDE.md §5). TIENE_MATRICULA_REAL y ES_TITULAR_ACTIVO marcan cuáles de
-- esas filas arrastran titularidad.

-- ===========================================================================
-- Bloque 2: qué matrículas cuelgan de cada uno de esos registros. Una fila por
-- (persona, tabla, matrícula) — es lo que hace falta para decidir a mano si
-- son la misma persona o personas distintas, y para ver el impacto registral
-- de cada caso.
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
    SELECT NU_DOCUMENTO FROM numerado
    WHERE (PRIORIDAD = 'P1' AND RN <= 30)
       OR (PRIORIDAD = 'P2' AND RN <= 20)
       OR (PRIORIDAD = 'P3' AND RN <= 10)
),
emblematicos AS (
    SELECT CAST('24506089' AS VARCHAR2(20)) AS NU_DOCUMENTO,
           CAST('EMBLEMATICO 1 - DOBLE SUBMIT (9 cargas identicas en una matricula vigente)' AS VARCHAR2(120)) AS CASO FROM DUAL
    UNION ALL SELECT '14041005', 'EMBLEMATICO 2 - COPROPIEDAD GRANDE (la misma persona con dos porcentajes)' FROM DUAL
    UNION ALL SELECT '26557033', 'EMBLEMATICO 3 - VARIANTE DE TIPEO EN EL APELLIDO (BOURGET / BOURGUET)' FROM DUAL
    UNION ALL SELECT '21949584', 'EMBLEMATICO 4 - POSIBLES DOS PERSONAS DISTINTAS (NO fusionar)' FROM DUAL
    UNION ALL SELECT '6899569',  'EMBLEMATICO 5 - DOS PERSONAS REALES BAJO UN MISMO DOCUMENTO' FROM DUAL
    UNION ALL SELECT '8145732',  'EMBLEMATICO 6 - REDUNDANCIA MASIVA DE FK (un ID_FORMULARIO 61 veces en B4)' FROM DUAL
    UNION ALL SELECT '6903524',  'EMBLEMATICO 7 - CUIL CON PREFIJO 24 (falso negativo contra la API)' FROM DUAL
    UNION ALL SELECT '25007077', 'EMBLEMATICO 8 - MEZCLADOS EXTREMO (fuera del universo, sin titularidad)' FROM DUAL
),
documentos_caso AS (
    SELECT NU_DOCUMENTO, MIN(CASO) AS CASO
    FROM (
        SELECT NU_DOCUMENTO, CAST('MUESTRA ALEATORIA' AS VARCHAR2(120)) AS CASO FROM muestra
        UNION ALL
        SELECT NU_DOCUMENTO, CASO FROM emblematicos
    )
    GROUP BY NU_DOCUMENTO
),
personas_caso AS (
    SELECT dc.CASO, dc.NU_DOCUMENTO, p.ID_FORMULARIO, p.NM_APELLIDO, p.NM_NOMBRE
    FROM documentos_caso dc
    JOIN DIG_DOC_R62 p ON p.NU_DOCUMENTO = dc.NU_DOCUMENTO AND p.TP_PERSONA = 'PF'
),
-- Una tabla "muchos" por rama, unida solo contra DIG_DOC_R00 (§4). Todas las
-- ramas castean a VARCHAR2: el UNION ALL exige el mismo tipo columna por
-- columna y un NULL pelado no tiene tipo (ORA-01790, ya pisado).
titularidades AS (
    SELECT t.CD_PERSONA AS ID_FORMULARIO, 'B2 - ACTIVO' AS TABLA,
           TO_CHAR(i.ID_MATRICULA)                AS ID_MATRICULA,
           TO_CHAR(i.NU_MATRICULA)                AS NU_MATRICULA,
           TO_CHAR(i.CD_ESTADO)                   AS CD_ESTADO,
           SUBSTR(TO_CHAR(i.DS_INMUEBLE), 1, 120) AS DS_INMUEBLE,
           TO_CHAR(t.DS_PORCENTAJE)               AS PORCENTAJE,
           TO_CHAR(t.DT_DESDE, 'YYYY-MM-DD')      AS DESDE,
           CAST(NULL AS VARCHAR2(10))             AS HASTA
    FROM DIG_DOC_R00_B2 t JOIN DIG_DOC_R00 i ON i.ID_MATRICULA = t.ID_MATRICULA
    WHERE i.NU_MATRICULA IS NOT NULL AND NVL(t.ELIMINADO, 0) = 0
    UNION ALL
    SELECT t.CD_PERSONA_H, 'B4 - HISTORICO',
           TO_CHAR(i.ID_MATRICULA),
           TO_CHAR(i.NU_MATRICULA),
           TO_CHAR(i.CD_ESTADO),
           SUBSTR(TO_CHAR(i.DS_INMUEBLE), 1, 120),
           TO_CHAR(t.NU_NUMERAD_2) || '/' || TO_CHAR(t.NU_DENOMINAD_2),
           TO_CHAR(t.DT_DES_2, 'YYYY-MM-DD'),
           TO_CHAR(t.DT_HASTA,  'YYYY-MM-DD')
    FROM DIG_DOC_R00_B4 t JOIN DIG_DOC_R00 i ON i.ID_MATRICULA = t.ID_MATRICULA
    WHERE i.NU_MATRICULA IS NOT NULL
    UNION ALL
    SELECT t.CD_PERSONA_P, 'B5 - NO VIGENTE',
           TO_CHAR(i.ID_MATRICULA),
           TO_CHAR(i.NU_MATRICULA),
           TO_CHAR(i.CD_ESTADO),
           SUBSTR(TO_CHAR(i.DS_INMUEBLE), 1, 120),
           CAST(NULL AS VARCHAR2(40)),
           CAST(NULL AS VARCHAR2(10)),
           TO_CHAR(t.DT_HAS_2, 'YYYY-MM-DD')
    FROM DIG_DOC_R00_B5 t JOIN DIG_DOC_R00 i ON i.ID_MATRICULA = t.ID_MATRICULA
    WHERE i.NU_MATRICULA IS NOT NULL AND NVL(t.ELIMINADO, 0) = 0
)
SELECT
    pc.CASO,
    pc.NU_DOCUMENTO,
    pc.ID_FORMULARIO,
    pc.NM_APELLIDO,
    pc.NM_NOMBRE,
    tt.TABLA,
    tt.ID_MATRICULA,
    tt.NU_MATRICULA,
    tt.CD_ESTADO,
    tt.DS_INMUEBLE,
    tt.PORCENTAJE,
    tt.DESDE,
    tt.HASTA
FROM personas_caso pc
JOIN titularidades tt ON tt.ID_FORMULARIO = pc.ID_FORMULARIO
ORDER BY pc.CASO, pc.NU_DOCUMENTO, tt.TABLA, tt.NU_MATRICULA, pc.ID_FORMULARIO;
