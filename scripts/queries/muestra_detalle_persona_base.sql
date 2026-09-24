-- Versión combinada de muestra_aleatoria_estratificada.sql: en vez de traer
-- solo la lista de NU_DOCUMENTO para después copiarla a mano en otra query,
-- esta trae directo el detalle de DIG_DOC_R62 de la muestra completa, listo
-- para exportar y pasarle a EvaluadorLote.java.
--
-- OJO: DBMS_RANDOM elige una muestra distinta cada vez que se ejecuta esta
-- query. Si ya corriste muestra_aleatoria_estratificada.sql y querés
-- evaluar EXACTAMENTE esos ~140 documentos (no una muestra nueva), avisame
-- y te armo la versión con los NU_DOCUMENTO fijos en un IN (...) en vez de
-- volver a samplear.
--
-- SCORE_COMPLETITUD: cuenta de campos "informativos" no nulos (no cuenta
-- IDs ni columnas de auditoría) — aproximación simple a "completitud de
-- datos" (CLAUDE.md §5, selección de candidato) sin traer las ~48 columnas
-- de DIG_DOC_R62 completas.

WITH conteo AS (
    SELECT NU_DOCUMENTO, COUNT(*) AS cant_ids
    FROM DIG_DOC_R62
    WHERE TP_PERSONA = 'PF'
      AND NU_DOCUMENTO IS NOT NULL
      AND NOT REGEXP_LIKE(NU_DOCUMENTO, '^0+$')
      AND NU_DOCUMENTO NOT IN ('99907804', '1')
    GROUP BY NU_DOCUMENTO
    HAVING COUNT(*) > 1
),
estratos AS (
    SELECT NU_DOCUMENTO, cant_ids,
        CASE
            WHEN cant_ids BETWEEN 2 AND 3  THEN 'BAJO'
            WHEN cant_ids BETWEEN 4 AND 6  THEN 'MEDIO'
            WHEN cant_ids BETWEEN 7 AND 10 THEN 'ALTO'
            ELSE                                'MUY_ALTO'
        END AS estrato
    FROM conteo
),
numerado AS (
    SELECT NU_DOCUMENTO, cant_ids, estrato,
           ROW_NUMBER() OVER (PARTITION BY estrato ORDER BY DBMS_RANDOM.VALUE) AS rn
    FROM estratos
),
muestra AS (
    SELECT NU_DOCUMENTO, cant_ids, estrato
    FROM numerado
    WHERE (estrato = 'BAJO'     AND rn <= 50)
       OR (estrato = 'MEDIO'    AND rn <= 40)
       OR (estrato = 'ALTO'     AND rn <= 30)
       OR (estrato = 'MUY_ALTO')
)
SELECT
    m.estrato,
    p.NU_DOCUMENTO,
    p.ID_FORMULARIO,
    p.NM_NOMBRE,
    p.NM_APELLIDO,
    p.CD_SEXO,
    p.NU_CUIL_CUIT,
    p.NU_CUIL_CUIT_STR,
    (
        (CASE WHEN p.DS_CALLE IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN p.DS_NUMERO IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN p.CD_LOCALIDAD IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN p.DT_NACIMIENTO IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN p.DS_EMAIL IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN p.NU_CELULAR IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN p.NU_TELEFONO IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN p.CD_ESTADO_CIVIL IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN p.NM_NOMBRE_CONYUGUE IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN p.CD_NACIONALIDAD IS NOT NULL THEN 1 ELSE 0 END)
    ) AS SCORE_COMPLETITUD,
    TO_CHAR(p.DT_LAST_UPDATE, 'YYYY-MM-DD HH24:MI:SS') AS DT_LAST_UPDATE
FROM muestra m
JOIN DIG_DOC_R62 p ON p.NU_DOCUMENTO = m.NU_DOCUMENTO AND p.TP_PERSONA = 'PF'
ORDER BY m.estrato, p.NU_DOCUMENTO, p.ID_FORMULARIO;

-- Exportar el resultado como tabla Markdown (mismo formato que ya venís
-- usando) y pasarle el archivo a EvaluadorLote.java (scripts/).
