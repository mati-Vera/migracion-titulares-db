# Etapa 2 — Plan de trabajo: titularidades PF colgadas de matrículas inexistentes

> Fecha: 22/09/2026 · Autor: sesión de trabajo con asistente · Estado: **propuesta, nada ejecutado**
> Alcance de este documento: cómo llevar adelante la evaluación y la planificación del
> borrado. **No contiene ningún DML para correr** (CLAUDE.md §0: acceso de solo lectura).

---

## 1. Encuadre

La Etapa 2 es "planeación del borrado de titulares". El primer lote elegido son las filas
de titularidad que apuntan a un `ID_MATRICULA` que no existe en `DIG_DOC_R00`, acotado a
**personas físicas**.

Conviene ser explícito sobre para qué sirve este lote, porque es chico:

- **No es un lote por volumen.** Son 477 filas PF sobre 980.931 de `DIG_DOC_R00_B2`
  (0,05%). Borrarlas no mueve ninguna cifra del proyecto.
- **Es el lote por el que conviene empezar** porque permite construir y validar el
  **protocolo de borrado** (criterio → evidencia → clasificación → DML → reverso →
  aprobación) sobre un universo revisable caso por caso a mano. Ese protocolo es lo que
  después se reusa con los borrados grandes (fusión de duplicados, 67.200 reasignaciones
  de FK).
- El entregable de valor de esta etapa es, en este orden: **(a)** la causa de las
  huérfanas, **(b)** la clasificación fila por fila con su justificación, **(c)** el
  protocolo, y recién **(d)** el DML.

---

## 2. Punto de partida verificado

De `titularidad_matricula_inexistente.sql` (corrida 18/09) y
`titulares_activos_matricula_inexistente.sql` (corrida 21/09, export
`scripts/out/titulares_activos_sin_matricula_2026-09-21_bloque1.csv`):

| Métrica | Valor |
|---|---|
| Filas huérfanas en B2 (activos) | 519 |
| Filas huérfanas en B4 (históricos) | 38 |
| Filas huérfanas en B5 | 0 |
| **De las 519 de B2: personas físicas** | **477** |
| De las 519 de B2: personas jurídicas | 42 |
| De las 519 de B2: `CD_PERSONA` sin registro en `DIG_DOC_R62` | 1 |
| De las 519 de B2: con `ELIMINADO = 1` | 1 |
| `ID_MATRICULA` NULO | 0 — las 557 apuntan a un número concreto que no está en R00 |

Reparto de `RECIENTE` dentro de las 519 de B2 (recontado sobre el CSV del 21/09):
**NULL = 57 · 0 = 150 · 1 = 311.**

> ⚠️ **Esto no cierra con "la mitad viene de la migración".** Con el criterio de CLAUDE.md
> §3 ("Verificación ELIMINADO/RECIENTE"), `RECIENTE IS NULL` es el marcador de origen
> migración, y son 57 de 519 (11%), no la mitad. Antes de seguir hay que fijar **con qué
> señal se midió ese "la mitad"**: `B2.CD_USER_STORE` (`NULL`/`RPI_RV_MIG` vs `WORKFLOW`),
> `B2.DT_ALTA` (corte 2017-08-18), `B2.MIG_FHPI_ID`, o el `CD_USER_STORE` de la persona en
> `DIG_DOC_R62`. Son cuatro señales distintas y pueden dar proporciones distintas. Queda
> como paso H4 de la Fase 1; hasta medirlo, ninguna cifra de origen se publica.

Señales sueltas ya visibles en el CSV, útiles como pistas (no como conclusión):

- Aparecen **familias de filas repetidas**: mismo `ID_MATRICULA` + mismo `ID_FORMULARIO` +
  misma `DT_DESDE`, distinta `ROWID` (ej. `31479`/`1429154` ×5, `254990`/`5025872` ×6).
  Mismo patrón que el bug de doble-submit ya documentado (CLAUDE.md §7).
- Conviven dos "generaciones" de `ID_FORMULARIO` para la misma persona en la misma
  matrícula huérfana: uno viejo (rango ~1.4M, `RECIENTE=0`) y uno nuevo (rango ~5.5M+,
  `RECIENTE=1`), este último muchas veces con el apellido con espacio final o con una
  variante de tipeo (`PAVESI ` / `GONZALEZ ` / `DELABALLE` → `CARINA` vs `CELINA`).
- Hay fechas corruptas concentradas en las filas `RECIENTE=1`: `0095-04-20`, `0084-12-28`,
  `0092-05-11`, `0006-04-05` — año truncado.

Las tres apuntan a lo mismo como hipótesis: **un reproceso/recarga posterior que volvió a
crear personas y titularidades**, no a filas nacidas rotas. Hay que probarlo.

---

## 3. Revisión de la heurística (lo que pediste mirar primero)

La heurística vigente es de un solo término: *"la fila apunta a una matrícula que no existe
⇒ la fila sobra"*. No alcanza, por cuatro motivos concretos:

1. **"No existe" está medido contra la base de DESARROLLO**, que va ~2 semanas atrás de
   producción y se refresca por tandas (CLAUDE.md §3). Si `DIG_DOC_R00` se recargó y las
   tablas de titularidad no, o al revés, la huérfana es un artefacto del ambiente y en
   producción no existe. Borrar por esto sería borrar por un problema de copia.
2. **Ausencia de la matrícula ≠ ausencia del hecho registral.** La fila dice "esta persona
   fue titular de la matrícula N". Si la matrícula se renumeró, se unificó o se dio de baja
   en R00 sin limpiar sus titularidades, la fila es **evidencia recuperable** (se re-vincula
   al `ID_MATRICULA` nuevo), no basura. Borrarla destruye el único rastro de quién era
   titular.
3. **Sin FK declaradas (CLAUDE.md §2), "inexistente" no es un estado estable.** Nada impide
   que una carga futura vuelva a crear ese `ID_MATRICULA`. La condición se evalúa en un
   momento dado y hay que fecharla.
4. **No hay causa confirmada** (CLAUDE.md §7). Un criterio de borrado sin causa es una
   apuesta: si la causa resulta ser "reproceso que duplicó filas", el borrado es correcto y
   además hay que buscar las *no huérfanas* que el mismo reproceso duplicó; si resulta ser
   "R00 depurado sin cascada", lo correcto es re-vincular; si resulta ser "desfasaje de
   ambiente", lo correcto es no tocar nada.

**Heurística propuesta en reemplazo — evidencia convergente.** Una fila pasa a "candidata a
baja" sólo si cumple **todas**:

- **C1.** `ID_MATRICULA` inexistente en `DIG_DOC_R00`, verificado el mismo día del
  entregable (condición fechada, no heredada del 18/09).
- **C2.** No existe candidato de re-vinculación (ver H2/H3 abajo): ninguna matrícula real
  con el mismo elenco de titulares y fechas, ni ninguna que coincida por `NU_MATRICULA`,
  asiento (`CD_COLUM_2`/`NU_ASIEN_2`) o `NU_CASO_ORIGEN`.
- **C3.** La fila no aporta información registral única: o es duplicado exacto de otra fila
  (misma persona, misma matrícula, misma fecha), o no tiene porcentaje ni asiento ni caso
  de origen.
- **C4.** El mismo `ID_MATRICULA` tampoco existe en producción (verificación externa) **o**
  el equipo de SIRCLAN confirma el borrado histórico de esas matrículas.
- **C5.** Hay snapshot completo de la fila (todas las columnas + `ROWID`) guardado fuera de
  la base, y sentencia de reverso generada.

Lo que no cumple C2 va a **re-vincular**, no a borrar. Lo que no cumple C4 queda
**retenido** hasta tener la confirmación — y esa retención es un resultado válido de la
etapa, no un fracaso.

---

## 4. Fases

### Fase 0 — Congelar el universo y sacar el snapshot (bloqueante para todo lo demás)

Sin foto previa no hay reverso posible, y `ROWID` no es estable ante reorganizaciones de
tabla, así que la foto tiene que traer también las claves de negocio.

1. Query nueva `huerfanas_snapshot_b2_b4.sql`: **todas** las columnas de B2 (y de B4) para
   las filas huérfanas, más `ROWID`, más los datos de la persona en `DIG_DOC_R62`. Export a
   `scripts/out/huerfanas_snapshot_<fecha>.csv` con `RunQuery --csv`.
2. Guardar en el mismo export el conteo de control (519 / 38 / 0) y la fecha de corte.
3. Registrar el conteo total de `DIG_DOC_R00_B2` y `_B4` del mismo día (control de que
   entre el snapshot y el borrado no cambió el universo).

### Fase 1 — Forense de causa (antes de clasificar nada)

Seis hipótesis, cada una con su prueba. Todas son `SELECT`, todas corribles con `RunQuery`.

| # | Hipótesis | Prueba | Qué implica si da positivo |
|---|---|---|---|
| **H1** | El valor guardado no es un `ID_MATRICULA` sino un `NU_MATRICULA` (confusión de campo) | Join `B2.ID_MATRICULA = R00.NU_MATRICULA` | No se borra: se corrige la referencia. Cambia por completo el entregable |
| **H2** | La matrícula existió y fue reemplazada/renumerada | Buscar matrículas reales cuyo elenco de titulares (`CD_PERSONA` + `DT_DESDE`) coincida con el de la huérfana; y por `CD_COLUM_2`+`NU_ASIEN_2` y `NU_CASO_ORIGEN` | Re-vinculación, no borrado |
| **H3** | Los `ID_MATRICULA` huérfanos son huecos dentro del rango usado (borrado real) vs. valores fuera de rango (dato inventado/ajeno) | Min/máx y densidad de huecos de `R00.ID_MATRICULA` contra los ~N valores huérfanos distintos | Dentro de rango ⇒ borrado de R00 sin cascada. Fuera de rango ⇒ referencia espuria |
| **H4** | Origen: migración vs. WORKFLOW — **la afirmación "la mitad viene de la migración"** | Cruzar las 4 señales: `B2.CD_USER_STORE`, `B2.DT_ALTA` (corte 2017-08-18), `B2.MIG_FHPI_ID`, `R62.CD_USER_STORE`; tabla cruzada contra `RECIENTE` | Define si es lastre histórico (una sola limpieza) o un bug vivo (además hay que reportarlo) |
| **H5** | Reproceso posterior que re-creó personas y titularidades | Para cada huérfana, buscar otra fila de B2 con el mismo documento y misma `DT_DESDE` pero matrícula **válida**; y perfilar el rango de `ID_FORMULARIO` (~5.5M+) y las fechas con año truncado | La huérfana es la copia sobrante ⇒ borrado limpio, con el resto del reproceso a auditar aparte |
| **H6** | Desfasaje de ambiente (R00 de dev incompleto) | Correr el conteo de huérfanas contra **producción** (o pedirlo al equipo SIRCLAN); comparar `MAX(DT_CREACION)` de R00 contra `MAX(DT_ALTA)` de B2 | No se borra nada: es un artefacto de la copia |

Salida de la fase: un documento corto (`hallazgo_causa_huerfanas_<fecha>.md`) que responda
"por qué existen estas filas", con la evidencia de cada hipótesis — incluidas las
descartadas.

> H6 es la única que puede invalidar la etapa entera, y es barata. Conviene correrla
> primero.

### Fase 2 — Clasificación fila por fila

Sobre las 477 PF (más las de B4 si entran, ver §5), asignar a cada `ROWID` exactamente una
categoría, con la regla que la justifica:

| Categoría | Regla | Acción propuesta |
|---|---|---|
| `RE_VINCULAR` | Falla C2: hay matrícula real candidata | `UPDATE` de `ID_MATRICULA` — entregable aparte, no es borrado |
| `DUPLICADO_EXACTO` | Cumple C1–C3, y es copia de otra fila del mismo grupo | Baja, dejando **una** fila (la de origen, no la del reproceso) |
| `HUERFANA_VACIA` | Cumple C1–C3, sin porcentaje, sin asiento, sin caso de origen | Baja |
| `RETENER` | Falla C4 (sin confirmación de producción / SIRCLAN) | Nada, se reporta |
| `YA_DE_BAJA` | `ELIMINADO = 1` (hoy: 1 fila) | Nada |
| `FUERA_DE_ALCANCE` | PJ (42) o `CD_PERSONA` sin persona en R62 (1) | Se listan aparte |

Cada fila clasificada lleva: `ROWID`, claves de negocio, categoría, regla aplicada,
evidencia (qué query lo sostiene) y, si corresponde, el `ID_MATRICULA` destino de la
re-vinculación. Sale como `clasificacion_huerfanas_pf_<fecha>.csv`.

Las 477 son revisables a ojo: conviene **auditar a mano una muestra de 30** contra la
clasificación automática antes de dar la regla por buena, igual que se hizo con
`EvaluadorLote`.

### Fase 3 — Radio de impacto, por fila candidata a baja

Antes de escribir una sola sentencia, por cada `ROWID` a dar de baja:

1. **¿La persona queda sin ninguna titularidad?** Contar sus filas en B2/B4/B5 con matrícula
   válida. Si queda en cero, el registro de `DIG_DOC_R62` pasa a ser huérfano él también —
   se marca, **no se borra** (el catálogo es compartido por todo el BPM, CLAUDE.md §4/§5).
2. **¿Esa persona está en algún grupo de duplicados del universo de trabajo** (los 55.918)?
   Si sí, el borrado cambia el conteo de "personas vinculadas" de ese grupo y hay que
   rehacer su fila en `detalle_grupos_priorizado`. Cruce obligatorio.
3. **¿Alguna otra tabla del BPM referencia esta fila o esta persona?** Sin FK declaradas, la
   única vía es buscar columnas candidatas en el diccionario (`USER_TAB_COLUMNS` por nombre
   `%PERSONA%`, `%MATRICULA%`) y verificar. Es el chequeo que más fácil se saltea y el que
   más caro sale.
4. **¿Suma de porcentajes de la matrícula?** No aplica acá (la matrícula no existe), pero se
   deja registrado para el protocolo general.

### Fase 4 — Entregable de borrado

Dos artefactos, ninguno para ejecutar desde este repo:

1. **`scripts/out/dml_baja_huerfanas_pf_<fecha>.sql`** — propuesta a revisar, con:
   - encabezado con el criterio, la fecha de corte y el conteo esperado;
   - un `SELECT` de control previo que **tiene que devolver exactamente N filas** antes de
     habilitar el resto (si devuelve otra cosa, el universo cambió: abortar);
   - las sentencias dirigidas por `ROWID` **y** con el predicado de negocio repetido en el
     `WHERE` (cinturón y tiradores: si el `ROWID` se movió, el predicado protege);
   - sin `COMMIT` — el `COMMIT` lo pone quien ejecuta, después de verificar `SQL%ROWCOUNT`;
   - `SELECT` de control posterior.
2. **`scripts/out/reverso_baja_huerfanas_pf_<fecha>.sql`** — `INSERT` (o `UPDATE` de
   reversa, si se opta por baja lógica) generado desde el snapshot de la Fase 0, fila por
   fila. Sin esto, el borrado es irreversible y no se propone.

Más un `README_baja_huerfanas_<fecha>.md` para Mónica: qué se propone dar de baja, con qué
criterio, qué **no** se toca y por qué, y qué queda pendiente de confirmación externa.

### Fase 5 — Aprobación y ejecución

1. Revisión técnica del DML por el usuario.
2. Confirmación de C4 (producción / equipo SIRCLAN) — es la que hoy no está.
3. Aprobación de Mónica sobre el criterio, no sobre el SQL.
4. Ejecución en **desarrollo** primero, con los conteos de control, y recién después el
   pedido para producción por la vía que corresponda (no hay permiso de escritura hoy:
   CLAUDE.md §10, "Gestionar permiso de escritura").

---

## 5. Decisiones abiertas (las necesito de tu lado)

1. **¿Borrado físico (`DELETE`) o baja lógica (`ELIMINADO = 1`)?**
   **Recomiendo baja lógica** donde exista la columna: B2 y B5 ya tienen esa semántica y
   está confirmada como baja real (CLAUDE.md §3), el sistema ya sabe ignorar esas filas, es
   reversible con un `UPDATE`, y no destruye evidencia registral mientras la causa siga sin
   confirmarse. El costo es que las filas siguen ahí y hay que acordarse de filtrarlas —
   cosa que las queries del proyecto ya hacen. `DIG_DOC_R00_B4` **no tiene `ELIMINADO`**:
   ahí la baja lógica no está disponible, así que o se deja fuera del lote, o se propone
   tabla de cuarentena (copiar y borrar), o se acepta `DELETE` sólo para B4.
2. **¿El lote incluye B4 (históricos) o sólo B2 (activos)?** Hoy el CSV del 21/09 es sólo
   B2. Las 38 de B4 hay que abrirlas por `TP_PERSONA` para saber cuántas son PF.
3. **¿Las 42 filas PJ quedan listadas como "fuera de alcance" en el mismo entregable, o se
   omiten?** Recomiendo listarlas: es información gratis y evita que aparezcan como
   novedad más adelante.
4. **¿Con qué señal se midió "la mitad viene de la migración"?** (§2). Si fue una query que
   corriste el 21/09, pasámela y la incorporo como H4 en vez de rehacerla.

---

## 6. Criterio de "terminado" para esta etapa

- [ ] Snapshot con reverso generado y guardado (Fase 0).
- [ ] Documento de causa con las 6 hipótesis resueltas, incluidas las descartadas (Fase 1).
- [ ] Las 477 filas PF clasificadas, 100% con regla y evidencia; muestra de 30 auditada a
      mano (Fase 2).
- [ ] Radio de impacto medido para cada candidata a baja, con el cruce contra los 55.918
      grupos (Fase 3).
- [ ] DML + reverso + README para Mónica (Fase 4).
- [ ] Decisión registrada de `DELETE` vs. baja lógica, y de qué pasa con B4 (§5).
- [ ] CLAUDE.md actualizado: cifras nuevas con fuente y fecha de corte, y el protocolo de
      borrado como decisión de diseño (§5 del CLAUDE.md).

---

## 7. Riesgos

| Riesgo | Mitigación |
|---|---|
| Borrar filas que en producción sí tienen matrícula (H6) | H6 se corre primero; C4 bloquea el borrado sin confirmación externa |
| Borrar evidencia registral re-vinculable (H2) | C2 + categoría `RE_VINCULAR` separada del borrado |
| `ROWID` inestable entre el snapshot y la ejecución | Predicado de negocio repetido en el `WHERE` + `SELECT` de control previo con conteo exacto |
| Dejar personas de `DIG_DOC_R62` sin ninguna titularidad y romper conteos ya publicados | Fase 3, cruce obligatorio contra el universo de trabajo de 55.918 grupos |
| Que el protocolo se arme a medida de este lote y no escale a la fusión de duplicados | El protocolo se escribe genérico (criterio → evidencia → clasificación → DML → reverso → aprobación); este lote es el primer caso de uso, no el único destinatario |
