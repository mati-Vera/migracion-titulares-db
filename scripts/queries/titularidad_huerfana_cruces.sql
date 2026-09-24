-- Cruces para encontrar la heurística de las titularidades ACTIVAS (B2) de
-- personas físicas que apuntan a un ID_MATRICULA inexistente en DIG_DOC_R00.
--
-- Origen: docs/Titulares_activos_con_matricula_inexistente.csv (volcado del
-- usuario, 477 filas, 24/09/2026) — mismo universo que el bloque B2 de
-- titularidad_matricula_inexistente.sql, acotado a PF vivas (ELIMINADO=0).
-- El CSV no trae NU_SEQUENCE, DT_MODIFICACION ni las columnas MIG_*, y no
-- permite saber si la persona o el caso de origen tienen titularidad en una
-- matrícula que SÍ existe. Esta query agrega eso; el análisis lo hace
-- scripts/analisis/analizar_titulares_huerfanos.py (o su gemelo .js).
--
-- Un solo tabla "muchos" por rama (CLAUDE.md §4): los cruces contra otras
-- filas de B2 van como subconsultas escalares con COUNT/MIN, no como JOIN.

-- ===========================================================================
-- Bloque 1: control — tiene que dar 477 (las filas del CSV).
-- ===========================================================================
SELECT COUNT(*) AS FILAS_HUERFANAS_PF_VIVAS,
       COUNT(DISTINCT b.ID_MATRICULA) AS MATRICULAS,
       COUNT(DISTINCT b.CD_PERSONA) AS PERSONAS
FROM DIG_DOC_R00_B2 b
JOIN DIG_DOC_R62 p ON p.ID_FORMULARIO = b.CD_PERSONA AND p.TP_PERSONA = 'PF'
WHERE NVL(b.ELIMINADO,0) = 0
  AND NOT EXISTS (SELECT 1 FROM DIG_DOC_R00 i WHERE i.ID_MATRICULA = b.ID_MATRICULA);

-- ===========================================================================
-- Bloque 2: detalle fila por fila con los cruces.
--   PERSONA_EN_MAT_EXISTENTE  : filas vivas de B2 de ese mismo CD_PERSONA en
--                               una matrícula que sí existe.
--   DOC_EN_MAT_EXISTENTE      : idem, pero para cualquier registro de R62 con
--                               el mismo NU_DOCUMENTO (captura el duplicado).
--   CASO_EN_MAT_EXISTENTE     : filas vivas de B2 con el mismo NU_CASO_ORIGEN
--                               en una matrícula que sí existe (¿el trámite
--                               terminó creando la matrícula con otro ID?).
--   CASO_ID_MAT_EXISTENTE     : el menor de esos ID_MATRICULA.
--   ID_ES_UN_NU_MATRICULA     : el "ID" coincide con un NU_MATRICULA de R00.
--   R00_VECINOS_10            : IDs de R00 a ±10 del huérfano (0 = cae en un
--                               hueco o fuera de rango).
-- ===========================================================================
SELECT
    b.ID_MATRICULA,
    b.NU_SEQUENCE,
    b.CD_PERSONA,
    p.NU_DOCUMENTO,
    b.NU_CASO_ORIGEN,
    b.NU_ASIEN_2,
    b.CD_ESTA_2,
    TO_CHAR(b.DT_ALTA, 'YYYY-MM-DD HH24:MI:SS') AS DT_ALTA,
    TO_CHAR(b.DT_MODIFICACION, 'YYYY-MM-DD HH24:MI:SS') AS DT_MODIFICACION,
    b.CD_USER_UPDATE,
    b.MIG_FHPI_ID,
    TO_CHAR(b.MIG_DT_UPD, 'YYYY-MM-DD') AS MIG_DT_UPD,
    TO_CHAR(b.MIG_DT_CREACION_PROC, 'YYYY-MM-DD') AS MIG_DT_CREACION_PROC,
    (SELECT COUNT(*) FROM DIG_DOC_R00_B2 x
      WHERE x.CD_PERSONA = b.CD_PERSONA AND NVL(x.ELIMINADO,0) = 0
        AND EXISTS (SELECT 1 FROM DIG_DOC_R00 i WHERE i.ID_MATRICULA = x.ID_MATRICULA)) AS PERSONA_EN_MAT_EXISTENTE,
    (SELECT COUNT(*) FROM DIG_DOC_R00_B2 x
       JOIN DIG_DOC_R62 q ON q.ID_FORMULARIO = x.CD_PERSONA
      WHERE q.NU_DOCUMENTO = p.NU_DOCUMENTO AND NVL(x.ELIMINADO,0) = 0
        AND EXISTS (SELECT 1 FROM DIG_DOC_R00 i WHERE i.ID_MATRICULA = x.ID_MATRICULA)) AS DOC_EN_MAT_EXISTENTE,
    (SELECT COUNT(*) FROM DIG_DOC_R00_B2 x
      WHERE x.NU_CASO_ORIGEN = b.NU_CASO_ORIGEN AND NVL(x.ELIMINADO,0) = 0
        AND EXISTS (SELECT 1 FROM DIG_DOC_R00 i WHERE i.ID_MATRICULA = x.ID_MATRICULA)) AS CASO_EN_MAT_EXISTENTE,
    (SELECT MIN(x.ID_MATRICULA) FROM DIG_DOC_R00_B2 x
      WHERE x.NU_CASO_ORIGEN = b.NU_CASO_ORIGEN AND NVL(x.ELIMINADO,0) = 0
        AND EXISTS (SELECT 1 FROM DIG_DOC_R00 i WHERE i.ID_MATRICULA = x.ID_MATRICULA)) AS CASO_ID_MAT_EXISTENTE,
    (SELECT COUNT(*) FROM DIG_DOC_R00 i WHERE i.NU_MATRICULA = b.ID_MATRICULA) AS ID_ES_UN_NU_MATRICULA,
    (SELECT COUNT(*) FROM DIG_DOC_R00 i
      WHERE i.ID_MATRICULA BETWEEN b.ID_MATRICULA - 10 AND b.ID_MATRICULA + 10) AS R00_VECINOS_10,
    (SELECT COUNT(*) FROM DIG_DOC_R00_B4 h WHERE h.ID_MATRICULA = b.ID_MATRICULA) AS FILAS_B4_MISMO_ID
FROM DIG_DOC_R00_B2 b
JOIN DIG_DOC_R62 p ON p.ID_FORMULARIO = b.CD_PERSONA AND p.TP_PERSONA = 'PF'
WHERE NVL(b.ELIMINADO,0) = 0
  AND NOT EXISTS (SELECT 1 FROM DIG_DOC_R00 i WHERE i.ID_MATRICULA = b.ID_MATRICULA)
ORDER BY b.ID_MATRICULA, b.CD_PERSONA, b.NU_SEQUENCE;
