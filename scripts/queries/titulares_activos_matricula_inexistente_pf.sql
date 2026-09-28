-- Origen de docs/Titulares_activos_con_matricula_inexistente.csv (volcado del
-- usuario, 477 filas, 24/09/2026). Pasada por el usuario el 24/09/2026 —
-- coincide columna por columna con el header del CSV (26 columnas, mismo
-- orden), confirmado.
--
-- Titulares ACTIVOS (DIG_DOC_R00_B2) cuyo ID_MATRICULA no existe en DIG_DOC_R00,
-- acotado a personas físicas (p.TP_PERSONA = 'PF').
--
-- ⚠️ A diferencia de las demás queries de impacto registral (§3 "Verificación
-- ELIMINADO/RECIENTE" de CLAUDE.md), esta NO filtra `NVL(b.ELIMINADO,0)=0` —
-- lo trae como columna, no como condición. En el corte del 24/09 dio igual
-- (las 477 filas tienen ELIMINADO=0), pero no está garantizado que siga así
-- en una corrida futura: si hace falta reproducir exactamente estas 477,
-- agregar el filtro explícito.
--
-- Complementada con los cruces contra la base en titularidad_huerfana_cruces.sql
-- y titularidad_huerfana_clave_alternativa.sql (mismo universo, mismo filtro
-- PF + ID_MATRICULA inexistente), que agregan lo que este SELECT no trae:
-- NU_SEQUENCE (clave de fila dentro de B2), columnas MIG_*, y si el mismo caso
-- / persona / documento ya tiene titularidad viva en una matrícula que sí
-- existe. Ver scripts/analisis/analizar_titulares_huerfanos.js.
SELECT
    b.ID_MATRICULA,
    b.CD_PERSONA,
    b.CD_SITUACION,
    b.DT_DESDE,
    b.TM_DESDE,
    b.NU_CASO_ORIGEN,
    b.DS_PORCENTAJE,
    b.DT_ALTA,
    b.CD_USER_STORE,
    p.CD_NACIONALIDAD,
    p.TP_DOCUMENTO,
    p.NU_CUIL_CUIT,
    p.NU_CUIL_CUIT_STR,
    p.NU_DOCUMENTO,
    p.NM_APELLIDO,
    p.NM_NOMBRE,
    p.TP_PERSONA,
    p.DT_LAST_UPDATE,
    p.CD_USER_STORE,
    p.DT_STORE,
    p.CD_USER_LAST_UPDATE,
    ROUND(b.NU_NUMERADOR / NULLIF(b.NU_DENOMINADOR,0) * 100, 4) AS PORCENTAJE,
    b.CD_SITUACION,
    TO_CHAR(b.DT_DESDE, 'YYYY-MM-DD') AS DESDE,
    NVL(b.ELIMINADO, 0)     AS ELIMINADO,
    b.RECIENTE
FROM DIG_DOC_R00_B2 b
LEFT JOIN DIG_DOC_R62 p ON p.ID_FORMULARIO = b.CD_PERSONA
WHERE NOT EXISTS (SELECT 1 FROM DIG_DOC_R00 i WHERE i.ID_MATRICULA = b.ID_MATRICULA)
    AND p.TP_PERSONA = 'PF'
ORDER BY b.ID_MATRICULA, b.CD_PERSONA;
