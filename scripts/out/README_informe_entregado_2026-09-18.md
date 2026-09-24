# Depuración de titulares duplicados

**Fecha:** 18 de septiembre de 2026  
**Base analizada:** SIRCLAN (Oracle), entorno de **desarrollo**  
**Alcance del informe:** personas físicas/humanas titulares vinculadas a una matrícula real (se excluye del análisis matricualas de sistemas anteriores identificados por Tomo/Filio)

---

## 1. Resumen

| Indicador                                                              | Valor               |
| ---------------------------------------------------------------------- | ------------------- |
| Grupos de personas físicas duplicadas (por numero de DNI)              | **121.852** (total) |
| Grupos que **se relacionan con una matrícula real** y se deben revisar | **55.918** (45,9%)  |
| **Matrículas con la misma persona cargada dos veces como titular**     | **2.868**           |

**Conclusiones:**

1. **Filtrar por matrícula real redujo el trabajo a menos de la mitad.** De
   121.852 grupos a revisar pasamos a 55.918.

2. Dentro de los 55.918 grupos, 30.136 (54%) tienen **dos o más registros
   como titular activo** de la misma persona. De esos,
   el 91% son grupos chicos, de 2 o 3 duplicados: casos simples de resolver.

3. **Hay 2.868 matrículas** donde la misma persona figura dos o más veces como titular
   vigente **del mismo inmueble**. En una de ellas llega a estar repetida 9 veces
   (ver ejemplos en el Anexo I).

---

## 2. El universo de trabajo: 55.918 grupos

| Prioridad | Signfcicado                                              | Grupos     | %     |
| --------- | -------------------------------------------------------- | ---------- | ----- |
| **P1**    | Dos o más registros de la persona son **titular activo** | **30.136** | 53,9% |
| **P2**    | Un titular activo + registros en históricos              | 17.449     | 31,2% |
| **P3**    | Solo registros en históricos / no vigentes               | 8.333      | 14,9% |

### Los casos P1 son en su mayoria más simples

| Tamaño del grupo | Grupos P1 | %     |
| ---------------- | --------- | ----- |
| 2 a 3 registros  | 27.389    | 90,9% |
| 4 a 6 registros  | 2.600     | 8,6%  |
| 7 a 10 registros | 137       | 0,45% |
| 11 o más         | 10        | 0,03% |

---

## 3. Qué queda fuera del alcance automático

| Segmento                               | Volumen                  | Situación                                                                               |
| -------------------------------------- | ------------------------ | --------------------------------------------------------------------------------------- |
| Personas físicas sin documento cargado | 163.986                  | Solo 2.516 son recuperables desde otros campos. No entran en la detección por documento |
| Documentos comodín (0, 00, 1, etc.)    | 7.111                    | Excluidos de todo el análisis: no identifican a nadie                                   |
| Personas jurídicas sin CUIT utilizable | 23.920 (42,4% de 56.399) | Sin CUIT válido no hay deduplicación automática posible                                 |

Para personas jurídicas, sobre las que **sí** tienen CUIT válido se detectaron **5.814
grupos duplicados** con **12.787 registros de más**. El cruce contra matrículas para
jurídicas está pendiente de ejecución.

---

## 4. Salvedades metodológicas

1. **Base de desarrollo.** Todas las mediciones se hicieron sobre el entorno de
   desarrollo, que tiene datos actualizados hasta el 10 de septiembre del 2026.

2. **Titulares que apuntan a una matrícula que no existe:** 557 titulares
   (519 activos + 38 históricos) apuntan a un número de matrícula que no existe en la
   tabla de inmuebles. Volumen relativamente chico, pendiente de revisar en la próxima vuelta.

3. **Datos generales de matrículas** (523.617 reales, 40.976 sin titular, 316 con
   porcentaje inválido).

---

## Anexo I — Ejemplos de "doble titular en la misma matrícula"

Tres casos que muestran tres causas distintas del mismo problema.

### Caso 1 — La persona repetida 9 veces

**Matrícula 800.622.102** (estado ACT — vigente hoy). Documento 24.506.089, **Mauricio
Ariel Cantalejos**, figura como titular activo bajo **9 `ID_FORMULARIO` distintos**
(5696437 a 5696445), los 9 con **exactamente el mismo nombre, el mismo documento y la
misma fecha de alta: 19/08/2025**, y ninguno con porcentaje de titularidad asignado.

Los `ID_FORMULARIO` son **consecutivos** — la señal más fuerte de que no son 9 cargas
independientes, sino la **misma carga repetida 9 veces en un solo evento**. Este caso lo
confirma también sobre titulares **activos** de un inmueble real, no solo en el catálogo
general de personas.

### Caso 2 — Una copropiedad grande, con dos colisiones distintas adentro

**Matrícula 300.079.974** (estado ACT), un inmueble con cerca de 60 titulares distintos
(un consorcio o propiedad con muchos copropietarios, cada uno con una fracción chica). Dos
de esos titulares están duplicados:

| Documento  | `ID_FORMULARIO` | Apellido cargado | Nombre           | % de titularidad | Titular activo desde |
| ---------- | --------------- | ---------------- | ---------------- | ---------------- | -------------------- |
| 14.041.005 | 1519817         | ROSAS            | MÓNICA ELISABETH | 1,19             | 2026-05-06           |
| 14.041.005 | 5623333         | ROSAS            | MÓNICA ELISABETH | 5,56             | 2021-02-08           |
| 26.557.033 | 1646471         | BOURGET          | VALENTIN ADOLFO  | 0,10             | 2011-01-07           |
| 26.557.033 | 5426867         | BOURGUET         | VALENTIN ADOLFO  | 0,14             | 2011-03-01           |

Mónica Elisabeth Rosas está cargada dos veces, con dos porcentajes distintos (1,19% +
5,56%) en vez de uno solo. Valentín Adolfo Bourget/Bourguet, además, muestra una variante
de tipeo en el apellido.

### Caso 3 — Posible colisión entre dos personas distintas

**Documento 21.949.584, Matrícula 1.600.244.228.**

| `ID_FORMULARIO` | Apellido cargado | Nombre           | % de titularidad | Titular activo desde |
| --------------- | ---------------- | ---------------- | ---------------- | -------------------- |
| 5022754         | NOTTI            | GLORIA ALEJANDRA | 16,67            | 2024-02-07           |
| 5673493         | NOTTI            | LEONARDO JAVIER  | 16,66            | 2024-02-07           |

Este caso es **más delicado**: los nombres son **claramente diferentes**
(Gloria Alejandra vs. Leonardo Javier), aunque comparten apellido, tienen el mismo número de
documento y CUIT cargados. Los porcentajes (16,67% + 16,66% ≈ un tercio de la propiedad) —
es un tipo de caso de "personas mezcladas" que deben ser buscados para separar antes de
fusionar: acá fusionar sería un error, porque probablemente sean dos personas reales distintas.

> Nota: Se verifica con la api que el dni 21949584 corresponde a GLORIA ALEJANDRA (cuit: 27219495841)

---

## Anexo II — Casos de "personas mezcladas" ya confirmados por revisión manual

### Documento 25.007.077

De 11 registros cargados bajo este documento, se detecto que **solo 4**
correspondían a la misma persona (Francisco Gaitán: `ID_FORMULARIO` 5302372,
5302369, 5302373, 5115894); los otros 7 son personas distintas que quedaron agrupadas por
compartir el mismo número de documento. No tiene registros en las tablas de titularidad,
así que no impacta una matrícula puntual.

### Documento 6.899.569

El `ID_FORMULARIO` 568153 aparece unas **56 veces** en la tabla de titulares históricos.
El revisar se confirma que, bajo el mismo documento, hay **dos personas reales distintas**
