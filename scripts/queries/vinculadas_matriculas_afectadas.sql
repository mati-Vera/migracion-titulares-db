-- El mismo filtro de Mónica visto desde el otro lado: cuántas MATRÍCULAS y
-- cuántas FILAS de titularidad están tocadas por el problema de duplicados.
--
-- vinculadas_kpi_pf.sql cuenta personas y grupos. Esta cuenta el impacto
-- registral, que es lo que se puede mostrar como "esto es lo que hay que
-- arreglar" y lo que dimensiona el trabajo real de reasignación de FK:
-- una persona perdedora puede tener decenas de filas en B4 (el ID_FORMULARIO
-- 5038282 aparece 60 veces, CLAUDE.md §7), así que "personas a reasignar" y
-- "filas a reasignar" no son el mismo número ni por asomo.
--
-- Devuelve una fila por tabla de titularidad (B2 activos / B4 históricos /
-- B5 no vigentes) + una fila TOTAL de matrículas distintas afectadas.
--
-- ACTUALIZADO 17/09/2026: filtra ELIMINADO=1 en B2 y B5 — confirmado como baja
-- lógica real (CLAUDE.md §10: matrículas con TODAS sus filas de B2 en
-- ELIMINADO=1 quedan sin ningún titular vivo si no se excluyen; hay filas
-- ELIMINADO=1 cargadas tanto por la migración como por usuarios de WORKFLOW
-- corrigiendo errores en producción). B4 no tiene esta columna, queda igual.
-- RECIENTE se investigó y NO se filtra: correlaciona con origen migración
-- (NULL) vs. workflow (0/1), no con si la titularidad está viva.

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
    SELECT p.ID_FORMULARIO
    FROM DIG_DOC_R62 p
    JOIN grupos_dup g ON g.NU_DOCUMENTO = p.NU_DOCUMENTO
    WHERE p.TP_PERSONA = 'PF'
),
-- Una tabla "muchos" por rama, nunca dos juntas (CLAUDE.md §4).
titularidades AS (
    SELECT 'B2 - ACTIVOS'     AS TABLA, b.CD_PERSONA   AS ID_FORMULARIO, b.ID_MATRICULA
    FROM DIG_DOC_R00_B2 b JOIN personas_dup pd ON pd.ID_FORMULARIO = b.CD_PERSONA
    WHERE NVL(b.ELIMINADO, 0) = 0
    UNION ALL
    SELECT 'B4 - HISTORICOS'  AS TABLA, b.CD_PERSONA_H AS ID_FORMULARIO, b.ID_MATRICULA
    FROM DIG_DOC_R00_B4 b JOIN personas_dup pd ON pd.ID_FORMULARIO = b.CD_PERSONA_H
    UNION ALL
    SELECT 'B5 - NO VIGENTES' AS TABLA, b.CD_PERSONA_P AS ID_FORMULARIO, b.ID_MATRICULA
    FROM DIG_DOC_R00_B5 b JOIN personas_dup pd ON pd.ID_FORMULARIO = b.CD_PERSONA_P
    WHERE NVL(b.ELIMINADO, 0) = 0
)
SELECT
    TABLA,
    COUNT(*)                        AS FILAS_DE_TITULARIDAD,
    COUNT(DISTINCT ID_FORMULARIO)   AS PERSONAS_DISTINTAS,
    COUNT(DISTINCT ID_MATRICULA)    AS MATRICULAS_DISTINTAS,
    ROUND(COUNT(*) / NULLIF(COUNT(DISTINCT ID_FORMULARIO), 0), 2) AS FILAS_POR_PERSONA
FROM titularidades
GROUP BY TABLA
UNION ALL
SELECT
    'TOTAL (matriculas sin repetir entre tablas)',
    COUNT(*),
    COUNT(DISTINCT ID_FORMULARIO),
    COUNT(DISTINCT ID_MATRICULA),
    ROUND(COUNT(*) / NULLIF(COUNT(DISTINCT ID_FORMULARIO), 0), 2)
FROM titularidades
ORDER BY 1;

-- Lecturas del resultado:
--  * FILAS_DE_TITULARIDAD de la fila TOTAL = el volumen de UPDATEs de FK que
--    implicaría la fusión completa (cota superior: incluye las filas de los
--    ganadores, que no se tocan).
--  * FILAS_POR_PERSONA muy por encima de 1 en B4 confirma la redundancia
--    masiva ya detectada en §7 y dice cuánto se multiplica el trabajo.
--  * MATRICULAS_DISTINTAS de B2 es el número "duro" para Mónica: inmuebles con
--    titular activo que pertenece a un grupo duplicado.
--
-- Variante para el listado de matrículas concretas (para el Excel Detalle),
-- correr aparte cambiando el SELECT final por:
--   SELECT DISTINCT t.ID_MATRICULA, i.NU_MATRICULA, i.CD_ESTADO, i.DS_INMUEBLE
--   FROM titularidades t
--   LEFT JOIN DIG_DOC_R00 i ON i.ID_MATRICULA = t.ID_MATRICULA
--   WHERE t.TABLA = 'B2 - ACTIVOS';
