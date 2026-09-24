# Queries SQL (Oracle / SIRCLAN)

Consultas contra la base de desarrollo. **Solo lectura** — nada de DML acá.

## Universo vinculado a matrículas (criterio vigente desde el 16/09/2026)

Tras la reunión con Mónica, el universo de trabajo dejó de ser "todos los grupos de
documento duplicado" y pasó a ser **solo los grupos con registros vinculados a una
matrícula** (B2/B4/B5). Cifras del corte en `CLAUDE.md` §3; exports crudos en
`resultados-vinculadas/`.

| Archivo | Qué hace | Estado |
|---|---|---|
| `vinculadas_kpi_pf.sql` | KPI PF partido en 3 categorías: varios vinculados / un solo vinculado / sin vínculo | Corrida 16/09 — **60.847 / 45.178 / 15.827** |
| `vinculadas_distribucion_estratos_pf.sql` | Distribución por estrato de tamaño **cruzada** con la vinculación | Corrida 16/09 |
| `vinculadas_matriculas_afectadas.sql` | Filas de titularidad, personas y matrículas distintas tocadas, por tabla | Corrida 16/09 — 165.120 matrículas con titular activo duplicado |
| `vinculadas_listado_grupos_pf.sql` | **Lista de trabajo**: una fila por grupo con 2+ vinculados, priorizada P1/P2/P3 | Corrida 16/09 — 34.055 P1 / 19.028 P2 / 7.764 P3 |
| `vinculadas_muestra_estratificada.sql` | Muestra aleatoria estratificada por prioridad. Salida en el formato que consume `EvaluadorLote.java` | Corrida 16/09 — 140 documentos |
| `vinculadas_kpi_pj.sql` | Lo mismo para PJ, sobre la base de `pj_kpi_sin_placeholder.sql` | **Sin correr** |
| `vinculadas_doble_titular_misma_matricula.sql` | De los grupos P1, cuántos tienen dos titulares activos en la **misma** matrícula. Incluye el chequeo de `ELIMINADO`/`RECIENTE` | Corrida 16/09, recorrida 17/09 con el filtro — **2.868 matrículas** |
| `vinculadas_doble_titular_misma_matricula_detalle.sql` | El detalle fila por fila de la anterior (una fila por matrícula + documento) | Corrida 18/09 — 3.362 filas → `scripts/out/doble_titular_misma_matricula_2026-09-18.csv` |
| `vinculadas_matricula_real_listado_grupos_pf.sql` | **Lista de trabajo definitiva**: rehace `vinculadas_listado_grupos_pf.sql` con matrícula real + `ELIMINADO` | Corrida 18/09 — **55.918** grupos, 30.136 P1 / 17.449 P2 / 8.333 P3 |
| `casos_representativos_pf.sql` | Los 67 casos del entregable (59 de muestra + 8 emblemáticos), registro por registro + sus matrículas | Corrida 18/09 → `scripts/out/casos_representativos_*_2026-09-18.csv` |

✅ El chequeo de `ELIMINADO` / `RECIENTE` se hizo el 17/09/2026: `ELIMINADO=1` es baja
lógica real y se filtra con `NVL(ELIMINADO,0)=0` en B2 y B5 (B4 no tiene la columna);
`RECIENTE` **no** es un flag de baja y no se filtra. Detalle en `CLAUDE.md` §3. Las
queries de impacto registral ya lo aplican; **la única que todavía no es
`censo_matriculas_r00.sql`** (pendiente, `CLAUDE.md` §10).

⚠️ Las filas cuyo nombre NO lleva `matricula_real` son del corte del 16/09, **anterior** al filtro
de matrícula real. Para cifras de alcance usar las `vinculadas_matricula_real_*`.

## Universo completo (queries previas al cambio de criterio)

Siguen siendo válidas: son la línea de base contra la cual se mide cuánto recorta el
filtro de matrícula.

| Archivo | Qué hace | Estado |
|---|---|---|
| `consultas.sql` | Las 4 queries del patrón "Opción B" (persona base / B2+inmueble / B4+inmueble / B5+inmueble), parametrizadas por `:p_nu_documento`. Es el detalle de un caso puntual | Corrida |
| `distribucion_estratos_pf.sql` | Distribución de grupos PF por cantidad de duplicados | Corrida 16/09/2026 |
| `pj_kpi_sin_placeholder.sql` | KPI PJ excluyendo el placeholder `30999078040` | Corrida 16/09/2026 |
| `muestra_aleatoria_estratificada.sql` | Muestra aleatoria por estrato de tamaño, solo la lista de documentos | Sin correr |
| `muestra_detalle_persona_base.sql` | Igual que la anterior pero trayendo el detalle de `DIG_DOC_R62` | Sin correr. **Reemplazada** por `vinculadas_muestra_estratificada.sql` para el piloto |
| `recuperables_documento_cero.sql` | PF con `NU_DOCUMENTO = '0'` recuperables por campo alternativo (hoja "Recuperables dni 0", 416 casos) | Corrida |
| `censo_matriculas_r00.sql` | Censo de `DIG_DOC_R00`: matrícula real vs. legado Tomo/Folio, desglose por `CD_ESTADO`, sin titular y % inválido. Refresca el corte de 25/08 documentado en `docs/Metodologia_Queries_SIRCLAN.md` §3.3 | Corrida 17/09/2026 — **523.617** matrículas reales, 40.976 sin titular, 316 % inválido (ver CLAUDE.md §3) |
| `vinculadas_matricula_real_kpi_pf.sql` | Rehace `vinculadas_kpi_pf.sql` exigiendo `NU_MATRICULA IS NOT NULL` y `NVL(ELIMINADO,0)=0` en B2/B5 | Corrida 17/09/2026 — **55.918** grupos, 30.136 P1 (ver CLAUDE.md §3) |
| `vinculadas_matricula_real_muestra.sql` | Lote de revisión manual (60 documentos) + detalle de matrículas, sobre el universo con matrícula real y sin `ELIMINADO` | Corrida 17/09/2026 |
| `titularidad_matricula_inexistente.sql` | Detalle de las filas de B2/B4/B5 cuyo `ID_MATRICULA` no existe en `DIG_DOC_R00` (FK huérfana, sin FK declaradas en el sistema) | Corrida 18/09/2026 — 519 en B2, 38 en B4, 0 en B5 (ver CLAUDE.md §7) |

Los archivos `resultado-*.md` son los resultados exportados de DBeaver, con el nombre que
les pone la herramienta.

## Pendiente de cargar

Las queries que el desarrollador del informe original le pasó al usuario para obtener los
valores del `.docx` (ver `CLAUDE.md` §3, nota de procedencia).

## Convenciones

- Alias con sufijo por tabla: `_PERS`, `_ACT`, `_INM`, `_HIST`, `_B5` — para que al
  exportar a Excel no se confundan columnas homónimas de distintas tablas.
- Nunca unir dos tablas "muchos" en el mismo SELECT (multiplica filas). Para cruzar
  personas contra B2/B4/B5 en una sola query, preagregar cada tabla por su FK de persona
  (`GROUP BY`) y recién ahí hacer `LEFT JOIN` — es lo que hacen las queries `vinculadas_*`.
- `FETCH FIRST` no funciona en NINGÚN contexto en esta base (ni siquiera en un `SELECT`
  de primer nivel con `GROUP BY` + `ORDER BY`: da ORA-00933) → envolver en subconsulta y usar
  `ROWNUM` o `ROW_NUMBER()`.
- `NU_DOCUMENTO` es `VARCHAR2`: comparar contra `'0'`, nunca contra `0` (ORA-01722).
- `LISTAGG` revienta a los 4000 bytes con grupos grandes (ORA-01489) → acotar con
  `ROW_NUMBER()`.
- Exclusión de placeholders idéntica en todas las queries de PF:
  `NOT REGEXP_LIKE(NU_DOCUMENTO,'^0+$') AND NU_DOCUMENTO NOT IN ('99907804','1')`.
  Si una query se desvía de ese `WHERE`, sus totales dejan de ser comparables.
