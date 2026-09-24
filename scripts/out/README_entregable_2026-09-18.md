# Entregable 18/09/2026 — Personas físicas duplicadas

Seis CSV listos para pegar como hojas en un Excel. Todos con **BOM UTF-8 y separador
`;`**: se abren con doble clic en Excel en español, sin pasar por el asistente de
importación y sin romper acentos.

## Las hojas, en el orden en que conviene armarlas

| # | Archivo | Filas | Qué es |
|---|---|---|---|
| 1 | `resumen_kpi_pf_2026-09-18.csv` | 37 + 7 notas | Los KPI, cada uno con su query de origen y su fecha de corte |
| 2 | `detalle_grupos_priorizado_2026-09-18.csv` | 55.918 | Una fila por grupo a revisar, ordenada P1 → P2 → P3 |
| 3 | `casos_representativos_registros_2026-09-18.csv` | 202 | Registro por registro de `DIG_DOC_R62` para 67 documentos |
| 4 | `casos_representativos_candidato_2026-09-18.csv` | 67 | Un renglón por documento: candidato propuesto y diagnóstico automático |
| 5 | `casos_representativos_matriculas_2026-09-18.csv` | 590 | Qué matrículas cuelgan de cada uno de esos registros |
| 6 | `doble_titular_misma_matricula_2026-09-18.csv` | 3.362 | Las 2.868 matrículas con la misma persona repetida como titular activo |

Las hojas 3, 4 y 5 se cruzan por `NU_DOCUMENTO`; la 3 y la 5 además por `ID_FORMULARIO`.

## Los 67 casos representativos

Son dos conjuntos distintos, y la columna `CASO` los separa. **No mezclar al sacar
conclusiones:**

- **59 de muestra aleatoria** — sorteados por `ORA_HASH` (semilla 42) dentro del universo
  de trabajo, estratificados 30 P1 / 20 P2 / 10 P3. Reproducen exactamente el lote del
  17/09. De acá sí se pueden estimar proporciones.
- **8 emblemáticos** — elegidos a mano, uno por patrón. **No son muestra**: sirven para
  mostrar, no para estimar. Uno de ellos (21.949.584) había salido sorteado en la muestra,
  por eso la muestra figura con 59 y no 60 — el lote sigue siendo el mismo de 60.

El emblemático 8 (25.007.077) está **fuera del universo de trabajo**: no tiene ninguna
titularidad, así que no impacta ninguna matrícula. Está incluido igual porque es el caso
más extremo de identidades mezcladas (11 registros, solo 4 la misma persona real) y
justifica por qué no se fusiona nada automáticamente. Su `ESTRATO` dice `FUERA-ALCANCE`.

## Las columnas que completás a mano

En la hoja 3 (`..._registros_...`) las últimas cinco columnas salen **vacías a propósito**:

`VALIDADO_RENAPER` · `FECHA_FALLECIMIENTO` · `SEXO_RENAPER` · `NOMBRE_RENAPER_OK` ·
`OBSERVACIONES`

Ninguna consulta pegó contra la API. **La fecha de fallecimiento no existe en ninguna
tabla de SIRCLAN** — se verificó el catálogo completo de `DIG_DOC_R62` — así que es uno de
los campos a agregar en el modelo PostgreSQL.

Para validar cada caso, el CUIL a probar está en la hoja 4:

- `CUIL_YA_CARGADO` — el que ya trae la base, cuando lo hay (46 de los 67).
- `CUILES_CALCULADOS` — cuando no hay ninguno cargado, los candidatos en orden de
  probabilidad. Aparecen varios cuando `CD_SEXO` viene sin dato: hay que probarlos en ese
  orden hasta que RENAPER responda.

## Cómo leer el diagnóstico automático (hoja 4)

`REVISION_MANUAL = true` significa "no fusionar sin mirar", por alguno de estos motivos:

- **registros posiblemente mezclados** — el detector separó el grupo en un cluster
  principal y sospechosos (`IDS_SOSPECHOSOS`). Es la señal de dos personas reales distintas
  bajo el mismo documento.
- **grupo grande (11+)** — candidato a colisión de documento; se revisa igual aunque no
  haya sospechosos.
- **`CD_SEXO` desconocido** — hay que probar varios CUIL contra la API.

De los 67 documentos, **7 tienen registros sospechosos de ser personas distintas**. El
detector reprodujo solo los casos que ya habías confirmado a mano en `Titulares BD.xlsx`:
en 25.007.077 separó exactamente los 4 registros de Francisco Gaitán de los otros 7, y en
6.899.569 marcó 4 sospechosos.

## Salvedades que conviene decir de entrada

1. Todo sale del entorno de **desarrollo**, que va unas 2 semanas atrás de producción.
2. La hoja 2 tiene el universo **completo** (55.918 grupos), no una selección. Si se
   entrega recortada, decir en la hoja por dónde se cortó.
3. Las 164.418 matrículas con titular activo duplicado son una **cota superior** (nota 4
   de la hoja Resumen). Por eso no se publica el porcentaje contra el total de matrículas.
4. Este entregable cubre **solo personas físicas**. El mismo recorte para jurídicas está
   pendiente (`vinculadas_kpi_pj.sql`, sin correr).

## Controles que ya pasaron

Cada cifra se cruzó contra CLAUDE.md §3 antes de exportar, y cerró exacta:

| Control | Esperado | Obtenido |
|---|---|---|
| Grupos del universo de trabajo | 55.918 | 55.918 |
| Partición P1 / P2 / P3 | 30.136 / 17.449 / 8.333 | idem |
| Registros redundantes | 78.210 | 78.210 |
| Personas vinculadas | 123.118 | 123.118 |
| Personas a reasignar | 67.200 | 67.200 |
| Doble titular: filas / matrículas / documentos | 3.362 / 2.868 / 2.947 | idem |
| Los 60 documentos del lote del 17/09 | presentes | los 60 |
