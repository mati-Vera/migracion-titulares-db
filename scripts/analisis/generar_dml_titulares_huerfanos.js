// Genera el DML de revisión (DELETE) para las titularidades B2 de PF con
// ID_MATRICULA inexistente, a partir de la clasificación de
// analizar_titulares_huerfanos.js. NO se ejecuta — es un entregable para que
// el usuario revise y corra a mano (CLAUDE.md §0: nada de escrituras a la
// base desde acá).
//
// Alcance confirmado por el usuario (24/09/2026, respuestas a las preguntas
// del reporte anterior):
//   5) B4 no se toca en este análisis — el trabajo de fusión es sobre la
//      tabla de personas (R62) + reasignar FK al candidato, no tocar B4 acá.
//   7) Sí corresponde un DELETE (como propuesta a revisar) sobre el registro
//      de titular duplicado en B2.
//
// Clave de fila en B2: (ID_MATRICULA, NU_SEQUENCE) — verificado único sobre
// las 477 filas del cruce (checkseq.js, 24/09/2026); no viene en el CSV
// original del usuario, se toma de titularidad_huerfana_cruces_*_bloque2.csv.
//
// Categorías con DELETE propuesto directo:
//   3-COPIA_REGRABADO            (140 filas) — copia de la misma titularidad
//                                  ya grabada, alta confianza.
// Categorías con DELETE propuesto pero marcado "VERIFICAR ANTES" (comentado):
//   1-CLAVE_EQUIVOCADA           (5 filas)  — el ID cargado es en realidad un
//                                  NU_MATRICULA real y ahí ya está la persona.
//   2-BORRADOR_DE_TRAMITE        (19 filas) — el caso terminó creando otra
//                                  matrícula que sí existe.
// El resto (4, 5, 6 — 313 filas) NO se propone borrar: falta evidencia.
const fs = require('fs');
const path = require('path');

const RAIZ = path.resolve(__dirname, '..', '..');
const CSV_CLASIF = path.join(RAIZ, 'scripts', 'out', 'titulares_huerfanos_clasificados_2026-09-24.csv');
const CSV_CRUCES = path.join(RAIZ, 'scripts', 'out', 'titularidad_huerfana_cruces_2026-09-24_bloque2.csv');
const OUT = path.join(RAIZ, 'scripts', 'out', 'dml_borrado_titulares_huerfanos_propuesto_2026-09-24.sql');

function leerCsv(file, sep) {
  const t = fs.readFileSync(file, 'utf8').replace(/^﻿/, '');
  const rows = []; let r = [], f = '', q = false;
  for (let i = 0; i < t.length; i++) {
    const c = t[i];
    if (q) { if (c === '"') { if (t[i + 1] === '"') { f += '"'; i++; } else q = false; } else f += c; }
    else if (c === '"') q = true;
    else if (c === sep) { r.push(f); f = ''; }
    else if (c === '\r') { /* ignore */ }
    else if (c === '\n') { r.push(f); rows.push(r); r = []; f = ''; }
    else f += c;
  }
  if (f || r.length) { r.push(f); rows.push(r); }
  const H = rows[0];
  return rows.slice(1).filter(x => x.length > 1).map(x => Object.fromEntries(H.map((h, i) => [h, x[i]])));
}

const clasif = leerCsv(CSV_CLASIF, ';');
const cruces = leerCsv(CSV_CRUCES, ';');

// Join por (ID_MATRICULA, CD_PERSONA, DT_ALTA truncado a segundos, NU_CASO_ORIGEN),
// igual clave que usa analizar_titulares_huerfanos.js, con desempate por orden
// de aparición cuando hay filas idénticas en esa clave.
const key = r => [r.ID_MATRICULA, r.CD_PERSONA, (r.DT_ALTA || '').slice(0, 19), r.NU_CASO_ORIGEN].join('|');
const nth = {};
const idx = {};
cruces.forEach(r => { const k = key(r); const n = (nth[k] = (nth[k] ?? -1) + 1); idx[k + '#' + n] = r; });
const nth2 = {};
clasif.forEach(r => {
  const k = key(r); const n = (nth2[k] = (nth2[k] ?? -1) + 1);
  const c = idx[k + '#' + n];
  if (!c) throw new Error('Sin cruce para ' + k + '#' + n);
  r.NU_SEQUENCE = c.NU_SEQUENCE;
  r.CASO_ID_MAT_EXISTENTE = c.CASO_ID_MAT_EXISTENTE;
});

const esc = s => String(s || '').replace(/'/g, "''");
const comentarioFila = r =>
  `-- ID_MATRICULA=${r.ID_MATRICULA} NU_SEQUENCE=${r.NU_SEQUENCE} CD_PERSONA=${r.CD_PERSONA} ` +
  `DOC=${r.NU_DOCUMENTO} ${esc(r.NM_APELLIDO)}, ${esc(r.NM_NOMBRE)} | ALTA=${r.DT_ALTA} USER=${r.CD_USER_STORE_B2 || '(vacío)'} ` +
  `| grupo tiene ${r.FILAS_MISMA_MAT_PERSONA} filas, original=${r.ES_ORIGINAL}`;

const deleteStmt = r => `DELETE FROM DIG_DOC_R00_B2 WHERE ID_MATRICULA = ${r.ID_MATRICULA} AND NU_SEQUENCE = ${r.NU_SEQUENCE};`;

const L = [];
L.push('-- DML DE REVISIÓN — NO EJECUTAR SIN REVISAR CADA BLOQUE (CLAUDE.md §0).');
L.push('-- Generado 24/09/2026 por scripts/analisis/generar_dml_titulares_huerfanos.js');
L.push('-- desde scripts/out/titulares_huerfanos_clasificados_2026-09-24.csv.');
L.push('--');
L.push('-- Alcance: las 477 titularidades B2 de personas físicas VIVAS (ELIMINADO=0)');
L.push('-- cuyo ID_MATRICULA no existe en DIG_DOC_R00 (docs/Titulares_activos_con_');
L.push('-- matricula_inexistente.csv). Confirmado por el usuario (24/09/2026): este');
L.push('-- análisis NO toca DIG_DOC_R00_B4 (los históricos se dejan como están); el');
L.push('-- trabajo de fusión de personas duplicadas es aparte (tabla R62 + reasignar');
L.push('-- CD_PERSONA/_H/_P al candidato). Acá solo se propone BORRAR el registro de');
L.push('-- titular duplicado cuando hay evidencia de que es una copia.');
L.push('--');
L.push('-- Clave de fila: (ID_MATRICULA, NU_SEQUENCE) — verificada única sobre las 477.');
L.push('');

const grupos = {
  '3-COPIA_REGRABADO': { titulo: 'Copias de la misma titularidad ya grabada (alta confianza)', ejecutar: true },
  '1-CLAVE_EQUIVOCADA': { titulo: 'El ID cargado es un NU_MATRICULA real y ahí ya está la persona — VERIFICAR ANTES', ejecutar: false },
  '2-BORRADOR_DE_TRAMITE': { titulo: 'El mismo caso terminó creando otra matrícula que sí existe — VERIFICAR ANTES', ejecutar: false },
};

for (const [cat, { titulo, ejecutar }] of Object.entries(grupos)) {
  const filas = clasif.filter(r => r.CATEGORIA === cat);
  L.push('-- ' + '='.repeat(75));
  L.push(`-- ${cat} (${filas.length} filas) — ${titulo}`);
  L.push('-- ' + '='.repeat(75));
  if (!ejecutar) L.push('-- Los DELETE de este bloque van COMENTADOS: destrabar fila por fila tras verificar.');
  L.push('');
  for (const r of filas) {
    L.push(comentarioFila(r));
    if (cat === '2-BORRADOR_DE_TRAMITE') L.push(`-- (el trámite ${r.NU_CASO_ORIGEN} ya tiene titularidad viva en ID_MATRICULA=${r.CASO_ID_MAT_EXISTENTE})`);
    L.push((ejecutar ? '' : '-- ') + deleteStmt(r));
    L.push('');
  }
}

L.push('-- ' + '='.repeat(75));
const revisar = clasif.filter(r => !['3-COPIA_REGRABADO', '1-CLAVE_EQUIVOCADA', '2-BORRADOR_DE_TRAMITE'].includes(r.CATEGORIA));
L.push(`-- Sin propuesta de DELETE (${revisar.length} filas): categorías 4-LEGADO_SIN_ALTA, `);
L.push('-- 5-ORIGINAL_CON_TITULARIDAD_EN_OTRA y 6-ORIGINAL_UNICO. Ver el reporte');
L.push('-- (scripts/out/reporte_patrones_titulares_huerfanos_2026-09-24.md, §7) antes');
L.push('-- de decidir algo sobre ellas.');
L.push('-- ' + '='.repeat(75));

fs.writeFileSync(OUT, L.join('\n'), 'utf8');
const activos = clasif.filter(r => r.CATEGORIA === '3-COPIA_REGRABADO').length;
const comentados = clasif.filter(r => ['1-CLAVE_EQUIVOCADA', '2-BORRADOR_DE_TRAMITE'].includes(r.CATEGORIA)).length;
console.log(`Escrito ${OUT}`);
console.log(`DELETE activos (categoría 3): ${activos}`);
console.log(`DELETE comentados a verificar (categorías 1+2): ${comentados}`);
console.log(`Sin propuesta (categorías 4/5/6): ${revisar.length}`);
