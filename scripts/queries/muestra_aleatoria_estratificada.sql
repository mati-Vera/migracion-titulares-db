-- Muestra aleatoria estratificada de documentos PF duplicados, para revisar
-- a mano y corregir el sesgo detectado en §7 (la revisión hasta ahora
-- ordenó por cantidad de duplicados de mayor a menor, no es aleatoria, y
-- el ~70% de "mezclados" está sesgado hacia los grupos grandes, que son
-- una porción minúscula de la población real).
--
-- N por estrato elegido a partir de la distribución real corrida el
-- 16/09/2026 (ver CLAUDE.md §3):
--   bajo (2-3):    113.959 grupos (93,5%) -> N=50 (es el grueso del padrón)
--   medio (4-6):     7.545 grupos (6,2%)  -> N=40
--   alto (7-10):       328 grupos (0,27%) -> N=30 (~9% del estrato)
--   muy alto (11+):     20 grupos (0,02%) -> TODOS (son pocos y ya son
--                                            candidatos a "colisión", ver §5)
--
-- Ajustar los N si hace falta más precisión estadística; esto es un punto
-- de partida razonable para un piloto, no un cálculo de tamaño muestral
-- formal.

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
        NU_DOCUMENTO,
        cant_ids,
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
)
SELECT estrato, NU_DOCUMENTO, cant_ids
FROM numerado
WHERE (estrato = 'BAJO'     AND rn <= 50)
   OR (estrato = 'MEDIO'    AND rn <= 40)
   OR (estrato = 'ALTO'     AND rn <= 30)
   OR (estrato = 'MUY_ALTO')  
ORDER BY estrato, cant_ids DESC;

-- El resultado da ~140 documentos para revisar a mano (una fila por hoja
-- de caso nueva en el Excel, igual que las ya existentes). Con cada
-- NU_DOCUMENTO de esta lista, correr scripts/queries/consultas.sql
-- (query 1, persona base) para traer el detalle a pegar en una hoja nueva.
