// Extrae una muestra representativa (5-10 casos) del patrón "3-COPIA_REGRABADO"
// (re-grabado de la misma titularidad en la misma matrícula) para presentar como
// evidencia antes de programar el borrado (Etapa 2). No hay Python en esta máquina
// (ver CLAUDE.md, 24/09/2026) — mismo motivo que analizar_titulares_huerfanos.js.
// Uso: node scripts/analisis/muestra_regrabado.js
const fs = require('fs');
const path = require('path');

const RAIZ = path.resolve(__dirname, '..', '..');
const CSV_CLASIFICADO = path.join(RAIZ, 'scripts', 'out', 'titulares_huerfanos_clasificados_2026-09-24.csv');
const CSV_CRUCES = path.join(RAIZ, 'scripts', 'out', 'titularidad_huerfana_cruces_2026-09-24_bloque2.csv');

function leerCsv(file, sep) {
  const t = fs.readFileSync(file, 'utf8').replace(/^﻿/, '');
  const rows = []; let r = [], f = '', q = false;
  for (let i = 0; i < t.length; i++) {
    const c = t[i];
    if (q) { if (c === '"') { if (t[i + 1] === '"') { f += '"'; i++; } else q = false; } else f += c; }
    else if (c === '"') q = true;
    else if (c === sep) { r.push(f); f = ''; }
    else if (c === '\n') { r.push(f.replace(/\r$/, '')); rows.push(r); r = []; f = ''; }
    else f += c;
  }
  if (f || r.length) { r.push(f); rows.push(r); }
  const H = rows[0];
  return rows.slice(1).filter(x => x.length > 1).map(x => Object.fromEntries(H.map((h, i) => [h, x[i]])));
}

const groupBy = (a, f) => a.reduce((m, x) => { const k = f(x); (m[k] = m[k] || []).push(x); return m; }, {});

// 1. Cargar clasificación (original vs. copia por grupo matrícula+persona).
const clasif = leerCsv(CSV_CLASIFICADO, ';');

// 2. Traer NU_SEQUENCE (el identificador de fila física en B2) desde el cruce,
//    matcheando por (ID_MATRICULA, CD_PERSONA, DT_ALTA) con el mismo criterio de
//    n-ésima ocurrencia que usa analizar_titulares_huerfanos.js, para no mezclar
//    filas cuando dos copias comparten el mismo DT_ALTA.
const cruces = leerCsv(CSV_CRUCES, ';');
const idxCruces = {};
{
  const n = {};
  cruces.forEach(x => {
    const k = [x.ID_MATRICULA, x.CD_PERSONA, x.DT_ALTA].join('|');
    idxCruces[k + '#' + (n[k] = (n[k] ?? -1) + 1)] = x;
  });
}
{
  const n = {};
  clasif.forEach(r => {
    const dtAlta19 = r.DT_ALTA.slice(0, 19);
    const k = [r.ID_MATRICULA, r.CD_PERSONA, dtAlta19].join('|');
    const kk = k + '#' + (n[k] = (n[k] ?? -1) + 1);
    r.NU_SEQUENCE = (idxCruces[kk] || {}).NU_SEQUENCE || '?';
  });
}

// 3. Armar pares original/copia por grupo (ID_MATRICULA, CD_PERSONA).
const grupos = Object.values(groupBy(clasif, r => r.ID_MATRICULA + '|' + r.CD_PERSONA));
const pares = [];
grupos.forEach(g => {
  const original = g.find(r => r.ES_ORIGINAL === 'True');
  const copias = g.filter(r => r.CATEGORIA === '3-COPIA_REGRABADO');
  if (!original || !copias.length) return;
  copias.forEach(copia => pares.push({ original, copia, totalFilasGrupo: g.length }));
});

// 4. Seleccionar una muestra diversa y representativa (criterios explícitos, no al azar):
const porGap = [...pares].sort((a, b) => +a.copia.MIN_DESDE_ORIGINAL - +b.copia.MIN_DESDE_ORIGINAL);
const seleccion = [];
const yaElegido = new Set();
const agregar = (par, motivo) => {
  const key = par.original.ID_MATRICULA + '|' + par.original.CD_PERSONA + '|' + par.copia.NU_SEQUENCE;
  if (!par || yaElegido.has(key)) return false;
  yaElegido.add(key);
  seleccion.push({ ...par, motivo });
  return true;
};

// a) El re-grabado casi inmediato (gap más chico de todos).
agregar(porGap[0], 'Gap mínimo (re-submit casi inmediato)');

// b) Usuario distinto entre original y copia (si existe) — muestra que no es
//    solo "el mismo operario reintentando", también pasa entre usuarios.
const conUsuarioDistinto = porGap.find(p => p.original.CD_USER_STORE_B2 !== p.copia.CD_USER_STORE_B2);
if (conUsuarioDistinto) agregar(conUsuarioDistinto, 'Usuario distinto entre original y copia');

// c) El grupo con más copias de la misma titularidad (re-grabado repetido, no
//    una sola vez) — se toma su primera copia.
const porCantCopias = Object.values(groupBy(pares, p => p.original.ID_MATRICULA + '|' + p.original.CD_PERSONA))
  .sort((a, b) => b.length - a.length);
if (porCantCopias[0]) agregar(porCantCopias[0][0], `Titularidad re-grabada ${porCantCopias[0].length} veces en el mismo grupo`);

// d) Gap mediano (representativo del p50 reportado, ~982 min).
const medianaObjetivo = 982.5;
const porCercaniaMediana = [...porGap].sort((a, b) =>
  Math.abs(+a.copia.MIN_DESDE_ORIGINAL - medianaObjetivo) - Math.abs(+b.copia.MIN_DESDE_ORIGINAL - medianaObjetivo));
for (const p of porCercaniaMediana) { if (agregar(p, 'Gap cercano a la mediana (~982 min, ver reporte 24/09)')) break; }

// e) Gap justo debajo de las 24 h (borde del "70,9% dentro de las 24 h").
const porCercania24h = [...porGap].filter(p => +p.copia.MIN_DESDE_ORIGINAL <= 1440)
  .sort((a, b) => Math.abs(1440 - +a.copia.MIN_DESDE_ORIGINAL) - Math.abs(1440 - +b.copia.MIN_DESDE_ORIGINAL));
for (const p of porCercania24h) { if (agregar(p, 'Gap justo antes del corte de 24 h')) break; }

// f) Gap justo por encima de las 24 h (el otro lado del mismo borde).
const porFueraDe24h = porGap.filter(p => +p.copia.MIN_DESDE_ORIGINAL > 1440);
if (porFueraDe24h[0]) agregar(porFueraDe24h[0], 'Gap justo después del corte de 24 h');

// g) y h) Dos casos adicionales tomados de años distintos, para mostrar que el
//    patrón no es de una sola época (§2 del reporte: 2018-2026).
const porAnio = groupBy(porGap, p => p.original.DT_ALTA.slice(0, 4));
Object.keys(porAnio).sort().forEach(anio => {
  if (seleccion.length >= 8) return;
  const candidato = porAnio[anio].find(p => !yaElegido.has(p.original.ID_MATRICULA + '|' + p.original.CD_PERSONA + '|' + p.copia.NU_SEQUENCE));
  if (candidato) agregar(candidato, `Ejemplo del año ${anio}`);
});

const muestra = seleccion.slice(0, 8);

// 5. Tabla Markdown, registros enfrentados lado a lado.
const cols = ['Matrícula', 'Documento', 'Apellido y nombre', 'Fila B2 (NU_SEQUENCE) original → re-grabado',
  'DT_ALTA original', 'DT_ALTA re-grabado', 'Gap (min)', 'Usuario original → re-grabado',
  'NU_CASO_ORIGEN (orig.)', 'RECIENTE (orig.→copia)', 'Motivo de selección'];
const filas = muestra.map(({ original: o, copia: c, motivo }) => [
  o.ID_MATRICULA,
  o.NU_DOCUMENTO,
  `${o.NM_APELLIDO}, ${o.NM_NOMBRE}`,
  `${o.NU_SEQUENCE} → ${c.NU_SEQUENCE}`,
  o.DT_ALTA,
  c.DT_ALTA,
  c.MIN_DESDE_ORIGINAL,
  `${o.CD_USER_STORE_B2} → ${c.CD_USER_STORE_B2}`,
  o.NU_CASO_ORIGEN || '(vacío)',
  `${o.RECIENTE} → ${c.RECIENTE}`,
  motivo,
]);

const md = ['| ' + cols.join(' | ') + ' |', '|' + '---|'.repeat(cols.length),
  ...filas.map(r => '| ' + r.join(' | ') + ' |')].join('\n');

console.log(`Pares original/copia disponibles en categoría 3-COPIA_REGRABADO: ${pares.length}`);
console.log(`Grupos (matrícula, persona) con re-grabado: ${porCantCopias.length}`);
console.log('');
console.log(md);
