// Validación de las categorías heurísticas del 24/09 (analizar_titulares_huerfanos.js)
// sobre los 477 titulares activos PF con ID_MATRICULA inexistente. 25/09/2026.
//
// Entradas (todas exportadas con RunQuery --csv, solo lectura):
//   scripts/out/validacion_huerfanos_01_dataset_<F>_bloque1.csv          una fila por huérfano
//   scripts/out/validacion_huerfanos_02_relacionados_<F>_bloque1.csv     huérfano x fila B2 real relacionada
//   scripts/out/validacion_huerfanos_03_trazas_id_<F>_bloque{1,2,3}.csv  una fila por ID huérfano + bandas
//   scripts/out/validacion_huerfanos_04_clave_alternativa_<F>_bloque1.csv  candidatas por NU_MATRICULA
//   scripts/out/validacion_huerfanos_05_r18_matriculacion_<F>_bloque1.csv  formularios R18 enlazados
// La categoría original se recalcula con la lógica del 24/09 (importada, no copiada).
//
// Salidas (scripts/out/): ANALISIS_TITULARES_MATRICULA_INEXISTENTE_DETALLE.csv, un CSV por
// sección (validacion_huerfanos_sN_*.csv) y reporte_validacion_titulares_huerfanos_<F>.md.
// NO genera DML. "CANDIDATO_ELIMINACION" = evidencia suficiente para que un humano revise.
//
// Uso: node scripts/analisis/validar_titulares_huerfanos.js [fecha_corte=2026-09-25]
const fs = require('fs');
const path = require('path');
const original = require('./analizar_titulares_huerfanos.js');

const RAIZ = path.resolve(__dirname, '..', '..');
const OUT = path.join(RAIZ, 'scripts', 'out');
const F = process.argv[2] || '2026-09-25';
const IN = n => path.join(OUT, `validacion_huerfanos_${n}_${F}_bloque1.csv`);

// ---------------------------------------------------------------- utilidades
function leerCsv(file, sep = ';') {
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
  return rows.slice(1).filter(x => x.length > 1).map(x => Object.fromEntries(H.map((h, i) => [h, x[i] ?? ''])));
}
const esc = v => { v = v == null ? '' : String(v); return /[;"\n\r]/.test(v) ? '"' + v.replace(/"/g, '""') + '"' : v; };
function escribirCsv(nombre, cols, filas) {
  fs.writeFileSync(path.join(OUT, nombre), '﻿' + [cols.join(';'), ...filas.map(r => cols.map(c => esc(r[c])).join(';'))].join('\r\n'), 'utf8');
}
const groupBy = (a, f) => a.reduce((m, x) => { const k = f(x); (m[k] = m[k] || []).push(x); return m; }, {});
const cuenta = (a, f) => Object.entries(groupBy(a, f)).map(([k, v]) => [k, v.length]).sort((x, y) => y[1] - x[1]);
const pct = (n, d) => (d ? (100 * n / d).toFixed(1) : '0.0');
const md = (cols, filas) => ['| ' + cols.join(' | ') + ' |', '|' + cols.map(() => '---').join('|') + '|', ...filas.map(r => '| ' + r.map(v => String(v ?? '').replace(/\|/g, '/')).join(' | ') + ' |')].join('\n');
const ts = s => (s ? new Date(s.slice(0, 19).replace(' ', 'T')) : null);
const n = v => (v === '' || v == null ? 0 : +v);
const minutos = (a, b) => (a && b ? Math.round((b - a) / 60000) : null);
const fmtMin = m => (m == null ? '' : m < 120 ? `${m} min` : m < 2880 ? `${(m / 60).toFixed(1)} h` : `${(m / 1440).toFixed(1)} d`);

// Nombre: normaliza y compara por tokens (tolera 1 error de tipeo en tokens >= 4).
const norm = s => (s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toUpperCase().replace(/[^A-Z ]/g, ' ').split(/\s+/).filter(t => t.length > 1);
function lev(a, b) {
  const d = Array.from({ length: a.length + 1 }, (_, i) => [i]);
  for (let j = 1; j <= b.length; j++) d[0][j] = j;
  for (let i = 1; i <= a.length; i++) for (let j = 1; j <= b.length; j++)
    d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
  return d[a.length][b.length];
}
function simNombre(x, y) {
  const a = norm(x), b = norm(y); if (!a.length || !b.length) return 0;
  const [c, l] = a.length <= b.length ? [a, b] : [b, a];
  return c.filter(t => l.some(u => u === t || (t.length >= 4 && lev(t, u) <= 1))).length / c.length;
}
const MISMO_NOMBRE = 0.6;

// ------------------------------------------------------------------ carga
const D = leerCsv(IN('01_dataset'));
const REL = leerCsv(IN('02_relacionados'));
const TR = Object.fromEntries(leerCsv(IN('03_trazas_id')).map(t => [t.ID_MATRICULA, t]));
const BANDAS_R00 = leerCsv(IN('03_trazas_id').replace('bloque1', 'bloque2'));
const BANDAS_HUERF = leerCsv(IN('03_trazas_id').replace('bloque1', 'bloque3'));
const KA = groupBy(leerCsv(IN('04_clave_alternativa')), k => k.ID_REGISTRO);
const R18 = groupBy(leerCsv(IN('05_r18_matriculacion')), k => k.ID_REGISTRO);
const RELX = groupBy(REL, x => x.ID_REGISTRO_HUERFANO);

// Categoría original (24/09): se recalcula con la misma lógica y se une por (ID, NU_SEQUENCE).
const CAT_ORIG = {};
original.marcarRegrabados(original.cargar()).forEach(r => { CAT_ORIG[r.ID_MATRICULA + '-' + r.NU_SEQUENCE] = original.clasificar(r)[0]; });
if (Object.keys(CAT_ORIG).length !== D.length) throw new Error('La categoría original no cubre las ' + D.length + ' filas');

const NOMBRE_BANDA = {
  A: 'A - 2 a 253.249 (rango de IDs creado por la migración)',
  B: 'B - 253.250 a 1.400.000 (sin ninguna fila en R00)',
  C: 'C - 1.400.001 a 1.736.177 (rango de IDs creado por la migración)',
  D: 'D - 1.736.178 a 4.999.999 (sin R00)',
  E: 'E - 5.000.000 a 6.396.110 (rango vivo del WORKFLOW)',
  F: 'F - mayor al máximo ID de R00',
};

// ------------------------------------------------------- enriquecimiento fila
D.forEach(r => {
  r.T = TR[r.ID_MATRICULA];
  r.BANDA = r.T.BANDA;
  r.CAT_ORIG = CAT_ORIG[r.ID_REGISTRO];
  r.ALTA = ts(r.DT_ALTA);
  r.rel = RELX[r.ID_REGISTRO] || [];
  const ka = KA[r.ID_REGISTRO] || [];
  r.S = ka.filter(k => k.HIPOTESIS === 'S');
  r.K = ka.filter(k => k.HIPOTESIS === 'K');
  r.R = ka.filter(k => k.HIPOTESIS === 'R');
  r.Tm = ka.filter(k => k.HIPOTESIS === 'T');
  r.r18 = R18[r.ID_REGISTRO] || [];
  r.hijas = n(r.T.A1_FILAS) + n(r.T.A2_FILAS) + n(r.T.B1_FILAS) + n(r.T.B3_FILAS) + n(r.T.B8_FILAS);
  r.migracion = n(r.FILA_EN_SNAPSHOT_2017) > 0 || (r.ALTA && r.ALTA < new Date('2017-08-19')) || !!r.MIG_FHPI_ID;
});

// Evalúa una matrícula candidata: ¿está la misma persona / el mismo documento como titular?
function evaluarCandidata(r, k) {
  const b2Rel = r.rel.filter(x => x.R_ID_MATRICULA === k.ID_CAND && (x.TIPO_VINCULO === 'P' || x.TIPO_VINCULO === 'D'));
  const nomB2 = k.DOC_B2_NOMBRE, nomB4 = k.DOC_B4_NOMBRE;
  const e = {
    persB2: n(k.PERS_TIT_B2) > 0, persB4: n(k.PERS_TIT_B4) > 0,
    docB2: n(k.DOC_TIT_B2) > 0 && simNombre(nomB2, r.NOMBRE_COMPLETO) >= MISMO_NOMBRE,
    docB4: n(k.DOC_TIT_B4) > 0 && simNombre(nomB4, r.NOMBRE_COMPLETO) >= MISMO_NOMBRE,
    docOtroNombre: (n(k.DOC_TIT_B2) > 0 && simNombre(nomB2, r.NOMBRE_COMPLETO) < MISMO_NOMBRE) ||
                   (n(k.DOC_TIT_B4) > 0 && simNombre(nomB4, r.NOMBRE_COMPLETO) < MISMO_NOMBRE),
    filaB2: (b2Rel.find(x => x.TIPO_VINCULO === 'P') || b2Rel[0]) || null,
    nomRel: nomB2 || nomB4 || '',
  };
  e.alguna = e.persB2 || e.persB4 || e.docB2 || e.docB4;
  return e;
}

// ----------------------------------------------------- familia (mecanismo)
// Candidatas a "la matrícula real a la que la fila pertenece" (query 04):
//   S+R18 / R  trámite de matriculación R18 con NU_MATRICULA_PRO = ID  (documentado)
//   K          el ID es el NU_MATRICULA completo                        (documentado)
//   T          misma procedencia tomo/foja/inscripción de la migración  (estructural)
//   S sin R18  número sin departamento, sin formulario que lo respalde  (numérico)
const RANGO_HIP = { SR: 0, R: 1, K: 2, T: 3, S: 4 };
const DOCUMENTADA = h => h === 'SR' || h === 'R' || h === 'K';
function candidatas(r) {
  const vistos = new Set(), out = [];
  const add = (k, hip) => { if (vistos.has(k.ID_CAND)) return; vistos.add(k.ID_CAND); out.push({ k, hip, e: evaluarCandidata(r, k) }); };
  const conR18 = id => r.r18.find(x => x.R18_CD_MATRICULA === id && x.PRO_IGUAL_ID_HUERFANO === '1') ||
                       r.r18.find(x => x.R18_CD_MATRICULA === id && x.VIA === 'CASO');
  r.S.filter(k => conR18(k.ID_CAND)).forEach(k => add(k, 'SR'));
  r.R.forEach(k => add(k, 'R'));
  r.K.forEach(k => add(k, 'K'));
  r.Tm.forEach(k => add(k, 'T'));
  r.S.forEach(k => add(k, 'S'));
  out.forEach(c => { c.r18 = conR18(c.k.ID_CAND); });
  const fuerza = e => (e.persB2 ? 0 : e.docB2 ? 1 : e.persB4 ? 2 : e.docB4 ? 3 : 9);
  return out.sort((a, b) => fuerza(a.e) - fuerza(b.e) || RANGO_HIP[a.hip] - RANGO_HIP[b.hip]);
}
const NOMBRE_FAM = { SR: 'MATRICULACION_CON_NUMERO_DE_PROCEDENCIA', R: 'MATRICULACION_CON_NUMERO_DE_PROCEDENCIA', K: 'CLAVE_NU_MATRICULA_COMPLETO', T: 'MATRICULA_MIGRADA_RE_MATRICULADA', S: 'NUMERO_SIN_DEPTO_SIN_R18' };
const ORIGEN_NU = { SR: 'NU_MATRICULA real = depto + ID huérfano (R18)', R: 'matrícula generada por el R18 cuya procedencia es el ID', K: 'ID = NU_MATRICULA de la matrícula real', T: 'misma procedencia tomo/foja/inscripción', S: 'NU_MATRICULA real = depto + ID huérfano (sin R18)' };
function textoMecanismo(r, c) {
  const k = c.k, x = c.r18;
  if ((c.hip === 'SR' || c.hip === 'R') && x)
    return `El trámite de matriculación (R18 ${x.R18_NU_FORMULARIO}, ${x.R18_DT_STORE.slice(0, 10)}, ${x.R18_USUARIO}${x.VIA === 'CASO' ? ', anexado al mismo caso ' + r.NU_CASO_ORIGEN : ''}) generó la matrícula ID ${k.ID_CAND} (${k.NU_CAND}) desde la procedencia "MAT ${x.NU_MATRICULA_PRO}" del depto ${x.R18_DEPTO_PROV}. La fila B2 quedó con ID_MATRICULA = ${r.ID_MATRICULA} (número de procedencia) en vez de ${k.ID_CAND}.`;
  if (c.hip === 'K') return `El ID ${r.ID_MATRICULA} es el NU_MATRICULA de la matrícula ID ${k.ID_CAND} (estado ${k.CAND_CD_ESTADO}).`;
  if (c.hip === 'T') return `El ID ${r.ID_MATRICULA} es una matrícula de la migración (V_PROCEDENCIA_DOMNIO_MIG) que ya no tiene cabecera en R00. La matrícula ID ${k.ID_CAND} (${k.NU_CAND || 'sin NU'}) tiene el mismo tomo/foja/inscripción/departamento: es la misma finca, re-matriculada.`;
  return `El ID es el número sin departamento de la matrícula ID ${k.ID_CAND} (${k.NU_CAND}), pero ningún R18 enlaza ambos.`;
}

function familia(r) {
  const out = { fam: '', rec: '', niv: '', motivo: '', mat: '', nuMat: '', origenNu: '', pers: '', caso: '', reg: '' };
  const set = (o) => Object.assign(out, o);
  const cs = candidatas(r);
  const mejor = cs.find(c => c.e.alguna && c.hip !== 'S') || cs.find(c => c.e.alguna);

  // 1. Hay una matrícula real explicada por un mecanismo, y el titular está ahí.
  if (mejor) {
    const { k, e, hip } = mejor, doc = DOCUMENTADA(hip), mec = textoMecanismo(r, mejor);
    set({ fam: NOMBRE_FAM[hip], mat: k.ID_CAND, nuMat: k.NU_CAND, origenNu: ORIGEN_NU[hip], caso: mejor.r18 ? (r.NU_CASO_ORIGEN || 'R18 ' + mejor.r18.R18_NU_FORMULARIO) : '' });
    if (e.persB2) return set({ rec: doc || hip === 'T' ? 'CANDIDATO_ELIMINACION' : 'REVISAR', niv: doc ? 'ALTO' : 'MEDIO', pers: r.CD_PERSONA,
      reg: e.filaB2?.ID_REGISTRO_RELACIONADO || '', motivo: mec + ' En esa matrícula la MISMA persona (CD_PERSONA) ya es titular ACTIVA: la fila huérfana repite una titularidad existente.' });
    if (e.docB2) return set({ rec: doc ? 'CANDIDATO_ELIMINACION' : 'REVISAR', niv: 'MEDIO', pers: e.filaB2?.R_CD_PERSONA || '',
      reg: e.filaB2?.ID_REGISTRO_RELACIONADO || '', motivo: mec + ` En esa matrícula otro registro de persona con el mismo documento y nombre compatible (${e.nomRel}) ya es titular ACTIVO. Es probable que sea la misma titularidad, pero mismo DNI no es misma persona.` });
    if (e.persB4) return set({ rec: doc ? 'CANDIDATO_ELIMINACION' : 'REVISAR', niv: 'MEDIO', pers: r.CD_PERSONA, reg: 'B4 de ' + k.ID_CAND,
      motivo: mec + ' En esa matrícula la MISMA persona figura como titular HISTÓRICO (B4): la titularidad ya está registrada y cerrada, y el huérfano la sigue mostrando como activa.' });
    return set({ rec: 'REVISAR', niv: 'MEDIO', reg: 'B4 de ' + k.ID_CAND,
      motivo: mec + ` En esa matrícula figura como histórico (B4) otro registro de persona con el mismo documento y nombre compatible (${e.nomRel}).` });
  }

  // 2. Cabecera R00 ausente con el resto del formulario vivo y una gemela con el titular.
  const gem = r.rel.filter(x => x.TIPO_VINCULO === 'N' || x.TIPO_VINCULO === 'G');
  const mismoTit = x => x.R_CD_PERSONA === r.CD_PERSONA || (r.NU_DOCUMENTO && x.R_NU_DOCUMENTO === r.NU_DOCUMENTO && simNombre(x.R_NOMBRE_COMPLETO, r.NOMBRE_COMPLETO) >= MISMO_NOMBRE);
  const gemDoc = gem.find(mismoTit);
  const casoDoc = r.rel.find(x => x.TIPO_VINCULO === 'C' && mismoTit(x));
  const conHijas = r.hijas > 0 && (r.BANDA === 'E' || r.BANDA === 'C');
  if (conHijas && (gemDoc || casoDoc)) {
    const g = gemDoc || casoDoc, mismoCaso = r.NU_CASO_ORIGEN && g.R_NU_CASO_ORIGEN === r.NU_CASO_ORIGEN;
    return set({ fam: 'CABECERA_R00_FALTANTE_CON_GEMELA', rec: 'CANDIDATO_ELIMINACION', niv: (mismoCaso || (gemDoc && casoDoc)) ? 'ALTO' : 'MEDIO',
      mat: g.R_ID_MATRICULA, nuMat: g.R_NU_MATRICULA, origenNu: gemDoc ? 'matrícula gemela por nomenclatura/padrón' : 'matrícula real del mismo caso',
      pers: g.R_CD_PERSONA, caso: g.R_NU_CASO_ORIGEN || r.NU_CASO_ORIGEN, reg: g.ID_REGISTRO_RELACIONADO,
      motivo: `El ID ${r.ID_MATRICULA} no tiene cabecera en R00 pero conserva ${r.hijas} filas hijas del formulario (procedencia, nomenclatura, padrón). La matrícula ID ${g.R_ID_MATRICULA} (${g.R_NU_MATRICULA}) ${gemDoc ? 'tiene la misma nomenclatura o padrón' : 'la generó el mismo caso'}${mismoCaso ? ' y comparte el caso de origen' : ''}, y ${g.R_CD_PERSONA === r.CD_PERSONA ? 'la misma persona' : 'el mismo documento'} es titular activo ahí. El trámite generó la matrícula dos veces y la primera quedó sin cabecera.` });
  }
  // 3. Mismo caso de origen en una matrícula real con el mismo titular.
  if (casoDoc) return set({ fam: 'MISMO_CASO_EN_MATRICULA_REAL', rec: 'CANDIDATO_ELIMINACION', niv: 'MEDIO',
    mat: casoDoc.R_ID_MATRICULA, nuMat: casoDoc.R_NU_MATRICULA, origenNu: 'matrícula real del mismo caso', pers: casoDoc.R_CD_PERSONA,
    caso: r.NU_CASO_ORIGEN, reg: casoDoc.ID_REGISTRO_RELACIONADO, motivo: `El caso ${r.NU_CASO_ORIGEN} grabó la misma titularidad en la matrícula real ID ${casoDoc.R_ID_MATRICULA}.` });

  // 4. Dato de la migración: se conserva salvo lo anterior.
  if (r.migracion) return set({ fam: 'HEREDADO_DE_MIGRACION', rec: 'CONSERVAR', niv: 'MEDIO',
    mat: cs[0]?.k.ID_CAND || '', nuMat: cs[0]?.k.NU_CAND || '', origenNu: cs[0] ? ORIGEN_NU[cs[0].hip] + ' (sin el titular)' : '',
    motivo: `La fila ya existía en la migración (${n(r.FILA_EN_SNAPSHOT_2017) ? 'está en DIG_DOC_R00_B2_20170902' : 'DT_ALTA ' + (r.DT_ALTA || '').slice(0, 10)})${r.hijas ? ' y el ID conserva ' + r.hijas + ' filas hijas en R00' : ''}. La matrícula ${r.ID_MATRICULA} no llegó a R00 o se borró después. Es historia registral, no una copia${cs[0] ? `. La candidata ${cs[0].k.ID_CAND} no tiene a esta persona como titular` : ''}.` });

  // 5. Mecanismo documentado (o gemela por tomo), pero el titular NO está en la matrícula real.
  const doc = cs.find(c => DOCUMENTADA(c.hip)) || cs.find(c => c.hip === 'T');
  if (doc) {
    const { k, hip, e } = doc, mec = textoMecanismo(r, doc);
    const sinTit = hip === 'K' ? { fam: 'NU_MATRICULA_COMPLETO_SIN_TITULAR', rec: 'REVISAR', niv: 'BAJO' }
                 : { fam: NOMBRE_FAM[hip] + '_SIN_TITULAR_EN_REAL', rec: 'CONSERVAR', niv: 'MEDIO' };
    return set({ ...sinTit, mat: k.ID_CAND, nuMat: k.NU_CAND, origenNu: ORIGEN_NU[hip], caso: doc.r18 ? (r.NU_CASO_ORIGEN || 'R18 ' + doc.r18.R18_NU_FORMULARIO) : '',
      motivo: mec + (e.docOtroNombre ? ` El documento aparece ahí con OTRO nombre (${e.nomRel}).` : '') +
        (hip === 'K' ? ' Pero ni la persona ni el documento son titulares ahí (ni en B2 ni en B4): puede ser una coincidencia numérica o una titularidad que nunca se trasladó.'
                     : ` Pero la persona NO figura como titular, ni activa ni histórica, en la matrícula ID ${k.ID_CAND}: la fila huérfana puede ser el único rastro de esa titularidad. Corresponde re-vincular tras verificar, no borrar.`) });
  }

  // 6. Cabecera ausente sin gemela con el titular, o matrícula migrada sin R00.
  if (conHijas && gem.length) return set({ fam: 'CABECERA_R00_FALTANTE_GEMELA_SIN_TITULAR', rec: 'REVISAR', niv: 'BAJO',
    mat: gem[0].R_ID_MATRICULA, nuMat: gem[0].R_NU_MATRICULA, origenNu: 'matrícula gemela por nomenclatura/padrón',
    motivo: `Sin cabecera R00, con filas hijas. La matrícula ID ${gem[0].R_ID_MATRICULA} tiene la misma nomenclatura o padrón, pero esta persona no es titular ahí: puede ser otro inmueble del mismo parcelario o una titularidad que no se trasladó.` });
  if (conHijas) return set({ fam: 'CABECERA_R00_FALTANTE_SIN_GEMELA', rec: 'CONSERVAR', niv: 'MEDIO',
    motivo: `Sin cabecera R00, pero con ${r.hijas} filas hijas del formulario${n(r.T.B4_FILAS) ? ' y ' + r.T.B4_FILAS + ' filas en B4' : ''}, y sin matrícula gemela ni titularidad equivalente. Parece una matrícula real a la que le falta la fila de R00: lo que falta es la cabecera, no sobra el titular.` });
  if (n(r.T.PROC_MIG_FILAS) > 0) return set({ fam: 'MATRICULA_MIGRADA_SIN_R00', rec: 'CONSERVAR', niv: 'BAJO',
    motivo: `El ID es una matrícula registrada por la migración (V_PROCEDENCIA_DOMNIO_MIG) cuya cabecera R00 ya no existe, y no hay otra matrícula con su tomo/foja donde esta persona sea titular. El WORKFLOW grabó la titularidad (${(r.DT_ALTA || '').slice(0, 10)}), así que la matrícula probablemente existía en ese momento y se borró después.` });

  // 7. Resto.
  const vecino = r.rel.find(x => x.TIPO_VINCULO === 'P' && Math.abs(+x.R_ID_MATRICULA - +r.ID_MATRICULA) <= 5);
  if (vecino) return set({ fam: 'ID_SIN_R00_TITULAR_EN_MATRICULA_VECINA', rec: 'REVISAR', niv: 'BAJO',
    mat: vecino.R_ID_MATRICULA, nuMat: vecino.R_NU_MATRICULA, origenNu: 'matrícula con ID contiguo', pers: vecino.R_CD_PERSONA, reg: vecino.ID_REGISTRO_RELACIONADO,
    motivo: `Sin cabecera ni hijas. La misma persona es titular de la matrícula con ID contiguo ${vecino.R_ID_MATRICULA}: puede ser un error de ±1 al elegir la matrícula, a confirmar con el asiento.` });
  return set({ fam: 'SIN_EXPLICACION', rec: 'INDETERMINADO', niv: 'NULO',
    motivo: `ID en banda ${r.BANDA} sin cabecera, sin filas hijas, sin R18 ni matrícula equivalente identificable${cs.length ? ' (el número coincide con ' + cs.map(c => c.k.NU_CAND).join(', ') + ', pero sin titular ni formulario que lo respalde)' : ''}.` });
}

// ---------------------------------------------- re-grabado (grupo mat+persona)
const RELEVANTES = ['CD_SITUACION', 'DT_DESDE', 'NU_NUMERADOR', 'NU_DENOMINADOR', 'DS_PORCENTAJE', 'CD_COLUM_2', 'NU_ASIEN_2'];
const MENORES = ['NU_CASO_ORIGEN', 'RECIENTE', 'CD_USER_STORE', 'CD_ESTA_2', 'DS_OBSERVA'];
const info = r => RELEVANTES.filter(c => r[c] !== '').length + (r.NU_CASO_ORIGEN ? 2 : 0);
const grupos = Object.values(groupBy(D, r => r.ID_MATRICULA + '|' + r.CD_PERSONA)).filter(g => g.length > 1);
grupos.forEach(g => {
  g.sort((a, b) => (a.ALTA ? +a.ALTA : 0) - (b.ALTA ? +b.ALTA : 0) || +a.NU_SEQUENCE - +b.NU_SEQUENCE);
  const keep = [...g].sort((a, b) => info(b) - info(a) || (a.ALTA ? +a.ALTA : 0) - (b.ALTA ? +b.ALTA : 0))[0];
  const clave = (c, v) => (c === 'DT_DESDE' && v ? v.slice(2) : v);
  const conflicto = RELEVANTES.filter(c => new Set(g.map(r => clave(c, r[c])).filter(v => v !== '')).size > 1);
  const truncado = new Set(g.map(r => r.DT_DESDE).filter(Boolean)).size > new Set(g.map(r => clave('DT_DESDE', r.DT_DESDE)).filter(Boolean)).size;
  const huecos = RELEVANTES.filter(c => !conflicto.includes(c) && g.some(r => r[c] === '') && new Set(g.map(r => r[c])).size > 1);
  const menores = MENORES.filter(c => new Set(g.map(r => r[c])).size > 1);
  const usuarios = new Set(g.map(r => r.CD_USER_STORE)).size;
  const altas = g.map(r => r.ALTA).filter(Boolean);
  const spanMin = altas.length > 1 ? minutos(altas[0], altas[altas.length - 1]) : 0;
  let tipo, expl;
  if (conflicto.length) { tipo = 'C'; expl = 'cambian datos relevantes: ' + conflicto.join(', '); }
  else if (huecos.length && (usuarios > 1 && spanMin > 1440)) { tipo = 'D'; expl = `difieren por datos vacíos (${huecos.join(', ')}), con ${usuarios} usuarios y ${fmtMin(spanMin)} entre la primera y la última: no se distingue si es completar o corregir`; }
  else if (huecos.length || menores.length || truncado) { tipo = 'B'; expl = 'diferencias menores: ' + [...huecos.map(c => c + ' vacío en alguna'), ...(truncado ? ['DT_DESDE con año truncado (00AA)'] : []), ...menores].join(', '); }
  else { tipo = 'A'; expl = 'idénticas salvo DT_ALTA / TM_DESDE / NU_SEQUENCE'; }
  g.forEach((r, i) => {
    r.G = { tipo, expl, keep, n: g.length, conflicto, orden: i + 1 };
    const prev = g[i - 1];
    r.G.intervaloPrev = prev ? minutos(prev.ALTA, r.ALTA) : null;
    r.G.vsKeep = r === keep ? null : {
      mismoUsuario: r.CD_USER_STORE === keep.CD_USER_STORE, mismoCaso: r.NU_CASO_ORIGEN === keep.NU_CASO_ORIGEN,
      mismaFechaDesde: r.DT_DESDE === keep.DT_DESDE, mismoDiaAlta: (r.DT_ALTA || '').slice(0, 10) === (keep.DT_ALTA || '').slice(0, 10),
      mismaSituacion: r.CD_SITUACION === keep.CD_SITUACION,
      mismoResto: RELEVANTES.every(c => r[c] === keep[c]) && MENORES.filter(c => c !== 'NU_CASO_ORIGEN' && c !== 'CD_USER_STORE').every(c => r[c] === keep[c]),
    };
  });
});

// --------------------------------------------------------- clasificación final
D.forEach(r => {
  const f = familia(r);
  r.FAM = f;
  r.E = (candidatas(r).find(c => c.k.ID_CAND === f.mat) || {}).e || {};
  let rec = f.rec, niv = f.niv, cat = f.fam, motivo = f.motivo, reg = f.reg;
  if (r.G && r.G.keep !== r) {
    const k = r.G.keep;
    const copia = `Además es la copia n.º ${r.G.orden} de ${r.G.n} de la misma titularidad en el mismo ID (tipo ${r.G.tipo}: ${r.G.expl}); se conserva como representante ${k.ID_REGISTRO}.`;
    if (rec !== 'CANDIDATO_ELIMINACION') {
      if (r.G.tipo === 'A') { rec = 'CANDIDATO_ELIMINACION'; niv = 'ALTO'; }
      else if (r.G.tipo === 'B') { rec = 'CANDIDATO_ELIMINACION'; niv = 'MEDIO'; }
      else { rec = 'REVISAR'; niv = niv === 'NULO' ? 'BAJO' : niv; }
      cat = 'COPIA_REGRABADO_' + r.G.tipo + ' / ' + cat;
      if (!reg) reg = k.ID_REGISTRO;
    } else cat = cat + ' + COPIA_' + r.G.tipo;
    motivo = motivo + ' ' + copia;
  }
  // Grupo tipo C (o D, ambiguo): las filas difieren en fecha desde / porcentaje / asiento. Pueden ser
  // actos de adquisición distintos: ninguna fila del grupo se propone sin revisión.
  if (r.G && (r.G.tipo === 'C' || r.G.tipo === 'D') && rec === 'CANDIDATO_ELIMINACION') {
    rec = 'REVISAR';
    if (!/COPIA/.test(cat)) cat += ' + GRUPO_' + r.G.tipo;
    motivo += ` El grupo (${r.G.n} filas) ${r.G.expl}: pueden ser actos distintos (otra fecha de adquisición u otro porcentaje), así que hay que compararlo con la matrícula real antes de tocarlo.`;
  }
  Object.assign(r, { CATEGORIA_VERIFICADA: cat, NIVEL_EVIDENCIA: niv, RECOMENDACION: rec, MOTIVO: motivo, REGISTRO_RELACIONADO: reg });
});

// ------------------------------------------------------------------- salidas
const detalle = D.map(r => ({
  ID_REGISTRO: r.ID_REGISTRO, CD_PERSONA: r.CD_PERSONA, NU_DOCUMENTO: r.NU_DOCUMENTO, NOMBRE: r.NOMBRE_COMPLETO,
  ID_MATRICULA: r.ID_MATRICULA, NU_MATRICULA: r.FAM.nuMat, ORIGEN_NU_MATRICULA: r.FAM.origenNu,
  CATEGORIA_ORIGINAL: r.CAT_ORIG, CATEGORIA_VERIFICADA: r.CATEGORIA_VERIFICADA, NIVEL_EVIDENCIA: r.NIVEL_EVIDENCIA,
  MOTIVO: r.MOTIVO, MATRICULA_RELACIONADA: r.FAM.mat, PERSONA_RELACIONADA: r.FAM.pers, CASO_RELACIONADO: r.FAM.caso,
  REGISTRO_RELACIONADO: r.REGISTRO_RELACIONADO, RECOMENDACION: r.RECOMENDACION,
  BANDA_ID: r.BANDA, DT_ALTA: r.DT_ALTA, CD_USER_STORE: r.CD_USER_STORE, NU_CASO_ORIGEN: r.NU_CASO_ORIGEN, RECIENTE: r.RECIENTE,
  GRUPO_COPIAS: r.G ? `${r.G.n} filas, tipo ${r.G.tipo}, representante ${r.G.keep.ID_REGISTRO}` : '',
}));
const COLS_DET = Object.keys(detalle[0]);
escribirCsv('ANALISIS_TITULARES_MATRICULA_INEXISTENTE_DETALLE.csv', COLS_DET, detalle);

// Sección 2: CLAVE_EQUIVOCADA (las 5 originales + toda fila con hipótesis K).
const s2 = [];
D.filter(r => r.CAT_ORIG.startsWith('1-') || r.K.length).forEach(r => {
  const k = r.K[0];
  const tits = r.rel.filter(x => x.TIPO_VINCULO === 'K');
  (tits.length ? tits : [{}]).forEach(t => s2.push({
    ID_REGISTRO: r.ID_REGISTRO, CATEGORIA_ORIGINAL: r.CAT_ORIG, CD_PERSONA: r.CD_PERSONA, NU_DOCUMENTO: r.NU_DOCUMENTO, NOMBRE: r.NOMBRE_COMPLETO,
    ID_MATRICULA_HUERFANO: r.ID_MATRICULA, ID_FORMULARIO_PERSONA: r.ID_FORMULARIO_PERSONA, NU_CASO_ORIGEN: r.NU_CASO_ORIGEN,
    CD_USER_STORE: r.CD_USER_STORE, DT_ALTA: r.DT_ALTA, TM_DESDE: r.TM_DESDE, CD_SITUACION: r.CD_SITUACION, DS_PORCENTAJE: r.DS_PORCENTAJE,
    EXISTE_COMO_NU_MATRICULA: k ? 'SI' : 'NO', ID_MATRICULA_REAL: k?.ID_CAND || '', NU_MATRICULA_REAL: k?.NU_CAND || '', ESTADO_REAL: k?.CAND_CD_ESTADO || '',
    PERSONA_TITULAR_ACTIVA_EN_REAL: k ? (n(k.PERS_TIT_B2) ? 'SI' : 'NO') : '', DOC_TITULAR_ACTIVO_EN_REAL: k ? (n(k.DOC_TIT_B2) ? 'SI' : 'NO') : '',
    DOC_TITULAR_HISTORICO_EN_REAL: k ? (n(k.DOC_TIT_B4) ? 'SI' : 'NO') : '',
    REAL_TIT_REGISTRO: t.ID_REGISTRO_RELACIONADO || '', REAL_TIT_CD_PERSONA: t.R_CD_PERSONA || '', REAL_TIT_DOCUMENTO: t.R_NU_DOCUMENTO || '',
    REAL_TIT_NOMBRE: t.R_NOMBRE_COMPLETO || '', REAL_TIT_CASO: t.R_NU_CASO_ORIGEN || '', REAL_TIT_USER: t.R_CD_USER_STORE || '',
    REAL_TIT_DT_ALTA: t.R_DT_ALTA || '', REAL_TIT_TM_DESDE: t.R_TM_DESDE || '', REAL_TIT_PORCENTAJE: t.R_DS_PORCENTAJE || '',
    VEREDICTO: r.CATEGORIA_VERIFICADA, NIVEL: r.NIVEL_EVIDENCIA,
  }));
});
escribirCsv(`validacion_huerfanos_s2_clave_equivocada_${F}.csv`, Object.keys(s2[0]), s2);

// Sección 3: BORRADOR_DE_TRAMITE — huérfano vs. registro real del mismo caso.
const s3 = D.filter(r => r.CAT_ORIG.startsWith('2-')).map(r => {
  const cs = r.rel.filter(x => x.TIPO_VINCULO === 'C');
  const gm = r.rel.filter(c => c.TIPO_VINCULO === 'N' || c.TIPO_VINCULO === 'G');
  const x = cs.find(c => c.R_CD_PERSONA === r.CD_PERSONA) || cs.find(c => c.R_NU_DOCUMENTO === r.NU_DOCUMENTO) ||
            gm.find(c => c.R_CD_PERSONA === r.CD_PERSONA || c.R_NU_DOCUMENTO === r.NU_DOCUMENTO) || gm[0] || cs[0] || {};
  const a = r.ALTA, b = ts(x.R_DT_ALTA);
  return {
    ID_REGISTRO: r.ID_REGISTRO, H_CD_PERSONA: r.CD_PERSONA, H_DOCUMENTO: r.NU_DOCUMENTO, H_NOMBRE: r.NOMBRE_COMPLETO, H_ID_MATRICULA: r.ID_MATRICULA,
    H_NU_CASO_ORIGEN: r.NU_CASO_ORIGEN, H_USER: r.CD_USER_STORE, H_DT_ALTA: r.DT_ALTA, H_TM_DESDE: r.TM_DESDE, H_SITUACION: r.CD_SITUACION, H_RECIENTE: r.RECIENTE,
    H_FILAS_HIJAS_R00: r.hijas, H_BANDA: r.BANDA,
    R_REGISTRO: x.ID_REGISTRO_RELACIONADO || '', R_ID_MATRICULA: x.R_ID_MATRICULA || '', R_NU_MATRICULA: x.R_NU_MATRICULA || '',
    R_CD_PERSONA: x.R_CD_PERSONA || '', R_DOCUMENTO: x.R_NU_DOCUMENTO || '', R_NOMBRE: x.R_NOMBRE_COMPLETO || '', R_NU_CASO_ORIGEN: x.R_NU_CASO_ORIGEN || '',
    R_USER: x.R_CD_USER_STORE || '', R_DT_ALTA: x.R_DT_ALTA || '', R_TM_DESDE: x.R_TM_DESDE || '', R_SITUACION: x.R_CD_SITUACION || '', R_RECIENTE: x.R_RECIENTE || '',
    R_MATRICULA_CREADA_R00: x.R_DT_STORE_R00 || '',
    REGISTROS_REALES_MISMO_CASO: cs.length, MATRICULAS_REALES_MISMO_CASO: new Set(cs.map(c => c.R_ID_MATRICULA)).size,
    DIFERENCIA: a && b ? fmtMin(Math.abs(minutos(a, b))) : !a && !b ? '(ninguno tiene DT_ALTA)' : !a ? '(huérfano sin DT_ALTA)' : '(real sin DT_ALTA)',
    TIPO_VINCULO_REAL: x.TIPO_VINCULO || '',
    MISMO_USUARIO: x.R_CD_USER_STORE ? (x.R_CD_USER_STORE === r.CD_USER_STORE ? 'SI' : 'NO') : '',
    MISMA_PERSONA: x.R_CD_PERSONA === r.CD_PERSONA ? 'SI' : 'NO', MISMO_DOCUMENTO: x.R_NU_DOCUMENTO === r.NU_DOCUMENTO ? 'SI' : 'NO',
    MISMO_CASO: 'SI', PRIMERO: a && b ? (a < b ? 'HUERFANO' : 'REAL') : (x.R_DT_STORE_R00 ? 'ver R00: real creada ' + x.R_DT_STORE_R00.slice(0, 10) : ''),
    VEREDICTO: r.CATEGORIA_VERIFICADA, NIVEL: r.NIVEL_EVIDENCIA, RECOMENDACION: r.RECOMENDACION,
  };
});
escribirCsv(`validacion_huerfanos_s3_borrador_tramite_${F}.csv`, Object.keys(s3[0]), s3);

// Sección 4: re-grabados, una fila por registro, ordenado por grupo y cronología.
const s4 = [];
grupos.sort((a, b) => +a[0].ID_MATRICULA - +b[0].ID_MATRICULA || +a[0].CD_PERSONA - +b[0].CD_PERSONA).forEach(g => g.forEach(r => {
  const v = r.G.vsKeep; const b = x => (x == null ? '' : x ? 'SI' : 'NO');
  s4.push({
    GRUPO: r.ID_MATRICULA + '|' + r.CD_PERSONA, TIPO_GRUPO: r.G.tipo, EXPLICACION_TIPO: r.G.expl, CANT_REGISTROS: r.G.n, ORDEN: r.G.orden,
    ES_REPRESENTANTE: r === r.G.keep ? 'SI' : 'NO', ID_REGISTRO: r.ID_REGISTRO, ID_MATRICULA: r.ID_MATRICULA, CD_PERSONA: r.CD_PERSONA,
    NU_DOCUMENTO: r.NU_DOCUMENTO, NOMBRE: r.NOMBRE_COMPLETO, CD_USER_STORE: r.CD_USER_STORE, DT_ALTA: r.DT_ALTA, TM_DESDE: r.TM_DESDE,
    DT_DESDE: r.DT_DESDE, RECIENTE: r.RECIENTE, NU_CASO_ORIGEN: r.NU_CASO_ORIGEN, CD_SITUACION: r.CD_SITUACION, DS_PORCENTAJE: r.DS_PORCENTAJE,
    NU_NUMERADOR: r.NU_NUMERADOR, NU_DENOMINADOR: r.NU_DENOMINADOR, NU_ASIEN_2: r.NU_ASIEN_2,
    INTERVALO_DESDE_ANTERIOR: fmtMin(r.G.intervaloPrev), MISMO_USUARIO: b(v?.mismoUsuario), MISMO_CASO: b(v?.mismoCaso),
    MISMA_FECHA_DESDE: b(v?.mismaFechaDesde), MISMO_DIA_ALTA: b(v?.mismoDiaAlta), MISMA_SITUACION: b(v?.mismaSituacion), MISMO_RESTO: b(v?.mismoResto),
    CATEGORIA_VERIFICADA: r.CATEGORIA_VERIFICADA, RECOMENDACION: r.RECOMENDACION,
  });
}));
escribirCsv(`validacion_huerfanos_s4_regrabado_${F}.csv`, Object.keys(s4[0]), s4);

// Sección 5: ORIGINAL_CON_TITULARIDAD_EN_OTRA.
function veredicto5(r) {
  if (r.RECOMENDACION === 'CANDIDATO_ELIMINACION' && r.NIVEL_EVIDENCIA === 'ALTO') return 'FUERTE_EVIDENCIA_DE_DUPLICADO';
  if (r.RECOMENDACION === 'CANDIDATO_ELIMINACION' || (r.RECOMENDACION === 'REVISAR' && r.NIVEL_EVIDENCIA === 'MEDIO')) return 'POSIBLE_DUPLICADO';
  if (r.RECOMENDACION === 'CONSERVAR') return 'POSIBLE_HISTORIA_REAL';
  return 'INDETERMINADO';
}
const s5 = D.filter(r => r.CAT_ORIG.startsWith('5-')).map(r => {
  const otras = [...new Set(r.rel.filter(x => x.TIPO_VINCULO === 'P' || x.TIPO_VINCULO === 'D').map(x => x.R_ID_MATRICULA))];
  r.V5 = veredicto5(r);
  return {
    ID_REGISTRO: r.ID_REGISTRO, CD_PERSONA: r.CD_PERSONA, NU_DOCUMENTO: r.NU_DOCUMENTO, NOMBRE: r.NOMBRE_COMPLETO, ID_MATRICULA: r.ID_MATRICULA,
    BANDA: r.BANDA, DT_ALTA: r.DT_ALTA, CD_USER_STORE: r.CD_USER_STORE, NU_CASO_ORIGEN: r.NU_CASO_ORIGEN,
    MATRICULAS_CON_OTRA_TITULARIDAD: otras.length, OTRAS_IDS: otras.slice(0, 8).join(' '),
    MATRICULA_VINCULADA_POR_MECANISMO: r.FAM.mat, OTRA_TITULARIDAD_ES_LA_VINCULADA: r.FAM.mat && otras.includes(r.FAM.mat) ? 'SI' : 'NO',
    VEREDICTO: r.V5, CATEGORIA_VERIFICADA: r.CATEGORIA_VERIFICADA, NIVEL: r.NIVEL_EVIDENCIA, EVIDENCIA: r.MOTIVO,
  };
});
escribirCsv(`validacion_huerfanos_s5_titularidad_en_otra_${F}.csv`, Object.keys(s5[0]), s5);

// Sección 6: ORIGINAL_UNICO.
const s6 = D.filter(r => r.CAT_ORIG.startsWith('6-')).map(r => ({
  ID_REGISTRO: r.ID_REGISTRO, CD_PERSONA: r.CD_PERSONA, NU_DOCUMENTO: r.NU_DOCUMENTO, NOMBRE: r.NOMBRE_COMPLETO, ID_MATRICULA: r.ID_MATRICULA,
  BANDA: r.BANDA, DT_ALTA: r.DT_ALTA, ANIO: (r.DT_ALTA || '').slice(0, 4) || '(sin DT_ALTA)', CD_USER_STORE: r.CD_USER_STORE,
  NU_CASO_ORIGEN: r.NU_CASO_ORIGEN, CASO_PROCESO: r.CASO_CD_PROCESS, ORIGEN_PERSONA: r.CD_USER_STORE_PERS,
  PERSONA_B4_FILAS: r.PERSONA_B4_FILAS, PERSONA_B4_EN_MAT_EXISTENTE: r.PERSONA_B4_MAT_EXISTENTE, DOC_B4_FILAS: r.DOC_B4_FILAS, PERSONA_B5_FILAS: r.PERSONA_B5_FILAS,
  FILA_EN_SNAPSHOT_2017: r.FILA_EN_SNAPSHOT_2017, FILAS_HIJAS_R00: r.hijas, B4_EN_EL_MISMO_ID: r.T.B4_FILAS,
  PATRON: r.CATEGORIA_VERIFICADA, RECOMENDACION: r.RECOMENDACION, NIVEL: r.NIVEL_EVIDENCIA, EVIDENCIA: r.MOTIVO,
}));
escribirCsv(`validacion_huerfanos_s6_original_unico_${F}.csv`, Object.keys(s6[0]), s6);

// --------------------------------------------------------------- reporte
const L = [];
const P = (...x) => L.push(...x);
const famBase = r => r.FAM.fam;
const nuniq = (a, f) => new Set(a.map(f)).size;
const tabla = (a, f, titulo) => md([titulo, 'Filas', '%'], cuenta(a, f).map(([k, v]) => [k, v, pct(v, a.length)]));
const cruz = (a, fr, fc, titulo) => {
  const cs = [...new Set(a.map(fc))].sort(); const rs = [...new Set(a.map(fr))].sort();
  return md([titulo, ...cs, 'Total'], rs.map(x => [x, ...cs.map(c => a.filter(r => fr(r) === x && fc(r) === c).length), a.filter(r => fr(r) === x).length]));
};

P(`# Validación de titulares activos PF con matrícula inexistente (${F})`, '',
  '> Etapa de validación, **sin ninguna modificación a la base**. Todo se obtuvo con `SELECT` (RunQuery, guardrail de solo lectura).',
  '> "CANDIDATO_ELIMINACION" significa evidencia suficiente para que una persona revise el caso antes de una eventual limpieza. **No hay DML en este documento.**', '',
  '**Fuentes reproducibles** (todas en `scripts/`):', '',
  '- `queries/validacion_huerfanos_01_dataset.sql`: una fila por titular huérfano, con los indicadores pedidos.',
  '- `queries/validacion_huerfanos_02_relacionados.sql`: cada huérfano contra sus registros reales relacionados (persona, documento, caso, NU_MATRICULA, nomenclatura, padrón, asientos del caso).',
  '- `queries/validacion_huerfanos_03_trazas_id.sql`: qué queda de cada ID huérfano en el resto del sistema, y la densidad de R00 por banda.',
  '- `queries/validacion_huerfanos_04_clave_alternativa.sql`: el ID como NU_MATRICULA completo o sin el prefijo de departamento.',
  '- `queries/validacion_huerfanos_05_r18_matriculacion.sql`: el formulario de matriculación (R18) de cada caso.',
  '- `analisis/validar_titulares_huerfanos.js`: las reglas, la clasificación y este reporte.', '',
  `Detalle fila por fila: \`scripts/out/ANALISIS_TITULARES_MATRICULA_INEXISTENTE_DETALLE.csv\`. Anexos por sección: \`scripts/out/validacion_huerfanos_s{2..6}_*_${F}.csv\`.`, '');

// 1-3
const conteoRec = cuenta(D, r => r.RECOMENDACION);
P('## 1. Universo analizado', '',
  `- **${D.length} filas** de \`DIG_DOC_R00_B2\` vivas (\`ELIMINADO=0\`), de persona física, con \`ID_MATRICULA\` inexistente en \`DIG_DOC_R00\`. Corresponden a **${nuniq(D, r => r.ID_MATRICULA)} IDs**, **${nuniq(D, r => r.CD_PERSONA)} CD_PERSONA** y **${nuniq(D, r => r.NU_DOCUMENTO)} documentos**. El universo coincide exacto con el CSV del 24/09.`,
  '- Clave física de fila: `(ID_MATRICULA, NU_SEQUENCE)`, única sobre las 477. B2 **no tiene** `NU_MATRICULA` ni `ID_FORMULARIO` propios: `ID_FORMULARIO` es el de la persona (`= CD_PERSONA`). `NU_MATRICULA` en el detalle es **inferido**; la columna `ORIGEN_NU_MATRICULA` dice de dónde sale.', '');
P('## 2. Cantidad por categoría', '', '### 2.1 Categoría original (24/09) contra categoría verificada', '',
  cruz(D, r => r.CAT_ORIG, r => famBase(r).replace(/_SIN_TITULAR_EN_REAL$/, '_SIN_TIT'), 'Original \\ Verificada (mecanismo)'), '',
  '> La categoría verificada describe el **mecanismo que explica la fila**. La condición de copia de otra fila huérfana se suma aparte, en la sección 4. Una fila puede ser, por ejemplo, `MATRICULACION_CON_NUMERO_DE_PROCEDENCIA` y además una copia.', '',
  '### 2.2 Recomendación', '', md(['Recomendación', 'Filas', '%'], conteoRec.map(([k, v]) => [k, v, pct(v, D.length)])), '',
  cruz(D, r => r.CAT_ORIG, r => r.RECOMENDACION, 'Original \\ Recomendación'), '');
P('## 3. Cantidad por nivel de evidencia', '', cruz(D, r => r.RECOMENDACION, r => r.NIVEL_EVIDENCIA, 'Recomendación \\ Nivel'), '',
  'Criterios de nivel:', '',
  '- **ALTO**: el mecanismo está documentado en la base (R18 o NU_MATRICULA), **y** la misma `CD_PERSONA` ya es titular **activa** en la matrícula real. También cuenta la copia idéntica (tipo A) de otra fila huérfana.',
  '- **MEDIO**: hay mecanismo, pero la coincidencia es solo por documento con nombre compatible, o la titularidad en la matrícula real es **histórica** (B4). También la copia con diferencias menores (tipo B).',
  '- **BAJO**: hay un indicio (número, nomenclatura o ID contiguo), pero no coincide el titular, o el documento aparece con otro nombre.',
  '- **NULO**: nada vincula la fila con otra titularidad.', '');

// 4 patrones
const S = D.filter(r => famBase(r).startsWith('MATRICULACION_CON_NUMERO'));
const SA = D.filter(r => r.BANDA === 'A' || r.BANDA === 'B');
const cab = D.filter(r => famBase(r).startsWith('CABECERA'));
P('## 4. Principales patrones encontrados', '',
  `### 4.1 CONFIRMADO en los datos: el trámite de matriculación grabó el número de la matrícula de procedencia como ID (${S.length} filas, ${pct(S.length, D.length)}%)`, '',
  `\`NU_MATRICULA\` tiene el formato \`<departamento><número de 8 dígitos>\` (400586391 = departamento 4, número 586391). De las ${SA.length} filas con ID en las bandas A y B:`, '',
  `- **${SA.filter(r => r.S.length).length}** tienen una matrícula real cuyo \`NU_MATRICULA\`, sin el departamento, es igual al ID huérfano. Siempre es una sola candidata.`,
  `- **${SA.filter(r => r.r18.some(x => x.PRO_IGUAL_ID_HUERFANO === '1' && r.S[0] && x.R18_CD_MATRICULA === r.S[0].ID_CAND)).length}** además tienen un formulario R18 ("Generación de Mat SIRC", procesos 1230/4029/4033/4035) con \`NU_MATRICULA_PRO\` = ID huérfano y \`CD_MATRICULA\` = esa matrícula real. En ${SA.filter(r => r.r18.some(x => x.VIA === 'CASO' && x.PRO_IGUAL_ID_HUERFANO === '1')).length} filas ese R18 está anexado **al mismo caso** que figura en \`NU_CASO_ORIGEN\`.`,
  `- En **${S.filter(r => r.E.alguna).length}** de las ${S.length} filas con mecanismo, la persona o el documento (con nombre compatible) es titular de la matrícula real. Casi siempre aparece como **histórico en B4**: ${S.filter(r => !r.E.persB2 && !r.E.docB2 && (r.E.persB4 || r.E.docB4)).length} solo en B4, ${S.filter(r => r.E.persB2 || r.E.docB2).length} activo en B2.`,
  '', 'Lectura: al matricular en SIRC un inmueble que venía de una matrícula anterior (procedencia "MAT n"), los titulares de la procedencia quedaron grabados en B2 con `ID_MATRICULA = n`, el número de procedencia, en vez del ID de la matrícula nueva. En la matrícula nueva esos mismos titulares aparecen en B4, porque después hubo una transferencia, o en B2. **El mecanismo es consistente fila por fila, pero es una inferencia sobre los datos. La confirmación del bug en el código la tiene que dar el equipo de SIRCLAN** (sección 12).', '',
  `Dato lateral que apunta al mecanismo: cuando la misma persona es titular ACTIVA en la matrícula real, esa fila real casi nunca tiene auditoría (${(()=>{const p=D.filter(r=>famBase(r).startsWith('MATRICULACION')).flatMap(r=>r.rel.filter(x=>x.TIPO_VINCULO==='P'&&x.R_ID_MATRICULA===r.FAM.mat));return p.filter(x=>!x.R_DT_ALTA).length+' de '+p.length;})()} filas sin \`DT_ALTA\` ni \`CD_USER_STORE\`). La fila huérfana del mismo caso, en cambio, sí tiene usuario y hora. Es compatible con dos caminos de grabación distintos: el motor del proceso graba sin auditoría en la matrícula correcta, y la pantalla del operador graba con auditoría usando el número de procedencia. Es una hipótesis para el equipo de SIRCLAN, no una conclusión.`, '',
  `### 4.2 CONFIRMADO: matrículas sin cabecera R00, con el resto del formulario vivo (${cab.length} filas)`, '',
  `${nuniq(D.filter(r => r.hijas > 0), r => r.ID_MATRICULA)} IDs huérfanos conservan filas en otras tablas del formulario R00: \`_A1\` (estado), \`_A2\` (asientos), \`_B1\` (procedencia), \`_B3\` (nomenclatura) y \`_B8\` (padrón). Todos están en las bandas E y C. Falta solamente la fila de \`DIG_DOC_R00\`, la cabecera. En los IDs 6.0M–6.39M (2023–2026), la nomenclatura catastral de ${cab.filter(r => famBase(r) === 'CABECERA_R00_FALTANTE_CON_GEMELA').length} filas coincide con la de una matrícula real creada unos IDs después, por el mismo proceso 4025 y a menudo con el mismo caso, y con la misma persona como titular activa. Parece un trámite que generó la matrícula dos veces, con la primera generación a medio borrar. **${cab.filter(r => !r.DT_ALTA && !r.CD_USER_STORE && r.RECIENTE === '').length} de esas ${cab.length} filas tienen \`DT_ALTA\`, \`CD_USER_STORE\` y \`RECIENTE\` nulos**, así que la categoría original "LEGADO_SIN_ALTA" es incorrecta: no son legado. El rango de ID y los vecinos de R00 las fechan en 2023–2026.`, '',
  `### 4.3 CONFIRMADO: el re-grabado existe, pero no siempre es una copia idéntica`, '',
  `${grupos.length} grupos (matrícula, persona) con más de una fila, que suman ${grupos.reduce((s, g) => s + g.length, 0)} filas: ` +
  Object.entries(groupBy(grupos, g => g[0].G.tipo)).sort().map(([t, g]) => `**${t}** = ${g.length} grupos`).join(', ') +
  '. Detalle en la sección 4 de los anexos (`s4`).', '',
  '### 4.4 Descartado: "ORIGINAL_UNICO" y "ORIGINAL_CON_TITULARIDAD_EN_OTRA" no son categorías reales', '',
  'Las dos se definían por la presencia o ausencia de la persona en **otras** matrículas **activas**, sin mirar B4 ni la matrícula a la que la fila en realidad pertenece. Al agregar el departamento al número, la mayoría de esas filas encuentra su matrícula (sección 5 y sección 6).', '');

// 5 casos representativos
const ej = (f, nMax = 1) => D.filter(f).slice(0, nMax);
const repr = [
  ...ej(r => r.ID_MATRICULA === '184' && r.NU_SEQUENCE === '0'),
  ...ej(r => r.ID_MATRICULA === '2083' && r.NU_SEQUENCE === '0'),
  ...ej(r => famBase(r) === 'MATRICULACION_CON_NUMERO_DE_PROCEDENCIA_SIN_TITULAR_EN_REAL'),
  ...ej(r => r.ID_MATRICULA === '6372231'),
  ...ej(r => famBase(r) === 'CABECERA_R00_FALTANTE_SIN_GEMELA'),
  ...ej(r => r.ID_MATRICULA === '800390493'),
  ...ej(r => r.ID_MATRICULA === '400013472'),
  ...ej(r => famBase(r) === 'HEREDADO_DE_MIGRACION'),
  ...ej(r => r.ID_MATRICULA === '5198683' && r.NU_SEQUENCE === '0'),
  ...ej(r => famBase(r) === 'SIN_EXPLICACION'),
];
P('## 5. Casos representativos', '', md(['Registro', 'Persona', 'Doc.', 'Alta / usuario', 'Verificada', 'Rec.', 'Evidencia'],
  repr.map(r => [r.ID_REGISTRO, r.NOMBRE_COMPLETO, r.NU_DOCUMENTO, (r.DT_ALTA || '(sin alta)').slice(0, 16) + ' ' + r.CD_USER_STORE, r.CATEGORIA_VERIFICADA, r.RECOMENDACION + ' / ' + r.NIVEL_EVIDENCIA, r.MOTIVO])), '');

// secciones detalladas del pedido (2 a 6)
const s2orig = D.filter(r => r.CAT_ORIG.startsWith('1-'));
P('### 5.1 CLAVE_EQUIVOCADA (pedido §2): los 5 casos, uno por uno', '');
s2orig.forEach(r => {
  const k = r.K[0]; const tits = r.rel.filter(x => x.TIPO_VINCULO === 'K');
  P(`**${r.ID_REGISTRO}** · ${r.NOMBRE_COMPLETO} (doc. ${r.NU_DOCUMENTO}, CD_PERSONA ${r.CD_PERSONA}) · alta ${r.DT_ALTA} por ${r.CD_USER_STORE} · TM_DESDE ${r.TM_DESDE} · caso ${r.NU_CASO_ORIGEN || '(vacío)'}`, '',
    `- ID_MATRICULA huérfano: **${r.ID_MATRICULA}**. ¿Existe como NU_MATRICULA? **${k ? 'Sí' : 'No'}**${k ? `: matrícula ID **${k.ID_CAND}**, NU ${k.NU_CAND}, estado ${k.CAND_CD_ESTADO}, depto ${k.CAND_DEPTO}` : ''}.`,
    `- Titulares activos de la matrícula real (${tits.length}): ${tits.map(t => `${t.R_NOMBRE_COMPLETO} (doc ${t.R_NU_DOCUMENTO}, CD_PERSONA ${t.R_CD_PERSONA}, alta ${t.R_DT_ALTA ? t.R_DT_ALTA.slice(0, 10) + ' ' + t.R_CD_USER_STORE : 's/d'}${t.R_NU_CASO_ORIGEN ? ', caso ' + t.R_NU_CASO_ORIGEN : ''})`).join('; ') || '—'}.`,
    `- ¿La misma persona/documento es titular ahí? Persona activa: ${k && n(k.PERS_TIT_B2) ? 'sí' : 'no'} · documento activo: ${k && n(k.DOC_TIT_B2) ? 'sí' : 'no'} · documento histórico (B4): ${k && n(k.DOC_TIT_B4) ? 'sí' : 'no'}.`,
    `- **Veredicto:** ${r.CATEGORIA_VERIFICADA} (${r.NIVEL_EVIDENCIA}). ${r.MOTIVO}`, '');
});
const kNo = D.filter(r => r.K.length && !r.CAT_ORIG.startsWith('1-'));
P(`Hay además **${kNo.length} filas** cuyo ID también es un NU_MATRICULA completo y que el 24/09 **no** se clasificaron como clave equivocada: ${[...new Set(kNo.map(r => r.ID_MATRICULA))].join(', ')}. En ${kNo.filter(r => famBase(r) === 'NU_MATRICULA_COMPLETO_SIN_TITULAR').length} de ellas la persona no es titular de la matrícula con ese número, así que la coincidencia numérica sola no alcanza. Por ejemplo, las tres filas GARCIA del ID 400013472 (alta 24/08/2018, LUGONZALEZ): la matrícula 400013472 existe (ID 1559363), pero sus titulares son otras personas.`, '',
  `**Respuesta a "¿realmente se cargó el NU_MATRICULA como ID?":** en las 5 filas originales el ID es, efectivamente, un NU_MATRICULA existente, y el titular activo coincide (${s2orig.filter(r => r.E.persB2).length} por CD_PERSONA y ${s2orig.filter(r => !r.E.persB2 && r.E.docB2).length} por documento con nombre compatible). Pero **"se tipeó el NU_MATRICULA en el campo ID" no es la mejor explicación**: en las 5 hay un R18 de matriculación cuyo \`NU_MATRICULA_PRO\` (procedencia) es exactamente ese número, y cuya \`CD_MATRICULA\` es la matrícula real. Es el mismo mecanismo de la sección 4.1: en GARAVAGLIA la procedencia se cargó con el departamento (800390493) y en NAVARRO sin él (53877, que casualmente también es un NU_MATRICULA de legado). Ver \`s2\`.`, '');

P('### 5.2 BORRADOR_DE_TRAMITE (pedido §3): comparación huérfano contra registro real', '',
  md(['Huérfano', 'Persona', 'Alta huérfano', 'Registro real', 'Matrícula real', 'Alta real', 'Δ', 'Mismo usuario', 'Misma persona', 'Mismo doc.', 'Primero', 'Veredicto'],
    s3.map(x => [x.ID_REGISTRO, x.H_NOMBRE, (x.H_DT_ALTA || '(sin alta)').slice(0, 16), x.R_REGISTRO, x.R_ID_MATRICULA + ' / ' + x.R_NU_MATRICULA, x.R_DT_ALTA.slice(0, 16), x.DIFERENCIA, x.MISMO_USUARIO, x.MISMA_PERSONA, x.MISMO_DOCUMENTO, x.PRIMERO, x.VEREDICTO + ' (' + x.NIVEL + ')'])), '',
  `**Lectura.** Los 19 son dos fenómenos distintos que la heurística juntó:`, '',
  `- **${s3.filter(x => x.H_BANDA === 'B').length} filas (ID en banda B)** son el mecanismo de la sección 4.1. El "caso compartido" es el mismo trámite de matriculación, que grabó a la persona una vez con el número de procedencia y otra vez en la matrícula nueva. Coinciden la persona y el caso, y en general el usuario. La diferencia es de minutos. No es un borrador: es la **misma titularidad grabada con dos claves**.`,
  `- **${s3.filter(x => x.H_BANDA === 'E').length} filas (IDs 6.372.231–6.372.244 y 6.372.514)** sí encajan con "borrador de trámite". Un mismo caso (proceso 4025) generó dos juegos de matrículas: el primero quedó sin cabecera R00 y el segundo existe, con IDs más altos, la **misma nomenclatura catastral uno a uno** y el mismo titular. Las huérfanas no tienen \`DT_ALTA\`, así que el orden se deduce de los IDs de R00 y de la fecha de creación de la matrícula real.`,
  `- Evidencia suficiente para leer el huérfano como residuo del trámite: **sí** en ${s3.filter(x => x.RECOMENDACION === 'CANDIDATO_ELIMINACION').length} de 19, porque coinciden la persona o el documento, el caso y la nomenclatura. **No** en ${s3.filter(x => x.RECOMENDACION !== 'CANDIDATO_ELIMINACION').length}, porque la persona no aparece en la matrícula real del caso, o porque esa matrícula es la gemela de otra parcela.`, '');

const tiposG = groupBy(grupos, g => g[0].G.tipo);
P('### 5.3 COPIA_REGRABADO (pedido §4): los grupos repetidos', '',
  md(['Tipo', 'Significado', 'Grupos', 'Filas'], [
    ['A', 'prácticamente idéntica (solo cambian DT_ALTA, TM_DESDE y NU_SEQUENCE)', (tiposG.A || []).length, (tiposG.A || []).flat().length],
    ['B', 'diferencias menores (caso vacío en la copia, RECIENTE, usuario, dato vacío completado en un mismo reintento)', (tiposG.B || []).length, (tiposG.B || []).flat().length],
    ['C', 'cambian datos relevantes (porcentaje, fecha desde, situación o asiento con valores distintos)', (tiposG.C || []).length, (tiposG.C || []).flat().length],
    ['D', 'ambiguo (difieren por datos vacíos, con usuarios distintos y más de 24 h de distancia)', (tiposG.D || []).length, (tiposG.D || []).flat().length],
  ]), '',
  `El 24/09 se contaron 83 grupos y 141 copias. Hoy se ven ${grupos.length} grupos con ${grupos.reduce((s, g) => s + g.length - 1, 0)} filas "de más". Es el mismo universo: la diferencia es qué fila se toma como original. Acá el representante es la fila con más datos (caso, porcentaje, desde, asiento), no la más vieja.`, '',
  '**Grupos donde la duplicación NO parece un simple regrabado (tipo C y D):**', '',
  md(['Grupo', 'Persona', 'Filas', 'Qué cambia', 'Usuarios', 'Primera → última alta'],
    [...(tiposG.C || []), ...(tiposG.D || [])].map(g => [g[0].ID_MATRICULA + '|' + g[0].CD_PERSONA, g[0].NOMBRE_COMPLETO, g.length, g[0].G.expl, [...new Set(g.map(r => r.CD_USER_STORE || '(vacío)'))].join(','), (g[0].DT_ALTA || '—').slice(0, 16) + ' → ' + (g[g.length - 1].DT_ALTA || '—').slice(0, 16)])), '');

const V5 = D.filter(r => r.CAT_ORIG.startsWith('5-'));
P('### 5.4 ORIGINAL_CON_TITULARIDAD_EN_OTRA (pedido §5)', '',
  md(['Veredicto', 'Filas', '%'], cuenta(V5, r => r.V5).map(([k, v]) => [k, v, pct(v, V5.length)])), '',
  cruz(V5, r => r.V5, r => famBase(r).replace(/_SIN_TITULAR_EN_REAL$/, '_SIN_TIT'), 'Veredicto \\ mecanismo'), '',
  `- En **${s5.filter(x => x.OTRA_TITULARIDAD_ES_LA_VINCULADA === 'SI').length}** filas, la "otra matrícula" donde la persona es titular activa **es la misma** matrícula a la que el mecanismo vincula el huérfano: no es otra titularidad, es la misma. En **${s5.filter(x => x.OTRA_TITULARIDAD_ES_LA_VINCULADA === 'NO').length}** es otro inmueble. Esas coincidencias solas no prueban nada: una persona puede tener varios inmuebles.`,
  '- **FUERTE_EVIDENCIA_DE_DUPLICADO**: el mecanismo está documentado (R18 o NU_MATRICULA) y la misma `CD_PERSONA` es titular activa en la matrícula real vinculada.',
  '- **POSIBLE_DUPLICADO**: el mecanismo está documentado, pero la titularidad real es histórica (B4) o la coincidencia es por documento con nombre compatible. También la copia de otra fila huérfana.',
  '- **POSIBLE_HISTORIA_REAL**: la persona no está en la matrícula vinculada, o la fila es de la migración, o es una matrícula sin cabecera y sin gemela. Borrarla puede destruir el único rastro de la titularidad.',
  '- **INDETERMINADO**: no hay nada que vincule la fila, salvo que la persona tiene otras titularidades sin relación.', '');

const V6 = D.filter(r => r.CAT_ORIG.startsWith('6-'));
P('### 5.5 ORIGINAL_UNICO (pedido §6): qué representan las 104', '',
  md(['Patrón', 'Filas', 'Recomendación dominante'], cuenta(V6, r => famBase(r)).map(([k, v]) => [k, v, cuenta(V6.filter(r => famBase(r) === k), r => r.RECOMENDACION)[0][0]])), '',
  `- Solo **${V6.filter(r => n(r.PERSONA_B4_FILAS) === 0 && n(r.DOC_B4_FILAS) === 0 && n(r.PERSONA_B5_FILAS) === 0).length}** de las 104 no tienen **ninguna** fila en B4 ni en B5, ni por persona ni por documento. Las demás tienen historia, casi siempre en la matrícula a la que el número lleva.`,
  `- Por año de alta: ${cuenta(V6, r => (r.DT_ALTA || '').slice(0, 4) || 'sin alta').sort().map(([k, v]) => k + '=' + v).join(', ')}.`,
  `- Por usuario (top 5): ${cuenta(V6, r => r.CD_USER_STORE || '(vacío)').slice(0, 5).map(([k, v]) => k + '=' + v).join(', ')}.`,
  `- Filas presentes en el snapshot de la migración (\`DIG_DOC_R00_B2_20170902\`): ${V6.filter(r => n(r.FILA_EN_SNAPSHOT_2017)).length}.`,
  '- **Ninguna se recomienda borrar por ser "única".** Las que quedan como `CANDIDATO_ELIMINACION` lo son por el mecanismo de la sección 4.1 con la misma persona en la matrícula real, o por ser copias.', '');

// 6-8
const byY = r => (r.DT_ALTA || '').slice(0, 4) || '(sin DT_ALTA)';
P('## 6. Patrones temporales', '', cruz(D, byY, r => famBase(r).split('_').slice(0, 2).join('_'), 'Año de alta \\ mecanismo'), '',
  'Días con más filas por mecanismo (¿carga en bloque?):', '',
  md(['Día', 'Filas', 'IDs', 'Usuarios', 'Mecanismo dominante'], Object.entries(groupBy(D.filter(r => r.DT_ALTA), r => r.DT_ALTA.slice(0, 10))).map(([d, g]) => [d, g.length, nuniq(g, r => r.ID_MATRICULA), [...new Set(g.map(r => r.CD_USER_STORE))].join(','), cuenta(g, famBase)[0][0]]).sort((a, b) => b[1] - a[1]).slice(0, 10)), '',
  `No hay un día de carga masiva: el día más cargado tiene ${Math.max(...Object.values(groupBy(D.filter(r => r.DT_ALTA), r => r.DT_ALTA.slice(0, 10))).map(g => g.length))} filas. El patrón es goteo continuo 2017–2026, compatible con un defecto del flujo normal de trabajo y no con una importación.`, '');
P('## 7. Patrones por usuario', '', md(['Usuario B2', 'Filas', 'IDs', 'Años', 'Mecanismo dominante', '% candidato'],
  Object.entries(groupBy(D, r => r.CD_USER_STORE || '(vacío)')).map(([u, g]) => [u, g.length, nuniq(g, r => r.ID_MATRICULA), [...new Set(g.map(r => (r.DT_ALTA || '').slice(0, 4)).filter(Boolean))].sort().join(','), cuenta(g, famBase)[0][0], pct(g.filter(r => r.RECOMENDACION === 'CANDIDATO_ELIMINACION').length, g.length)]).sort((a, b) => b[1] - a[1]).slice(0, 15)), '',
  `${nuniq(D.filter(r => r.CD_USER_STORE), r => r.CD_USER_STORE)} usuarios distintos. Ninguno concentra el problema: el mismo mecanismo (4.1) aparece con ${nuniq(S, r => r.CD_USER_STORE)} usuarios. Los usuarios hacen el trámite de matriculación; el ID lo pone el sistema. **Esto es correlación, no culpa de un operador.**`, '');
P('## 8. Patrones de migración y significado de las bandas de ID', '',
  'Densidad de `DIG_DOC_R00` por banda (bloque 2 de la query 03):', '',
  md(['Banda', 'Filas R00', 'Min ID', 'Max ID', 'DT_STORE min–max', 'Creadas por migración', 'Sin NU_MATRICULA'], BANDAS_R00.map(b => [NOMBRE_BANDA[b.BANDA], b.R00_FILAS, b.MIN_ID, b.MAX_ID, b.MIN_DT_STORE + ' – ' + b.MAX_DT_STORE, b.R00_MIGRACION, b.R00_SIN_NU_MATRICULA])), '',
  'Filas con ID inexistente por banda, en B2 hoy (todas las personas, vivas o no), en B4 y en el snapshot de B2 del 02/09/2017 (bloque 3):', '',
  md(['Tabla', 'Banda', 'Filas', 'IDs', 'Eliminadas', 'Alta mín.', 'Alta máx.'], BANDAS_HUERF.map(b => [b.TABLA, b.BANDA, b.FILAS, b.IDS, b.ELIMINADAS, b.MIN_ALTA, b.MAX_ALTA])), '',
  md(['Banda', 'Filas', 'IDs', 'Años de alta', 'Con R18 (4.1)', 'Con filas hijas R00', 'En snapshot 2017', 'Mecanismo dominante'],
    Object.entries(groupBy(D, r => r.BANDA)).sort().map(([b, g]) => [NOMBRE_BANDA[b], g.length, nuniq(g, r => r.ID_MATRICULA),
      [...new Set(g.map(r => (r.DT_ALTA || '').slice(0, 4) || 'nulo'))].sort().join(','), g.filter(r => famBase(r).startsWith('MATRICULACION')).length,
      g.filter(r => r.hijas > 0).length, g.filter(r => n(r.FILA_EN_SNAPSHOT_2017)).length, cuenta(g, famBase)[0][0]])), '',
  '**Qué significa cada banda** (los rangos son descriptivos. Ninguno se da por incorrecto por su valor):', '',
  '- **A (≤253.249) y C (1,4M–1,74M)** son los rangos de `ID_MATRICULA` que **creó la migración**: el 100% de sus filas de R00 tiene `DT_STORE = 2017-04-18` y usuario de migración. Pero las huérfanas de la banda A de hoy son todas posteriores (altas desde 11/2017), y el ID no es un "hueco" de ese rango: es un **número de matrícula sin departamento** que cae ahí por casualidad numérica. En la banda C (7 filas) el ID sí es de la migración: 4 filas del snapshot 2017 y 3 del WORKFLOW (2019 y 2024) sobre IDs cuyo R00 no existe.',
  '- **B (253.250–1.400.000)** nunca tuvo ninguna fila en R00 ni en el snapshot de 2017. No es un sistema anterior: son **números de matrícula sin departamento** (los números de matrícula por departamento llegan hasta ~1,4M). Todas las filas son del WORKFLOW, 2017–2025.',
  '- **D** no tiene huérfanas.',
  '- **E (5M–6,4M)** es el rango vivo del WORKFLOW, con dos sub-poblaciones. **E1 (5,0M–5,24M)**: IDs asignados por la migración (vecinos con `DT_STORE` 2017-04-18) cuya cabecera R00 ya no está, con filas de 2008 (snapshot) y altas del WORKFLOW de 2020–2023. **E2 (6,0M–6,39M)**: matrículas generadas en 2023–2026 por el proceso 4025, sin cabecera, con hijas y casi siempre con una gemela.',
  '- **F (>6.396.110)** son `NU_MATRICULA` completos (9 dígitos, formato depto+número) usados como ID: 6 filas, todas del 24/08/2018. Las 3 de GARAVAGLIA siguen el mecanismo 4.1: un R18 con procedencia "MAT 800390493" o "MAT 800433207", **con** departamento, y la persona activa en la matrícula real. Las 3 de GARCIA (ID 400013472) vienen de un R18 (68267, LUGONZALEZ) cuyo **propio** `CD_MATRICULA` es 400013472, un número y no un ID. El error ya estaba en el formulario de matriculación. La matrícula 400013472 existe (ID 1559363), pero con otros titulares: REVISAR.',
  `- El snapshot de migración \`DIG_DOC_R00_B2_20170902\` ya tenía **1.999 filas con ID inexistente** (bandas A, C y E), pero **casi ninguna sigue viva hoy**: solo ${D.filter(r => n(r.FILA_EN_SNAPSHOT_2017)).length} de las 477 estaban en el snapshot. El problema actual **no es herencia de la migración**. Es un defecto posterior del WORKFLOW (4.1 y 4.2) más un resto chico de datos de la migración.`, '');

// 9-12
P('## 9. Posibles causas (hipótesis, no causalidad)', '',
  md(['Hipótesis', 'Filas que explica', 'Evidencia', 'Estado'], [
    ['Bug de asignación de matrícula en "Generación de Mat SIRC" (R18): graba los titulares de la procedencia con ID = NU_MATRICULA_PRO (el número de procedencia, casi siempre sin departamento)', S.length + ' (+' + D.filter(r => famBase(r) === 'NUMERO_SIN_DEPTO_SIN_R18').length + ' sin R18)', 'R18 con NU_MATRICULA_PRO = ID y CD_MATRICULA = matrícula real; persona titular ahí; mismo caso', 'PROBABLE (patrón confirmado en datos, falta el código)'],
    ['Trámite que genera la matrícula dos veces (proceso 4025) y deja la primera sin cabecera R00', cab.length, 'Filas hijas vivas, gemela por nomenclatura con ID mayor, mismo caso, sin DT_ALTA', 'PROBABLE'],
    ['Re-grabado / doble submit de la misma titularidad', grupos.reduce((s, g) => s + g.length - 1, 0) + ' filas de más', 'Mismo usuario, minutos de distancia, datos iguales', 'CONFIRMADO en datos (tipo A/B)'],
    ['Error de carga manual en el formulario R18: NU_MATRICULA en el campo del ID', D.filter(r => famBase(r) === 'NU_MATRICULA_COMPLETO_SIN_TITULAR').length, 'R18 68267 con CD_MATRICULA = 400013472 (un número, no un ID); titulares distintos en la matrícula 400013472', 'PROBABLE, con pocos casos'],
    ['Matrícula de la migración borrada de R00 después de que el WORKFLOW le grabara titulares', D.filter(r => famBase(r).startsWith('MATRICULA_MIGRADA')).length, 'ID en V_PROCEDENCIA_DOMNIO_MIG y en el snapshot 2017, sin R00 hoy; a veces existe otra matrícula con el mismo tomo/foja/inscripción. De los 716.639 IDs de esa tabla, 2.393 ya no están en R00', 'PROBABLE (falta el log de bajas)'],
    ['Datos de la migración cuyo R00 no llegó o se borró', D.filter(r => famBase(r) === 'HEREDADO_DE_MIGRACION').length, 'Snapshot 2017, DT_ALTA anterior a 2017', 'CONFIRMADO en datos (pocas filas)'],
    ['Importación masiva', 0, 'No hay día de carga masiva ni usuario técnico dominante', 'DESCARTADA con estos datos'],
    ['Desfasaje del ambiente de desarrollo (R00 incompleto en dev)', '?', 'SIRCWEB.DIG_DOC_R00 (otra copia, analizada 10/09) tampoco tiene ninguno de los 197 IDs', 'POCO PROBABLE, pero sin verificar en producción'],
  ]), '');
const cons = D.filter(r => r.RECOMENDACION === 'CONSERVAR');
P('## 10. Casos que NO deben eliminarse', '', `**${cons.length} filas con recomendación CONSERVAR**, que por ahora no se tocan:`, '',
  md(['Patrón', 'Filas', 'Por qué no'], cuenta(cons, famBase).map(([k, v]) => [k, v, {
    MATRICULACION_CON_NUMERO_DE_PROCEDENCIA_SIN_TITULAR_EN_REAL: 'Es el único rastro de la persona en la matrícula real: hay que re-vincularla, no borrarla',
    NUMERO_SIN_DEPTO_SIN_R18_SIN_TITULAR_EN_REAL: 'Idem, con menos evidencia',
    CABECERA_R00_FALTANTE_SIN_GEMELA: 'Parece una matrícula real sin cabecera: lo que falta es R00',
    HEREDADO_DE_MIGRACION: 'Historia registral de la migración',
    MATRICULA_MIGRADA_SIN_R00: 'Titularidad sobre una matrícula de la migración que desapareció de R00: hay que recuperar la cabecera o encontrar la re-matriculación',
    MATRICULA_MIGRADA_RE_MATRICULADA_SIN_TITULAR_EN_REAL: 'Hay otra matrícula con el mismo tomo/foja, pero sin esta persona: puede ser el único rastro',
  }[k] || ''])), '',
  'Además, **ninguna fila con recomendación REVISAR o INDETERMINADO** debería entrar en una limpieza sin revisión caso por caso.', '');
P('## 11. Candidatos que merecen revisión prioritaria', '', 'Orden sugerido para la revisión humana:', '',
  `1. **CANDIDATO_ELIMINACION / ALTO (${D.filter(r => r.RECOMENDACION === 'CANDIDATO_ELIMINACION' && r.NIVEL_EVIDENCIA === 'ALTO').length} filas)**: son las que menos riesgo tienen y validan el protocolo.`,
  `2. **CANDIDATO_ELIMINACION / MEDIO (${D.filter(r => r.RECOMENDACION === 'CANDIDATO_ELIMINACION' && r.NIVEL_EVIDENCIA === 'MEDIO').length})**: casi todas son titularidades que en la matrícula real ya son históricas. Hay que confirmar que la historia de B4 es la correcta.`,
  `3. **REVISAR (${D.filter(r => r.RECOMENDACION === 'REVISAR').length})**: coincidencias por documento, la banda F, los grupos de copias tipo C y D.`, '');

const dml = fs.readFileSync(path.join(OUT, 'dml_borrado_titulares_huerfanos_propuesto_2026-09-24.sql'), 'utf8');
const dmlAct = [...dml.matchAll(/^DELETE FROM DIG_DOC_R00_B2 WHERE ID_MATRICULA = (\d+) AND NU_SEQUENCE = (\d+);/gm)].map(m => m[1] + '-' + m[2]);
const porId = Object.fromEntries(D.map(r => [r.ID_REGISTRO, r]));
const dmlMal = dmlAct.filter(k => porId[k] && porId[k].RECOMENDACION !== 'CANDIDATO_ELIMINACION');
P('### 11.1 Contraste con el DML propuesto el 24/09', '', `\`scripts/out/dml_borrado_titulares_huerfanos_propuesto_2026-09-24.sql\` deja **${dmlAct.length} DELETE activos** (categoría COPIA_REGRABADO). Con la validación de hoy, **${dmlMal.length} de ellos ya no son candidatos** y pasan a REVISAR. Son copias de grupos tipo C o D, donde las filas difieren en fecha desde, porcentaje o asiento, y pueden ser actos distintos. **Ese DML no debe usarse tal como está.** Las filas: ${dmlMal.join(', ')}.`, '');
P('## 12. Preguntas que requieren conocimiento funcional (equipo SIRCLAN)', '',
  '1. En "Generación de Mat SIRC" (R18, procesos 1230/4029/4033/4035), ¿qué código graba `DIG_DOC_R00_B2` para los titulares de la procedencia? ¿Puede usar `R18_A1.NU_MATRICULA_PRO` como `ID_MATRICULA`? ¿Sigue pasando hoy? (La última fila de este tipo es de 2025.)',
  '2. En esos trámites, ¿los titulares de la procedencia tienen que quedar activos en la matrícula nueva o pasar a histórico? Esto decide si una fila huérfana cuyo titular está en B4 de la matrícula real sobra, o si le falta una fila activa a la matrícula real.',
  '3. El proceso 4025 ("Generación asiento"), ¿puede crear el formulario R00 dos veces para el mismo caso? ¿Qué borra cuando se anula una generación, y por qué deja las tablas hijas y B2 y solo borra la cabecera?',
  '4. ¿Por qué las filas B2 que graba el 4025 quedan sin `DT_ALTA`, `CD_USER_STORE` ni `RECIENTE`? Eso contradice la regla de CLAUDE.md §3 de que `RECIENTE IS NULL` indica origen migración.',
  '5. ¿Los IDs de la banda E1 (5,0M–5,24M, asignados por la migración) se borraron de R00 a propósito (unificaciones o bajas) después de 2017? ¿Hay un log?',
  '6. ¿Qué es `SIRCWEB` (copia del 10/09 con las mismas tablas)? ¿Sirve como segunda fuente para comparar?',
  '7. ¿Las 6 filas de la banda F (24/08/2018, LUGONZALEZ y MEESPINOLA) vienen de una pantalla que pedía el número de matrícula en vez del ID?', '');

const REVISION = [
  ['184-3', 'Caso tipo del mecanismo 4.1 (R18 86194). Además, la copia difiere en el asiento (3 contra 1): ¿son dos actos?'],
  ['2083-0', 'Siete grabaciones de la misma titularidad en 4 días, con DT_DESDE vacío en algunas'],
  ['800390493-0', 'Procedencia cargada CON departamento: la misma persona activa en la real (ALTO)'],
  ['53877-1', 'Procedencia que coincide además con un NU_MATRICULA de legado (dos candidatas posibles)'],
  ['400013472-0', 'R18 con CD_MATRICULA = número (no ID): los titulares no están en la matrícula 400013472'],
  ['63111-0', 'Mecanismo 4.1, pero la persona NO está en la matrícula real: ¿titularidad perdida?'],
  ['6372231-0', 'Proceso 4025 que generó 8 matrículas dos veces (6372231–44 contra 6372245–53)'],
  ['6372237-0', 'Mismo caso, gemela por nomenclatura, pero con otro titular: ¿qué parcela es?'],
  ['6368677-0', 'Cabecera ausente con 4 asientos R14 que apuntan al ID huérfano: hay actos registrales sobre una matrícula sin cabecera'],
  ['1439223-1', 'Alta WORKFLOW de 2024 sobre un ID de la migración que no tiene R00'],
  ['5198683-0', 'Matrícula de la migración re-matriculada con el mismo tomo/foja (6351345). Hay 4 filas en 67 segundos'],
  ['5134600-1', 'ID E1 (con una fila de 2008 en el snapshot) y dos filas de 2020 2/3 y 1/3 de usuarios distintos'],
  ['216069-0', 'DELABALLE CELINA y CARINA: dos personas R62 (¿la misma?) con dos actos 2005/2007 cada una'],
  ['363631-0', 'BLAZQUEZ: 20% (2011) y 13,33% (2013) para las mismas tres personas BLAZQUEZ: parecen actos distintos, no copias'],
  ['100311-7', 'DT_DESDE con año truncado (0006-04-05) cargado por otro usuario 2 días después'],
  ['1400669-0', 'Fila de 2008 de la migración, matrícula sin R00 y sin titular en la gemela por tomo'],
  ['5050106-0', 'Matrícula migrada, gemela por tomo con otros titulares: posible titularidad perdida'],
];
P('## 13. Casos concretos para revisar con el equipo funcional', '',
  md(['Registro', 'Persona', 'Verificada', 'Recomendación', 'Por qué este caso'],
    REVISION.filter(([k]) => D.some(r => r.ID_REGISTRO === k)).map(([k, why]) => { const r = D.find(x => x.ID_REGISTRO === k); return [k, r.NOMBRE_COMPLETO, r.CATEGORIA_VERIFICADA, r.RECOMENDACION + ' / ' + r.NIVEL_EVIDENCIA, why]; })), '');

P('## Anexo — reglas de clasificación (en orden de aplicación)', '',
  '1. **Matrícula real candidata** (query 04). Se evalúan, en este orden de fuerza: **SR/R**, un R18 de matriculación con `NU_MATRICULA_PRO` = ID, por número o por el caso de la fila, cuya `CD_MATRICULA` existe; **K**, el ID es el NU_MATRICULA completo de una matrícula real; **T**, el ID es una matrícula de la migración y otra matrícula tiene el mismo tomo/foja/inscripción/departamento; **S**, el ID es `MOD(NU_MATRICULA, 10^8)` de una matrícula real, sin formulario que lo respalde. Se elige la candidata donde el titular coincide con más fuerza: la misma CD_PERSONA activa, después el mismo documento con nombre compatible activo, después la misma CD_PERSONA en B4, después el mismo documento en B4.',
  '2. **Con coincidencia de titular** → familia según la candidata (`MATRICULACION_CON_NUMERO_DE_PROCEDENCIA`, `CLAVE_NU_MATRICULA_COMPLETO`, `MATRICULA_MIGRADA_RE_MATRICULADA`). Si el mecanismo está documentado (SR/R/K): la misma CD_PERSONA activa → CANDIDATO ALTO; el documento activo o la misma CD_PERSONA en B4 → CANDIDATO MEDIO; el documento solo en B4 → REVISAR MEDIO. En T y S, nunca más que REVISAR, salvo T con la misma CD_PERSONA activa → CANDIDATO MEDIO. **Sin coincidencia de titular**, pero con mecanismo documentado o T → `*_SIN_TITULAR_EN_REAL` → CONSERVAR (re-vincular), salvo K → REVISAR BAJO. Este paso se aplica después de los puntos 3 a 5.',
  '3. **CABECERA_R00_FALTANTE_***: la fila tiene hijas en R00_A1/A2/B1/B3/B8. Con una gemela (nomenclatura o padrón) o una matrícula del mismo caso donde la misma persona o documento es titular → CANDIDATO (ALTO si además comparten caso). Con una gemela sin el titular → REVISAR. Sin gemela → CONSERVAR.',
  '4. **MISMO_CASO_EN_MATRICULA_REAL**: el mismo caso grabó la misma persona en una matrícula real → CANDIDATO MEDIO.',
  '5. **HEREDADO_DE_MIGRACION**: la fila está en el snapshot 2017, o tiene alta anterior al 19/08/2017, o tiene `MIG_FHPI_ID` → CONSERVAR.',
  '6. **ID_SIN_R00_TITULAR_EN_MATRICULA_VECINA**: la persona es titular de una matrícula con ID a ±5 → REVISAR BAJO.',
  '7. **SIN_EXPLICACION** → INDETERMINADO.',
  '8. **Copias**: dentro de cada grupo (ID, CD_PERSONA) se conserva como representante la fila con más datos. Las demás, si su regla no daba ya CANDIDATO, quedan así: tipo A → CANDIDATO ALTO; B → CANDIDATO MEDIO; C/D → REVISAR.',
  `9. "Nombre compatible": al menos el ${MISMO_NOMBRE * 100}% de los tokens del nombre más corto aparece en el otro, tolerando 1 error de tipeo en tokens de 4 letras o más. **Mismo documento nunca se toma por sí solo como misma persona.**`, '');

fs.writeFileSync(path.join(OUT, `reporte_validacion_titulares_huerfanos_${F}.md`), L.join('\n'), 'utf8');

console.log('Filas:', D.length);
console.log('Recomendación:', JSON.stringify(Object.fromEntries(conteoRec)));
console.log('Nivel:', JSON.stringify(Object.fromEntries(cuenta(D, r => r.RECOMENDACION + '/' + r.NIVEL_EVIDENCIA))));
console.log('Mecanismo:', JSON.stringify(Object.fromEntries(cuenta(D, famBase))));
console.log('Grupos copia:', grupos.length, JSON.stringify(Object.fromEntries(Object.entries(tiposG).map(([k, v]) => [k, v.length]))));
console.log('S5:', JSON.stringify(Object.fromEntries(cuenta(V5, r => r.V5))));
