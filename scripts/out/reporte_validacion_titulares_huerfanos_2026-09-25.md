# Validación de titulares activos PF con matrícula inexistente (2026-09-25)

> Etapa de validación, **sin ninguna modificación a la base**. Todo se obtuvo con `SELECT` (RunQuery, guardrail de solo lectura).
> "CANDIDATO_ELIMINACION" significa evidencia suficiente para que una persona revise el caso antes de una eventual limpieza. **No hay DML en este documento.**

**Fuentes reproducibles** (todas en `scripts/`):

- `queries/validacion_huerfanos_01_dataset.sql`: una fila por titular huérfano, con los indicadores pedidos.
- `queries/validacion_huerfanos_02_relacionados.sql`: cada huérfano contra sus registros reales relacionados (persona, documento, caso, NU_MATRICULA, nomenclatura, padrón, asientos del caso).
- `queries/validacion_huerfanos_03_trazas_id.sql`: qué queda de cada ID huérfano en el resto del sistema, y la densidad de R00 por banda.
- `queries/validacion_huerfanos_04_clave_alternativa.sql`: el ID como NU_MATRICULA completo o sin el prefijo de departamento.
- `queries/validacion_huerfanos_05_r18_matriculacion.sql`: el formulario de matriculación (R18) de cada caso.
- `analisis/validar_titulares_huerfanos.js`: las reglas, la clasificación y este reporte.

Detalle fila por fila: `scripts/out/ANALISIS_TITULARES_MATRICULA_INEXISTENTE_DETALLE.csv`. Anexos por sección: `scripts/out/validacion_huerfanos_s{2..6}_*_2026-09-25.csv`.

## 1. Universo analizado

- **477 filas** de `DIG_DOC_R00_B2` vivas (`ELIMINADO=0`), de persona física, con `ID_MATRICULA` inexistente en `DIG_DOC_R00`. Corresponden a **197 IDs**, **333 CD_PERSONA** y **269 documentos**. El universo coincide exacto con el CSV del 24/09.
- Clave física de fila: `(ID_MATRICULA, NU_SEQUENCE)`, única sobre las 477. B2 **no tiene** `NU_MATRICULA` ni `ID_FORMULARIO` propios: `ID_FORMULARIO` es el de la persona (`= CD_PERSONA`). `NU_MATRICULA` en el detalle es **inferido**; la columna `ORIGEN_NU_MATRICULA` dice de dónde sale.

## 2. Cantidad por categoría

### 2.1 Categoría original (24/09) contra categoría verificada

| Original \ Verificada (mecanismo) | CABECERA_R00_FALTANTE_CON_GEMELA | CABECERA_R00_FALTANTE_GEMELA_SIN_TITULAR | CABECERA_R00_FALTANTE_SIN_GEMELA | HEREDADO_DE_MIGRACION | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA_SIN_TIT | MATRICULA_MIGRADA_RE_MATRICULADA | MATRICULA_MIGRADA_RE_MATRICULADA_SIN_TIT | MATRICULA_MIGRADA_SIN_R00 | NU_MATRICULA_COMPLETO_SIN_TITULAR | Total |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1-CLAVE_EQUIVOCADA | 0 | 0 | 0 | 0 | 5 | 0 | 0 | 0 | 0 | 0 | 5 |
| 2-BORRADOR_DE_TRAMITE | 8 | 2 | 2 | 0 | 7 | 0 | 0 | 0 | 0 | 0 | 19 |
| 3-COPIA_REGRABADO | 0 | 0 | 0 | 0 | 134 | 3 | 1 | 1 | 1 | 0 | 140 |
| 4-LEGADO_SIN_ALTA | 19 | 7 | 10 | 4 | 0 | 0 | 0 | 0 | 0 | 0 | 40 |
| 5-ORIGINAL_CON_TITULARIDAD_EN_OTRA | 0 | 0 | 1 | 1 | 153 | 5 | 4 | 2 | 3 | 0 | 169 |
| 6-ORIGINAL_UNICO | 0 | 0 | 0 | 3 | 86 | 7 | 0 | 2 | 2 | 4 | 104 |

> La categoría verificada describe el **mecanismo que explica la fila**. La condición de copia de otra fila huérfana se suma aparte, en la sección 4. Una fila puede ser, por ejemplo, `MATRICULACION_CON_NUMERO_DE_PROCEDENCIA` y además una copia.

### 2.2 Recomendación

| Recomendación | Filas | % |
|---|---|---|
| CANDIDATO_ELIMINACION | 315 | 66.0 |
| REVISAR | 120 | 25.2 |
| CONSERVAR | 42 | 8.8 |

| Original \ Recomendación | CANDIDATO_ELIMINACION | CONSERVAR | REVISAR | Total |
|---|---|---|---|---|
| 1-CLAVE_EQUIVOCADA | 5 | 0 | 0 | 5 |
| 2-BORRADOR_DE_TRAMITE | 15 | 2 | 2 | 19 |
| 3-COPIA_REGRABADO | 104 | 0 | 36 | 140 |
| 4-LEGADO_SIN_ALTA | 19 | 14 | 7 | 40 |
| 5-ORIGINAL_CON_TITULARIDAD_EN_OTRA | 112 | 12 | 45 | 169 |
| 6-ORIGINAL_UNICO | 60 | 14 | 30 | 104 |

## 3. Cantidad por nivel de evidencia

| Recomendación \ Nivel | ALTO | BAJO | MEDIO | Total |
|---|---|---|---|---|
| CANDIDATO_ELIMINACION | 92 | 0 | 223 | 315 |
| CONSERVAR | 0 | 5 | 37 | 42 |
| REVISAR | 2 | 13 | 105 | 120 |

Criterios de nivel:

- **ALTO**: el mecanismo está documentado en la base (R18 o NU_MATRICULA), **y** la misma `CD_PERSONA` ya es titular **activa** en la matrícula real. También cuenta la copia idéntica (tipo A) de otra fila huérfana.
- **MEDIO**: hay mecanismo, pero la coincidencia es solo por documento con nombre compatible, o la titularidad en la matrícula real es **histórica** (B4). También la copia con diferencias menores (tipo B).
- **BAJO**: hay un indicio (número, nomenclatura o ID contiguo), pero no coincide el titular, o el documento aparece con otro nombre.
- **NULO**: nada vincula la fila con otra titularidad.

## 4. Principales patrones encontrados

### 4.1 CONFIRMADO en los datos: el trámite de matriculación grabó el número de la matrícula de procedencia como ID (400 filas, 83.9%)

`NU_MATRICULA` tiene el formato `<departamento><número de 8 dígitos>` (400586391 = departamento 4, número 586391). De las 396 filas con ID en las bandas A y B:

- **384** tienen una matrícula real cuyo `NU_MATRICULA`, sin el departamento, es igual al ID huérfano. Siempre es una sola candidata.
- **384** además tienen un formulario R18 ("Generación de Mat SIRC", procesos 1230/4029/4033/4035) con `NU_MATRICULA_PRO` = ID huérfano y `CD_MATRICULA` = esa matrícula real. En 127 filas ese R18 está anexado **al mismo caso** que figura en `NU_CASO_ORIGEN`.
- En **385** de las 400 filas con mecanismo, la persona o el documento (con nombre compatible) es titular de la matrícula real. Casi siempre aparece como **histórico en B4**: 299 solo en B4, 86 activo en B2.

Lectura: al matricular en SIRC un inmueble que venía de una matrícula anterior (procedencia "MAT n"), los titulares de la procedencia quedaron grabados en B2 con `ID_MATRICULA = n`, el número de procedencia, en vez del ID de la matrícula nueva. En la matrícula nueva esos mismos titulares aparecen en B4, porque después hubo una transferencia, o en B2. **El mecanismo es consistente fila por fila, pero es una inferencia sobre los datos. La confirmación del bug en el código la tiene que dar el equipo de SIRCLAN** (sección 12).

Dato lateral que apunta al mecanismo: cuando la misma persona es titular ACTIVA en la matrícula real, esa fila real casi nunca tiene auditoría (65 de 71 filas sin `DT_ALTA` ni `CD_USER_STORE`). La fila huérfana del mismo caso, en cambio, sí tiene usuario y hora. Es compatible con dos caminos de grabación distintos: el motor del proceso graba sin auditoría en la matrícula correcta, y la pantalla del operador graba con auditoría usando el número de procedencia. Es una hipótesis para el equipo de SIRCLAN, no una conclusión.

### 4.2 CONFIRMADO: matrículas sin cabecera R00, con el resto del formulario vivo (49 filas)

37 IDs huérfanos conservan filas en otras tablas del formulario R00: `_A1` (estado), `_A2` (asientos), `_B1` (procedencia), `_B3` (nomenclatura) y `_B8` (padrón). Todos están en las bandas E y C. Falta solamente la fila de `DIG_DOC_R00`, la cabecera. En los IDs 6.0M–6.39M (2023–2026), la nomenclatura catastral de 27 filas coincide con la de una matrícula real creada unos IDs después, por el mismo proceso 4025 y a menudo con el mismo caso, y con la misma persona como titular activa. Parece un trámite que generó la matrícula dos veces, con la primera generación a medio borrar. **48 de esas 49 filas tienen `DT_ALTA`, `CD_USER_STORE` y `RECIENTE` nulos**, así que la categoría original "LEGADO_SIN_ALTA" es incorrecta: no son legado. El rango de ID y los vecinos de R00 las fechan en 2023–2026.

### 4.3 CONFIRMADO: el re-grabado existe, pero no siempre es una copia idéntica

83 grupos (matrícula, persona) con más de una fila, que suman 224 filas: **A** = 23 grupos, **B** = 40 grupos, **C** = 18 grupos, **D** = 2 grupos. Detalle en la sección 4 de los anexos (`s4`).

### 4.4 Descartado: "ORIGINAL_UNICO" y "ORIGINAL_CON_TITULARIDAD_EN_OTRA" no son categorías reales

Las dos se definían por la presencia o ausencia de la persona en **otras** matrículas **activas**, sin mirar B4 ni la matrícula a la que la fila en realidad pertenece. Al agregar el departamento al número, la mayoría de esas filas encuentra su matrícula (sección 5 y sección 6).

## 5. Casos representativos

| Registro | Persona | Doc. | Alta / usuario | Verificada | Rec. | Evidencia |
|---|---|---|---|---|---|---|
| 184-0 | JURY, GUSTAVO ENRIQUE | 17598181 | 2018-12-21 14:10 ACHIARELLO | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA | CANDIDATO_ELIMINACION / MEDIO | El trámite de matriculación (R18 86194, 2018-12-21, ACHIARELLO, anexado al mismo caso 00CASO034630418000) generó la matrícula ID 1568507 (500000184) desde la procedencia "MAT 184" del depto 05. La fila B2 quedó con ID_MATRICULA = 184 (número de procedencia) en vez de 1568507. En esa matrícula la MISMA persona figura como titular HISTÓRICO (B4): la titularidad ya está registrada y cerrada, y el huérfano la sigue mostrando como activa. |
| 2083-0 | BENITO, RICARDO | 216034 | 2020-11-06 15:06 CMIRANDA | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA | CANDIDATO_ELIMINACION / MEDIO | El trámite de matriculación (R18 152722, 2020-11-06, CMIRANDA, anexado al mismo caso 00CASO020843220000) generó la matrícula ID 1492543 (400002083) desde la procedencia "MAT 2083" del depto 04. La fila B2 quedó con ID_MATRICULA = 2083 (número de procedencia) en vez de 1492543. En esa matrícula la MISMA persona figura como titular HISTÓRICO (B4): la titularidad ya está registrada y cerrada, y el huérfano la sigue mostrando como activa. |
| 63111-0 | FUNES, FERNANDO | 3342112 | 2024-11-22 14:33 AEGUAJARDO | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA_SIN_TITULAR_EN_REAL | CONSERVAR / MEDIO | El trámite de matriculación (R18 311671, 2024-11-15, FALEGRE) generó la matrícula ID 5215534 (100063111) desde la procedencia "MAT 63111" del depto 01. La fila B2 quedó con ID_MATRICULA = 63111 (número de procedencia) en vez de 5215534. Pero la persona NO figura como titular, ni activa ni histórica, en la matrícula ID 5215534: la fila huérfana puede ser el único rastro de esa titularidad. Corresponde re-vincular tras verificar, no borrar. |
| 6372231-0 | PALACIO, MANUEL OSCAR | 16616535 | (sin alta)  | CABECERA_R00_FALTANTE_CON_GEMELA | CANDIDATO_ELIMINACION / ALTO | El ID 6372231 no tiene cabecera en R00 pero conserva 5 filas hijas del formulario (procedencia, nomenclatura, padrón). La matrícula ID 6372245 (400605031) tiene la misma nomenclatura o padrón y comparte el caso de origen, y la misma persona es titular activo ahí. El trámite generó la matrícula dos veces y la primera quedó sin cabecera. |
| 1439223-1 | LEMOLI, JUAN CARLOS | 8149976 | 2024-06-28 13:43 DRIVEROS | CABECERA_R00_FALTANTE_SIN_GEMELA | CONSERVAR / MEDIO | Sin cabecera R00, pero con 1 filas hijas del formulario y 1 filas en B4, y sin matrícula gemela ni titularidad equivalente. Parece una matrícula real a la que le falta la fila de R00: lo que falta es la cabecera, no sobra el titular. |
| 800390493-0 | GARAVAGLIA, DANIEL EDGARDO | 14880514 | 2018-08-24 11:14 MEESPINOLA | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA | CANDIDATO_ELIMINACION / ALTO | El trámite de matriculación (R18 9284, 2017-06-13, LUGONZALEZ) generó la matrícula ID 5750840 (800390493) desde la procedencia "MAT 800390493" del depto 08. La fila B2 quedó con ID_MATRICULA = 800390493 (número de procedencia) en vez de 5750840. En esa matrícula la MISMA persona (CD_PERSONA) ya es titular ACTIVA: la fila huérfana repite una titularidad existente. |
| 400013472-2 | GARCIA, MARGARITA | 30308924 | 2018-08-24 09:56 LUGONZALEZ | NU_MATRICULA_COMPLETO_SIN_TITULAR | REVISAR / BAJO | El ID 400013472 es el NU_MATRICULA de la matrícula ID 1559363 (estado ACT). Pero ni la persona ni el documento son titulares ahí (ni en B2 ni en B4): puede ser una coincidencia numérica o una titularidad que nunca se trasladó. |
| 1400669-0 | ZOGBI, ROBERTO |  | 2008-06-20 00:00  | HEREDADO_DE_MIGRACION | CONSERVAR / MEDIO | La fila ya existía en la migración (está en DIG_DOC_R00_B2_20170902) y el ID conserva 1 filas hijas en R00. La matrícula 1400669 no llegó a R00 o se borró después. Es historia registral, no una copia. La candidata 5017797 no tiene a esta persona como titular. |
| 5198683-0 | CORDOBA DE BOERO, RAMONA OLGA | 3612503 | 2022-03-31 12:00 MVILLADA | MATRICULA_MIGRADA_RE_MATRICULADA | REVISAR / MEDIO | El ID 5198683 es una matrícula de la migración (V_PROCEDENCIA_DOMNIO_MIG) que ya no tiene cabecera en R00. La matrícula ID 6351345 (300581115) tiene el mismo tomo/foja/inscripción/departamento: es la misma finca, re-matriculada. En esa matrícula otro registro de persona con el mismo documento y nombre compatible (CORDOBA DE BOERO, RAMONA OLGA) ya es titular ACTIVO. Es probable que sea la misma titularidad, pero mismo DNI no es misma persona. |

### 5.1 CLAVE_EQUIVOCADA (pedido §2): los 5 casos, uno por uno

**53877-1** · NAVARRO, DANIEL (doc. 11213695, CD_PERSONA 5621188) · alta 2021-12-20 12:33:30 por GARCE · TM_DESDE 2021-12-20 12:33:30 · caso (vacío)

- ID_MATRICULA huérfano: **53877**. ¿Existe como NU_MATRICULA? **Sí**: matrícula ID **1474552**, NU 53877, estado CRE, depto 04.
- Titulares activos de la matrícula real (2): NAVARRO, DANIEL (doc 11213695, CD_PERSONA 1486404, alta s/d); NAVARRO, SILVIA (doc 6644922, CD_PERSONA 1572842, alta s/d).
- ¿La misma persona/documento es titular ahí? Persona activa: no · documento activo: sí · documento histórico (B4): no.
- **Veredicto:** MATRICULACION_CON_NUMERO_DE_PROCEDENCIA (MEDIO). El trámite de matriculación (R18 204646, 2022-03-10, RGUILLOT) generó la matrícula ID 1474552 (53877) desde la procedencia "MAT 53877" del depto 04. La fila B2 quedó con ID_MATRICULA = 53877 (número de procedencia) en vez de 1474552. En esa matrícula otro registro de persona con el mismo documento y nombre compatible (NAVARRO, DANIEL) ya es titular ACTIVO. Es probable que sea la misma titularidad, pero mismo DNI no es misma persona.

**53877-2** · NAVARRO, SILVIA (doc. 6644922, CD_PERSONA 5621191) · alta 2021-12-20 12:36:38 por GARCE · TM_DESDE 2021-12-20 12:36:38 · caso (vacío)

- ID_MATRICULA huérfano: **53877**. ¿Existe como NU_MATRICULA? **Sí**: matrícula ID **1474552**, NU 53877, estado CRE, depto 04.
- Titulares activos de la matrícula real (2): NAVARRO, DANIEL (doc 11213695, CD_PERSONA 1486404, alta s/d); NAVARRO, SILVIA (doc 6644922, CD_PERSONA 1572842, alta s/d).
- ¿La misma persona/documento es titular ahí? Persona activa: no · documento activo: sí · documento histórico (B4): no.
- **Veredicto:** MATRICULACION_CON_NUMERO_DE_PROCEDENCIA (MEDIO). El trámite de matriculación (R18 204646, 2022-03-10, RGUILLOT) generó la matrícula ID 1474552 (53877) desde la procedencia "MAT 53877" del depto 04. La fila B2 quedó con ID_MATRICULA = 53877 (número de procedencia) en vez de 1474552. En esa matrícula otro registro de persona con el mismo documento y nombre compatible (NAVARRO, SILVIA) ya es titular ACTIVO. Es probable que sea la misma titularidad, pero mismo DNI no es misma persona.

**800390493-0** · GARAVAGLIA, DANIEL EDGARDO (doc. 14880514, CD_PERSONA 1590942) · alta 2018-08-24 11:14:42 por MEESPINOLA · TM_DESDE 2018-08-24 11:14:42 · caso (vacío)

- ID_MATRICULA huérfano: **800390493**. ¿Existe como NU_MATRICULA? **Sí**: matrícula ID **5750840**, NU 800390493, estado ACT, depto 08.
- Titulares activos de la matrícula real (24): CIANCIO, ESTEFANIA (doc 34312751, CD_PERSONA 5447876, alta s/d); GIRALA, SHARBELA YAMILE (doc 33321188, CD_PERSONA 5354945, alta s/d); RUIZ, JUAN PABLO (doc 33429978, CD_PERSONA 5447435, alta s/d); CIANCIO, RICARDO JUAN PABLO (doc 13218488, CD_PERSONA 1602519, alta s/d); ARIAS, MONICA ELVIRA (doc 13328155, CD_PERSONA 1602517, alta s/d); SPOGGI, ANTONELA LIZ (doc 35515016, CD_PERSONA 5488380, alta s/d); ABDALA, PATRICIA ELENA (doc 16284947, CD_PERSONA 1592207, alta s/d); MARTINEZ, MARIA DEL VALLE (doc 25842484, CD_PERSONA 5485878, alta s/d); ,  (doc , CD_PERSONA 5435416, alta s/d); ESPINOZA, VICTOR GABRIEL (doc 29244433, CD_PERSONA 5436854, alta s/d); CORNEJO, CLAUDIA GABRIELA (doc 27615366, CD_PERSONA 5431320, alta s/d); ,  (doc , CD_PERSONA 5077315, alta s/d); ,  (doc , CD_PERSONA 5077315, alta s/d); SOTANA, ALEXIS GABRIEL (doc 22828358, CD_PERSONA 1402199, alta s/d); MARTIN, MIGUEL ALBERTO (doc 7937045, CD_PERSONA 1585878, alta s/d); CAMPODONICO, LUCIA MABEL (doc 5671197, CD_PERSONA 5531567, alta s/d); FIGUEROA, LEONARDO JOSE (doc 32634911, CD_PERSONA 5401902, alta s/d); LORCA, PABLO DAMIAN (doc 28668829, CD_PERSONA 5483870, alta s/d); FIGUEROA, VANESA PAOLA (doc 30203685, CD_PERSONA 1610652, alta s/d); GARAVAGLIA, DANIEL EDGARDO (doc 14880514, CD_PERSONA 1590942, alta s/d, caso 00CASO010730922000); COCCONI, RUBEN SEBASTIAN (doc 28882943, CD_PERSONA 5365674, alta s/d); TAGLIAFERRO, ISABELLA LUCIA (doc 38334685, CD_PERSONA 5663384, alta s/d); TAGLIAFERRO, CAMILA (doc 40465356, CD_PERSONA 5338081, alta s/d); STACCHIOLA, LUCAS DAN (doc 33583300, CD_PERSONA 5714773, alta 2026-08-25 GMFERNANDE).
- ¿La misma persona/documento es titular ahí? Persona activa: sí · documento activo: sí · documento histórico (B4): sí.
- **Veredicto:** MATRICULACION_CON_NUMERO_DE_PROCEDENCIA (ALTO). El trámite de matriculación (R18 9284, 2017-06-13, LUGONZALEZ) generó la matrícula ID 5750840 (800390493) desde la procedencia "MAT 800390493" del depto 08. La fila B2 quedó con ID_MATRICULA = 800390493 (número de procedencia) en vez de 5750840. En esa matrícula la MISMA persona (CD_PERSONA) ya es titular ACTIVA: la fila huérfana repite una titularidad existente.

**800433207-0** · GARAVAGLIA, DANIEL EDGARDO (doc. 14880514, CD_PERSONA 1590942) · alta 2018-08-24 11:05:01 por MEESPINOLA · TM_DESDE 2018-08-24 11:05:01 · caso (vacío)

- ID_MATRICULA huérfano: **800433207**. ¿Existe como NU_MATRICULA? **Sí**: matrícula ID **5953069**, NU 800433207, estado ACT, depto 08.
- Titulares activos de la matrícula real (1): GARAVAGLIA, DANIEL EDGARDO (doc 14880514, CD_PERSONA 1590942, alta s/d).
- ¿La misma persona/documento es titular ahí? Persona activa: sí · documento activo: sí · documento histórico (B4): no.
- **Veredicto:** MATRICULACION_CON_NUMERO_DE_PROCEDENCIA (ALTO). El trámite de matriculación (R18 19446, 2017-08-31, SRAMIREZ) generó la matrícula ID 5953069 (800433207) desde la procedencia "MAT 800433207" del depto 08. La fila B2 quedó con ID_MATRICULA = 800433207 (número de procedencia) en vez de 5953069. En esa matrícula la MISMA persona (CD_PERSONA) ya es titular ACTIVA: la fila huérfana repite una titularidad existente.

**800433207-1** · GARAVAGLIA, DANIEL EDGARDO (doc. 14880514, CD_PERSONA 1590942) · alta 2018-08-24 11:05:38 por MEESPINOLA · TM_DESDE 2018-08-24 11:05:38 · caso (vacío)

- ID_MATRICULA huérfano: **800433207**. ¿Existe como NU_MATRICULA? **Sí**: matrícula ID **5953069**, NU 800433207, estado ACT, depto 08.
- Titulares activos de la matrícula real (1): GARAVAGLIA, DANIEL EDGARDO (doc 14880514, CD_PERSONA 1590942, alta s/d).
- ¿La misma persona/documento es titular ahí? Persona activa: sí · documento activo: sí · documento histórico (B4): no.
- **Veredicto:** MATRICULACION_CON_NUMERO_DE_PROCEDENCIA + COPIA_A (ALTO). El trámite de matriculación (R18 19446, 2017-08-31, SRAMIREZ) generó la matrícula ID 5953069 (800433207) desde la procedencia "MAT 800433207" del depto 08. La fila B2 quedó con ID_MATRICULA = 800433207 (número de procedencia) en vez de 5953069. En esa matrícula la MISMA persona (CD_PERSONA) ya es titular ACTIVA: la fila huérfana repite una titularidad existente. Además es la copia n.º 2 de 2 de la misma titularidad en el mismo ID (tipo A: idénticas salvo DT_ALTA / TM_DESDE / NU_SEQUENCE); se conserva como representante 800433207-0.

Hay además **14 filas** cuyo ID también es un NU_MATRICULA completo y que el 24/09 **no** se clasificaron como clave equivocada: 41401, 53877, 62687, 71421, 88819, 117137, 400013472. En 4 de ellas la persona no es titular de la matrícula con ese número, así que la coincidencia numérica sola no alcanza. Por ejemplo, las tres filas GARCIA del ID 400013472 (alta 24/08/2018, LUGONZALEZ): la matrícula 400013472 existe (ID 1559363), pero sus titulares son otras personas.

**Respuesta a "¿realmente se cargó el NU_MATRICULA como ID?":** en las 5 filas originales el ID es, efectivamente, un NU_MATRICULA existente, y el titular activo coincide (3 por CD_PERSONA y 2 por documento con nombre compatible). Pero **"se tipeó el NU_MATRICULA en el campo ID" no es la mejor explicación**: en las 5 hay un R18 de matriculación cuyo `NU_MATRICULA_PRO` (procedencia) es exactamente ese número, y cuya `CD_MATRICULA` es la matrícula real. Es el mismo mecanismo de la sección 4.1: en GARAVAGLIA la procedencia se cargó con el departamento (800390493) y en NAVARRO sin él (53877, que casualmente también es un NU_MATRICULA de legado). Ver `s2`.

### 5.2 BORRADOR_DE_TRAMITE (pedido §3): comparación huérfano contra registro real

| Huérfano | Persona | Alta huérfano | Registro real | Matrícula real | Alta real | Δ | Mismo usuario | Misma persona | Mismo doc. | Primero | Veredicto |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 384754-1 | BALIANI, ELSA SILVIA | 2020-12-17 11:11 | 5726486-2 | 5726486 / 900384754 |  | (real sin DT_ALTA) |  | SI | SI | ver R00: real creada 2017-04-18 | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA (ALTO) |
| 384754-3 | PALLERES, MONICA GRACIELA | 2020-12-17 11:13 | 5726486-4 | 5726486 / 900384754 |  | (real sin DT_ALTA) |  | SI | SI | ver R00: real creada 2017-04-18 | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA (ALTO) |
| 384754-2 | ROLDAN, ELSA GLADYS | 2020-12-17 11:12 | 5726486-3 | 5726486 / 900384754 |  | (real sin DT_ALTA) |  | SI | SI | ver R00: real creada 2017-04-18 | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA (ALTO) |
| 384754-0 | VIGNONI, HECTOR SERGIO | 2020-12-17 11:09 | 5726486-1 | 5726486 / 900384754 |  | (real sin DT_ALTA) |  | SI | SI | ver R00: real creada 2017-04-18 | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA (ALTO) |
| 384754-5 | MAINERI, MARIO EDUARDO | 2020-12-17 11:15 | 5726486-6 | 5726486 / 900384754 |  | (real sin DT_ALTA) |  | SI | SI | ver R00: real creada 2017-04-18 | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA (ALTO) |
| 384754-4 | FERNANDEZ, SERVANDO DOMINGO | 2020-12-17 11:14 | 5726486-5 | 5726486 / 900384754 |  | (real sin DT_ALTA) |  | SI | SI | ver R00: real creada 2017-04-18 | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA (ALTO) |
| 384754-6 | GONZALEZ, LAURA ELIZABETH | 2020-12-17 11:17 | 5726486-7 | 5726486 / 900384754 |  | (real sin DT_ALTA) |  | SI | SI | ver R00: real creada 2017-04-18 | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA (ALTO) |
| 6372231-0 | PALACIO, MANUEL OSCAR | (sin alta) | 6372245-0 | 6372245 / 400605031 |  | (ninguno tiene DT_ALTA) |  | SI | SI | ver R00: real creada 2024-03-25 | CABECERA_R00_FALTANTE_CON_GEMELA (ALTO) |
| 6372232-0 | VALDES, GONZALO RAÚL | (sin alta) | 6372246-0 | 6372246 / 400605032 |  | (ninguno tiene DT_ALTA) |  | SI | SI | ver R00: real creada 2024-03-25 | CABECERA_R00_FALTANTE_CON_GEMELA (ALTO) |
| 6372233-0 | IBARZABAL, GERARDO ANTONIO | (sin alta) | 6372247-0 | 6372247 / 400605033 |  | (ninguno tiene DT_ALTA) |  | SI | SI | ver R00: real creada 2024-03-25 | CABECERA_R00_FALTANTE_CON_GEMELA (ALTO) |
| 6372233-1 | RUIZ SAEZ, ANABELIA | (sin alta) | 6372247-1 | 6372247 / 400605033 |  | (ninguno tiene DT_ALTA) |  | SI | SI | ver R00: real creada 2024-03-25 | CABECERA_R00_FALTANTE_CON_GEMELA (ALTO) |
| 6372237-0 | GARCIA, HÉCTOR MARTÍN | (sin alta) | 6372248-0 | 6372248 / 400605034 | 2025-02-26 15:35 | (huérfano sin DT_ALTA) | NO | NO | NO | ver R00: real creada 2024-03-25 | CABECERA_R00_FALTANTE_GEMELA_SIN_TITULAR (BAJO) |
| 6372241-0 | ÁLVAREZ, ROXANA LOURDES | (sin alta) | 6372249-0 | 6372249 / 400605035 | 2026-08-17 09:51 | (huérfano sin DT_ALTA) | NO | NO | NO | ver R00: real creada 2024-03-25 | CABECERA_R00_FALTANTE_GEMELA_SIN_TITULAR (BAJO) |
| 6372242-0 | GARRIDO, CARLOS HERNÁN | (sin alta) | 6372250-0 | 6372250 / 400605036 |  | (ninguno tiene DT_ALTA) |  | SI | SI | ver R00: real creada 2024-03-25 | CABECERA_R00_FALTANTE_CON_GEMELA (ALTO) |
| 6372242-1 | COMERCI HERNANDEZ, ANDREA SOLEDAD | (sin alta) | 6372250-1 | 6372250 / 400605036 |  | (ninguno tiene DT_ALTA) |  | SI | SI | ver R00: real creada 2024-03-25 | CABECERA_R00_FALTANTE_CON_GEMELA (ALTO) |
| 6372243-1 | VEDIA DELMAU, LUCAS DAVID | (sin alta) | 6372245-0 | 6372245 / 400605031 |  | (ninguno tiene DT_ALTA) |  | NO | NO | ver R00: real creada 2024-03-25 | CABECERA_R00_FALTANTE_SIN_GEMELA (MEDIO) |
| 6372243-0 | CANO SARAPURA, CINTIA | (sin alta) | 6372245-0 | 6372245 / 400605031 |  | (ninguno tiene DT_ALTA) |  | NO | NO | ver R00: real creada 2024-03-25 | CABECERA_R00_FALTANTE_SIN_GEMELA (MEDIO) |
| 6372244-0 | BELMONTE, MARÍA FERNANDA | (sin alta) | 6372252-0 | 6372252 / 400605038 |  | (ninguno tiene DT_ALTA) |  | SI | SI | ver R00: real creada 2024-03-25 | CABECERA_R00_FALTANTE_CON_GEMELA (ALTO) |
| 6372514-0 | GARNICA, CLAUDIA BEATRIZ | (sin alta) | 6372516-0 | 6372516 / 600605309 |  | (ninguno tiene DT_ALTA) |  | SI | SI | ver R00: real creada 2024-04-05 | CABECERA_R00_FALTANTE_CON_GEMELA (ALTO) |

**Lectura.** Los 19 son dos fenómenos distintos que la heurística juntó:

- **7 filas (ID en banda B)** son el mecanismo de la sección 4.1. El "caso compartido" es el mismo trámite de matriculación, que grabó a la persona una vez con el número de procedencia y otra vez en la matrícula nueva. Coinciden la persona y el caso, y en general el usuario. La diferencia es de minutos. No es un borrador: es la **misma titularidad grabada con dos claves**.
- **12 filas (IDs 6.372.231–6.372.244 y 6.372.514)** sí encajan con "borrador de trámite". Un mismo caso (proceso 4025) generó dos juegos de matrículas: el primero quedó sin cabecera R00 y el segundo existe, con IDs más altos, la **misma nomenclatura catastral uno a uno** y el mismo titular. Las huérfanas no tienen `DT_ALTA`, así que el orden se deduce de los IDs de R00 y de la fecha de creación de la matrícula real.
- Evidencia suficiente para leer el huérfano como residuo del trámite: **sí** en 15 de 19, porque coinciden la persona o el documento, el caso y la nomenclatura. **No** en 4, porque la persona no aparece en la matrícula real del caso, o porque esa matrícula es la gemela de otra parcela.

### 5.3 COPIA_REGRABADO (pedido §4): los grupos repetidos

| Tipo | Significado | Grupos | Filas |
|---|---|---|---|
| A | prácticamente idéntica (solo cambian DT_ALTA, TM_DESDE y NU_SEQUENCE) | 23 | 56 |
| B | diferencias menores (caso vacío en la copia, RECIENTE, usuario, dato vacío completado en un mismo reintento) | 40 | 112 |
| C | cambian datos relevantes (porcentaje, fecha desde, situación o asiento con valores distintos) | 18 | 48 |
| D | ambiguo (difieren por datos vacíos, con usuarios distintos y más de 24 h de distancia) | 2 | 8 |

El 24/09 se contaron 83 grupos y 141 copias. Hoy se ven 83 grupos con 141 filas "de más". Es el mismo universo: la diferencia es qué fila se toma como original. Acá el representante es la fila con más datos (caso, porcentaje, desde, asiento), no la más vieja.

**Grupos donde la duplicación NO parece un simple regrabado (tipo C y D):**

| Grupo | Persona | Filas | Qué cambia | Usuarios | Primera → última alta |
|---|---|---|---|---|---|
| 184/1605172 | JURY, MARIELA ANABEL | 2 | cambian datos relevantes: NU_ASIEN_2 | ACHIARELLO | 2018-12-21 14:11 → 2018-12-21 14:13 |
| 184/1605173 | JURY, VIVIANA CLAUDIA | 2 | cambian datos relevantes: NU_ASIEN_2 | ACHIARELLO | 2018-12-21 14:10 → 2018-12-21 14:12 |
| 184/1605174 | JURY, ALFREDO JORGE | 2 | cambian datos relevantes: NU_ASIEN_2 | ACHIARELLO | 2018-12-21 14:10 → 2018-12-21 14:12 |
| 35660/5620865 | CANNIZZO, OLGA | 3 | cambian datos relevantes: DS_PORCENTAJE, NU_ASIEN_2 | FALEGRE | 2021-12-15 12:54 → 2021-12-15 13:02 |
| 59224/1642620 | CORTEZ, MARIA AZUCENA | 2 | cambian datos relevantes: DT_DESDE | FALEGRE | 2024-11-06 09:29 → 2024-11-06 12:45 |
| 73018/1653758 | TALQUENCA, CARLOS JOSE | 7 | cambian datos relevantes: DT_DESDE | ESOTELO | 2018-11-26 13:34 → 2018-11-27 13:27 |
| 74600/5355090 | BALACCO, DARIO ANDRES | 2 | cambian datos relevantes: DT_DESDE | CMIRANDA,AFUENTES | 2020-05-28 10:46 → 2020-05-29 11:51 |
| 79771/5598307 | GIUGNO, CARMELO ROBERTO | 3 | cambian datos relevantes: NU_ASIEN_2 | CMIRANDA | 2020-09-22 13:10 → 2020-09-22 18:34 |
| 106041/5555775 | GODOY SPORTARO, HECTOR RUBEN | 3 | cambian datos relevantes: NU_ASIEN_2 | GARCE,AEGUAJARDO | 2022-10-03 08:13 → 2022-10-05 09:09 |
| 144124/1527696 | TORRESI, FAVIO AROLDO | 2 | cambian datos relevantes: DS_PORCENTAJE | FALEGRE | 2021-03-26 11:17 → 2021-03-26 11:18 |
| 216069/1443847 | DELABALLE, CELINA MARIANA | 2 | cambian datos relevantes: DT_DESDE, NU_ASIEN_2 | IFERNANDEZ | 2026-06-12 07:38 → 2026-06-12 07:39 |
| 216069/5710541 | DELABALLE, CARINA MARIANA | 2 | cambian datos relevantes: DT_DESDE, NU_ASIEN_2 | RFARRUGGIA | 2026-06-16 10:24 → 2026-06-16 10:25 |
| 254990/5025872 | GONZALEZ, VICENTE JOSE | 6 | cambian datos relevantes: DT_DESDE | MDINASSO | 2024-07-16 12:58 → 2024-07-23 09:35 |
| 363631/5380979 | BLAZQUEZ, MATIAS DANIEL | 2 | cambian datos relevantes: DT_DESDE, DS_PORCENTAJE, NU_ASIEN_2 | GJFIORENS | 2025-02-13 14:04 → 2025-02-13 14:05 |
| 363631/5380980 | BLAZQUEZ, FEDERICO MARTIN | 2 | cambian datos relevantes: DT_DESDE, DS_PORCENTAJE, NU_ASIEN_2 | GJFIORENS | 2025-02-13 14:05 → 2025-02-13 14:06 |
| 363631/5380981 | BLAZQUEZ, GUILLERMO ANDRES | 2 | cambian datos relevantes: DT_DESDE, DS_PORCENTAJE, NU_ASIEN_2 | GJFIORENS | 2025-02-13 14:04 → 2025-02-13 14:06 |
| 394733/5528035 | SORIANO, LEANDRO EMANUEL | 2 | cambian datos relevantes: DS_PORCENTAJE | ESOTELO | 2018-11-22 08:34 → 2018-11-22 08:35 |
| 5134600/5363923 | PORRO, ABELARDO ARTURO | 2 | cambian datos relevantes: NU_NUMERADOR, NU_ASIEN_2 | GJFIORENS,GACHIARELL | 2020-09-23 17:13 → 2020-09-23 18:19 |
| 244133/5441898 | CHACON, VERONICA SILVANA | 3 | difieren por datos vacíos (DT_DESDE), con 2 usuarios y 2.9 d entre la primera y la última: no se distingue si es completar o corregir | CALBANI,MFERNANDEZ | 2020-09-28 14:02 → 2020-10-01 11:41 |
| 244133/5441900 | JEREZ, MYRIAM OLGA | 5 | difieren por datos vacíos (DT_DESDE, NU_ASIEN_2), con 2 usuarios y 2.9 d entre la primera y la última: no se distingue si es completar o corregir | CALBANI,MFERNANDEZ | 2020-09-28 14:04 → 2020-10-01 11:41 |

### 5.4 ORIGINAL_CON_TITULARIDAD_EN_OTRA (pedido §5)

| Veredicto | Filas | % |
|---|---|---|
| POSIBLE_DUPLICADO | 128 | 75.7 |
| FUERTE_EVIDENCIA_DE_DUPLICADO | 28 | 16.6 |
| POSIBLE_HISTORIA_REAL | 12 | 7.1 |
| INDETERMINADO | 1 | 0.6 |

| Veredicto \ mecanismo | CABECERA_R00_FALTANTE_SIN_GEMELA | HEREDADO_DE_MIGRACION | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA_SIN_TIT | MATRICULA_MIGRADA_RE_MATRICULADA | MATRICULA_MIGRADA_RE_MATRICULADA_SIN_TIT | MATRICULA_MIGRADA_SIN_R00 | Total |
|---|---|---|---|---|---|---|---|---|
| FUERTE_EVIDENCIA_DE_DUPLICADO | 0 | 0 | 28 | 0 | 0 | 0 | 0 | 28 |
| INDETERMINADO | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 1 |
| POSIBLE_DUPLICADO | 0 | 0 | 124 | 0 | 4 | 0 | 0 | 128 |
| POSIBLE_HISTORIA_REAL | 1 | 1 | 0 | 5 | 0 | 2 | 3 | 12 |

- En **46** filas, la "otra matrícula" donde la persona es titular activa **es la misma** matrícula a la que el mecanismo vincula el huérfano: no es otra titularidad, es la misma. En **123** es otro inmueble. Esas coincidencias solas no prueban nada: una persona puede tener varios inmuebles.
- **FUERTE_EVIDENCIA_DE_DUPLICADO**: el mecanismo está documentado (R18 o NU_MATRICULA) y la misma `CD_PERSONA` es titular activa en la matrícula real vinculada.
- **POSIBLE_DUPLICADO**: el mecanismo está documentado, pero la titularidad real es histórica (B4) o la coincidencia es por documento con nombre compatible. También la copia de otra fila huérfana.
- **POSIBLE_HISTORIA_REAL**: la persona no está en la matrícula vinculada, o la fila es de la migración, o es una matrícula sin cabecera y sin gemela. Borrarla puede destruir el único rastro de la titularidad.
- **INDETERMINADO**: no hay nada que vincule la fila, salvo que la persona tiene otras titularidades sin relación.

### 5.5 ORIGINAL_UNICO (pedido §6): qué representan las 104

| Patrón | Filas | Recomendación dominante |
|---|---|---|
| MATRICULACION_CON_NUMERO_DE_PROCEDENCIA | 86 | CANDIDATO_ELIMINACION |
| MATRICULACION_CON_NUMERO_DE_PROCEDENCIA_SIN_TITULAR_EN_REAL | 7 | CONSERVAR |
| NU_MATRICULA_COMPLETO_SIN_TITULAR | 4 | REVISAR |
| HEREDADO_DE_MIGRACION | 3 | CONSERVAR |
| MATRICULA_MIGRADA_RE_MATRICULADA_SIN_TITULAR_EN_REAL | 2 | CONSERVAR |
| MATRICULA_MIGRADA_SIN_R00 | 2 | CONSERVAR |

- Solo **16** de las 104 no tienen **ninguna** fila en B4 ni en B5, ni por persona ni por documento. Las demás tienen historia, casi siempre en la matrícula a la que el número lleva.
- Por año de alta: 1997=1, 2008=2, 2017=1, 2018=11, 2019=12, 2020=16, 2021=15, 2022=9, 2023=13, 2024=18, 2025=5, 2026=1.
- Por usuario (top 5): FALEGRE=15, CMIRANDA=11, VCACERES=10, VPAREJAS=7, OESPEJO=7.
- Filas presentes en el snapshot de la migración (`DIG_DOC_R00_B2_20170902`): 3.
- **Ninguna se recomienda borrar por ser "única".** Las que quedan como `CANDIDATO_ELIMINACION` lo son por el mecanismo de la sección 4.1 con la misma persona en la matrícula real, o por ser copias.

## 6. Patrones temporales

| Año de alta \ mecanismo | CABECERA_R00 | HEREDADO_DE | MATRICULACION_CON | MATRICULA_MIGRADA | NU_MATRICULA | Total |
|---|---|---|---|---|---|---|
| (sin DT_ALTA) | 48 | 4 | 0 | 0 | 0 | 52 |
| 1997 | 0 | 1 | 0 | 0 | 0 | 1 |
| 2008 | 0 | 2 | 0 | 0 | 0 | 2 |
| 2017 | 0 | 0 | 5 | 0 | 0 | 5 |
| 2018 | 0 | 0 | 74 | 0 | 3 | 77 |
| 2019 | 0 | 0 | 34 | 2 | 0 | 36 |
| 2020 | 0 | 0 | 68 | 1 | 0 | 69 |
| 2021 | 0 | 1 | 58 | 3 | 1 | 63 |
| 2022 | 0 | 0 | 35 | 7 | 0 | 42 |
| 2023 | 0 | 0 | 26 | 3 | 0 | 29 |
| 2024 | 1 | 0 | 55 | 0 | 0 | 56 |
| 2025 | 0 | 0 | 36 | 0 | 0 | 36 |
| 2026 | 0 | 0 | 9 | 0 | 0 | 9 |

Días con más filas por mecanismo (¿carga en bloque?):

| Día | Filas | IDs | Usuarios | Mecanismo dominante |
|---|---|---|---|---|
| 2018-08-23 | 14 | 8 | GCMIRANDA,OVILLALON | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA |
| 2018-12-26 | 10 | 3 | VPAREJAS,CMIRANDA | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA |
| 2018-12-21 | 9 | 2 | ACHIARELLO,CMIRANDA | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA |
| 2022-12-15 | 9 | 2 | VPAREJAS,LUGONZALEZ,AEGUAJARDO | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA |
| 2020-12-17 | 8 | 1 | CALBANI | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA |
| 2018-08-24 | 7 | 4 | AFUENTES,LUGONZALEZ,MEESPINOLA | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA |
| 2020-01-20 | 6 | 1 | ESOTELO | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA |
| 2024-11-25 | 6 | 1 | AEGUAJARDO,FALEGRE | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA_SIN_TITULAR_EN_REAL |
| 2018-11-27 | 6 | 1 | ESOTELO | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA |
| 2019-03-19 | 6 | 1 | VCACERES | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA |

No hay un día de carga masiva: el día más cargado tiene 14 filas. El patrón es goteo continuo 2017–2026, compatible con un defecto del flujo normal de trabajo y no con una importación.

## 7. Patrones por usuario

| Usuario B2 | Filas | IDs | Años | Mecanismo dominante | % candidato |
|---|---|---|---|---|---|
| (vacío) | 55 | 37 | 1997,2008 | CABECERA_R00_FALTANTE_CON_GEMELA | 49.1 |
| FALEGRE | 41 | 19 | 2019,2021,2022,2024,2025,2026 | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA | 65.9 |
| ESOTELO | 38 | 8 | 2018,2019,2020,2021,2022 | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA | 73.7 |
| CMIRANDA | 36 | 14 | 2018,2020,2021,2022,2023,2025 | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA | 72.2 |
| GARCE | 36 | 19 | 2019,2020,2021,2022,2023,2024,2025,2026 | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA | 75.0 |
| VCACERES | 27 | 12 | 2019,2020,2021 | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA | 70.4 |
| GJFIORENS | 19 | 8 | 2020,2024,2025 | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA | 63.2 |
| VPAREJAS | 15 | 5 | 2018,2020,2022,2023 | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA | 80.0 |
| AEGUAJARDO | 15 | 8 | 2022,2023,2024,2025 | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA | 53.3 |
| CALBANI | 15 | 3 | 2020,2022 | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA | 60.0 |
| DELOPEZ | 12 | 4 | 2021,2022,2025 | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA | 83.3 |
| TEALVAREZ | 12 | 3 | 2018,2019 | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA | 100.0 |
| GCMIRANDA | 12 | 8 | 2018 | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA | 66.7 |
| OESPEJO | 12 | 5 | 2024,2025 | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA | 91.7 |
| MDINASSO | 11 | 2 | 2024,2025 | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA | 27.3 |

45 usuarios distintos. Ninguno concentra el problema: el mismo mecanismo (4.1) aparece con 40 usuarios. Los usuarios hacen el trámite de matriculación; el ID lo pone el sistema. **Esto es correlación, no culpa de un operador.**

## 8. Patrones de migración y significado de las bandas de ID

Densidad de `DIG_DOC_R00` por banda (bloque 2 de la query 03):

| Banda | Filas R00 | Min ID | Max ID | DT_STORE min–max | Creadas por migración | Sin NU_MATRICULA |
|---|---|---|---|---|---|---|
| A - 2 a 253.249 (rango de IDs creado por la migración) | 50331 | 2 | 253249 | 2017-04-18 – 2017-04-18 | 50331 | 35090 |
| C - 1.400.001 a 1.736.177 (rango de IDs creado por la migración) | 261829 | 1400001 | 1736177 | 2017-04-18 – 2017-04-18 | 261829 | 63535 |
| E - 5.000.000 a 6.396.110 (rango vivo del WORKFLOW) | 488669 | 5000000 | 6396110 | 2014-08-11 – 2026-09-09 | 397122 | 178587 |

Filas con ID inexistente por banda, en B2 hoy (todas las personas, vivas o no), en B4 y en el snapshot de B2 del 02/09/2017 (bloque 3):

| Tabla | Banda | Filas | IDs | Eliminadas | Alta mín. | Alta máx. |
|---|---|---|---|---|---|---|
| B2 | A | 253 | 92 | 0 | 2017-11-29 | 2026-06-16 |
| B2 | B | 181 | 69 | 0 | 2017-12-06 | 2025-11-07 |
| B2 | C | 9 | 5 | 1 | 1997-07-22 | 2024-06-28 |
| B2 | E | 70 | 44 | 0 | 2008-05-26 | 2023-05-30 |
| B2 | F | 6 | 3 | 0 | 2018-08-24 | 2018-08-24 |
| B2_2017 | A | 195 | 113 | 0 | 2006-10-24 | 2017-02-20 |
| B2_2017 | C | 415 | 216 | 0 | 1996-08-28 | 2016-11-07 |
| B2_2017 | E | 1389 | 864 | 0 | 1999-06-11 | 2016-12-07 |
| B4 | C | 6 | 3 | 0 |  |  |
| B4 | E | 32 | 32 | 0 |  |  |

| Banda | Filas | IDs | Años de alta | Con R18 (4.1) | Con filas hijas R00 | En snapshot 2017 | Mecanismo dominante |
|---|---|---|---|---|---|---|---|
| A - 2 a 253.249 (rango de IDs creado por la migración) | 240 | 85 | 2017,2018,2019,2020,2021,2022,2023,2024,2025,2026 | 239 | 0 | 0 | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA |
| B - 253.250 a 1.400.000 (sin ninguna fila en R00) | 156 | 62 | 2017,2018,2019,2020,2021,2022,2023,2024,2025 | 156 | 0 | 0 | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA |
| C - 1.400.001 a 1.736.177 (rango de IDs creado por la migración) | 7 | 4 | 1997,2008,2019,2024,nulo | 0 | 5 | 4 | HEREDADO_DE_MIGRACION |
| E - 5.000.000 a 6.396.110 (rango vivo del WORKFLOW) | 68 | 43 | 2008,2020,2021,2022,2023,nulo | 2 | 53 | 4 | CABECERA_R00_FALTANTE_CON_GEMELA |
| F - mayor al máximo ID de R00 | 6 | 3 | 2018 | 3 | 0 | 0 | NU_MATRICULA_COMPLETO_SIN_TITULAR |

**Qué significa cada banda** (los rangos son descriptivos. Ninguno se da por incorrecto por su valor):

- **A (≤253.249) y C (1,4M–1,74M)** son los rangos de `ID_MATRICULA` que **creó la migración**: el 100% de sus filas de R00 tiene `DT_STORE = 2017-04-18` y usuario de migración. Pero las huérfanas de la banda A de hoy son todas posteriores (altas desde 11/2017), y el ID no es un "hueco" de ese rango: es un **número de matrícula sin departamento** que cae ahí por casualidad numérica. En la banda C (7 filas) el ID sí es de la migración: 4 filas del snapshot 2017 y 3 del WORKFLOW (2019 y 2024) sobre IDs cuyo R00 no existe.
- **B (253.250–1.400.000)** nunca tuvo ninguna fila en R00 ni en el snapshot de 2017. No es un sistema anterior: son **números de matrícula sin departamento** (los números de matrícula por departamento llegan hasta ~1,4M). Todas las filas son del WORKFLOW, 2017–2025.
- **D** no tiene huérfanas.
- **E (5M–6,4M)** es el rango vivo del WORKFLOW, con dos sub-poblaciones. **E1 (5,0M–5,24M)**: IDs asignados por la migración (vecinos con `DT_STORE` 2017-04-18) cuya cabecera R00 ya no está, con filas de 2008 (snapshot) y altas del WORKFLOW de 2020–2023. **E2 (6,0M–6,39M)**: matrículas generadas en 2023–2026 por el proceso 4025, sin cabecera, con hijas y casi siempre con una gemela.
- **F (>6.396.110)** son `NU_MATRICULA` completos (9 dígitos, formato depto+número) usados como ID: 6 filas, todas del 24/08/2018. Las 3 de GARAVAGLIA siguen el mecanismo 4.1: un R18 con procedencia "MAT 800390493" o "MAT 800433207", **con** departamento, y la persona activa en la matrícula real. Las 3 de GARCIA (ID 400013472) vienen de un R18 (68267, LUGONZALEZ) cuyo **propio** `CD_MATRICULA` es 400013472, un número y no un ID. El error ya estaba en el formulario de matriculación. La matrícula 400013472 existe (ID 1559363), pero con otros titulares: REVISAR.
- El snapshot de migración `DIG_DOC_R00_B2_20170902` ya tenía **1.999 filas con ID inexistente** (bandas A, C y E), pero **casi ninguna sigue viva hoy**: solo 8 de las 477 estaban en el snapshot. El problema actual **no es herencia de la migración**. Es un defecto posterior del WORKFLOW (4.1 y 4.2) más un resto chico de datos de la migración.

## 9. Posibles causas (hipótesis, no causalidad)

| Hipótesis | Filas que explica | Evidencia | Estado |
|---|---|---|---|
| Bug de asignación de matrícula en "Generación de Mat SIRC" (R18): graba los titulares de la procedencia con ID = NU_MATRICULA_PRO (el número de procedencia, casi siempre sin departamento) | 400 (+0 sin R18) | R18 con NU_MATRICULA_PRO = ID y CD_MATRICULA = matrícula real; persona titular ahí; mismo caso | PROBABLE (patrón confirmado en datos, falta el código) |
| Trámite que genera la matrícula dos veces (proceso 4025) y deja la primera sin cabecera R00 | 49 | Filas hijas vivas, gemela por nomenclatura con ID mayor, mismo caso, sin DT_ALTA | PROBABLE |
| Re-grabado / doble submit de la misma titularidad | 141 filas de más | Mismo usuario, minutos de distancia, datos iguales | CONFIRMADO en datos (tipo A/B) |
| Error de carga manual en el formulario R18: NU_MATRICULA en el campo del ID | 4 | R18 68267 con CD_MATRICULA = 400013472 (un número, no un ID); titulares distintos en la matrícula 400013472 | PROBABLE, con pocos casos |
| Matrícula de la migración borrada de R00 después de que el WORKFLOW le grabara titulares | 16 | ID en V_PROCEDENCIA_DOMNIO_MIG y en el snapshot 2017, sin R00 hoy; a veces existe otra matrícula con el mismo tomo/foja/inscripción. De los 716.639 IDs de esa tabla, 2.393 ya no están en R00 | PROBABLE (falta el log de bajas) |
| Datos de la migración cuyo R00 no llegó o se borró | 8 | Snapshot 2017, DT_ALTA anterior a 2017 | CONFIRMADO en datos (pocas filas) |
| Importación masiva | 0 | No hay día de carga masiva ni usuario técnico dominante | DESCARTADA con estos datos |
| Desfasaje del ambiente de desarrollo (R00 incompleto en dev) | ? | SIRCWEB.DIG_DOC_R00 (otra copia, analizada 10/09) tampoco tiene ninguno de los 197 IDs | POCO PROBABLE, pero sin verificar en producción |

## 10. Casos que NO deben eliminarse

**42 filas con recomendación CONSERVAR**, que por ahora no se tocan:

| Patrón | Filas | Por qué no |
|---|---|---|
| CABECERA_R00_FALTANTE_SIN_GEMELA | 13 | Parece una matrícula real sin cabecera: lo que falta es R00 |
| MATRICULACION_CON_NUMERO_DE_PROCEDENCIA_SIN_TITULAR_EN_REAL | 12 | Es el único rastro de la persona en la matrícula real: hay que re-vincularla, no borrarla |
| HEREDADO_DE_MIGRACION | 8 | Historia registral de la migración |
| MATRICULA_MIGRADA_SIN_R00 | 5 | Titularidad sobre una matrícula de la migración que desapareció de R00: hay que recuperar la cabecera o encontrar la re-matriculación |
| MATRICULA_MIGRADA_RE_MATRICULADA_SIN_TITULAR_EN_REAL | 4 | Hay otra matrícula con el mismo tomo/foja, pero sin esta persona: puede ser el único rastro |

Además, **ninguna fila con recomendación REVISAR o INDETERMINADO** debería entrar en una limpieza sin revisión caso por caso.

## 11. Candidatos que merecen revisión prioritaria

Orden sugerido para la revisión humana:

1. **CANDIDATO_ELIMINACION / ALTO (92 filas)**: son las que menos riesgo tienen y validan el protocolo.
2. **CANDIDATO_ELIMINACION / MEDIO (223)**: casi todas son titularidades que en la matrícula real ya son históricas. Hay que confirmar que la historia de B4 es la correcta.
3. **REVISAR (120)**: coincidencias por documento, la banda F, los grupos de copias tipo C y D.

### 11.1 Contraste con el DML propuesto el 24/09

`scripts/out/dml_borrado_titulares_huerfanos_propuesto_2026-09-24.sql` deja **140 DELETE activos** (categoría COPIA_REGRABADO). Con la validación de hoy, **36 de ellos ya no son candidatos** y pasan a REVISAR. Son copias de grupos tipo C o D, donde las filas difieren en fecha desde, porcentaje o asiento, y pueden ser actos distintos. **Ese DML no debe usarse tal como está.** Las filas: 184-7, 184-6, 184-5, 35660-1, 35660-2, 59224-3, 73018-1, 73018-2, 73018-3, 73018-4, 73018-5, 73018-6, 74600-2, 79771-2, 79771-3, 106041-1, 106041-2, 144124-2, 216069-1, 216069-3, 244133-6, 244133-8, 244133-3, 244133-5, 244133-7, 244133-9, 254990-2, 254990-3, 254990-4, 254990-5, 254990-8, 363631-3, 363631-4, 363631-5, 394733-6, 5134600-2.

## 12. Preguntas que requieren conocimiento funcional (equipo SIRCLAN)

1. En "Generación de Mat SIRC" (R18, procesos 1230/4029/4033/4035), ¿qué código graba `DIG_DOC_R00_B2` para los titulares de la procedencia? ¿Puede usar `R18_A1.NU_MATRICULA_PRO` como `ID_MATRICULA`? ¿Sigue pasando hoy? (La última fila de este tipo es de 2025.)
2. En esos trámites, ¿los titulares de la procedencia tienen que quedar activos en la matrícula nueva o pasar a histórico? Esto decide si una fila huérfana cuyo titular está en B4 de la matrícula real sobra, o si le falta una fila activa a la matrícula real.
3. El proceso 4025 ("Generación asiento"), ¿puede crear el formulario R00 dos veces para el mismo caso? ¿Qué borra cuando se anula una generación, y por qué deja las tablas hijas y B2 y solo borra la cabecera?
4. ¿Por qué las filas B2 que graba el 4025 quedan sin `DT_ALTA`, `CD_USER_STORE` ni `RECIENTE`? Eso contradice la regla de CLAUDE.md §3 de que `RECIENTE IS NULL` indica origen migración.
5. ¿Los IDs de la banda E1 (5,0M–5,24M, asignados por la migración) se borraron de R00 a propósito (unificaciones o bajas) después de 2017? ¿Hay un log?
6. ¿Qué es `SIRCWEB` (copia del 10/09 con las mismas tablas)? ¿Sirve como segunda fuente para comparar?
7. ¿Las 6 filas de la banda F (24/08/2018, LUGONZALEZ y MEESPINOLA) vienen de una pantalla que pedía el número de matrícula en vez del ID?

## 13. Casos concretos para revisar con el equipo funcional

| Registro | Persona | Verificada | Recomendación | Por qué este caso |
|---|---|---|---|---|
| 184-3 | JURY, MARIELA ANABEL | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA + GRUPO_C | REVISAR / MEDIO | Caso tipo del mecanismo 4.1 (R18 86194). Además, la copia difiere en el asiento (3 contra 1): ¿son dos actos? |
| 2083-0 | BENITO, RICARDO | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA | CANDIDATO_ELIMINACION / MEDIO | Siete grabaciones de la misma titularidad en 4 días, con DT_DESDE vacío en algunas |
| 800390493-0 | GARAVAGLIA, DANIEL EDGARDO | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA | CANDIDATO_ELIMINACION / ALTO | Procedencia cargada CON departamento: la misma persona activa en la real (ALTO) |
| 53877-1 | NAVARRO, DANIEL | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA | CANDIDATO_ELIMINACION / MEDIO | Procedencia que coincide además con un NU_MATRICULA de legado (dos candidatas posibles) |
| 400013472-0 | GARCIA, MARIA INES | NU_MATRICULA_COMPLETO_SIN_TITULAR | REVISAR / BAJO | R18 con CD_MATRICULA = número (no ID): los titulares no están en la matrícula 400013472 |
| 63111-0 | FUNES, FERNANDO | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA_SIN_TITULAR_EN_REAL | CONSERVAR / MEDIO | Mecanismo 4.1, pero la persona NO está en la matrícula real: ¿titularidad perdida? |
| 6372231-0 | PALACIO, MANUEL OSCAR | CABECERA_R00_FALTANTE_CON_GEMELA | CANDIDATO_ELIMINACION / ALTO | Proceso 4025 que generó 8 matrículas dos veces (6372231–44 contra 6372245–53) |
| 6372237-0 | GARCIA, HÉCTOR MARTÍN | CABECERA_R00_FALTANTE_GEMELA_SIN_TITULAR | REVISAR / BAJO | Mismo caso, gemela por nomenclatura, pero con otro titular: ¿qué parcela es? |
| 6368677-0 | GOMERO ALFARO, EMELINA VICTORIA | CABECERA_R00_FALTANTE_SIN_GEMELA | CONSERVAR / MEDIO | Cabecera ausente con 4 asientos R14 que apuntan al ID huérfano: hay actos registrales sobre una matrícula sin cabecera |
| 1439223-1 | LEMOLI, JUAN CARLOS | CABECERA_R00_FALTANTE_SIN_GEMELA | CONSERVAR / MEDIO | Alta WORKFLOW de 2024 sobre un ID de la migración que no tiene R00 |
| 5198683-0 | CORDOBA DE BOERO, RAMONA OLGA | MATRICULA_MIGRADA_RE_MATRICULADA | REVISAR / MEDIO | Matrícula de la migración re-matriculada con el mismo tomo/foja (6351345). Hay 4 filas en 67 segundos |
| 5134600-1 | PORRO, ABELARDO ARTURO | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA + GRUPO_C | REVISAR / ALTO | ID E1 (con una fila de 2008 en el snapshot) y dos filas de 2020 2/3 y 1/3 de usuarios distintos |
| 216069-0 | DELABALLE, CELINA MARIANA | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA + GRUPO_C | REVISAR / MEDIO | DELABALLE CELINA y CARINA: dos personas R62 (¿la misma?) con dos actos 2005/2007 cada una |
| 363631-0 | BLAZQUEZ, MATIAS DANIEL | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA + GRUPO_C | REVISAR / MEDIO | BLAZQUEZ: 20% (2011) y 13,33% (2013) para las mismas tres personas BLAZQUEZ: parecen actos distintos, no copias |
| 100311-7 | VELE, SANTOS DAVID | MATRICULACION_CON_NUMERO_DE_PROCEDENCIA + COPIA_B | CANDIDATO_ELIMINACION / ALTO | DT_DESDE con año truncado (0006-04-05) cargado por otro usuario 2 días después |
| 1400669-0 | ZOGBI, ROBERTO | HEREDADO_DE_MIGRACION | CONSERVAR / MEDIO | Fila de 2008 de la migración, matrícula sin R00 y sin titular en la gemela por tomo |
| 5050106-0 | ALONSO AVILA, FERNANDO | MATRICULA_MIGRADA_RE_MATRICULADA_SIN_TITULAR_EN_REAL | CONSERVAR / MEDIO | Matrícula migrada, gemela por tomo con otros titulares: posible titularidad perdida |

## Anexo — reglas de clasificación (en orden de aplicación)

1. **Matrícula real candidata** (query 04). Se evalúan, en este orden de fuerza: **SR/R**, un R18 de matriculación con `NU_MATRICULA_PRO` = ID, por número o por el caso de la fila, cuya `CD_MATRICULA` existe; **K**, el ID es el NU_MATRICULA completo de una matrícula real; **T**, el ID es una matrícula de la migración y otra matrícula tiene el mismo tomo/foja/inscripción/departamento; **S**, el ID es `MOD(NU_MATRICULA, 10^8)` de una matrícula real, sin formulario que lo respalde. Se elige la candidata donde el titular coincide con más fuerza: la misma CD_PERSONA activa, después el mismo documento con nombre compatible activo, después la misma CD_PERSONA en B4, después el mismo documento en B4.
2. **Con coincidencia de titular** → familia según la candidata (`MATRICULACION_CON_NUMERO_DE_PROCEDENCIA`, `CLAVE_NU_MATRICULA_COMPLETO`, `MATRICULA_MIGRADA_RE_MATRICULADA`). Si el mecanismo está documentado (SR/R/K): la misma CD_PERSONA activa → CANDIDATO ALTO; el documento activo o la misma CD_PERSONA en B4 → CANDIDATO MEDIO; el documento solo en B4 → REVISAR MEDIO. En T y S, nunca más que REVISAR, salvo T con la misma CD_PERSONA activa → CANDIDATO MEDIO. **Sin coincidencia de titular**, pero con mecanismo documentado o T → `*_SIN_TITULAR_EN_REAL` → CONSERVAR (re-vincular), salvo K → REVISAR BAJO. Este paso se aplica después de los puntos 3 a 5.
3. **CABECERA_R00_FALTANTE_***: la fila tiene hijas en R00_A1/A2/B1/B3/B8. Con una gemela (nomenclatura o padrón) o una matrícula del mismo caso donde la misma persona o documento es titular → CANDIDATO (ALTO si además comparten caso). Con una gemela sin el titular → REVISAR. Sin gemela → CONSERVAR.
4. **MISMO_CASO_EN_MATRICULA_REAL**: el mismo caso grabó la misma persona en una matrícula real → CANDIDATO MEDIO.
5. **HEREDADO_DE_MIGRACION**: la fila está en el snapshot 2017, o tiene alta anterior al 19/08/2017, o tiene `MIG_FHPI_ID` → CONSERVAR.
6. **ID_SIN_R00_TITULAR_EN_MATRICULA_VECINA**: la persona es titular de una matrícula con ID a ±5 → REVISAR BAJO.
7. **SIN_EXPLICACION** → INDETERMINADO.
8. **Copias**: dentro de cada grupo (ID, CD_PERSONA) se conserva como representante la fila con más datos. Las demás, si su regla no daba ya CANDIDATO, quedan así: tipo A → CANDIDATO ALTO; B → CANDIDATO MEDIO; C/D → REVISAR.
9. "Nombre compatible": al menos el 60% de los tokens del nombre más corto aparece en el otro, tolerando 1 error de tipeo en tokens de 4 letras o más. **Mismo documento nunca se toma por sí solo como misma persona.**
