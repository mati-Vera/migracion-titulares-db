-- Distribución de los grupos de personas físicas duplicadas por estrato de
-- cantidad de duplicados (CLAUDE.md §10, pendiente "Correr la query de
-- distribución de grupos por estrato: bajo 2-3 / medio 4-6 / alto 7-10 /
-- muy alto 11+").
--
-- Sirve para: (a) dimensionar cuánto pesa cada estrato sobre el total de
-- 121.793 grupos, y (b) armar la muestra aleatoria estratificada pendiente
-- (§7, corrección metodológica: la revisión manual hasta ahora se ordenó
-- por cantidad de duplicados de mayor a menor, no es aleatoria, y el ~70%
-- de "mezclados" está sesgado hacia los grupos grandes).
--
-- Basada en el CTE "conteo" de la Query 14 de docs/Metodologia_Queries_SIRCLAN.md
-- (KPI final, guardado: placeholder=7.100, grupos=121.663, redundantes=162.225),
-- con el mismo criterio de exclusión de placeholders.

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
    SELECT
        CASE
            WHEN cant_ids BETWEEN 2 AND 3  THEN '1 - BAJO (2-3)'
            WHEN cant_ids BETWEEN 4 AND 6  THEN '2 - MEDIO (4-6)'
            WHEN cant_ids BETWEEN 7 AND 10 THEN '3 - ALTO (7-10)'
            ELSE                                '4 - MUY ALTO (11+)'
        END AS estrato,
        cant_ids
    FROM conteo
)
SELECT
    estrato,
    COUNT(*)                       AS cantidad_grupos,
    SUM(cant_ids)                  AS total_registros_en_estrato,
    SUM(cant_ids - 1)              AS registros_redundantes_en_estrato,
    MIN(cant_ids)                  AS min_duplicados,
    MAX(cant_ids)                  AS max_duplicados,
    ROUND(AVG(cant_ids), 2)        AS promedio_duplicados
FROM estratos
GROUP BY estrato
ORDER BY estrato;

-- Chequeo de consistencia: la suma de cantidad_grupos de las 4 filas debe
-- dar 121.793 (Excel, vigente) y la suma de registros_redundantes_en_estrato
-- debe dar 162.491. Si no cierra, revisar que este WHERE sea idéntico al
-- de la query que produjo esos totales (Excel hoja PF).

-- Para armar la muestra aleatoria estratificada (pendiente §10): una vez
-- confirmada la distribución, tomar N documentos al azar POR ESTRATO
-- (no del total, para no repetir el sesgo hacia los grupos grandes ya
-- detectado) con algo como:
--
-- SELECT NU_DOCUMENTO FROM (
--     SELECT c.NU_DOCUMENTO,
--            CASE WHEN c.cant_ids BETWEEN 2 AND 3 THEN '1 - BAJO (2-3)' ... END AS estrato
--     FROM conteo c
-- )
-- WHERE estrato = '1 - BAJO (2-3)'
-- ORDER BY DBMS_RANDOM.VALUE
-- FETCH FIRST 15 ROWS ONLY;  -- ajustar N y repetir por cada estrato
