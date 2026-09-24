-- Personas físicas cargadas con el placeholder NU_DOCUMENTO = '0' que, pese a eso,
-- tienen un dato identificatorio útil en algún campo alternativo.
--
-- Produjo la hoja "Recuperables dni 0" de docs/Titulares BD.xlsx (416 casos sobre
-- 7.042 registros con documento '0').
--
-- Nota: la hoja "Recuperables NULL" del mismo Excel (2.516 casos sobre 163.986 PF sin
-- documento) sale de una variante de esta query con NU_DOCUMENTO IS NULL en lugar de
-- TRIM(...) = '0'. Esa variante todavía no está escrita acá.

SELECT
    ddr.ID_FORMULARIO,
    ddr.NM_NOMBRE,
    ddr.NM_APELLIDO,
    ddr.NU_DOCUMENTO,
    ddr.NU_DOCUMENTO_STR,
    ddr.NU_CUIL_CUIT,
    ddr.NU_CUIL_CUIT_STR,
    CASE
        WHEN ddr.NU_DOCUMENTO_STR IS NOT NULL
             AND TRIM(ddr.NU_DOCUMENTO_STR) NOT IN ('0','00') THEN 'NU_DOCUMENTO_STR'
        WHEN ddr.NU_CUIL_CUIT IS NOT NULL
             AND ddr.NU_CUIL_CUIT NOT IN (0)                  THEN 'NU_CUIL_CUIT'
        WHEN ddr.NU_CUIL_CUIT_STR IS NOT NULL
             AND TRIM(ddr.NU_CUIL_CUIT_STR) NOT IN ('0','00') THEN 'NU_CUIL_CUIT_STR'
    END AS CAMPO_CON_DATO_UTIL,
    ddr.TP_DOCUMENTO,
    ddr.CD_USER_STORE,
    ddr.DT_STORE,
    ddr.CD_USER_LAST_UPDATE,
    ddr.DT_LAST_UPDATE
FROM DIG_DOC_R62 ddr
WHERE ddr.TP_PERSONA = 'PF'
  AND TRIM(ddr.NU_DOCUMENTO) = '0'
  AND (
        (ddr.NU_DOCUMENTO_STR IS NOT NULL AND TRIM(ddr.NU_DOCUMENTO_STR) NOT IN ('0','00'))
     OR (ddr.NU_CUIL_CUIT IS NOT NULL AND ddr.NU_CUIL_CUIT NOT IN (0))
     OR (ddr.NU_CUIL_CUIT_STR IS NOT NULL AND TRIM(ddr.NU_CUIL_CUIT_STR) NOT IN ('0','00'))
      )
ORDER BY ddr.NM_APELLIDO, ddr.NM_NOMBRE;
