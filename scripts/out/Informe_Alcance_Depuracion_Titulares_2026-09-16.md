# Depuración de titulares duplicados — Informe de alcance

**Fecha:** 16 de septiembre de 2026
**Base analizada:** SIRCLAN (Oracle), entorno de **desarrollo**
**Alcance del informe:** personas físicas. Personas jurídicas, dimensionadas aparte al final.

---

## 1. Resumen ejecutivo

Se aplicó el criterio acordado en la reunión de hoy: **analizar únicamente las personas
que están efectivamente vinculadas a una matrícula**, en lugar de todo el padrón de
personas duplicadas.

| Indicador | Valor |
|---|---|
| Grupos de personas físicas duplicadas (total) | **121.852** |
| Grupos que **tocan una matrícula** y requieren revisión | **60.847** (49,9%) |
| Grupos donde la fusión es automática, sin revisión | 45.178 (37,1%) |
| Grupos fuera de alcance (no tocan ninguna matrícula) | 15.827 (13,0%) |
| Matrículas con al menos un titular activo duplicado | **165.120** |
| **Matrículas con la misma persona cargada dos veces como titular** | **3.006** |

**Tres conclusiones:**

1. **El filtro por matrícula reduce el trabajo a la mitad.** De 121.852 grupos a revisar
   pasamos a 60.847. Las validaciones contra la API de RENAPER bajan de ~122.000 a
   ~61.000, y los otros 45.178 grupos se resuelven solos: uno solo de sus registros tiene
   matrícula, y ese es el que queda, sin necesidad de decidir nada.

2. **El problema está concentrado y es abordable.** Dentro de los 60.847 grupos, 34.055
   (56%) tienen **dos o más registros como titular activo** de la misma persona. De esos,
   el 91% son grupos chicos, de 2 o 3 duplicados: casos simples de resolver.

3. **Hay 3.006 matrículas con un error registral concreto y verificable**, donde la misma
   persona figura dos o más veces como titular vigente **del mismo inmueble**. En una de
   ellas llega a estar repetida 9 veces. Es el hallazgo más accionable del análisis.

---

## 2. Qué cambió respecto del informe de agosto

El informe anterior midió el padrón completo: cuántas personas están cargadas más de una
vez en el sistema. Ese número es grande (162.491 registros de más) pero mezcla dos cosas
muy distintas: personas duplicadas que sostienen la titularidad de un inmueble, y
duplicados que quedaron en el catálogo sin ninguna consecuencia registral.

La tabla de personas la comparte **todo el sistema BPM**, no solo el módulo de titulares.
Por eso una parte de los duplicados no tiene ningún efecto sobre las matrículas.

Al cruzar cada registro duplicado contra las tres tablas de titularidad (titulares
activos, históricos y no vigentes), el padrón queda partido así:

| Categoría | Grupos | % | Registros | Registros de más |
|---|---|---|---|---|
| **Varios registros vinculados a matrícula** | **60.847** | 49,9% | 145.621 | 84.774 |
| Un solo registro vinculado | 45.178 | 37,1% | 102.810 | 57.632 |
| Ningún registro vinculado | 15.827 | 13,0% | 35.912 | 20.085 |
| **Total** | **121.852** | 100% | 284.343 | **162.491** |

Los totales coinciden exactamente con las mediciones anteriores (121.852 grupos y 162.491
registros redundantes), lo que confirma que este recorte es una reclasificación del mismo
universo y no una medición distinta.

> **Aclaración:** "no vinculado a matrícula" no significa "se puede borrar". Esos
> registros pueden estar en uso en otros formularios del BPM. Quedan fuera del alcance de
> **este** proyecto; no están marcados para eliminación.

---

## 3. El universo de trabajo: 60.847 grupos

Los grupos que requieren revisión se ordenaron por gravedad:

| Prioridad | Qué significa | Grupos | % |
|---|---|---|---|
| **P1** | Dos o más registros de la persona son **titular activo** | **34.055** | 56,0% |
| **P2** | Un titular activo + registros en históricos | 19.028 | 31,3% |
| **P3** | Solo registros en históricos / no vigentes | 7.764 | 12,8% |

**P1 es la prioridad real:** son los casos donde el padrón vigente de titulares tiene hoy
información duplicada. P2 y P3 involucran registros históricos, que igual deben corregirse
al fusionar, pero no afectan la vista actual de titularidad.

### Los casos son mayoritariamente simples

Distribución de los 34.055 grupos P1 según cuántas veces está repetida la persona:

| Tamaño del grupo | Grupos P1 | % |
|---|---|---|
| 2 a 3 registros | 30.937 | 90,8% |
| 4 a 6 registros | 2.947 | 8,7% |
| 7 a 10 registros | 161 | 0,5% |
| 11 o más | 10 | 0,03% |

Y según cuántos vínculos de titularidad hay que corregir por grupo:

| Vínculos a corregir | Grupos P1 |
|---|---|
| 5 o menos | 20.543 |
| 6 a 20 | 12.277 |
| 21 a 50 | 1.144 |
| Más de 50 | 91 |

**Solo 91 grupos superan los 50 vínculos.** La cola de casos complejos es muy corta y
puede revisarse manualmente uno por uno.

---

## 4. Impacto sobre las matrículas

Cantidad de inmuebles alcanzados por el problema, según la tabla de titularidad:

| Tabla | Vínculos de titularidad | Personas distintas | **Matrículas distintas** |
|---|---|---|---|
| Titulares activos | 228.103 | 125.298 | **165.120** |
| Titulares históricos | 213.771 | 97.397 | 127.803 |
| Titulares no vigentes | 2.638 | 2.117 | 1.861 |
| **Total (sin repetir)** | **444.512** | **179.187** | **256.175** |

**165.120 matrículas tienen al menos un titular activo que pertenece a un grupo de
personas duplicadas.** Como referencia, el informe de agosto contabilizó 523.058 matrículas
con número de matrícula real; la proporción es del orden del 30%, aunque las dos
mediciones corresponden a fechas distintas y ese porcentaje debe recalcularse antes de
publicarse.

---

## 5. El hallazgo crítico: la misma persona, dos veces titular del mismo inmueble

De los 34.055 grupos P1 se aisló el subconjunto donde los registros duplicados **no están
en inmuebles distintos, sino en el mismo**:

| Indicador | Valor |
|---|---|
| Casos (matrícula + documento) | **3.537** |
| **Matrículas afectadas** | **3.006** |
| Documentos (personas) involucrados | 3.082 |
| Registros de persona involucrados | 7.194 |
| Vínculos de titularidad involucrados | 7.741 |
| Máximo de registros de una misma persona en una matrícula | **9** |

Son **3.006 inmuebles donde el titular está contado dos o más veces**. No es un problema de
prolijidad del catálogo: es el dato registral del inmueble el que está mal armado, con la
titularidad repartida entre registros que corresponden a una única persona real.

Esto se relaciona directamente con las **309 matrículas cuya suma de porcentajes de
titularidad no da 100%** detectadas en el informe de agosto: cuando una persona aparece dos
veces, el porcentaje que le corresponde queda dividido entre sus copias.

Representa el 9,1% de los grupos P1 y el 0,57% de las matrículas del registro. **Es el
conjunto con el que conviene empezar:** es acotado, el error es demostrable caso por caso y
la corrección es verificable.

---

## 6. Qué queda fuera del alcance automático

Segmentos que no pueden deduplicarse con el método actual y requieren una decisión aparte:

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

2. **Verificación pendiente sobre bajas lógicas.** La tabla de titulares activos tiene dos
   campos de control cuyo uso real aún no fue confirmado. Si alguno de ellos marca bajas
   lógicas, las cifras de impacto sobre matrículas (165.120 y 3.006) podrían reducirse. Es
   la verificación más urgente antes de dar estos números por definitivos.

3. **Ningún dato fue modificado.** El acceso a la base es de solo lectura. Todo el análisis
   es no destructivo.

4. **Trazabilidad.** Cada cifra de este informe proviene de una consulta SQL versionada,
   con sus resultados archivados: cualquier número puede reproducirse.

---

## 8. Próximos pasos propuestos

**Inmediatos**

1. Verificar el significado de los campos de baja lógica para confirmar las cifras de
   impacto.
2. Generar el listado detallado de las **3.006 matrículas** con titular duplicado, para
   revisión del área registral.
3. Completar el cruce contra matrículas para personas jurídicas.

**Validación de la metodología**

4. Revisar manualmente una muestra aleatoria de **140 casos** (ya seleccionada, con
   representación de las tres prioridades) y contrastarla contra la detección automática.
   El objetivo es medir la tasa de acierto antes de procesar los 60.847 grupos.
5. Punto de atención conocido: en algunos casos un mismo número de documento agrupa a
   **personas reales distintas** por errores de carga. Por eso ningún grupo se fusiona
   automáticamente sin pasar antes por la detección de identidades mezcladas: el costo de
   unir por error a dos personas es mucho mayor que el de una revisión manual adicional.

**Procesamiento a escala**

6. Ejecutar la validación contra RENAPER sobre los grupos priorizados (~34.000 consultas
   para P1; ~61.000 para el universo completo), coordinando previamente el volumen y la
   frecuencia con el área responsable de la API.
7. Entregar el Excel final con hoja Resumen y hoja Detalle: un registro por grupo, con su
   prioridad, los inmuebles afectados y el registro propuesto como válido.

---

*Informe generado a partir de consultas ejecutadas el 16/09/2026 sobre el entorno de
desarrollo de SIRCLAN. Resultados crudos archivados en el repositorio del proyecto.*
