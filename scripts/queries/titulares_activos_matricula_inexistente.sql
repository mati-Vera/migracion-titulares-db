-- Titulares ACTIVOS (DIG_DOC_R00_B2) cuyo ID_MATRICULA no existe en DIG_DOC_R00.
--
-- Recorte a solo B2 de titularidad_matricula_inexistente.sql (hallazgo del
-- 17/09/2026, confirmado 18/09/2026: 519 filas en B2, ver CLAUDE.md §3/§7).
-- Pedido del usuario (21/09/2026): armar el CSV de candidatos a baja de estas
-- filas huérfanas, para que el usuario arme el DML de borrado a revisar (no se
-- ejecuta ningún DELETE desde acá — CLAUDE.md §0, solo lectura).
--
-- Incluye ROWID: no hay PK declarada en B2 (CLAUDE.md §2/§4) y hay filas
-- duplicadas con los mismos valores de negocio (mismo ID_FORMULARIO + misma
-- fecha, ver el detalle del 18/09) — probablemente el mismo bug de
-- doble-submit de MAREU S.A.S. (CLAUDE.md §7). ROWID es el único identificador
-- que distingue cada fila física, necesario para un DELETE dirigido a filas
-- puntuales y no "por documento" (que borraría de más si el documento tiene
-- también titularidades válidas en otras matrículas).
--
-- ⚠️ A propósito NO filtra ELIMINADO: interesa ver también las que ya están de
-- baja lógica (no hace falta borrarlas de nuevo, pero conviene que figuren).
--
-- ⚠️ Antes de borrar: esta lista es "sin ID_MATRICULA válido en DIG_DOC_R00",
-- no "sin ninguna referencia en el sistema". DIG_DOC_R62 es un catálogo
-- compartido por todo el BPM (CLAUDE.md §4) y no hay FK declaradas — nada
-- garantiza que CD_PERSONA no esté referenciado desde otro lado. Y la causa
-- de estas 519 filas sigue sin confirmar (CLAUDE.md §7: "candidato a revisar
-- contra producción o a preguntarle al equipo de SIRCLAN"). No asumir que son
-- borrables solo por este resultado.
SELECT
    b.ROWID                AS B2_ROWID,
    b.ID_MATRICULA,
    b.CD_PERSONA            AS ID_FORMULARIO,
    p.NU_DOCUMENTO,
    p.NM_APELLIDO,
    p.NM_NOMBRE,
    p.TP_PERSONA,
    ROUND(b.NU_NUMERADOR / NULLIF(b.NU_DENOMINADOR,0) * 100, 4) AS PORCENTAJE,
    b.CD_SITUACION,
    TO_CHAR(b.DT_DESDE, 'YYYY-MM-DD') AS DESDE,
    NVL(b.ELIMINADO, 0)     AS ELIMINADO,
    b.RECIENTE
FROM DIG_DOC_R00_B2 b
LEFT JOIN DIG_DOC_R62 p ON p.ID_FORMULARIO = b.CD_PERSONA
WHERE NOT EXISTS (SELECT 1 FROM DIG_DOC_R00 i WHERE i.ID_MATRICULA = b.ID_MATRICULA)
ORDER BY b.ID_MATRICULA, b.CD_PERSONA;
