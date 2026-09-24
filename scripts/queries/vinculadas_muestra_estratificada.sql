-- Muestra aleatoria para revisión manual, ahora sobre el UNIVERSO VINCULADO A
-- MATRÍCULAS (el que pidió Mónica el 16/09/2026), no sobre los 121.793 grupos.
--
-- Reemplaza a muestra_detalle_persona_base.sql para el piloto: mismo diseño
-- (aleatoria y estratificada, para no repetir el sesgo de §7) pero muestreando
-- solo entre los grupos con 2+ registros colgando de una matrícula, y
-- estratificando por PRIORIDAD (P1/P2/P3 de vinculadas_listado_grupos_pf.sql),
-- que es el eje que ahora manda, en vez de por cantidad de duplicados.
--
-- El ESTRATO por tamaño sigue saliendo como columna para poder chequear que la
-- muestra no quede concentrada en grupos grandes.
--
-- El formato de salida es el que consume EvaluadorLote.java (columnas ESTRATO,
-- NU_DOCUMENTO, ID_FORMULARIO, NM_NOMBRE, NM_APELLIDO, CD_SEXO,
-- SCORE_COMPLETITUD, DT_LAST_UPDATE; las demás las ignora): exportar el
-- resultado como tabla Markdown y pasarle el archivo.
--
-- ⚠️ DBMS_RANDOM devuelve una muestra distinta en cada corrida. Si hay que
-- evaluar exactamente la misma lista dos veces, guardar los NU_DOCUMENTO de la
-- primera corrida y fijarlos en un IN (...).
--
-- N por prioridad: provisorio. Ajustarlo después de correr
-- vinculadas_distribucion_estratos_pf.sql y ver cuánto pesa cada prioridad en
-- el universo vinculado (hoy no sabemos si P1 son 200 grupos o 40.000).
--
-- PENDIENTE DE CORRER.

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
    SELECT CD_PERSONA   AS ID_FORMULARIO, 'B2' AS ORIGEN FROM DIG_DOC_R00_B2 WHERE CD_PERSONA   IS NOT NULL GROUP BY CD_PERSONA
    UNION ALL
    SELECT CD_PERSONA_H AS ID_FORMULARIO, 'B4' AS ORIGEN FROM DIG_DOC_R00_B4 WHERE CD_PERSONA_H IS NOT NULL GROUP BY CD_PERSONA_H
    UNION ALL
    SELECT CD_PERSONA_P AS ID_FORMULARIO, 'B5' AS ORIGEN FROM DIG_DOC_R00_B5 WHERE CD_PERSONA_P IS NOT NULL GROUP BY CD_PERSONA_P
),
persona_flag AS (
    SELECT
        pd.NU_DOCUMENTO,
        pd.ID_FORMULARIO,
        MAX(CASE WHEN v.ORIGEN = 'B2' THEN 1 ELSE 0 END)      AS EN_B2,
        MAX(CASE WHEN v.ORIGEN IS NOT NULL THEN 1 ELSE 0 END) AS VINCULADA
    FROM personas_dup pd
    LEFT JOIN vinculos v ON v.ID_FORMULARIO = pd.ID_FORMULARIO
    GROUP BY pd.NU_DOCUMENTO, pd.ID_FORMULARIO
),
grupo AS (
    SELECT
        NU_DOCUMENTO,
        COUNT(*)       AS CANT_IDS,
        SUM(VINCULADA) AS CANT_VINCULADAS,
        SUM(EN_B2)     AS CANT_EN_B2
    FROM persona_flag
    GROUP BY NU_DOCUMENTO
    HAVING SUM(VINCULADA) > 1
),
etiquetado AS (
    SELECT
        NU_DOCUMENTO, CANT_IDS, CANT_VINCULADAS, CANT_EN_B2,
        CASE
            WHEN CANT_EN_B2 > 1 THEN 'P1'
            WHEN CANT_EN_B2 = 1 THEN 'P2'
            ELSE                     'P3'
        END AS PRIORIDAD,
        CASE
            WHEN CANT_IDS BETWEEN 2 AND 3  THEN 'BAJO'
            WHEN CANT_IDS BETWEEN 4 AND 6  THEN 'MEDIO'
            WHEN CANT_IDS BETWEEN 7 AND 10 THEN 'ALTO'
            ELSE                                'MUY_ALTO'
        END AS ESTRATO_TAMANIO
    FROM grupo
),
numerado AS (
    SELECT e.*,
           ROW_NUMBER() OVER (PARTITION BY PRIORIDAD ORDER BY DBMS_RANDOM.VALUE) AS RN
    FROM etiquetado e
),
muestra AS (
    SELECT NU_DOCUMENTO, CANT_IDS, CANT_VINCULADAS, CANT_EN_B2, PRIORIDAD, ESTRATO_TAMANIO
    FROM numerado
    WHERE (PRIORIDAD = 'P1' AND RN <= 50)
       OR (PRIORIDAD = 'P2' AND RN <= 50)
       OR (PRIORIDAD = 'P3' AND RN <= 40)
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
    pf.VINCULADA                            AS TIENE_MATRICULA,
    pf.EN_B2                                AS ES_TITULAR_ACTIVO,
    m.CANT_VINCULADAS                       AS VINCULADAS_EN_EL_GRUPO,
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
    )                                       AS SCORE_COMPLETITUD,
    TO_CHAR(p.DT_LAST_UPDATE, 'YYYY-MM-DD HH24:MI:SS') AS DT_LAST_UPDATE
FROM muestra m
JOIN DIG_DOC_R62 p  ON p.NU_DOCUMENTO = m.NU_DOCUMENTO AND p.TP_PERSONA = 'PF'
JOIN persona_flag pf ON pf.ID_FORMULARIO = p.ID_FORMULARIO
ORDER BY m.PRIORIDAD, m.NU_DOCUMENTO, p.ID_FORMULARIO;

-- Ojo al revisar: el grupo se trae COMPLETO (vinculados y no vinculados), porque
-- para decidir si son la misma persona hay que ver todos los registros. El
-- filtro de matrícula elige QUÉ GRUPOS se revisan, no qué filas se miran dentro
-- del grupo. Las columnas TIENE_MATRICULA / ES_TITULAR_ACTIVO marcan cuáles de
-- esas filas arrastran titularidad.
