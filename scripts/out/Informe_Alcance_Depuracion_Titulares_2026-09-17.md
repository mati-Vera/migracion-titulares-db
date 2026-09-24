# Depuración de titulares duplicados — Informe de alcance (actualizado)

**Fecha:** 17 de septiembre de 2026
**Reemplaza a:** `Informe_Alcance_Depuracion_Titulares_2026-09-16.md` (mismo análisis, con dos
correcciones aplicadas al día siguiente — ver sección 2)
**Base analizada:** SIRCLAN (Oracle), entorno de **desarrollo**
**Alcance del informe:** personas físicas. Personas jurídicas, dimensionadas aparte al final.

---

## 1. Resumen ejecutivo

| Indicador | Valor |
|---|---|
| Grupos de personas físicas duplicadas (total) | **121.852** |
| Grupos que **tocan una matrícula real** y requieren revisión | **55.918** (45,9%) |
| Grupos donde la fusión es automática, sin revisión | 45.632 (37,5%) |
| Grupos fuera de alcance (no tocan ninguna matrícula real) | 20.302 (16,7%) |
| Matrículas con al menos un titular activo duplicado | **164.418** |
| **Matrículas con la misma persona cargada dos veces como titular** | **2.868** |

**Tres conclusiones:**

1. **El filtro por matrícula real sigue reduciendo el trabajo a menos de la mitad.** De
   121.852 grupos a revisar pasamos a 55.918. Las validaciones contra la API de RENAPER
   bajan de ~122.000 a ~55.900.

2. **El problema está concentrado y es abordable.** Dentro de los 55.918 grupos, 30.136
   (54%) tienen **dos o más registros como titular activo** de la misma persona. De esos,
   el 91% son grupos chicos, de 2 o 3 duplicados: casos simples de resolver.

3. **Hay 2.868 matrículas con un error registral concreto y verificable**, donde la misma
   persona figura dos o más veces como titular vigente **del mismo inmueble**. En una de
   ellas llega a estar repetida 9 veces. Sigue siendo el hallazgo más accionable del
   análisis (ver ejemplos reales en el Anexo I).

---

## 2. Qué cambió respecto del informe del 16/09

El informe anterior (60.847 grupos / 165.120 matrículas / 3.006 matrículas con doble
titular) tenía **una salvedad abierta**: dos campos de control de la base
(`ELIMINADO`, `RECIENTE`) sin verificar, con la advertencia de que si `ELIMINADO` marcaba
baja lógica, las cifras iban a bajar. Al día siguiente se cerraron **dos correcciones**,
ambas reductoras (nunca aumentan el universo):

**(a) Matrícula real, no legado.** Las queries del 16/09 marcaban una persona como
"vinculada" con solo mirar si aparecía en las tablas de titularidad, sin chequear si el
inmueble tenía número de matrícula real o era legado Tomo/Folio (34,6% de la tabla de
inmuebles). Se corrigió exigiendo matrícula real.

**(b) `ELIMINADO` es baja lógica real — verificado.** Se confirmó con evidencia concreta:
hay matrículas donde **todas** las filas de titular activo tienen `ELIMINADO=1` (quedarían
sin titular si no se excluyeran), y filas `ELIMINADO=1` cargadas tanto por la migración
original como por usuarios corrigiendo errores ya en producción. `RECIENTE` (el otro
campo) se investigó y **no** es un indicador de baja — distingue si el registro viene de
la migración o de carga posterior, nada más.

| Indicador | 16/09 (sin corregir) | **17/09 (corregido)** | Δ |
|---|---|---|---|
| Grupos a revisar (varios vinculados) | 60.847 | **55.918** | −4.929 (−8,1%) |
| — de esos, prioridad 1 (dos+ activos) | 34.055 | **30.136** | −3.919 (−11,5%) |
| Matrículas con titular activo duplicado | 165.120 | **164.418** | −702 (−0,4%) |
| Matrículas con doble titular (misma persona) | 3.006 | **2.868** | −138 (−4,6%) |

Los totales de partida (121.852 grupos, 162.491 registros redundantes) no se movieron: las
correcciones **reclasifican** casos entre categorías, no cambian el universo de origen.

---

## 3. El universo de trabajo: 55.918 grupos

| Prioridad | Qué significa | Grupos | % |
|---|---|---|---|
| **P1** | Dos o más registros de la persona son **titular activo** | **30.136** | 53,9% |
| **P2** | Un titular activo + registros en históricos | 17.449 | 31,2% |
| **P3** | Solo registros en históricos / no vigentes | 8.333 | 14,9% |

**P1 es la prioridad real:** son los casos donde el padrón vigente de titulares tiene hoy
información duplicada.

### Los casos P1 son mayoritariamente simples

| Tamaño del grupo | Grupos P1 | % |
|---|---|---|
| 2 a 3 registros | 27.389 | 90,9% |
| 4 a 6 registros | 2.600 | 8,6% |
| 7 a 10 registros | 137 | 0,45% |
| 11 o más | 10 | 0,03% |

Solo 10 grupos P1 llegan a 11 o más duplicados — se pueden revisar todos a mano en vez de
diseñar una regla general de "techo de tamaño".

> La tabla de "vínculos de titularidad a corregir por grupo" del informe del 16/09 (5 o
> menos / 6 a 20 / 21 a 50 / más de 50 filas) todavía no se recalculó con este filtro
> final — queda pendiente (sección 7) y no se repite acá para no mezclar cortes.

---

## 4. Impacto sobre las matrículas

| Tabla | Vínculos de titularidad | Personas distintas | **Matrículas distintas** |
|---|---|---|---|
| Titulares activos | 226.594 | 124.679 | **164.418** |
| Titulares históricos | 213.771 | 97.397 | 127.803 |
| Titulares no vigentes | 2.627 | 2.107 | 1.852 |
| **Total (sin repetir)** | **442.992** | **178.821** | **255.683** |

**164.418 matrículas tienen al menos un titular activo que pertenece a un grupo de
personas duplicadas.** Contra las 523.617 matrículas reales del censo del 17/09/2026 (mismo
día, mismo corte), da un orden de magnitud de ~31,4% — a diferencia del informe anterior,
esta vez numerador y denominador son del mismo día.

---

## 5. El hallazgo crítico: la misma persona, dos veces titular del mismo inmueble

| Indicador | Valor |
|---|---|
| Casos (matrícula + documento) | **3.362** |
| **Matrículas afectadas** | **2.868** |
| Documentos (personas) involucrados | 2.947 |
| Registros de persona involucrados | 6.842 |
| Vínculos de titularidad involucrados | 7.365 |
| Máximo de registros de una misma persona en una matrícula | **9** |

Son **2.868 inmuebles donde el titular está contado dos o más veces**. No es un problema de
prolijidad del catálogo: es el dato registral del inmueble el que está mal armado, con la
titularidad repartida entre registros que corresponden a una única persona real. Se
relaciona directamente con las matrículas cuya suma de porcentajes de titularidad no da
100% (informe de agosto: 309 casos; censo del 17/09: 316). Ver ejemplos reales en el
**Anexo I**.

---

## 6. Qué queda fuera del alcance automático

| Segmento | Volumen | Situación |
|---|---|---|
| Personas físicas sin documento cargado | 163.986 | Solo 2.516 son recuperables desde otros campos. No entran en la detección por documento |
| Documentos comodín (0, 00, 1, etc.) | 7.111 | Excluidos de todo el análisis: no identifican a nadie |
| Personas jurídicas sin CUIT utilizable | 23.920 (42,4% de 56.399) | Sin CUIT válido no hay deduplicación automática posible |

Para personas jurídicas, sobre las que **sí** tienen CUIT válido se detectaron **5.814
grupos duplicados** con **12.787 registros de más**. El cruce contra matrículas para
jurídicas está pendiente de ejecución y se informará en la próxima entrega.

---

## 7. Salvedades metodológicas

1. **Base de desarrollo.** Todas las mediciones se hicieron sobre el entorno de
   desarrollo, que se actualiza periódicamente y está aproximadamente dos semanas por
   detrás de producción. Los órdenes de magnitud son válidos; las cifras exactas deben
   reconfirmarse antes de cualquier acción sobre producción.

2. ~~Verificación pendiente sobre bajas lógicas~~ — **resuelta el 17/09/2026.** Ver sección
   2. Las cifras de este informe ya tienen el filtro aplicado.

3. **Hallazgo nuevo, sin investigar (no bloquea este informe):** 557 filas de titularidad
   (519 activas + 38 históricas) apuntan a un número de matrícula que no existe en la
   tabla de inmuebles. Como el sistema no tiene claves foráneas declaradas, nada lo
   impide. Volumen chico, pendiente de mirar en la próxima vuelta.

4. **El censo general de matrículas** (523.617 reales, 40.976 sin titular, 316 con
   porcentaje inválido) todavía no tiene aplicado el filtro de baja lógica de la sección
   2 — es la única cifra de esta familia que falta recorrer con la corrección.

5. **Ningún dato fue modificado.** El acceso a la base es de solo lectura. Todo el análisis
   es no destructivo.

6. **Trazabilidad.** Cada cifra proviene de una consulta SQL versionada en el repositorio,
   con sus resultados archivados en `scripts/out/` — cualquier número puede reproducirse.

---

## 8. Próximos pasos propuestos

**Inmediatos**

1. Generar el listado detallado de las **2.868 matrículas** con titular duplicado, para
   revisión del área registral.
2. Completar el cruce contra matrículas para personas jurídicas.
3. Revisar a mano la muestra de 60 casos ya sorteada (Anexo I) y contrastarla contra la
   detección automática.

**Procesamiento a escala**

4. Ejecutar la validación contra RENAPER sobre los grupos priorizados (~30.100 consultas
   para P1; ~55.900 para el universo completo), coordinando previamente el volumen y la
   frecuencia con el área responsable de la API.
5. Entregar el Excel final con hoja Resumen y hoja Detalle: un registro por grupo, con su
   prioridad, los inmuebles afectados y el registro propuesto como válido.

---

## Anexo I — Ejemplos reales de "doble titular en la misma matrícula"

Casos reales extraídos en vivo de la base el 17/09/2026, dentro del universo corregido
(matrícula real, sin bajas lógicas). Tres casos que muestran tres causas distintas del
mismo problema.

### Caso 1 — El extremo del análisis: la persona repetida 9 veces

**Matrícula 800.622.102** (estado ACT — vigente hoy). Documento 24.506.089, **Mauricio
Ariel Cantalejos**, figura como titular activo bajo **9 `ID_FORMULARIO` distintos**
(5696437 a 5696445), los 9 con **exactamente el mismo nombre, el mismo documento y la
misma fecha de alta: 19/08/2025**, y ninguno con porcentaje de titularidad asignado.

Los `ID_FORMULARIO` son **consecutivos** — la señal más fuerte de que no son 9 cargas
independientes, sino la **misma carga repetida 9 veces en un solo evento**. Es el mismo
patrón que el bug de doble-submit ya documentado para MAREU S.A.S. (§7 del contexto del
proyecto: 29 de 32 registros cargados el mismo día, en un rango de 2 horas). Este caso lo
confirma también sobre titulares **activos** de un inmueble real, no solo en el catálogo
general de personas.

### Caso 2 — Una copropiedad grande, con dos colisiones distintas adentro

**Matrícula 300.079.974** (estado ACT), un inmueble con cerca de 60 titulares distintos
(un consorcio o propiedad con muchos copropietarios, cada uno con una fracción chica). Dos
de esos titulares están duplicados:

| Documento | `ID_FORMULARIO` | Apellido cargado | Nombre | % de titularidad | Titular activo desde |
|---|---|---|---|---|---|
| 14.041.005 | 1519817 | ROSAS | MÓNICA ELISABETH | 1,19 | 2026-05-06 |
| 14.041.005 | 5623333 | ROSAS | MÓNICA ELISABETH | 5,56 | 2021-02-08 |
| 26.557.033 | 1646471 | BOURGET | VALENTIN ADOLFO | 0,10 | 2011-01-07 |
| 26.557.033 | 5426867 | BOURGUET | VALENTIN ADOLFO | 0,14 | 2011-03-01 |

Mónica Elisabeth Rosas está cargada dos veces, con dos porcentajes distintos (1,19% +
5,56%) en vez de uno solo. Valentín Adolfo Bourget/Bourguet, además, muestra la variante
de tipeo típica en el apellido. Este ejemplo sirve para mostrarle a Mónica que el problema
no está aislado en casos chicos: **puede convivir más de una colisión dentro del mismo
inmueble grande.**

### Caso 3 — Posible colisión entre dos personas distintas (a confirmar)

De la muestra de 60 documentos sorteada el 17/09/2026: **Documento 21.949.584, Matrícula
1.600.244.228.**

| `ID_FORMULARIO` | Apellido cargado | Nombre | % de titularidad | Titular activo desde |
|---|---|---|---|---|
| 5022754 | NOTTI | GLORIA ALEJANDRA | 16,67 | 2024-02-07 |
| 5673493 | NOTTI | LEONARDO JAVIER | 16,66 | 2024-02-07 |

Este caso es distinto y más delicado: los nombres de pila son **claramente diferentes**
(Gloria Alejandra vs. Leonardo Javier), aunque comparten apellido y el mismo número de
documento cargado. Los porcentajes (16,67% + 16,66% ≈ un tercio de la propiedad) son
compatibles con una sucesión repartida entre varios herederos. **A confirmar si es un
error de tipeo del documento entre dos hermanos, o una coincidencia real de números** —
es exactamente el tipo de caso que la detección de "personas mezcladas" (§5 del contexto
del proyecto) busca separar antes de fusionar nada automáticamente: acá fusionar sería un
error, porque probablemente sean dos personas reales distintas.

---

## Anexo II — Casos de "personas mezcladas" ya confirmados por revisión manual

Estos casos **no** vienen de la muestra de hoy: son de la revisión manual que ya hiciste
sobre `docs/Titulares BD.xlsx`, y muestran por qué ningún grupo se fusiona sin pasar antes
por la detección de identidades mezcladas.

### Documento 25.007.077

De 11 registros cargados bajo este documento, la revisión manual encontró que **solo 4**
correspondían a la misma persona real (Francisco Gaitán: `ID_FORMULARIO` 5302372,
5302369, 5302373, 5115894); los otros 7 son personas distintas que quedaron agrupadas por
compartir el mismo número de documento. Es el caso más extremo detectado hasta ahora. No
tiene registros en las tablas de titularidad, así que no impacta una matrícula puntual,
pero muestra el riesgo de fusionar por documento sin revisar antes.

### Documento 6.899.569

El `ID_FORMULARIO` 568153 aparece unas **56 veces** en la tabla de titulares históricos.
La revisión manual confirmó que, bajo el mismo documento, hay **dos personas reales
distintas** — no es solo redundancia de carga de una sola persona.

---

*Informe generado a partir de consultas ejecutadas el 16 y 17/09/2026 sobre el entorno de
desarrollo de SIRCLAN, más la revisión manual registrada en `docs/Titulares BD.xlsx`.
Resultados crudos archivados en `scripts/out/` y `scripts/queries/`.*
