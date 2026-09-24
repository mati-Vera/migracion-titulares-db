# Patrones — titulares activos PF con matrícula inexistente (2026-09-24)

Fuente: `docs/Titulares_activos_con_matricula_inexistente.csv` + cruces contra la base de desarrollo.

## 0. Estructura

- Filas: **477** · matrículas distintas: **197** · personas (`CD_PERSONA`): **333** · documentos: **269**
- Columnas repetidas en el volcado: `CD_USER_STORE` (B2 vs R62), `CD_SITUACION` (idéntica), `DESDE` = `DT_DESDE` truncado. Constantes: `TP_PERSONA=PF`, `ELIMINADO=0`.

## 1. Origen

| ORIGEN_FILA_B2 | FILAS | % |
|---|---|---|
| WORKFLOW (usuario) | 422 | 88.5 |
| SIN ALTA / SIN USUARIO | 52 | 10.9 |
| MIGRACION (MIG_FHPI_ID) | 3 | 0.6 |

Origen de la fila B2 (filas) × origen del registro de persona en R62 (columnas):

| ORIGEN_FILA_B2 | MIGRACION | RPI_RV_MIG | WORKFLOW |
|---|---|---|---|
| WORKFLOW (usuario) | 261 | 2 | 159 |
| MIGRACION (MIG_FHPI_ID) | 3 | 0 | 0 |
| SIN ALTA / SIN USUARIO | 16 | 0 | 36 |

## 2. Distribución temporal (DT_ALTA de la fila B2)

| AÑO | FILAS | % |
|---|---|---|
| (sin DT_ALTA) | 52 | 10.9 |
| 1997 | 1 | 0.2 |
| 2008 | 2 | 0.4 |
| 2017 | 5 | 1.0 |
| 2018 | 77 | 16.1 |
| 2019 | 36 | 7.5 |
| 2020 | 69 | 14.5 |
| 2021 | 63 | 13.2 |
| 2022 | 42 | 8.8 |
| 2023 | 29 | 6.1 |
| 2024 | 56 | 11.7 |
| 2025 | 36 | 7.5 |
| 2026 | 9 | 1.9 |

Días con más filas (¿carga en bloque?):

| DIA | FILAS | MATRICULAS | USUARIOS |
|---|---|---|---|
| 2018-08-23 | 14 | 8 | 2 |
| 2018-12-26 | 10 | 3 | 2 |
| 2018-12-21 | 9 | 2 | 2 |
| 2022-12-15 | 9 | 2 | 3 |
| 2020-12-17 | 8 | 1 | 1 |
| 2018-08-24 | 7 | 4 | 3 |
| 2020-01-20 | 6 | 1 | 1 |
| 2024-11-25 | 6 | 1 | 2 |
| 2018-11-27 | 6 | 1 | 1 |
| 2019-03-19 | 6 | 1 | 1 |

Usuarios distintos en B2: **45**. Top 10:

| USUARIO | FILAS | % |
|---|---|---|
| (vacío) | 55 | 11.5 |
| FALEGRE | 41 | 8.6 |
| ESOTELO | 38 | 8.0 |
| CMIRANDA | 36 | 7.5 |
| GARCE | 36 | 7.5 |
| VCACERES | 27 | 5.7 |
| GJFIORENS | 19 | 4.0 |
| VPAREJAS | 15 | 3.1 |
| AEGUAJARDO | 15 | 3.1 |
| CALBANI | 15 | 3.1 |

## 3. Re-grabado de la misma titularidad

- (matrícula, persona) con más de una fila: **83** de 336; filas copia: **141**
- Copias con el mismo usuario que la original: **80.9%**
- Copias sin `NU_CASO_ORIGEN`: **95.0%** · con `RECIENTE=1`: **95.0%**
- Minutos entre la original y la copia: mediana **982.5**, p75 2611.1, p90 4177.5; copias dentro de las 24 h: **70.9%**
- `TM_DESDE` igual a `DT_ALTA` en copias: **95.0%** vs originales: 44.0%

## 4. Persona duplicada en R62 (mismo documento, distinto CD_PERSONA, misma matrícula)

| CD_PERSONA_DISTINTOS | FILAS | % |
|---|---|---|
| 1 | 233 | 83.5 |
| 2 | 36 | 12.9 |
| 3 | 9 | 3.2 |
| 4 | 1 | 0.4 |

## 5. Rango del ID_MATRICULA huérfano

| BANDA_ID | FILAS | MATRICULAS |
|---|---|---|
| A - rango bajo con R00 (hueco) | 240 | 85 |
| B - 253.250 a 1.400.000 (rango sin ninguna fila en R00) | 156 | 62 |
| C - 1,4M a 1,74M (hueco) | 7 | 4 |
| E - 5M a 6,4M (hueco, rango actual) | 68 | 43 |
| F - mayor al máximo ID (formato NU_MATRICULA) | 6 | 3 |

## 6. Cruces contra la base

- Persona (`CD_PERSONA`) titular viva en otra matrícula existente: **248** filas
- Documento titular vivo en otra matrícula existente: **334** filas
- Mismo `NU_CASO_ORIGEN` en una matrícula existente: **19** filas
- ID coincide con un `NU_MATRICULA` real: **19** filas (y la persona es titular ahí: **5**)
- ID huérfano con filas también en B4: **49** filas

## 7. Clasificación heurística propuesta

| CATEGORIA | ACCION | FILAS | MATRICULAS |
|---|---|---|---|
| 1-CLAVE_EQUIVOCADA | BORRAR: se cargó el NU_MATRICULA como ID; la titularidad ya existe en la matrícula real | 5 | 3 |
| 2-BORRADOR_DE_TRAMITE | BORRAR tras verificar: el mismo caso terminó creando otra matrícula que sí existe | 19 | 10 |
| 3-COPIA_REGRABADO | BORRAR: copia de la misma titularidad en la misma matrícula | 140 | 60 |
| 4-LEGADO_SIN_ALTA | REVISAR: sin DT_ALTA ni usuario (origen previo al WORKFLOW) | 40 | 25 |
| 5-ORIGINAL_CON_TITULARIDAD_EN_OTRA | REVISAR (probable borrado): la persona/documento es titular vivo de otra matrícula existente | 169 | 106 |
| 6-ORIGINAL_UNICO | NO BORRAR: única evidencia de titularidad de esa persona; investigar la matrícula | 104 | 67 |
