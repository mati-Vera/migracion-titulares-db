-- Detalle (bloque 2) de vinculadas_doble_titular_misma_matricula.sql, separado a
-- archivo propio para correrlo solo -- ese bloque estaba comentado en el original
-- y nunca se había corrido (pendiente en CLAUDE.md §10).
--
-- Una fila por (matrícula, documento) con 2+ titulares activos duplicados en la
-- MISMA matrícula. Mismo filtro NVL(ELIMINADO,0)=0 verificado el 17/09/2026
-- (CLAUDE.md §3 "Verificación ELIMINADO/RECIENTE"). Corrida 18/09/2026.
--
-- Lectura de SUMA_PORCENTAJE_DEL_GRUPO: cuánto de la titularidad de esa
-- matrícula está en manos de registros que son la MISMA persona. Si da 1
-- (=100%), el inmueble entero pertenece a una sola persona cargada N veces.

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
colision AS (
    SELECT
        b.ID_MATRICULA,
        pd.NU_DOCUMENTO,
        COUNT(DISTINCT b.CD_PERSONA) AS PERSONAS_DISTINTAS,
        COUNT(*)                     AS FILAS_B2,
        SUM(b.NU_NUMERADOR / NULLIF(b.NU_DENOMINADOR, 0)) AS SUMA_PORCENTAJE_DEL_GRUPO
    FROM DIG_DOC_R00_B2 b
    JOIN personas_dup pd ON pd.ID_FORMULARIO = b.CD_PERSONA
    WHERE NVL(b.ELIMINADO, 0) = 0
    GROUP BY b.ID_MATRICULA, pd.NU_DOCUMENTO
    HAVING COUNT(DISTINCT b.CD_PERSONA) > 1
)
SELECT
    c.NU_DOCUMENTO,
    c.ID_MATRICULA,
    i.NU_MATRICULA,
    i.CD_ESTADO,
    i.DS_INMUEBLE,
    c.PERSONAS_DISTINTAS,
    c.FILAS_B2,
    ROUND(c.SUMA_PORCENTAJE_DEL_GRUPO, 4) AS SUMA_PORCENTAJE_DEL_GRUPO
FROM colision c
LEFT JOIN DIG_DOC_R00 i ON i.ID_MATRICULA = c.ID_MATRICULA
ORDER BY c.PERSONAS_DISTINTAS DESC, c.FILAS_B2 DESC, c.NU_DOCUMENTO;
