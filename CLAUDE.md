# SIRCLAN — Depuración de Titulares Duplicados

> Contexto de proyecto para retomar el trabajo con un asistente de código.
> Última actualización: 18 de septiembre de 2026 — **se armó el entregable de personas
> físicas duplicadas para Mónica**: 6 CSV en `scripts/out/` (Resumen, Detalle priorizado
> de los 55.918 grupos, 67 casos representativos con su candidato propuesto, y las 2.868
> matrículas con doble titular), más su guía de armado
> `scripts/out/README_entregable_2026-09-18.md`. Se rehízo `vinculadas_listado_grupos_pf.sql`
> con el filtro de matrícula real + `ELIMINADO` (pendiente de §10, ya cerrado) y se le
> agregó a `RunQuery` salida UTF-8 y modo `--csv`, que resuelve el artefacto de acentos y
> de filas partidas de los exports. Ver §3 "Entregable del 18/09". **Sin validación contra
> RENAPER: por decisión del usuario, las columnas de validación van vacías para completar
> a mano.**
>
> Nota previa (17/09) — **el bloqueante de `ELIMINADO` /
> `RECIENTE` está resuelto**: `ELIMINADO=1` en `DIG_DOC_R00_B2`/`_B5` es baja lógica real
> (verificado, ver §3 "Verificación ELIMINADO/RECIENTE"); ya se aplicó como filtro en las
> queries de impacto registral. `RECIENTE` se investigó y **no** es un flag de baja — no
> se filtra. **Ya no queda ningún bloqueante pendiente para publicar cifras.**
>
> Nota previa (17/09, mismo día) — **el alcance se volvió a recortar**: el corte del 16/09
> contaba como "vinculada" a cualquier persona presente en B2/B4/B5 sin mirar si el
> inmueble tiene `NU_MATRICULA` real. Con ese filtro (+ `ELIMINADO`) el universo de trabajo
> queda en **55.918 grupos** (30.136 P1), de 60.847. Ver §3 "Corte con matrícula REAL —
> 17/09/2026".
>
> Nota previa (16/09) — **cambio de alcance ya medido**: tras
> la reunión con Mónica el universo de trabajo pasó a ser solo las personas vinculadas a
> una matrícula, y las queries `scripts/queries/vinculadas_*.sql` ya se corrieron. El
> alcance nuevo es de **60.847 grupos** (de 121.852), con 34.055 de prioridad 1. Ver §3
> "Corte del universo vinculado a matrículas", §5 (primeros dos bullets) y §10
> (Prioridad 1). Pendiente bloqueante antes de publicar cifras: verificar `ELIMINADO` /
> `RECIENTE` en `DIG_DOC_R00_B2`.

---

## 0. Reglas de trabajo en este repositorio

**`docs/` es de SOLO LECTURA.**
Nunca editar, sobrescribir, renombrar, mover ni borrar ningún archivo dentro de
`docs/`. Son entregables y fuente de verdad del usuario: el informe ya presentado, el
Excel de análisis manual y la trazabilidad de queries. Si algo de ahí está
desactualizado o difiere de lo que se ve hoy en la base (ver §3), **reportarlo, no arreglarlo**: se
propone el cambio y lo aplica el usuario, o se genera un archivo nuevo **fuera** de
`docs/`. Esto incluye no "regenerar" el `.docx` ni el `.xlsx` desde script.

Otras reglas:

- **Nada de escrituras a la base.** El acceso a Oracle es de solo lectura (DBeaver +
  jump host + túnel SSH). No proponer `UPDATE`/`DELETE`/`MERGE` para correr; los DML de
  fusión se escriben como entregable a revisar, no para ejecutar.
- **Desde el 17/09/2026, Claude puede correr las queries directamente**, sin pasar por
  DBeaver: `scripts/db-tools/RunQuery.java` reusa el mismo túnel SSH (necesita DBeaver
  conectado) y el mismo usuario de Oracle — no es una cuenta de solo lectura a nivel de
  grants, así que el propio script rechaza cualquier statement que no sea `SELECT`/`WITH`
  antes de conectarse. Ver `scripts/db-tools/README.md`. Sigue sin haber cuenta de Oracle
  de solo lectura real (pendiente, ver §10).
- **No pegarle a la API de RENAPER sin confirmar.** Es una API interna del organismo;
  cualquier corrida masiva se acuerda antes (ver §10, rate/concurrencia).
- **No inventar cifras.** Toda cifra que se cite tiene que estar en §3 con su fuente y su
  fecha de corte. Hay tres cortes distintos conviviendo y es fácil mezclarlos.
- **Salidas y temporales** van a `scripts/out/` (crear si hace falta) o al scratchpad de
  la sesión — nunca a `docs/` ni sueltos en la raíz.

---

## 1. Inventario de archivos

| Ruta | Qué es | Estado | ¿Editable? |
|---|---|---|---|
| `CLAUDE.md` | Este contexto | Vigente | Sí |
| `docs/Informe_Estado_Base_SIRCLAN_con_ejemplos.docx` | Informe de Estado de Base, 25/08/2026, con Anexo I (casos ELASKAR y MAREU S.A.S.) | **Hecho por otro desarrollador y ya presentado** (ver §3, procedencia). Cifras distintas a las del Excel | **NO** |
| `docs/Metodologia_Queries_SIRCLAN.md` | Trazabilidad de las ~30 queries usadas para armar el informe, con intentos fallidos, correcciones y el valor "guardado" de cada una | Vigente y muy útil: es el historial de cómo se llegó a cada número | **NO** |
| `docs/Titulares BD.xlsx` | Planilla de trabajo: 2 hojas de KPIs (PF/PJ) con la base refrescada, 2 hojas de recuperables, 20 hojas de casos revisados a mano, 1 plantilla | Vigente — es el corte de datos **más nuevo** y el log de la revisión manual (ver §8) | **NO** |
| `scripts/CalculadorCuil.java` | Cálculo de CUIL desde DNI + `CD_SEXO` (mod-11 AFIP/ARCA) | Probado contra un caso real | Sí |
| `scripts/ValidadorPersonaApi.java` | Cliente de la API RENAPER + comparación contra el candidato de la base | Probado con respuestas reales pegadas a mano | Sí |
| `scripts/DetectorMezclados.java` | Clustering por similitud de nombre para separar "personas mezcladas" | Probado contra 9 casos reales | Sí |
| `scripts/EvaluadorLote.java` | Corre `DetectorMezclados` sobre un lote exportado de la base (tabla Markdown) y elige candidato por grupo. Desde el 18/09 escribe el CSV con BOM y separador `;`, igual que `RunQuery --csv` | Corrido 18/09/2026 sobre los 67 casos del entregable | Sí |
| `scripts/queries/README.md` | Índice y convenciones de las queries SQL | Vigente | Sí |
| `scripts/queries/consultas.sql` | Las 4 queries "Opción B" parametrizadas por `:p_nu_documento` (detalle de un caso) | Vigente | Sí |
| `scripts/queries/distribucion_estratos_pf.sql`, `pj_kpi_sin_placeholder.sql` | KPI corridos el 16/09/2026 (resultados en `resultado-*.md`) | Vigentes | Sí |
| `scripts/queries/muestra_aleatoria_estratificada.sql`, `muestra_detalle_persona_base.sql` | Muestra aleatoria por estrato de tamaño, sin correr | Reemplazadas por `vinculadas_muestra_estratificada.sql` para el piloto | Sí |
| `scripts/queries/vinculadas_*.sql` (7 archivos) | Universo filtrado por vínculo a matrícula (§5): KPI PF/PJ, distribución cruzada, matrículas afectadas, lista de trabajo priorizada, muestra y doble titular en la misma matrícula | 5 corridas el 16/09/2026 (§3, resultados en `resultados-vinculadas/`); faltan la de PJ y la de doble titular | Sí |
| `scripts/queries/resultados-vinculadas/` | Exports crudos de DBeaver de las queries `vinculadas_*` corridas el 16/09/2026 | Vigente — fuente de las cifras de §3 | Sí (son salidas, no entregables) |
| `scripts/queries/recuperables_documento_cero.sql` | Personas con documento `'0'` recuperables por campo alternativo (produjo la hoja "Recuperables dni 0") | Vigente | Sí |
| `scripts/queries/censo_matriculas_r00.sql` | Censo de `DIG_DOC_R00` por `CD_ESTADO` (§3, "Censo de matrículas") | Corrida 17/09/2026 | Sí |
| `scripts/queries/vinculadas_matricula_real_kpi_pf.sql` | Rehace el corte del universo vinculado exigiendo `NU_MATRICULA IS NOT NULL` y `NVL(ELIMINADO,0)=0` (§3, "Corte con matrícula REAL") | Corrida 17/09/2026 | Sí |
| `scripts/queries/vinculadas_matricula_real_muestra.sql` | Lote de revisión manual sobre ese universo (60 documentos, muestra reproducible por `ORA_HASH`) + detalle de matrículas | Corrida 17/09/2026 → `scripts/out/lote_revision_manual_matricula_real_2026-09-17.md` | Sí |
| `scripts/queries/titularidad_matricula_inexistente.sql` | Detalle de las filas de titularidad (B2/B4/B5) cuyo `ID_MATRICULA` no existe en `DIG_DOC_R00` (§3, hallazgo del 17/09) | Corrida 18/09/2026 → `scripts/out/titularidad_matricula_inexistente_2026-09-18.md` — confirma 519/38/0, ver §7 | Sí |
| `scripts/queries/vinculadas_doble_titular_misma_matricula_detalle.sql` | Bloque 2 (detalle fila por fila) de `vinculadas_doble_titular_misma_matricula.sql`, separado a archivo propio | Corrida 18/09/2026 → `scripts/out/vinculadas_doble_titular_misma_matricula_detalle_2026-09-18.md` — 3.362 filas, 2.868 matrículas distintas, ver §3 | Sí |
| `scripts/queries/vinculadas_matricula_real_listado_grupos_pf.sql` | Lista de trabajo definitiva: una fila por grupo de los 55.918, priorizada P1/P2/P3, con matrícula real + `ELIMINADO` filtrados. Rehace `vinculadas_listado_grupos_pf.sql` (pendiente de §10, cerrado) | Corrida 18/09/2026 → `scripts/out/detalle_grupos_priorizado_2026-09-18.csv` — 55.918 filas, cierra exacto contra §3 | Sí |
| `scripts/queries/casos_representativos_pf.sql` | Los 67 casos del entregable (59 de muestra aleatoria + 8 emblemáticos), registro por registro de `DIG_DOC_R62` con `CD_SEXO`, `CD_USER_STORE`, `DT_NACIMIENTO` y columnas vacías para validar a mano; bloque 2 con sus matrículas | Corrida 18/09/2026 → `scripts/out/casos_representativos_*_2026-09-18.csv` | Sí |
| `scripts/queries/titularidad_huerfana_cruces.sql`, `titularidad_huerfana_clave_alternativa.sql` | Cruces de las 477 titularidades B2 PF vivas con matrícula inexistente (`docs/Titulares_activos_con_matricula_inexistente.csv`): columnas MIG_*, caso de origen en matrícula existente, ID que en realidad es un `NU_MATRICULA`, densidad de IDs de R00 | Corridas 24/09/2026 → `scripts/out/titularidad_huerfana_*_2026-09-24_bloque*.csv` | Sí |
| `scripts/analisis/analizar_titulares_huerfanos.py` + gemelo `.js` | Análisis de patrones de esas 477 filas y clasificación heurística (borrar / revisar / no borrar). El `.py` (Pandas) **no se pudo ejecutar** (no hay Python); el `.js` tiene la misma lógica y sí se corrió | 24/09/2026 → `scripts/out/reporte_patrones_titulares_huerfanos_2026-09-24.md` + `titulares_huerfanos_clasificados_2026-09-24.csv` | Sí |
| `scripts/out/README_entregable_2026-09-18.md` + los 6 `*_2026-09-18.csv` | **Entregable del 18/09 para Mónica**: guía de armado + Resumen, Detalle priorizado, casos representativos (registros / candidato / matrículas) y doble titular. CSV con BOM UTF-8 y separador `;` | Vigente — ver §3 "Entregable del 18/09" | Sí (son salidas) |
| `scripts/db-tools/RunQuery.java` + `README.md` | Corredor de queries de solo lectura contra Oracle, reusando el túnel SSH de DBeaver (JDBC Thin, `lib/ojdbc11.jar`). **Desde el 18/09: salida UTF-8 siempre + modo `--csv`** (BOM, separador `;`, comillado RFC 4180) | Probado y funcionando 18/09/2026 | Sí |

**No existen en el repo** (son archivos del usuario, en otra carpeta):
`Propuesta_Normalizacion_Titulares.docx`, `DER_titulares.png` y el DDL de PostgreSQL. No
asumir su contenido.

**Pendiente de cargar en `scripts/queries/`:** las 4 queries del patrón "Opción B" (las
pasa el usuario) y las que el desarrollador del informe original le compartió para
reproducir los valores del `.docx`.

> Existía un `Contexto_Proyecto_Depuracion_Titulares.md` en la raíz (contexto para un
> Project de claude.ai, con fecha 14/09). Se borró el 15/09/2026 por estar desactualizado
> y contradecir este archivo; lo único que tenía y no estaba en otro lado —la query de
> recuperables— se rescató a `scripts/queries/`.

---

## 2. Descripción del proyecto

Migración de datos del Poder Judicial (Mendoza): la base Oracle de un sistema BPM
"enlatado" (**SIRCLAN**) tiene registros duplicados de titulares de inmuebles (personas
físicas y jurídicas), porque históricamente resultó más rápido cargar una persona nueva
que buscar si ya existía.

- **Origen:** Oracle (SIRCLAN), acceso de solo lectura vía DBeaver (jump host + túnel
  SSH), base de desarrollo desactualizada ~2 semanas. Sin foreign keys declaradas — las
  relaciones se manejan por código de aplicación, no por constraints.
- **Etapa actual aprobada (acotada por la jefa, Mónica):** detectar duplicados de
  personas físicas y jurídicas, validar personas físicas contra la API interna
  (RENAPER), y entregar un Excel con detalle + números agregados (hoja Resumen + hoja
  Detalle). Los **números** son lo que más le importa mostrar primero.
- **Destino final (etapa futura, NO aprobada todavía):** base normalizada en
  **PostgreSQL** (motor ya decidido por el equipo, no proponer otro) + microservicio de
  sincronización SIRCLAN ↔ base nueva. El borrador de DER, DDL e informe de propuesta
  existe pero **fuera de este repo y sin revisar** — no dar por válido su contenido
  (ver §10).

**Estado actual:** etapa de análisis de datos y diseño de metodología, antes de escalar
al procesamiento automático de los ~121.800 grupos de personas físicas. Las tres piezas
centrales de lógica (cálculo de CUIL, validación contra la API, detección de personas
mezcladas) ya están construidas y probadas contra casos reales. Falta (a) confirmar que
esa lógica se sostiene en una muestra representativa real — no solo los casos más
extremos revisados hasta ahora, ver §7 — y (b) decidir la orquestación a escala.

**Cambio de alcance (16/09/2026, reunión con Mónica):** el filtro pasa a ser la
**vinculación a matrículas** — solo se revisan los grupos de duplicados que tienen
registros colgando de `DIG_DOC_R00_B2` / `_B4` / `_B5`. Los ~121.800 grupos dejan de ser
el universo de trabajo y pasan a ser la línea de base contra la cual se mide el recorte.
Las cifras del universo nuevo están **pendientes de medir** (§10, queries
`scripts/queries/vinculadas_*.sql`); hasta que se corran, no hay número de alcance que
mostrar. Ver §5 para el criterio completo.

---

## 3. Volumetría — tres cortes conviviendo (¡ojo con mezclarlos!)

### Procedencia y criterio

- El **informe `.docx` lo hizo otro desarrollador**, antes de que el usuario tomara el
  tema, y **ya fue presentado**. No es material propio ni se corrige acá: se cita como
  antecedente, nada más.
- La **`Metodologia_Queries_SIRCLAN.md`** documenta cómo ese desarrollador llegó a esos
  valores; parte de esas queries se las pasó al usuario para reproducirlos.
- El **Excel `Titulares BD.xlsx` es trabajo propio del usuario**: consultas corridas por
  él contra la base, con los resultados guardados hoja por hoja.

**Regla:** para cualquier cifra nueva se usa el **Excel**. Es lo más reciente y es
verificable contra la base actual.

**Por qué difieren los números:** se está trabajando contra la **base de desarrollo**, que
se refresca cada tanto y va ~2 semanas atrás de producción. Parte de la diferencia entre
el `.docx` y el Excel es legítima (la base cambió entre una medición y la otra), y parte
es metodológica (el informe no excluye los placeholders). No hay que tratar las
discrepancias como errores a reconciliar — sí hay que no mezclar cortes dentro de un
mismo entregable.

### Personas físicas

| Métrica | Informe .docx (25/08) | Metodología (corregido) | **Excel `Titulares BD` (vigente, base refrescada)** |
|---|---|---|---|
| Total personas cargadas (PF+PJ) | 1.039.219 | — | **1.040.238** |
| Total personas físicas | 982.926 | 982.926 | **983.839** |
| Sin documento (`NU_DOCUMENTO` NULL) | no relevado | no relevado | **163.986** (de las cuales **2.516 recuperables**) |
| Documentos placeholder | 7.100 | 7.100 | **7.111** (desglose abajo) |
| **Grupos** de documento duplicado | 121.670 (v. inicial) | 121.663 | **121.793** |
| **Registros redundantes** (copias de más) | **169.315** ❌ | 162.225 | **162.491** |
| Documentos extranjeros duplicados | — | — | **59** |

> ⚠️ El **169.315** del informe y el "17,2%" derivado se calcularon **antes de excluir los
> placeholders** — no sirven como base de trabajo. El informe ya presentado los muestra y
> así queda (§3, procedencia); simplemente no se reusan.
>
> ⚠️ **121.793 son GRUPOS; 162.491 son REGISTROS redundantes.** La versión anterior de
> este CLAUDE.md decía "~170.000 grupos" — era falso, confundía ambas cosas. Esto cambia
> la escala del piloto y del consumo de la API: **una llamada por grupo ⇒ ~122.000
> llamadas, no ~170.000.**

Desglose de placeholders PF (Excel, con recuperables entre paréntesis):
`0` = 7.042 (416) · `00` = 21 (1) · `000` = 3 (1) · `000000` = 2 · `0000000` = 4 ·
`00000000` = 3 · `1` = 16 · `99907804` = 20 (datos distintos en cada registro).

### Personas jurídicas

| Métrica | Informe .docx | **Excel (vigente)** |
|---|---|---|
| Total personas jurídicas | 56.293 | **56.399** |
| Sin CUIT cargado (NULL) | 12.307 | **12.322** |
| CUIT inválido (longitud ≠ 11) | 11.593 | **11.782** |
| Grupos de CUIT duplicado | 5.803 | **5.813** |
| Registros redundantes | 13.295 | 13.295 (⚠️ mismo valor: **no fue recalculado**) |

> ⚠️ El 13.295 **todavía incluye el placeholder `30999078040`** (563 registros bajo 31
> razones sociales distintas — "CUIT cajón de sastre", no una empresa real). Pendiente de
> recalcular (ver §10). ~42% de las PJ no tiene CUIT utilizable → no deduplicable
> automáticamente, es deuda técnica documentada.

### Corte adicional — 16/09/2026 (distribución por estrato PF y PJ sin placeholder)

Resultado de correr [scripts/queries/distribucion_estratos_pf.sql](scripts/queries/distribucion_estratos_pf.sql)
y [scripts/queries/pj_kpi_sin_placeholder.sql](scripts/queries/pj_kpi_sin_placeholder.sql) contra la base de
desarrollo el 16/09/2026 (mismo criterio de exclusión de placeholders que la Query 14 de
`Metodologia_Queries_SIRCLAN.md`).

**Distribución de los grupos de PF por cantidad de duplicados:**

| Estrato | Grupos | % del total | Registros redundantes |
|---|---|---|---|
| Bajo (2-3) | 113.959 | 93,5% | 134.833 |
| Medio (4-6) | 7.545 | 6,2% | 25.279 |
| Alto (7-10) | 328 | 0,27% | 2.156 |
| Muy alto (11+, máx. 18) | 20 | 0,016% | 223 |
| **Total** | **121.852** | 100% | **162.491** |

> ⚠️ El total de grupos (121.852) da **59 más** que el 121.793 del Excel — misma
> diferencia exacta que "Documentos extranjeros duplicados" (§3, tabla PF), pero no está
> confirmado que sea la causa; puede ser también drift normal entre cortes de la base de
> desarrollo (§3, "Por qué difieren los números"). El total de **registros redundantes
> coincide exacto con el Excel: 162.491 = 162.491.**
>
> **Conclusión clave para el piloto:** el 93,5% de los grupos tiene solo 2-3 duplicados.
> La muestra revisada hasta ahora (§7, ~70% "mezclados") viene de los grupos más grandes,
> que son el 0,3% de la población — confirma que ese sesgo es real y que hace falta la
> muestra aleatoria estratificada (§10). También implica que el "techo de tamaño de
> grupo" pendiente (§5, §10) es casi irrelevante en volumen: solo 20 grupos superan los
> 10 duplicados, se pueden revisar todos a mano en vez de diseñar una regla general.

**PJ recalculado excluyendo el placeholder `30999078040`:**

| Métrica | Valor (16/09/2026) |
|---|---|
| Sin CUIT | 12.322 |
| CUIT inválido (longitud ≠ 11) | 11.598 |
| CUIT `30999078040` (placeholder, excluido) | 566 (creció de 563 — sigue activo) |
| Grupos de CUIT duplicado | 5.814 |
| **Registros redundantes** | **12.787** |

> Comparar 1 a 1 contra el 13.295/5.813 de la tabla de arriba no es directo: además de
> sacar el placeholder, pasó tiempo entre cortes (mismo fenómeno de drift que en PF). El
> número a usar de acá en más para "registros redundantes PJ" es **12.787**.

### Corte del universo vinculado a matrículas — 16/09/2026 (VIGENTE para alcance)

Resultado de correr las queries `scripts/queries/vinculadas_*.sql` contra la base de
desarrollo el 16/09/2026. Exports crudos en
`scripts/queries/resultados-vinculadas/`. **Este es el corte que define el alcance del
proyecto** (§5, primer bullet).

Los chequeos de consistencia cerraron exactos: 60.847 + 45.178 + 15.827 = **121.852
grupos** y 84.774 + 57.632 + 20.085 = **162.491 registros redundantes**, idénticos al
corte del 16/09 y al Excel respectivamente. La distribución por estrato también reproduce
113.959 / 7.545 / 328 / 20 fila por fila. No hay drift entre estas mediciones.

**Partición de los grupos PF duplicados según vínculo a matrícula:**

| Categoría | Grupos | % | Registros | Redundantes | Personas vinculadas | Personas a reasignar |
|---|---|---|---|---|---|---|
| **1 - Varios vinculados** (trabajo real) | **60.847** | 49,9% | 145.621 | 84.774 | 134.009 | **73.162** |
| 2 - Un solo vinculado (fusión trivial) | 45.178 | 37,1% | 102.810 | 57.632 | 45.178 | 0 |
| 3 - Sin vínculo (fuera de alcance) | 15.827 | 13,0% | 35.912 | 20.085 | 0 | 0 |
| **Total** | **121.852** | 100% | 284.343 | **162.491** | 179.187 | 73.162 |

> **El filtro de Mónica parte el universo al medio, no lo pulveriza:** de 121.852 grupos
> quedan **60.847** para revisar. Las llamadas a la API bajan de ~122.000 a **~61.000**
> (§10, rate/concurrencia).

**El universo de trabajo (60.847) por prioridad** (de
`vinculadas_listado_grupos_pf.sql`; las columnas de filas y matrículas suman por grupo, así
que **se repiten entre grupos** — no son distintas, para eso está la tabla de abajo):

| Prioridad | Grupos | % | Registros en R62 | Filas de FK |
|---|---|---|---|---|
| **P1 — dos o más titulares ACTIVOS** | **34.055** | 56,0% | 82.977 | 222.782 |
| P2 — un activo + históricos | 19.028 | 31,3% | 44.453 | 94.482 |
| P3 — solo históricos (B4/B5) | 7.764 | 12,8% | 18.191 | 29.883 |

Los P1 están concentrados en grupos chicos: 30.937 de 34.055 son del estrato BAJO (2-3
duplicados), y 20.543 tienen 5 o menos filas de FK. Solo **91 grupos P1 superan las 50
filas de FK** — la cola larga es corta y se puede revisar a mano.

**La proporción de grupos vinculados sube con el tamaño del grupo:** 49,1% en el estrato
bajo, 62,1% en el medio, 65,5% en el alto. Coherente con §5 (grupos grandes = colisiones
sobre documentos muy usados), pero la diferencia es moderada: el estrato bajo aporta
55.938 de los 60.847 grupos de trabajo (92%).

**Impacto registral** (de `vinculadas_matriculas_afectadas.sql`):

| Tabla | Filas de titularidad | Personas distintas | Matrículas distintas | Filas por persona |
|---|---|---|---|---|
| B2 — activos | 228.103 | 125.298 | **165.120** | 1,82 |
| B4 — históricos | 213.771 | 97.397 | 127.803 | 2,19 |
| B5 — no vigentes | 2.638 | 2.117 | 1.861 | 1,25 |
| **Total (sin repetir entre tablas)** | **444.512** | **179.187** | **256.175** | 2,48 |

> ⚠️ Esta tabla cuenta **todas** las personas de grupos duplicados, incluidas las de los
> grupos "un solo vinculado" (donde no hay nada que fusionar). Para el impacto del
> universo de trabajo solo, hay que rehacerla filtrando por grupos con 2+ vinculados.
>
> ✅ **Resuelto 17/09/2026:** esta tabla es del corte 16/09, **sin filtrar `ELIMINADO`**.
> Confirmado que `ELIMINADO=1` es baja lógica real — ver "Verificación ELIMINADO/RECIENTE"
> más abajo, con el número corregido: **228.103 → 226.594 filas de B2, 165.120 → 164.418
> matrículas.** Para citar la cifra de matrículas con activo duplicado usar **164.418**,
> no 165.120.
>
> Las 165.120 matrículas con titular activo duplicado, puestas contra las 523.058
> matrículas reales del informe, dan ~31% — pero **son cortes distintos** (informe 25/08
> vs. este 16/09), así que sirve como orden de magnitud y no como cifra para un
> entregable. Para publicarlo hay que recontar el denominador el mismo día.


**Doble titular en la MISMA matrícula** (de `vinculadas_doble_titular_misma_matricula.sql`,
corrida el 16/09/2026 — export en `resultados-vinculadas/`):

| Métrica | Valor |
|---|---|
| Casos (matrícula + documento) | 3.537 |
| **Matrículas afectadas** | **3.006** |
| Documentos involucrados | 3.082 (9,1% de los 34.055 P1) |
| Registros de persona involucrados | 7.194 |
| Filas de B2 involucradas | 7.741 (2,19 por caso) |
| Máx. registros de una persona en una matrícula | **9** |

> Es el hallazgo más mostrable: no es "el catálogo está desprolijo", es "este inmueble
> tiene la titularidad repartida entre registros que son la misma persona". Engancha con
> las 309 matrículas con suma de porcentajes ≠ 100% del informe (ver más abajo).
>
> ✅ **Resuelto 17/09/2026:** confirmado `ELIMINADO=1` como baja lógica (ver más abajo).
> Con el filtro aplicado, **matrículas afectadas: 3.006 → 2.868 (−4,6%)**, casos 3.537 →
> 3.362, documentos 3.082 → 2.947, registros de persona 7.194 → 6.842, filas B2 7.741 →
> 7.365. El máximo (9) no cambió. Usar **2.868** como cifra vigente, no 3.006.
>
> ✅ **Detalle corrido 18/09/2026:** el bloque 2 de `vinculadas_doble_titular_misma_matricula.sql`
> (una fila por matrícula+documento, comentado hasta ahora) se separó a
> `scripts/queries/vinculadas_doble_titular_misma_matricula_detalle.sql` y se corrió con
> `RunQuery`. Export en
> `scripts/out/vinculadas_doble_titular_misma_matricula_detalle_2026-09-18.md`: 3.362 filas
> (cierra exacto con `CASOS_MATRICULA_MAS_DOCUMENTO`), 2.868 `ID_MATRICULA` distintos
> (cierra exacto con `MATRICULAS_AFECTADAS` — sin drift de un día a otro).
>
> ✅ **Los dos artefactos del export `.md` están resueltos (18/09/2026).** Ese export tenía
> los acentos de `DS_INMUEBLE` como `�` (`RunQuery` no fijaba el charset de salida) y 4
> filas partidas en dos líneas físicas por saltos de línea incrustados en ese mismo campo.
> Se le agregó a `RunQuery` salida UTF-8 y modo `--csv` con comillado RFC 4180, y se
> reexportó a `scripts/out/doble_titular_misma_matricula_2026-09-18.csv`: 3.362 filas
> lógicas, 2.868 matrículas, 2.947 documentos, sin un solo carácter de reemplazo. Las 4
> filas con salto de línea siguen ocupando dos líneas físicas, pero ahora van **dentro de
> comillas**, así que Excel las lee como una sola celda. Ojo al contar con `awk`/`grep`
> sobre ese CSV: hay que respetar el comillado o se cuentan 5 filas de más (una de ellas es
> un documento extranjero, `GF195820`, que no empieza con dígitos).

### Verificación `ELIMINADO` / `RECIENTE` en `DIG_DOC_R00_B2` — 17/09/2026 (RESUELTO)

Pendiente bloqueante desde el 16/09 (§10). Se investigaron ambas columnas contra la base
de desarrollo. Existen en **B2 y B5** (no solo B2 como se pensaba); **B4 no las tiene**.

**`ELIMINADO` — confirmado como baja lógica real.** Evidencia:

- Hay `ID_MATRICULA` donde **todas** las filas de B2 tienen `ELIMINADO=1`: esa matrícula
  queda sin ningún titular activo vivo si se excluyen (735 matrículas en ese caso sobre el
  total de B2, sin acotar a duplicados).
- Otros casos muestran el patrón "reemplazo": una fila `ELIMINADO=1` y otra viva para la
  misma matrícula (ej. `ID_MATRICULA` 1575665: 1 fila viva de 2 totales) — consistente con
  una corrección posterior, no con basura de carga.
- Se origina tanto en la migración (`CD_USER_STORE` NULL o `RPI_RV_MIG`: 3.350 + 228 de
  las 3.718 filas `ELIMINADO=1`) como en usuarios de WORKFLOW corrigiendo en producción
  (~150 usuarios distintos, cada uno con pocas filas).
- Volumen: **3.718 de 980.931 filas de B2 (0,38%)** y 39 de 9.826 en B5 — chico en
  proporción, pero concentrado justo en los casos de "doble titular" que son el hallazgo
  más mostrable del proyecto (ver impacto abajo).

**`RECIENTE` — investigado, NO es un flag de baja, no se filtra.** `RECIENTE IS NULL`
correlaciona con filas cargadas por la migración (`DT_ALTA` hasta 2017-08-18,
`CD_USER_STORE` NULL/`RPI_RV_MIG`); `RECIENTE` en `{0,1}` correlaciona con filas cargadas
por WORKFLOW después de esa fecha, hasta hoy. O sea: distingue **origen** del registro
(migración vs. WORKFLOW), no si la titularidad sigue vigente. No hay evidencia de que
`RECIENTE=1` (solo 3.524 filas) marque nada relacionado con validez.

**Filtro aplicado:** `WHERE NVL(ELIMINADO, 0) = 0` en toda query que lea B2 o B5. Ya
corregido en `vinculadas_matriculas_afectadas.sql`, `vinculadas_doble_titular_misma_matricula.sql`,
`vinculadas_matricula_real_kpi_pf.sql` y `vinculadas_matricula_real_muestra.sql`.

**Impacto medido sobre las cifras ya publicadas:**

| Métrica | Sin filtrar | **Filtrada** | Δ |
|---|---|---|---|
| Impacto registral — filas B2 | 228.103 | **226.594** | −1.509 (−0,7%) |
| Impacto registral — personas distintas en B2 | 125.298 | **124.679** | −619 |
| Impacto registral — **matrículas con activo duplicado** | 165.120 | **164.418** | −702 (−0,4%) |
| Impacto registral — TOTAL filas (B2+B4+B5) | 444.512 | **442.992** | −1.520 |
| Impacto registral — TOTAL matrículas distintas | 256.175 | **255.683** | −492 |
| Doble titular — casos | 3.537 | **3.362** | −175 |
| Doble titular — **matrículas afectadas** | 3.006 | **2.868** | **−138 (−4,6%)** |
| Doble titular — documentos involucrados | 3.082 | **2.947** | −135 |
| Doble titular — registros de persona | 7.194 | **6.842** | −352 |
| Doble titular — filas de B2 involucradas | 7.741 | **7.365** | −376 |
| Doble titular — máx. personas en 1 matrícula | 9 | 9 | 0 |

B4 no cambia en ninguna fila (no tiene `ELIMINADO`). El hallazgo más mostrable del
proyecto ("doble titular en la misma matrícula") es el más sensible al filtro (−4,6% en
matrículas), coherente con que `ELIMINADO=1` aparece justo en correcciones posteriores de
errores de carga — el mismo tipo de caso que este análisis busca.

Exports: `scripts/out/vinculadas_matriculas_afectadas_2026-09-17_filtrado.md`,
`scripts/out/vinculadas_doble_titular_misma_matricula_2026-09-17_filtrado.md`.

> Bug lateral encontrado al correr `vinculadas_doble_titular_misma_matricula.sql` con
> `RunQuery`: el alias `REGISTROS_DE_PERSONA_INVOLUCRADOS` tiene 33 caracteres y excede el
> límite de 30 de esta versión de Oracle (`ORA-00972`) — no había reventado antes porque el
> 16/09 se corrió desde DBeaver. Corregido a `REGISTROS_PERSONA_INVOLUC`.
>
> Pendiente (no bloqueante): recontar `censo_matriculas_r00.sql` (40.976 sin titular,
> §3 "Censo de matrículas") con el mismo filtro — tampoco lo aplica hoy.

### Corte con matrícula REAL — 17/09/2026 (VIGENTE para alcance; reemplaza al de arriba)

El corte del 16/09 marca "vinculada" a toda persona que aparece en B2/B4/B5, pero **no
mira a qué inmueble apunta esa fila**: ninguna de las `vinculadas_*.sql` joinea contra
`DIG_DOC_R00`. Como el 34,6% de `DIG_DOC_R00` es legado Tomo/Folio sin `NU_MATRICULA`
(§3, censo), parte de esos vínculos no son a una matrícula usable.
[scripts/queries/vinculadas_matricula_real_kpi_pf.sql](scripts/queries/vinculadas_matricula_real_kpi_pf.sql)
repite el corte exigiendo `NU_MATRICULA IS NOT NULL` (cualquier `CD_ESTADO`, las `BAJ`
dentro del alcance por §5) **y `NVL(ELIMINADO,0)=0`** en B2/B5 (verificación de arriba, ya
resuelta). Corrida el 17/09/2026 con `RunQuery`; export en
`scripts/out/vinculadas_matricula_real_kpi_pf_2026-09-17_filtrado.md`.

| Categoría | Grupos (16/09) | **Grupos (matrícula real + sin ELIMINADO)** | Δ |
|---|---|---|---|
| **1 - Varios vinculados** (trabajo real) | 60.847 | **55.918** | **−4.929 (−8,1%)** |
| 2 - Un solo vinculado | 45.178 | 45.632 | +454 |
| 3 - Sin vínculo | 15.827 | 20.302 | +4.475 |
| **Total** | 121.852 | **121.852** | 0 |

Chequeos: el total de grupos (121.852) y el de registros redundantes (78.210 + 58.337 +
25.944 = **162.491**) cierran exactos contra los cortes anteriores — el filtro **mueve
grupos entre categorías, no cambia el universo**.

Del universo de trabajo (55.918): **123.118 personas vinculadas**, **67.200 a reasignar**.
Por prioridad:

| Prioridad | Grupos (16/09) | **Grupos (final)** | Δ |
|---|---|---|---|
| **P1 — dos o más titulares activos** | 34.055 | **30.136** | −3.919 (−11,5%) |
| P2 — un activo + históricos | 19.028 | 17.449 | −1.579 |
| P3 — solo históricos | 7.764 | 8.333 | **+569** |

> P3 **sube**: hay grupos cuyos vínculos en B2 eran todos a inmuebles de legado o a filas
> `ELIMINADO=1`, así que dejan de ser P1/P2 y caen a P3. No es un error de conteo.
>
> Las llamadas a la API bajan a **~55.900** (~30.100 si se ataca P1 primero).

**Peso del legado y de la baja lógica dentro de las tablas de titularidad** (bloque 3 de
la misma query, sin acotar a duplicados — mide la estructura cruda de cada tabla):

| Tabla | Filas | A matrícula real | A legado Tomo/Folio | Sin inmueble (FK huérfana) | `ELIMINADO=1` |
|---|---|---|---|---|---|
| B2 — activos | 980.931 | 787.734 (80,3%) | 193.197 | **519** | 3.718 |
| B4 — históricos | 673.585 | 566.176 (84,1%) | 107.409 | **38** | (sin columna) |
| B5 — no vigentes | 9.826 | 9.800 (99,7%) | 26 | 0 | 39 |

> ⚠️ **Hallazgo pendiente de investigar (no bloquea el alcance): 557 filas de
> titularidad apuntan a un `ID_MATRICULA` que no existe en `DIG_DOC_R00`** (519 en B2 + 38
> en B4). Sin FK declaradas (§2) nada lo impide.

### Entregable del 18/09/2026 — agregados del universo de trabajo (VIGENTE)

Resultado de correr
[scripts/queries/vinculadas_matricula_real_listado_grupos_pf.sql](scripts/queries/vinculadas_matricula_real_listado_grupos_pf.sql),
que rehace la lista de trabajo del 16/09 con el filtro de matrícula real + `ELIMINADO`
(era el pendiente de §10). **Los tres chequeos contra el corte del 17/09 cerraron
exactos**, así que el listado es consistente con las cifras ya publicadas:

| Control | Esperado (§3, 17/09) | Obtenido (18/09) |
|---|---|---|
| Grupos del universo de trabajo | 55.918 | **55.918** |
| Partición P1 / P2 / P3 | 30.136 / 17.449 / 8.333 | **idénticos** |
| Registros redundantes | 78.210 | **78.210** |
| Personas vinculadas | 123.118 | **123.118** |
| Personas a reasignar | 67.200 | **67.200** |

Cifras nuevas que salen de este listado y no estaban medidas antes:

| Métrica | Valor |
|---|---|
| Registros de persona dentro de los 55.918 grupos | **134.128** |
| **Filas de titularidad (FK) a revisar y reasignar** | **304.774** |
| Matrículas tocadas (suma por persona, con repetición) | 293.987 |
| Máximo de registros vinculados en un mismo grupo | 12 |

**Distribución por estrato DENTRO del universo de trabajo** (distinta de la del padrón
completo de §3, que da 113.959 / 7.545 / 328 / 20):

| Estrato | Grupos | % |
|---|---|---|
| Bajo (2-3) | 51.323 | 91,8% |
| Medio (4-6) | 4.384 | 7,8% |
| Alto (7-10) | 200 | 0,4% |
| Muy alto (11+) | **11** | 0,02% |

> Solo **11 grupos** del universo de trabajo superan los 10 duplicados — refuerza lo de §5
> y §10: el "techo de tamaño de grupo" no hace falta como regla general, se revisan a mano.

**Casos representativos** (de
[scripts/queries/casos_representativos_pf.sql](scripts/queries/casos_representativos_pf.sql)):
67 documentos = 59 de la muestra aleatoria del 17/09 + 8 emblemáticos elegidos a mano, uno
por patrón (doble-submit, copropiedad con dos porcentajes, variante de tipeo, dos personas
distintas, redundancia masiva de FK, CUIL con prefijo 24, mezclados extremo). Los 60
documentos del lote del 17/09 se reprodujeron **exactos** con el mismo `ORA_HASH`; uno de
ellos (21.949.584) es además emblemático, por eso la muestra figura con 59.

`EvaluadorLote` sobre esos 67: **7 con registros sospechosos de ser personas distintas**,
46 con CUIL ya cargado en la base, 0 sin CUIL calculable. Reprodujo solo los casos ya
confirmados a mano en el Excel: en 25.007.077 separó exactamente los 4 registros de
Francisco Gaitán de los otros 7, y en 6.899.569 marcó 4 sospechosos.

> **Sin RENAPER.** Por decisión del usuario (18/09) el entregable no llama a la API: las
> columnas `VALIDADO_RENAPER`, `FECHA_FALLECIMIENTO`, `SEXO_RENAPER`, `NOMBRE_RENAPER_OK`
> y `OBSERVACIONES` van vacías para completar a mano. **La fecha de fallecimiento no existe
> en ninguna tabla de SIRCLAN** — se verificó el catálogo completo de `DIG_DOC_R62` — es
> uno de los campos a agregar en el modelo PostgreSQL.
>
> `CD_USER_STORE` en `DIG_DOC_R62` (PF): `MIGRACION` 809.874 · `WORKFLOW` 167.632 ·
> `RPI_RV_MIG` 6.143 · `RPI_RAV` 141 · `CONSIST` 49. Suman 983.839, el total PF de §3.
> Todo lo que no es `WORKFLOW` viene de la migración.

### Inmuebles / matrículas (informe, 25/08/2026 — antecedente, ver corte vigente abajo)

800.347 registros en `DIG_DOC_R00`, de los cuales **277.289 (34,6%) no tienen
`NU_MATRICULA`** (son legado Tomo/Folio, ninguno en estado ACT — se excluyen del análisis
de integridad). Sobre las **523.058** con matrícula real: **40.831 sin titular (7,8%)**,
de las cuales **1.885 activas/recién creadas** son prioritarias; **309** con suma de
porcentajes de titularidad ≠ 100%.

Desglose por `CD_ESTADO` de ese mismo corte (fuente: `docs/Metodologia_Queries_SIRCLAN.md`
§3.3, Queries 5, 7, 8, 9 y 10 — no está en el `.docx`):

| | MIG | ACT | BAJ | CRE | Total |
|---|---|---|---|---|---|
| Sin `NU_MATRICULA` (legado) | 275.230 | 0 | 1.799 | 260 | 277.289 |
| Con `NU_MATRICULA` (real) | 267.019 | 242.291 | 13.356 | 394 | 523.058 |
| — de esas, sin titular | 25.601 | 1.825 | 13.345 | 60 | 40.831 |

### Censo de matrículas — 17/09/2026 (VIGENTE)

Resultado de correr [scripts/queries/censo_matriculas_r00.sql](scripts/queries/censo_matriculas_r00.sql)
contra la base de desarrollo el 17/09/2026. Exports en
`scripts/queries/resultados-censo_matriculas_r00/`. Los chequeos de consistencia cierran
exactos (bloque 2 suma el `SIN_MATRICULA_LEGADO` del bloque 1; bloque 3 suma el
`CON_MATRICULA`; bloque 5 suma el `MATRICULAS_SIN_TITULAR` del bloque 4).

| | MIG | ACT | BAJ | CRE | Total |
|---|---|---|---|---|---|
| Sin `NU_MATRICULA` (legado) | 275.135 | 0 | 1.810 | 267 | 277.212 |
| Con `NU_MATRICULA` (real) | 266.571 | 243.094 | 13.549 | 403 | **523.617** |
| — de esas, sin titular | 25.598 | 1.780 | 13.538 | 60 | **40.976** |

**Total en `DIG_DOC_R00`: 800.829.** Matrículas con % de titularidad inválido (≠100%):
**316** (antes 309).

**"Matrículas que se pueden usar" = las 523.617 con `NU_MATRICULA` real** (el legado
Tomo/Folio, 277.212, sigue sin ningún registro en estado ACT — confirmado de nuevo, queda
fuera de alcance). Drift normal contra el corte del informe (mismo fenómeno de §3 "Por qué
difieren los números"; magnitud comparable a la vista en PF/PJ): +559 matrículas reales,
+145 sin titular, +7 con % inválido. Las prioritarias (ACT+CRE sin titular) bajan de 1.885
a **1.840**.

Dentro de esas 523.617, ningún `CD_ESTADO` está descartado como "no usable". **Decisión
del usuario (17/09/2026): las `BAJ` (13.549, el 2,6% de las reales) quedan DENTRO del
alcance por ahora** — si más adelante complican demasiado el trabajo, se sacan en ese
momento, no preventivamente (ver §5).

> ⚠️ `censo_matriculas_r00.sql` **todavía NO filtra `ELIMINADO`** en `DIG_DOC_R00_B2`/`_B5`
> (a diferencia de las demás queries de impacto registral, ya corregidas — §3
> "Verificación ELIMINADO/RECIENTE", §10). Confirmado que `ELIMINADO=1` es baja lógica: con
> el filtro, "sin titular" (40.976) va a subir un poco y "% inválido" (316) puede moverse.
> `RECIENTE` no aplica, no es un flag de baja. Pendiente de recorrer (§10).

---

## 4. Esquema conocido

| Tabla | Rol | Clave / FK real (no declarada) |
|---|---|---|
| `DIG_DOC_R62` | Personas físicas y jurídicas mezcladas (catálogo compartido por todo el BPM, no exclusivo de titulares) | PK `ID_FORMULARIO`. Dedup PF por `NU_DOCUMENTO`; PJ por `NU_CUIL_CUIT_STR` (11 dígitos) |
| `DIG_DOC_R00` | Inmueble / matrícula | PK `ID_MATRICULA` |
| `DIG_DOC_R00_B2` | Titulares **activos** | `CD_PERSONA` → `ID_FORMULARIO` (100% match verificado: 978.880 = 978.880) |
| `DIG_DOC_R00_B4` | Titulares **históricos** | `CD_PERSONA_H` → `ID_FORMULARIO` |
| `DIG_DOC_R00_B5` | Titulares **NO vigentes** (confirmado, ver §7) | `CD_PERSONA_P` → `ID_FORMULARIO` |

Columnas clave de `DIG_DOC_R62`: `TP_PERSONA` ('PF'/'PJ', confirmado con
`SELECT DISTINCT`), `NU_DOCUMENTO`/`NU_DOCUMENTO_STR`, `NU_CUIL_CUIT`/`_STR`,
`NM_NOMBRE`, `NM_APELLIDO`, `TP_DOCUMENTO` (inconsistente entre cargas del mismo
documento: toma 1, 3 y 5 para la misma persona), `CD_SEXO` (NULL=sin dato, 0=usado para
S.A. — anómalo en PF, 1=femenino, 2=masculino), `CD_NACIONALIDAD`, `NM_RAZON_SOCIAL`,
`TP_SOCIETARIO`, `IN_BAJA_LOGICA`, `MIG_ID_PERSONA`, `DT_STORE`/`DT_LAST_UPDATE` +
usuarios de auditoría (`MIGRACION` vs `WORKFLOW` distingue lastre histórico de carga
actual).

Columnas de las tablas de titularidad (necesarias para escribir las 4 queries "Opción B"):

| Tabla | FK a persona | Porcentaje | Situación | Fechas |
|---|---|---|---|---|
| `DIG_DOC_R00_B2` (activos) | `CD_PERSONA` | `NU_NUMERADOR` / `NU_DENOMINADOR` / `DS_PORCENTAJE` | `CD_SITUACION` | `DT_DESDE` |
| `DIG_DOC_R00_B4` (históricos) | `CD_PERSONA_H` | `NU_NUMERAD_2` / `NU_DENOMINAD_2` | `CD_SITUACI_2` | `DT_DES_2`, `DT_HASTA` |
| `DIG_DOC_R00_B5` (no vigentes) | `CD_PERSONA_P` | — | `CD_ESTA_2` (no confiable, §5) | `DT_HAS_2` |

Las tres llevan además `ID_MATRICULA` → `DIG_DOC_R00.ID_MATRICULA`. De `DIG_DOC_R00`
interesan `NU_MATRICULA`, `CD_ESTADO` (MIG/ACT/BAJ/CRE), `DS_INMUEBLE`, `DT_CREACION`,
`DS_PROCEDENCIA` y `NU_TOMO`/`NU_FOJA` (legado).

**`ELIMINADO` (NUMBER, 0/1/NULL) — confirmado baja lógica** en `DIG_DOC_R00_B2` y
`DIG_DOC_R00_B5` (verificado 17/09/2026, detalle en §3 "Verificación ELIMINADO/RECIENTE").
**`DIG_DOC_R00_B4` no tiene esta columna.** Filtrar siempre con `NVL(ELIMINADO,0) = 0` al
leer B2/B5 para titularidad viva. `RECIENTE` (misma tabla, mismo tipo) **no** es un flag
de baja — distingue origen migración (NULL) de WORKFLOW (0/1) — no se filtra.

**Placeholders a excluir siempre:**

- Documento (PF): `0`, `00`, `000`, `000000`, `0000000`, `00000000`, `1`, `99907804`.
  En SQL conviene
  `NOT REGEXP_LIKE(NU_DOCUMENTO,'^0+$') AND NU_DOCUMENTO NOT IN ('99907804','1')`.
- CUIT (PJ): `0` (11.119 registros) y **`30999078040`** (563 registros / 31 razones
  sociales) — este último **falta excluirlo en los KPI publicados**.

**Principio de queries:** nunca unir dos tablas "muchos" entre sí en el mismo SELECT
(multiplica filas). Separar en 4 queries independientes: persona base, B2+inmueble,
B4+inmueble, B5+inmueble — cada una uniendo como máximo una tabla "muchos" contra
`DIG_DOC_R00`. Alias con sufijo por tabla (`_PERS`, `_ACT`, `_INM`, `_HIST`, `_B5`) para
que en Excel no se confundan columnas homónimas.

**Gotchas de Oracle ya pisados** (detalle en `docs/Metodologia_Queries_SIRCLAN.md`):
`FETCH FIRST` **no anda en ningún lado** en esta versión del motor — no solo dentro de
subconsulta escalar o CTE: también revienta con `ORA-00933` en un `SELECT` de primer nivel
con `GROUP BY` + `ORDER BY` (probado el 18/09/2026) → envolver en subconsulta y usar
`ROWNUM`; `NU_DOCUMENTO` es VARCHAR2 → comparar con `'0'`, no `0` (ORA-01722); `LISTAGG`
revienta a los 4000 bytes con grupos grandes (ORA-01489) → limitar con `ROW_NUMBER()`;
un alias de más de 30 caracteres da `ORA-00972`; en un `UNION ALL` un `NULL` pelado no
tiene tipo (ORA-01790) → castear cada rama.

**Gotcha de `RunQuery`, no de Oracle:** el script corta todo lo que sigue a `--` en cada
línea y recién ahí parte por `;`. Un literal de string que contenga `;` o `--` rompe el
split y el statement resultante se rechaza por el guardrail de solo lectura (pisado el
18/09/2026 con un literal de prueba que tenía `;` adentro).

---

## 5. Decisiones de diseño tomadas

- **El universo de trabajo son las personas VINCULADAS A UNA MATRÍCULA**, no todos los
  duplicados de `DIG_DOC_R62` (decisión de Mónica en la reunión del 16/09/2026,
  textual: *"tenés que vincular las personas con las matrículas, filtralo por ese lado"*
  / *"ver las personas vinculadas por las matrículas, si están vinculadas a una matrícula
  entonces tomá esos registros y revisalos"*). `DIG_DOC_R62` es el catálogo de personas de
  todo el BPM (§4), así que una parte de los 121.793 grupos no toca ninguna matrícula y no
  impacta en el problema registral. Los grupos quedan partidos en tres:
  **varios vinculados** (fusión real, hay FK que reasignar y riesgo de personas
  mezcladas), **un solo vinculado** (el ganador ya está determinado: es el único con
  matrícula, no hay FK que mover) y **sin vínculo** (fuera de alcance). Queries en
  `scripts/queries/vinculadas_*.sql` — **pendientes de correr**, todavía no hay cifras.
  ⚠️ "Sin vínculo a matrícula" **no** quiere decir "borrable": esas personas pueden estar
  referenciadas desde otros formularios del BPM. El filtro acota el alcance de este
  proyecto, no habilita una depuración del catálogo.
- **Dentro de un grupo seleccionado se revisan TODOS los registros**, vinculados y no
  vinculados. El filtro de matrícula elige *qué grupos* entran, no *qué filas* se miran
  adentro — para decidir si son la misma persona hay que ver el grupo completo.
- **Las matrículas en estado `BAJ` quedan DENTRO del alcance** (decisión del usuario,
  17/09/2026, ante el hallazgo de §3 "Censo de matrículas": 13.549 de las 523.617
  matrículas reales, 2,6%, están dadas de baja). Es una decisión provisoria, no definitiva:
  si en la práctica revisarlas complica demasiado el trabajo, se sacan del alcance en ese
  momento — no preventivamente.
- **Detección de duplicados PF:** determinística por `NU_DOCUMENTO` exacto, excluyendo
  placeholders. **PJ:** por CUIT válido (11 dígitos); fusión automática solo si CUIT +
  razón social normalizada coinciden; si no, cola de revisión manual (la API no valida
  personas jurídicas).
- **Selección de candidato dentro de un grupo:** por completitud de datos + fecha de
  última actualización (`DT_LAST_UPDATE DESC NULLS LAST`).
- **Validación API:** una llamada por grupo, no por registro individual.
- **CUIL/CUIT no depende de estar cargado en la base:** se calcula desde `NU_DOCUMENTO` +
  `CD_SEXO` (algoritmo AFIP/ARCA). Si la API responde "El documento o sexo son
  incorrectos", se reintenta una vez con el prefijo de sexo contrario antes de concluir
  "sin datos en RENAPER" — el `CD_SEXO` de la base puede estar mal cargado (caso real
  confirmado, ver §7).
- **La API es la fuente de verdad:** un CUIT que no trae datos (tras probar ambos
  prefijos) se asume mal calculado o inexistente en RENAPER, no una falla de la API.
- **`DIG_DOC_R00_B5` se trata como histórica en su totalidad** — el campo
  `CD_ESTA_2='VIGENTE'` no es un filtro confiable (aparece igual en registros claramente
  cerrados).
- **Reasignación de FK al fusionar un grupo:** hay que reasignar `CD_PERSONA` /
  `CD_PERSONA_H` / `CD_PERSONA_P` de TODOS los perdedores que tengan vínculo de
  titularidad (no solo descartarlos) — puede haber varios registros del mismo grupo con
  vínculos distintos, incluso históricos redundantes dentro de B4 (ver §7: un mismo
  `ID_FORMULARIO` aparece hasta 60 veces en B4).
- **Detección de "personas mezcladas" ANTES de cualquier fusión automática**, nunca como
  auditoría posterior — el costo de fusionar por error las identidades/titularidades de
  dos personas reales distintas es mucho más alto que el de una revisión manual de más.
- **Grupos con muchos duplicados (11+)** son candidatos a ser "colisiones" (documento mal
  cargado que atrapó a varias personas reales) más que duplicados genuinos — necesitan un
  techo de tamaño antes de clusterizar (también para evitar O(n²) sobre grupos gigantes).
- **Piloto antes de escalar:** muestra representativa antes de correr sobre los ~121.800
  grupos completos.

---

## 6. Scripts

Están en `scripts/`, son Java plano sin dependencias externas (HttpClient + regex, sin
librería JSON), compilables con `javac` suelto. Cada uno tiene un `main` con casos de
prueba reales embebidos.

| Script | Propósito | Notas |
|---|---|---|
| `CalculadorCuil.java` | CUIL desde DNI + `CD_SEXO`, dígito verificador mod-11 (pesos `5 4 3 2 7 6 5 4 3 2`). Prefijos 20 (M) / 27 (F). `candidatosCuil(dni)` devuelve ambos cuando el sexo es desconocido. | Verificado: DNI 23598685 + M → `20235986850`. **Limitación real (§9.2): no contempla prefijos 23/24** — tira `IllegalStateException` si el DV da 10, y en la base hay CUIL con prefijo 24. |
| `ValidadorPersonaApi.java` | Llama a RENAPER, parsea la respuesta, reintenta con el prefijo contrario ante "El documento o sexo son incorrectos", distingue CUIT mal formado (HTTP 500, cuerpo `{timestamp,status,error,message}`) de "sin datos en RENAPER", y compara nombre/apellido/sexo/fallecido contra el candidato de la base normalizando mayúsculas y acentos. | Endpoint: `GET https://dev-api-drp.jus.mendoza.gov.ar/gateway/api/v1/persons/renaper/persona?tipoDoc=CUIL&nroDoc=<cuil>&sexo=<M o F>`, sin autenticación. Resultados: `COINCIDE`, `DIFERENCIA_NOMBRE`, `DIFERENCIA_SEXO`, `FALLECIDO`, `SIN_DATOS_API`, `CUIT_MAL_FORMADO`. |
| `DetectorMezclados.java` | Clusteriza los registros de un mismo `NU_DOCUMENTO` por similitud de nombre/apellido (Damerau-Levenshtein por token, umbral **0,75**), separando el cluster principal (candidato a fusión) de los "sospechosos" (posibles personas distintas → revisión manual). Contempla nombre/apellido invertidos entre registros. | Probado contra 9 casos reales; 8/9 exactos vs. la evaluación manual, el restante queda del lado seguro (flagea de más en vez de fusionar de más). |

---

## 7. Hallazgos clave del análisis

- **`DIG_DOC_R00_B5` confirmado como NO vigente/histórica** (pese al literal
  `CD_ESTA_2='VIGENTE'`): cruzando el documento 6772336, la matrícula 1662369 aparece con
  las mismas fechas desde/hasta en B4 y en B5 bajo dos `ID_FORMULARIO` distintos de la
  misma persona.
- **El CUIL se puede calcular sin depender de que esté cargado en la base**, incluyendo el
  caso borde de sexo mal cargado: el documento 6824505, clasificado al principio como
  "extranjero sin datos en la API", era en realidad un error de sexo (se calculó con
  prefijo masculino `20068245053`; el correcto es `27068245058`) — con el prefijo correcto
  RENAPER sí tenía los datos.
- **Hallazgo mayor — "personas mezcladas":** de 7 casos nuevos revisados, **5 combinaban
  varias personas reales distintas bajo el mismo `NU_DOCUMENTO`**, no variantes de tipeo
  de una sola persona (caso extremo: documento 25007077, solo 4 de 11 registros eran la
  misma persona real).
- **Corrección metodológica sobre la muestra:** los casos revisados **no son una muestra
  aleatoria** — se ordenaron por cantidad de duplicados de mayor a menor y se revisaron
  desde arriba. La tasa de "mezclados" (~70% en lo revisado) está casi seguro sesgada
  hacia arriba y no se sostiene en el grueso de los grupos (mayormente de 2-4 duplicados).
  **Pendiente confirmar con muestra aleatoria estratificada (§10).**
- **Redundancia masiva dentro de B4** (nuevo, del Excel): no es solo que la persona esté
  duplicada en R62, es que el **mismo `ID_FORMULARIO` aparece repetido decenas de veces en
  B4** — `5038282` × 60, `568153` × ~56, `1423051` × 30. Esto multiplica el trabajo de
  reasignación de FK y hay que contemplarlo antes de estimar el volumen de la fusión.
- **164.000 personas físicas sin documento** (`NU_DOCUMENTO` NULL, 16,7% del padrón PF),
  de las cuales solo **2.516 son recuperables** por `NU_DOCUMENTO_STR`/`NU_CUIL_CUIT`
  (hoja "Recuperables NULL" del Excel). Segmento entero que **no entra** en la
  deduplicación determinística y no estaba dimensionado en el informe.
- **416 personas con documento `0` recuperables** por campos alternativos (hoja
  "Recuperables dni 0"). No descartarlas sin revisar `NU_DOCUMENTO_STR`, `NU_CUIL_CUIT` y
  `NU_CUIL_CUIT_STR` primero.
- Bug de doble-submit confirmado en el WORKFLOW actual: el caso MAREU S.A.S. tiene 29 de
  32 registros cargados el 23/10/2019 entre 09:17 y 11:43 hs. Fuera de alcance de este
  proyecto, se reporta aparte.
- El problema **no es solo histórico**: en el caso ELASKAR, 17 de 18 cargas son de la
  migración 2017 pero la última es de marzo 2020 vía WORKFLOW; MAREU es 100% posterior a
  la migración.
- **El bug de doble-submit también aparece dentro de titulares activos, no solo en el
  catálogo general** (17/09/2026): el caso "máximo 9 registros en una matrícula" de §3
  ("Doble titular en la MISMA matrícula") es exactamente ese patrón — matrícula 800.622.102
  (`ID_MATRICULA` 6387176), documento 24.506.089, Mauricio Ariel Cantalejos, cargado 9
  veces con `ID_FORMULARIO` **consecutivos** (5696437-5696445), misma fecha exacta
  (19/08/2025) y sin porcentaje de titularidad asignado en ninguna. Mismo patrón que MAREU
  S.A.S., pero impactando un titular activo de un inmueble real hoy. Detalle en el Anexo I
  de `scripts/out/Informe_Alcance_Depuracion_Titulares_2026-09-17.md`.
- **557 filas de titularidad apuntan a un `ID_MATRICULA` que no existe** (18/09/2026,
  confirmado con `titularidad_matricula_inexistente.sql`: 519 en B2, 38 en B4, 0 en B5).
  No son campos vacíos: cada una tiene un número de matrícula concreto que simplemente no
  está en `DIG_DOC_R00`. Sin FK declaradas (§2), nada lo impide. Sin explicación de causa
  todavía — candidato a "matrículas borradas de R00 sin limpiar sus titularidades", pero
  no confirmado.

---

## 8. Casos revisados a mano (`docs/Titulares BD.xlsx`)

Cada hoja nombrada con un número de documento tiene: filas 1-2 con `Numero_Documento`,
`Numero_CUIT` (CUIL calculado) y **`Observaciones`** (columna D, la conclusión manual),
después el bloque de registros de `DIG_DOC_R62`, el candidato elegido, y marcadores
`b2` / `b4` / `b5`. La hoja `Plantilla` es el molde vacío.

| Documento | Conclusión manual registrada |
|---|---|
| 6824505 | Solo tiene registros en B4 |
| 6880087 | Muchas matrículas relacionadas; hay que reemplazar `CD_PERSONA` en B4 y B5 |
| 6850189 | Muchas matrículas relacionadas; reemplazar en B4 |
| 6146086 | Muchas relaciones con matrículas (B4) |
| 8145732 | El `5038282` está **60 veces** en B4 |
| 5109377 | Sin CUIT válido → no se valida con la API. La persona figura además con documento `51093771` en otros registros |
| 92833978 | Aparentemente extranjero; tiene CUIT; **sin** registros en B2/B4/B5 |
| 6842131 | Solo registros en B4 |
| 6903524 | El `5681889` tiene datos que no corresponden (mezclado); el `1423051` está 30 veces en B4 |
| 8154398 | Hay dos registros mezclados |
| 32162858 | `2732162858` → número inválido (10 dígitos); el `5671495` está mezclado |
| 25007077 | Datos mezclados; misma persona: `5302372`, `5302369`, `5302373`, `5115894` (Francisco Gaitán). Sin registros en B2/B4/B5 |
| 8023173 | `20080231734` → CUIT inválido (según la API) |
| 23598685 | Registros mezclados; `5099514` y `1606378` son la misma persona |
| 6772336 | (caso original GONZÁLEZ FELTRUP — sin observación escrita) |
| 6899569 | Del `568153` hay unos **56** en B4; dos personas distintas con el mismo DNI |
| **4090581, 22136013, 6438047, 5330620** | **Hojas cargadas, sin observación → revisión pendiente** |

**9 de estos casos** están como test embebidos en `DetectorMezclados.main` (23598685,
25007077, 6903524, 32162858, 6824505/ELASKAR, 6880087/MATHUS, 6772336, 8154398/FERIOZZI,
8023173/GINART). Los otros 11 son regresiones baratas de agregar.

---

## 9. Contradicciones e inconsistencias abiertas

1. **Las 4 queries del patrón "Opción B" no existen todavía como archivo.** Los documentos
   las remiten al "historial del chat original", que ya no está disponible. Las va a pasar
   el usuario → van a `scripts/queries/` (carpeta ya creada, ver su README).
2. **`CalculadorCuil` no cubre los prefijos 23/24.** En la base hay CUIL con prefijo 24
   (verificado: documento 6903524 → `24069035244`, DV correcto para prefijo 24). Con la
   lógica actual se calcularía `20069035249` / `27069035243`, ambos fallarían en RENAPER,
   y el caso se clasificaría como `SIN_DATOS_API` — exactamente el falso negativo que ya
   nos mordió con 6824505. Además, cuando el DV da 10 el código tira excepción en vez de
   caer al prefijo 23.
5. **Casos con CUIL de 11 dígitos y DV correcto que igual "no valida"**: 8023173 →
   `20080231734` está bien formado y sin embargo quedó anotado como inválido (el de
   32162858 sí era un typo de 10 dígitos). Falta entender si es prefijo equivocado,
   persona fallecida/extranjera, o dato que RENAPER no tiene.
6. **Celda sin rótulo en el Excel:** hojas PF y PJ, `G2="Actualizacion de db"` /
   `G3=46275`. No está claro qué mide ese 46.275 (¿altas desde el corte anterior?).
   Confirmar antes de usarlo en cualquier entregable.
7. **PJ: el conteo de redundantes no se recalculó** entre el informe y el Excel (mismo
   13.295 en ambos), a diferencia del resto de los KPI que sí se movieron con la base
   refrescada. Verificar que no sea un copiar/pegar.

---

## 10. Próximos pasos pendientes

**Prioridad 1 — el recorte por matrícula que pidió Mónica (§5)**

- [x] Correr `vinculadas_kpi_pf.sql`, `vinculadas_distribucion_estratos_pf.sql`,
      `vinculadas_matriculas_afectadas.sql` y `vinculadas_listado_grupos_pf.sql`.
      **Hecho 16/09/2026** — resultados en `scripts/queries/resultados-vinculadas/` y
      cifras en §3 ("Corte del universo vinculado"). **Alcance nuevo: 60.847 grupos**,
      de los cuales 34.055 son P1 (dos o más titulares activos).
- [x] Correr `vinculadas_muestra_estratificada.sql`. **Hecho 16/09/2026** — 140
      documentos (50 P1 / 50 P2 / 40 P3), export en `resultados-vinculadas/`. Falta
      pasarlos por `EvaluadorLote.java` y revisar los casos a mano.
- [x] **Verificar `ELIMINADO` / `RECIENTE` en `DIG_DOC_R00_B2`**. **Hecho 17/09/2026 —
      DESBLOQUEADO.** `ELIMINADO=1` confirmado como baja lógica real (existe también en
      B5, no solo B2; B4 no la tiene). `RECIENTE` investigado y **no** es flag de baja
      (distingue migración de WORKFLOW). Detalle completo, evidencia y el impacto medido
      sobre cada cifra publicada en §3 "Verificación ELIMINADO/RECIENTE". Filtro
      `WHERE NVL(ELIMINADO,0)=0` ya aplicado en las 4 queries que leen B2/B5.
- [x] Correr `vinculadas_doble_titular_misma_matricula.sql`. **Hecho 16/09/2026 — 3.006
      matrículas** con la misma persona duplicada como titular activo (§3); **recorrida
      17/09/2026 con el filtro de ELIMINADO → 2.868 matrículas (cifra vigente)**. Detalle
      (bloque 2, el listado fila por fila) **hecho 18/09/2026** en
      `vinculadas_doble_titular_misma_matricula_detalle.sql` → `scripts/out/`
      `vinculadas_doble_titular_misma_matricula_detalle_2026-09-18.md` (§3).
- [x] Informe de alcance para Mónica en Markdown: `scripts/out/`
      `Informe_Alcance_Depuracion_Titulares_2026-09-16.md`. **Hecho 16/09/2026.**
      **Actualizado 17/09/2026** en `scripts/out/Informe_Alcance_Depuracion_Titulares_2026-09-17.md`
      (archivo nuevo, no se sobrescribió el del 16/09): números finales con matrícula real
      + `ELIMINADO` filtrado (55.918 grupos, 30.136 P1, 164.418 matrículas, 2.868 doble
      titular), la salvedad de bajas lógicas ya cerrada, y dos anexos con ejemplos reales
      de registros — Anexo I con 3 casos en vivo (el extremo de 9 registros resultó ser
      el mismo bug de doble-submit que MAREU S.A.S., ver §7; una copropiedad grande con
      dos colisiones adentro; un posible caso de dos personas distintas con el mismo
      documento) y Anexo II con los casos de "personas mezcladas" ya confirmados en el
      Excel.
- [x] **Rehacer el corte exigiendo matrícula REAL** (`NU_MATRICULA IS NOT NULL`) **y sin
      `ELIMINADO`**: las `vinculadas_*.sql` del 16/09 no joineaban contra `DIG_DOC_R00` ni
      filtraban baja lógica. **Hecho 17/09/2026** — `vinculadas_matricula_real_kpi_pf.sql`,
      ver §3 "Corte con matrícula REAL". **Alcance final: 55.918 grupos, 30.136 P1.**
- [x] Lote de revisión manual sobre ese universo: `vinculadas_matricula_real_muestra.sql`
      (60 documentos, 30 P1 / 20 P2 / 10 P3, muestra reproducible por `ORA_HASH` en vez
      de `DBMS_RANDOM`, con el filtro de `ELIMINADO` ya aplicado). **Corrido 17/09/2026**
      → `scripts/out/lote_revision_manual_matricula_real_2026-09-17.md`. **Pasado por
      `EvaluadorLote.java` el 18/09/2026** junto con los 8 emblemáticos (67 documentos en
      total): 7 con registros sospechosos de ser personas distintas, 46 con CUIL ya cargado,
      0 sin CUIL calculable → `scripts/out/casos_representativos_candidato_2026-09-18.csv`.
      **Falta la revisión a mano** (y con ella la validación contra RENAPER, que el usuario
      hace él).
- [x] Investigar las **557 filas de titularidad con `ID_MATRICULA` inexistente** en
      `DIG_DOC_R00` (519 en B2, 38 en B4) — hallazgo del 17/09, §3. **Hecho 18/09/2026**
      con `titularidad_matricula_inexistente.sql` → `scripts/out/`
      `titularidad_matricula_inexistente_2026-09-18.md`. El conteo cierra exacto
      (519/38/0, sin drift de un día a otro). Ninguna fila tiene `ID_MATRICULA` NULO —
      las 557 son referencias a un número de matrícula que directamente no está en
      `DIG_DOC_R00` (no es un campo vacío, es un dato roto). Solo 1 de las 519 de B2 está
      además en `ELIMINADO=1`, y esa persona ni siquiera existe en `DIG_DOC_R62`
      (`CD_PERSONA` sin contraparte). Sigue sin explicación de causa — candidato a
      revisar contra producción o a preguntarle al equipo de SIRCLAN si hubo un borrado
      de matrículas sin depurar sus titularidades.
- [x] Rehacer `vinculadas_listado_grupos_pf.sql` (la hoja Detalle del entregable) con el
      filtro de matrícula real + `ELIMINADO`. **Hecho 18/09/2026** en
      `vinculadas_matricula_real_listado_grupos_pf.sql` → `scripts/out/`
      `detalle_grupos_priorizado_2026-09-18.csv`: 55.918 filas, partición
      30.136 / 17.449 / 8.333, y los tres agregados (78.210 redundantes, 123.118
      vinculadas, 67.200 a reasignar) cierran exactos contra §3. Ver §3 "Entregable del
      18/09".
- [x] Armar el entregable de PF duplicadas para Mónica. **Hecho 18/09/2026** — 6 CSV en
      `scripts/out/` (Resumen, Detalle priorizado, casos representativos en 3 archivos,
      doble titular) + `README_entregable_2026-09-18.md` con la guía de armado. **Se
      entrega como CSV, no como `.xlsx`**: no hay Python en la máquina y npm está bloqueado
      por el certificado corporativo, así que el libro lo arma el usuario pegando las
      hojas. Los CSV van con BOM UTF-8 y separador `;` para que Excel en español los abra
      con doble clic.
- [ ] Correr `vinculadas_kpi_pj.sql` (la única de las `vinculadas_*` que quedó sin
      correr) para tener el mismo recorte en jurídicas.
- [ ] Rehacer `vinculadas_matriculas_afectadas.sql` restringida a los grupos con 2+
      vinculados: la versión corrida cuenta también los "un solo vinculado", que no
      tienen nada que fusionar (el filtro de `ELIMINADO` ya está aplicado, ver §3).
- [ ] Recontar `censo_matriculas_r00.sql` (40.976 sin titular, 316 con % inválido) con el
      filtro de `ELIMINADO` — es la única cifra de impacto registral que todavía no lo
      tiene aplicado.
- [x] Correr `censo_matriculas_r00.sql` para refrescar el censo de matrículas. **Hecho
      17/09/2026** — ver §3 "Censo de matrículas — 17/09/2026 (VIGENTE)": 523.617
      matrículas reales usables (de 800.829 registros en R00), 40.976 sin titular, 316
      con % de titularidad inválido.
- [x] Decidir si las matrículas `BAJ` cuentan como "usables". **Decidido 17/09/2026: sí,
      quedan dentro del alcance por ahora** (§3, §5) — revisar si en la práctica conviene
      sacarlas más adelante.
- [ ] Con los KPI nuevos en la mano, rehacer la hoja Resumen del Excel: el alcance ahora
      es "grupos vinculados a matrícula", no el padrón entero. **No mezclar cortes**
      (§0): si una hoja usa el universo viejo, decirlo en la hoja.

**Datos / análisis**

- [x] Correr la query de distribución de grupos por estrato de cantidad de duplicados
      (bajo 2-3 / medio 4-6 / alto 7-10 / muy alto 11+). **Hecho 16/09/2026, ver §3.**
- [x] Cerrar las 4 hojas de caso sin observación: 4090581, 22136013, 6438047, 5330620.
      **Hecho — el usuario cargó los 4 casos en el Excel el 16/09/2026.**
- [x] Recalcular el KPI de PJ excluyendo el placeholder `30999078040`. **Hecho
      16/09/2026, ver §3** (variantes de typo del placeholder: pendiente, ver
      `pj_kpi_sin_placeholder.sql`, no cubiertas por la query).
- [ ] Dimensionar el segmento de 163.986 PF sin documento: qué porcentaje tiene
      titularidad en B2/B4/B5 y qué se hace con ellos. **Sube de prioridad con el criterio
      nuevo**: son personas sin documento que igual sostienen una matrícula, y el filtro
      de Mónica las mete en foco aunque no sean deduplicables por documento.
- [ ] Idem para las PJ sin CUIT utilizable (~42%): cuántas tienen titularidad real
      (variante comentada al pie de `vinculadas_kpi_pj.sql`).
- [~] Muestra aleatoria estratificada por estrato de tamaño
      (`muestra_aleatoria_estratificada.sql` / `muestra_detalle_persona_base.sql`):
      **superada** por la muestra sobre el universo vinculado. Se dejan los archivos como
      línea de base; no correrlos para el piloto.

**Código**

- [x] Extraer las 4 queries "Opción B" a `scripts/queries/*.sql` (las pasó el usuario,
      §9.1, en `consultas.sql`).
- [x] Extender `CalculadorCuil` a los prefijos 23/24 y devolver la lista de candidatos en
      orden, en vez de tirar excepción (§9.2). **Hecho 16/09/2026.**
- [x] Sumar los 11 casos del Excel que faltan como tests de `DetectorMezclados`. **Hecho
      16/09/2026 — 10/11 coinciden con la observación manual, 1 con un matiz (ver
      commit/historial de `DetectorMezclados.java`, caso 6899569).**
- [ ] Recalibrar o confirmar el umbral de similitud 0,75 contra la muestra representativa
      (la nueva, sobre el universo vinculado).
- [ ] Definir un techo de tamaño de grupo para no clusterizar grupos gigantescos. La
      distribución del 16/09 muestra que esto pesa muy poco en volumen (solo 20 grupos
      con 11+ duplicados, ver §3) — probablemente alcance con revisarlos a mano en vez de
      una regla general.

**Decisiones de arquitectura**

- [ ] Java (ya probado) vs. Python (a portar) para la orquestación a escala.
- [ ] Staging en Docker (Postgres/Oracle) para hacer bulk queries sin pegarle a la base de
      desarrollo compartida.
- [ ] Estimar rate/concurrencia seguro para las llamadas a la API: **~61.000** (una por
      cada uno de los 60.847 grupos del universo vinculado, §3), la mitad de las ~122.000
      que se estimaban sobre el padrón entero. Se puede bajar más si se ataca P1 primero
      (34.055 llamadas).

**Entrega**

- [ ] Una vez validada la metodología: correr el pipeline completo y generar el Excel final
      (hoja Resumen + hoja Detalle) para Mónica. La hoja Detalle sale de
      `vinculadas_listado_grupos_pf.sql` (una fila por grupo, priorizada P1/P2/P3).

**Etapa futura (no aprobada)**

- [ ] Revisar y verificar el DER, el DDL y el informe de propuesta de PostgreSQL — existen
      como borrador **fuera de este repo** y sin validar.
- [ ] Gestionar permiso de escritura (schema propio) en la base de desarrollo.
- [ ] Completar nombre y apellido de Mónica en el informe de propuesta antes de presentarlo.
