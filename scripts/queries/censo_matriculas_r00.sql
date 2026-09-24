-- Censo de DIG_DOC_R00: cuántas matrículas hay y cuáles son "matrícula real"
-- (usable para el proyecto) vs. legado Tomo/Folio, cruzado por CD_ESTADO
-- (MIG/ACT/BAJ/CRE).
--
-- Refresca, contra la base de desarrollo ACTUAL, el corte que sostiene al
-- informe .docx (25/08/2026). CLAUDE.md §3 marca esta sección como "sin
-- corte más nuevo" -- a diferencia de PF/PJ (refrescados 16/09/2026), nadie
-- volvió a correr esto todavía. El desglose por estado (bloques 2, 3 y 5) no
-- está en el .docx ni en CLAUDE.md §3, solo en
-- docs/Metodologia_Queries_SIRCLAN.md §3.3 (Queries 5, 7, 8, 9, 10, 11),
-- corridas por el desarrollador original. Son los mismos queries, para
-- volver a correrlos con datos de hoy y ver si hubo drift.
--
-- Valor "guardado" en la Metodología (informe, corte 25/08/2026 -- PARA
-- COMPARAR contra el resultado de hoy, no para citar como vigente sin
-- volver a correr):
--   Bloque 1: total=800.347, con matrícula=523.058, sin matrícula=277.289
--   Bloque 2 (sin NU_MATRICULA, por estado): MIG 275.230 / BAJ 1.799 / CRE 260 (ningún ACT)
--   Bloque 3 (con NU_MATRICULA, por estado): MIG 267.019 / ACT 242.291 / BAJ 13.356 / CRE 394
--   Bloque 4 (con matrícula, sin ningún titular en B2): 40.831
--   Bloque 5 (bloque 4, por estado): MIG 25.601 / BAJ 13.345 / ACT 1.825 / CRE 60
--   Bloque 6 (con matrícula, % de titularidad != 100%): 309
--
-- Qué es "usable" según el propio informe: matrícula real (NU_MATRICULA no
-- nulo, bloque 3), no el legado Tomo/Folio (bloque 2, ninguno en estado ACT
-- según el informe -- el bloque 2 sirve para reconfirmarlo). Dentro de las
-- reales, el informe no descarta ningún CD_ESTADO como "no usable"; usa
-- ACT+CRE como PRIORITARIAS sobre las "sin titular" (vigentes o recién
-- creadas), y trata MIG/BAJ como de menor prioridad, no como fuera de
-- alcance. Confirmar con el usuario/Mónica si para este proyecto BAJ
-- (matrícula dada de baja) se excluye directamente o se revisa igual.
--
-- ⚠️ Igual que el resto de las queries de impacto registral (README y
-- CLAUDE.md §10): esto NO filtra ELIMINADO / RECIENTE en DIG_DOC_R00_B2, así
-- que una matrícula cuyo único titular esté dado de baja lógica en B2 cuenta
-- igual como "con titular" en los bloques 4-6. Correr el bloque 0 de
-- vinculadas_doble_titular_misma_matricula.sql antes de publicar estas
-- cifras.
--
-- PENDIENTE DE CORRER.

-- Bloque 1: total de registros y partición matrícula real vs. legado Tomo/Folio
SELECT COUNT(*)                          AS TOTAL_FILAS,
       COUNT(NU_MATRICULA)               AS CON_MATRICULA,
       COUNT(*) - COUNT(NU_MATRICULA)    AS SIN_MATRICULA_LEGADO
FROM DIG_DOC_R00;

-- Bloque 2: legado Tomo/Folio (sin NU_MATRICULA) por estado -- se espera 0 en ACT
SELECT CD_ESTADO, COUNT(*) AS CANTIDAD
FROM DIG_DOC_R00
WHERE NU_MATRICULA IS NULL
GROUP BY CD_ESTADO
ORDER BY CANTIDAD DESC;

-- Bloque 3: matrículas reales (NU_MATRICULA cargado) por estado -- este es
-- el universo "usable" para el proyecto, no el del bloque 2
SELECT CD_ESTADO, COUNT(*) AS CANTIDAD
FROM DIG_DOC_R00
WHERE NU_MATRICULA IS NOT NULL
GROUP BY CD_ESTADO
ORDER BY CANTIDAD DESC;

-- Bloque 4: de las matrículas reales, cuántas no tienen ningún titular en B2
SELECT COUNT(*) AS MATRICULAS_SIN_TITULAR
FROM DIG_DOC_R00 r
WHERE r.NU_MATRICULA IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM DIG_DOC_R00_B2 b2 WHERE b2.ID_MATRICULA = r.ID_MATRICULA);

-- Bloque 5: las "sin titular" del bloque 4, por estado (ACT+CRE = prioritarias)
SELECT r.CD_ESTADO, COUNT(*) AS CANTIDAD
FROM DIG_DOC_R00 r
WHERE r.NU_MATRICULA IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM DIG_DOC_R00_B2 b2 WHERE b2.ID_MATRICULA = r.ID_MATRICULA)
GROUP BY r.CD_ESTADO
ORDER BY CANTIDAD DESC;

-- Bloque 6: matrículas reales con titular(es) cuya suma de porcentaje != 100%
SELECT COUNT(*) AS MATRICULAS_PORCENTAJE_INVALIDO
FROM (
    SELECT b2.ID_MATRICULA
    FROM DIG_DOC_R00_B2 b2
    JOIN DIG_DOC_R00 r ON r.ID_MATRICULA = b2.ID_MATRICULA
    WHERE r.NU_MATRICULA IS NOT NULL
      AND b2.NU_DENOMINADOR IS NOT NULL AND b2.NU_DENOMINADOR <> 0
    GROUP BY b2.ID_MATRICULA
    HAVING ROUND(SUM(b2.NU_NUMERADOR / NULLIF(b2.NU_DENOMINADOR, 0)), 4) <> 1
);
