// Gemelo sin dependencias de analizar_titulares_huerfanos.py (misma lógica,
// mismas salidas). Existe porque en esta máquina no hay Python (24/09/2026).
// Uso: node scripts/analisis/analizar_titulares_huerfanos.js
const fs = require('fs');
const path = require('path');

const RAIZ = path.resolve(__dirname, '..', '..');
const CSV_ORIGEN = path.join(RAIZ, 'docs', 'Titulares_activos_con_matricula_inexistente.csv');
const CSV_CRUCES = path.join(RAIZ, 'scripts', 'out', 'titularidad_huerfana_cruces_2026-09-24_bloque2.csv');
const CSV_CLAVE = path.join(RAIZ, 'scripts', 'out', 'titularidad_huerfana_clave_alternativa_2026-09-24_bloque2.csv');
const OUT = path.join(RAIZ, 'scripts', 'out');
const HOY = new Date().toISOString().slice(0, 10);
const MAX_ID_R00 = 6396110;

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
  // Columnas repetidas: igual que pandas, la segunda aparición lleva ".1".
  const H = rows[0].map((h, i) => rows[0].indexOf(h) < i ? h + '.1' : h);
  return rows.slice(1).filter(x => x.length > 1).map(x => Object.fromEntries(H.map((h, i) => [h, x[i]])));
}

const ts = s => (s ? new Date(s.slice(0, 19).replace(' ', 'T')) : null);
const pct = (n, d) => (d ? (n / d * 100).toFixed(1) : '0.0');
const quant = (a, p) => { const s = a.filter(v => v != null).sort((x, y) => x - y); if (!s.length) return null; const i = (s.length - 1) * p, lo = Math.floor(i); return +(s[lo] + (s[Math.ceil(i)] - s[lo]) * (i - lo)).toFixed(1); };
const groupBy = (a, f) => a.reduce((m, x) => { const k = f(x); (m[k] = m[k] || []).push(x); return m; }, {});

function mdTabla(cols, filas) {
  return ['| ' + cols.join(' | ') + ' |', '|' + '---|'.repeat(cols.length), ...filas.map(r => '| ' + r.join(' | ') + ' |')].join('\n');
}
function conteo(a, f, nombre, ordenarPorClave) {
  const g = Object.entries(groupBy(a, f)).map(([k, v]) => [k, v.length]);
  g.sort(ordenarPorClave ? (x, y) => (x[0] < y[0] ? -1 : 1) : (x, y) => y[1] - x[1]);
  return mdTabla([nombre, 'FILAS', '%'], g.map(([k, n]) => [k, n, pct(n, a.length)]));
}

function bandaId(i) {
  if (i <= 253249) return 'A - rango bajo con R00 (hueco)';
  if (i < 1400001) return 'B - 253.250 a 1.400.000 (rango sin ninguna fila en R00)';
  if (i <= 1736177) return 'C - 1,4M a 1,74M (hueco)';
  if (i < 5000000) return 'D - 1,74M a 5M (rango sin R00)';
  if (i <= MAX_ID_R00) return 'E - 5M a 6,4M (hueco, rango actual)';
  return 'F - mayor al máximo ID (formato NU_MATRICULA)';
}

function cargar() {
  const df = leerCsv(CSV_ORIGEN, ',').map(r => ({
    ...r,
    CD_USER_STORE_B2: r.CD_USER_STORE, CD_USER_STORE_R62: r['CD_USER_STORE.1'],
    ID_MATRICULA_N: +r.ID_MATRICULA, DT_ALTA_TS: ts(r.DT_ALTA), TM_DESDE_TS: ts(r.TM_DESDE),
  }));
  const key = (r, alta) => [r.ID_MATRICULA, r.CD_PERSONA, alta, r.NU_CASO_ORIGEN].join('|');
  const nth = {}; df.forEach(r => { const k = key(r, r.DT_ALTA.slice(0, 19)); r._K = k + '#' + (nth[k] = (nth[k] ?? -1) + 1); });
  if (fs.existsSync(CSV_CRUCES)) {
    const n2 = {}, idx = {};
    leerCsv(CSV_CRUCES, ';').forEach(x => { const k = key(x, x.DT_ALTA); idx[k + '#' + (n2[k] = (n2[k] ?? -1) + 1)] = x; });
    df.forEach(r => {
      const x = idx[r._K]; if (!x) throw new Error('Sin cruce para ' + r._K);
      for (const c of ['NU_SEQUENCE', 'MIG_FHPI_ID', 'CASO_ID_MAT_EXISTENTE']) r[c] = x[c];
      for (const c of ['PERSONA_EN_MAT_EXISTENTE', 'DOC_EN_MAT_EXISTENTE', 'CASO_EN_MAT_EXISTENTE', 'ID_ES_UN_NU_MATRICULA', 'FILAS_B4_MISMO_ID']) r[c] = +x[c] || 0;
    });
    df.cruces = true;
  }
  if (fs.existsSync(CSV_CLAVE)) {
    const idx = {}; leerCsv(CSV_CLAVE, ';').forEach(c => { idx[c.ID_MATRICULA + '|' + c.CD_PERSONA] = c; });
    df.forEach(r => { const c = idx[r.ID_MATRICULA + '|' + r.CD_PERSONA] || {}; r.DOC_TITULAR_EN_CANDIDATA = +c.DOC_TITULAR_EN_CANDIDATA || 0; r.ID_CANDIDATA = c.ID_CANDIDATA || ''; });
  }
  return df;
}

function marcarRegrabados(df) {
  // Original = la fila con NU_CASO_ORIGEN; si ninguna o varias, la de DT_ALTA más vieja.
  const t = d => (d ? d.getTime() : Infinity);
  Object.values(groupBy(df, r => r.ID_MATRICULA + '|' + r.CD_PERSONA)).forEach(g => {
    const o = [...g].sort((a, b) => (b.NU_CASO_ORIGEN ? 1 : 0) - (a.NU_CASO_ORIGEN ? 1 : 0) || t(a.DT_ALTA_TS) - t(b.DT_ALTA_TS))[0];
    g.forEach(r => {
      r.FILAS_MISMA_MAT_PERSONA = g.length;
      r.ES_ORIGINAL = r === o;
      r.MIN_DESDE_ORIGINAL = r.DT_ALTA_TS && o.DT_ALTA_TS ? +((r.DT_ALTA_TS - o.DT_ALTA_TS) / 60000).toFixed(1) : null;
      r.MISMO_USUARIO_ORIGINAL = r.CD_USER_STORE_B2 === o.CD_USER_STORE_B2;
    });
  });
  return df;
}

function clasificar(r) {
  if (r.ID_ES_UN_NU_MATRICULA > 0 && r.DOC_TITULAR_EN_CANDIDATA > 0)
    return ['1-CLAVE_EQUIVOCADA', 'BORRAR: se cargó el NU_MATRICULA como ID; la titularidad ya existe en la matrícula real'];
  if (r.CASO_EN_MAT_EXISTENTE > 0)
    return ['2-BORRADOR_DE_TRAMITE', 'BORRAR tras verificar: el mismo caso terminó creando otra matrícula que sí existe'];
  if (!r.ES_ORIGINAL)
    return ['3-COPIA_REGRABADO', 'BORRAR: copia de la misma titularidad en la misma matrícula'];
  if (!r.DT_ALTA_TS)
    return ['4-LEGADO_SIN_ALTA', 'REVISAR: sin DT_ALTA ni usuario (origen previo al WORKFLOW)'];
  if (r.DOC_EN_MAT_EXISTENTE > 0)
    return ['5-ORIGINAL_CON_TITULARIDAD_EN_OTRA', 'REVISAR (probable borrado): la persona/documento es titular vivo de otra matrícula existente'];
  return ['6-ORIGINAL_UNICO', 'NO BORRAR: única evidencia de titularidad de esa persona; investigar la matrícula'];
}

function main() {
  const df = marcarRegrabados(cargar());
  df.forEach(r => {
    r.BANDA_ID = bandaId(r.ID_MATRICULA_N);
    r.ORIGEN_FILA_B2 = r.MIG_FHPI_ID ? 'MIGRACION (MIG_FHPI_ID)' : (r.CD_USER_STORE_B2 === '' ? 'SIN ALTA / SIN USUARIO' : 'WORKFLOW (usuario)');
    [r.CATEGORIA, r.ACCION] = clasificar(r);
  });
  const nuniq = (a, f) => new Set(a.map(f)).size;

  const L = [`# Patrones — titulares activos PF con matrícula inexistente (${HOY})`, '',
    `Fuente: \`docs/Titulares_activos_con_matricula_inexistente.csv\` + cruces contra la base de desarrollo.`, ''];
  L.push('## 0. Estructura', '',
    `- Filas: **${df.length}** · matrículas distintas: **${nuniq(df, r => r.ID_MATRICULA)}** · personas (\`CD_PERSONA\`): **${nuniq(df, r => r.CD_PERSONA)}** · documentos: **${nuniq(df, r => r.NU_DOCUMENTO)}**`,
    '- Columnas repetidas en el volcado: `CD_USER_STORE` (B2 vs R62), `CD_SITUACION` (idéntica), `DESDE` = `DT_DESDE` truncado. Constantes: `TP_PERSONA=PF`, `ELIMINADO=0`.', '');

  const origenes = [...new Set(df.map(r => r.ORIGEN_FILA_B2))], r62 = [...new Set(df.map(r => r.CD_USER_STORE_R62))].sort();
  L.push('## 1. Origen', '', conteo(df, r => r.ORIGEN_FILA_B2, 'ORIGEN_FILA_B2'), '',
    'Origen de la fila B2 (filas) × origen del registro de persona en R62 (columnas):', '',
    mdTabla(['ORIGEN_FILA_B2', ...r62], origenes.map(o => [o, ...r62.map(u => df.filter(r => r.ORIGEN_FILA_B2 === o && r.CD_USER_STORE_R62 === u).length)])), '');

  const conAlta = df.filter(r => r.DT_ALTA_TS);
  const dias = Object.entries(groupBy(conAlta, r => r.DT_ALTA.slice(0, 10)))
    .map(([d, g]) => [d, g.length, nuniq(g, r => r.ID_MATRICULA), nuniq(g, r => r.CD_USER_STORE_B2)])
    .sort((a, b) => b[1] - a[1]).slice(0, 10);
  const usuarios = conteo(df, r => r.CD_USER_STORE_B2 || '(vacío)', 'USUARIO').split('\n').slice(0, 12).join('\n');
  L.push('## 2. Distribución temporal (DT_ALTA de la fila B2)', '',
    conteo(df, r => (r.DT_ALTA ? r.DT_ALTA.slice(0, 4) : '(sin DT_ALTA)'), 'AÑO', true), '',
    'Días con más filas (¿carga en bloque?):', '', mdTabla(['DIA', 'FILAS', 'MATRICULAS', 'USUARIOS'], dias), '',
    `Usuarios distintos en B2: **${nuniq(df.filter(r => r.CD_USER_STORE_B2), r => r.CD_USER_STORE_B2)}**. Top 10:`, '', usuarios, '');

  const grupos = Object.values(groupBy(df, r => r.ID_MATRICULA + '|' + r.CD_PERSONA));
  const copias = df.filter(r => !r.ES_ORIGINAL), origs = df.filter(r => r.ES_ORIGINAL);
  const tmEq = a => a.filter(r => r.TM_DESDE_TS && r.DT_ALTA_TS && +r.TM_DESDE_TS === +r.DT_ALTA_TS).length;
  const mins = copias.map(r => r.MIN_DESDE_ORIGINAL);
  L.push('## 3. Re-grabado de la misma titularidad', '',
    `- (matrícula, persona) con más de una fila: **${grupos.filter(g => g.length > 1).length}** de ${grupos.length}; filas copia: **${copias.length}**`,
    `- Copias con el mismo usuario que la original: **${pct(copias.filter(r => r.MISMO_USUARIO_ORIGINAL).length, copias.length)}%**`,
    `- Copias sin \`NU_CASO_ORIGEN\`: **${pct(copias.filter(r => !r.NU_CASO_ORIGEN).length, copias.length)}%** · con \`RECIENTE=1\`: **${pct(copias.filter(r => r.RECIENTE === '1').length, copias.length)}%**`,
    `- Minutos entre la original y la copia: mediana **${quant(mins, .5)}**, p75 ${quant(mins, .75)}, p90 ${quant(mins, .9)}; copias dentro de las 24 h: **${pct(mins.filter(m => m != null && m <= 1440).length, copias.length)}%**`,
    `- \`TM_DESDE\` igual a \`DT_ALTA\` en copias: **${pct(tmEq(copias), copias.length)}%** vs originales: ${pct(tmEq(origs), origs.length)}%`, '');

  const porDoc = Object.values(groupBy(df, r => r.ID_MATRICULA + '|' + r.NU_DOCUMENTO)).map(g => nuniq(g, r => r.CD_PERSONA));
  L.push('## 4. Persona duplicada en R62 (mismo documento, distinto CD_PERSONA, misma matrícula)', '',
    conteo(porDoc.map(n => ({ n })), x => x.n, 'CD_PERSONA_DISTINTOS', true), '');

  const bandas = Object.entries(groupBy(df, r => r.BANDA_ID)).sort().map(([b, g]) => [b, g.length, nuniq(g, r => r.ID_MATRICULA)]);
  L.push('## 5. Rango del ID_MATRICULA huérfano', '', mdTabla(['BANDA_ID', 'FILAS', 'MATRICULAS'], bandas), '');

  if (df.cruces) {
    const n = f => df.filter(f).length;
    L.push('## 6. Cruces contra la base', '',
      `- Persona (\`CD_PERSONA\`) titular viva en otra matrícula existente: **${n(r => r.PERSONA_EN_MAT_EXISTENTE > 0)}** filas`,
      `- Documento titular vivo en otra matrícula existente: **${n(r => r.DOC_EN_MAT_EXISTENTE > 0)}** filas`,
      `- Mismo \`NU_CASO_ORIGEN\` en una matrícula existente: **${n(r => r.CASO_EN_MAT_EXISTENTE > 0)}** filas`,
      `- ID coincide con un \`NU_MATRICULA\` real: **${n(r => r.ID_ES_UN_NU_MATRICULA > 0)}** filas (y la persona es titular ahí: **${n(r => r.DOC_TITULAR_EN_CANDIDATA > 0)}**)`,
      `- ID huérfano con filas también en B4: **${n(r => r.FILAS_B4_MISMO_ID > 0)}** filas`, '');
  }

  const cats = Object.entries(groupBy(df, r => r.CATEGORIA + '\u0000' + r.ACCION)).sort()
    .map(([k, g]) => [...k.split('\u0000'), g.length, nuniq(g, r => r.ID_MATRICULA)]);
  L.push('## 7. Clasificación heurística propuesta', '', mdTabla(['CATEGORIA', 'ACCION', 'FILAS', 'MATRICULAS'], cats), '');

  fs.mkdirSync(OUT, { recursive: true });
  fs.writeFileSync(path.join(OUT, `reporte_patrones_titulares_huerfanos_${HOY}.md`), L.join('\n'), 'utf8');
  const cols = ['ID_MATRICULA', 'CD_PERSONA', 'NU_DOCUMENTO', 'NM_APELLIDO', 'NM_NOMBRE', 'NU_CASO_ORIGEN', 'DT_ALTA', 'CD_USER_STORE_B2', 'RECIENTE', 'DS_PORCENTAJE', 'BANDA_ID', 'ORIGEN_FILA_B2', 'FILAS_MISMA_MAT_PERSONA', 'ES_ORIGINAL', 'MIN_DESDE_ORIGINAL', 'CATEGORIA', 'ACCION'];
  const esc = v => { v = v == null ? '' : String(v); return /[;"\n\r]/.test(v) ? '"' + v.replace(/"/g, '""') + '"' : v; };
  const orden = [...df].sort((a, b) => a.ID_MATRICULA_N - b.ID_MATRICULA_N || (a.CD_PERSONA < b.CD_PERSONA ? -1 : a.CD_PERSONA > b.CD_PERSONA ? 1 : 0) || ((a.DT_ALTA_TS || 0) - (b.DT_ALTA_TS || 0)));
  fs.writeFileSync(path.join(OUT, `titulares_huerfanos_clasificados_${HOY}.csv`),
    '﻿' + [cols.join(';'), ...orden.map(r => cols.map(c => esc(c === 'ES_ORIGINAL' ? (r[c] ? 'True' : 'False') : r[c])).join(';'))].join('\r\n'), 'utf8');
  console.log(L.join('\n'));
}

main();
