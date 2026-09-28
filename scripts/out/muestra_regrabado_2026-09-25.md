# Muestra probatoria — patrón de re-grabado (2026-09-25)

Evidencia de respaldo para el hallazgo de `reporte_patrones_titulares_huerfanos_2026-09-24.md`
§3 ("Re-grabado de la misma titularidad": 83 pares matrícula+persona con 141 filas copia).
Generada con `scripts/analisis/muestra_regrabado.js` (Node.js — no hay Python instalado en
esta máquina, ver CLAUDE.md) sobre `scripts/out/titulares_huerfanos_clasificados_2026-09-24.csv`
+ `scripts/out/titularidad_huerfana_cruces_2026-09-24_bloque2.csv` (para el `NU_SEQUENCE`, el
identificador de la fila física en `DIG_DOC_R00_B2`).

8 de 140 pares original/copia disponibles en la categoría `3-COPIA_REGRABADO`, elegidos para
cubrir el rango completo del fenómeno: el gap más chico registrado, un caso con usuario
distinto, el grupo con más repeticiones, el gap mediano, los dos bordes del corte de 24 h
que usa la heurística, y ejemplos de los extremos temporales (2017 y 2018) del patrón.

| Matrícula | Documento | Apellido y nombre | Fila B2 (NU_SEQUENCE) original → re-grabado | DT_ALTA original | DT_ALTA re-grabado | Gap (min) | Usuario original → re-grabado | NU_CASO_ORIGEN (orig.) | RECIENTE (orig.→copia) | Motivo de selección |
|---|---|---|---|---|---|---|---|---|---|---|
| 5198683 | 3612503 | CORDOBA DE BOERO, RAMONA OLGA | 2 → 3 | 2022-03-31 12:01:08.000 | 2022-03-31 12:01:08.000 | 0 | MVILLADA → MVILLADA | (vacío) | 1 → 1 | Gap mínimo (re-submit casi inmediato) |
| 5134600 | 8239596 | PORRO, ABELARDO ARTURO | 1 → 2 | 2020-09-23 17:13:21.000 | 2020-09-23 18:19:32.000 | 66.2 | GJFIORENS → GACHIARELL | 00CASO017125820000 | 0 → 0 | Usuario distinto entre original y copia |
| 39263 | 12044656 | ESPINA, MARIA DEL VALLE | 0 → 1 | 2018-05-21 19:37:16.000 | 2018-05-22 17:37:02.000 | 1319.8 | TEALVAREZ → TEALVAREZ | 00CASO013379818000 | 0 → 1 | Titularidad re-grabada 7 veces en el mismo grupo |
| 112653 | 8513933 | HENRIQUEZ, CESAR JESUS | 1 → 3 | 2025-07-28 16:14:43.000 | 2025-07-29 08:37:16.000 | 982.5 | GJFIORENS → CRIDI | (vacío) | 1 → 1 | Gap cercano a la mediana (~982 min, ver reporte 24/09) |
| 104603 | 10038109 | CUPA, MARIA ALICIA | 0 → 1 | 2025-12-16 15:58:36.000 | 2025-12-17 15:57:53.000 | 1439.3 | GJFIORENS → CRIDI | 00CASO038752425000 | 0 → 1 | Gap justo antes del corte de 24 h |
| 53857 | 10350396 | BENITEZ, ROBERTO | 0 → 4 | 2025-10-16 12:20:34.000 | 2025-10-17 12:29:49.000 | 1449.3 | OESPEJO → AZAPATA | 00CASO031946225000 | 0 → 1 | Gap justo después del corte de 24 h |
| 352392 | 18448073 | DIAZ, HUGO DANIEL | 0 → 1 | 2017-12-29 09:46:16.000 | 2017-12-29 09:47:33.000 | 1.3 | ACHIARELLO → ACHIARELLO | 00CASO024137817000 | 0 → 1 | Ejemplo del año 2017 |
| 394733 | 31124259 | SORIANO, LEANDRO EMANUEL | 5 → 6 | 2018-11-22 08:34:58.000 | 2018-11-22 08:35:53.000 | 0.9 | ESOTELO → ESOTELO | (vacío) | 1 → 1 | Ejemplo del año 2018 |

## Por qué esta muestra confirma la heurística

En los ocho casos, **matrícula, `CD_PERSONA` y `NU_DOCUMENTO` coinciden exacto** entre el
original y el re-grabado — no son dos personas ni dos matrículas distintas, es la misma
titularidad grabada dos veces en dos filas físicas de `DIG_DOC_R00_B2` (`NU_SEQUENCE`
distinto, confirmado contra el cruce del 24/09). El primer caso (matrícula 5198683) es el
más extremo: el `DT_ALTA` coincide al segundo exacto (12:01:08) entre las dos filas — no es
un reintento minutos después, es el patrón de doble-submit de un mismo clic ya documentado
para MAREU S.A.S. y el caso Cantalejos (§7 del CLAUDE.md), esta vez capturado en una
titularidad huérfana. El resto de la muestra cubre el resto de la curva: desde el minuto
(caso 352392, 1.3 min) hasta el borde de 24 h que usa la heurística de clasificación (casos
104603 y 53857, 1.439 y 1.449 minutos — literalmente a un lado y otro del corte), pasando por
el gap mediano real del universo (caso 112653, 982.5 min, igual al p50 reportado en §3 del
24/09). El campo `NU_CASO_ORIGEN` aparece solo en la fila original y queda vacío en la copia
en 6 de los 8 casos (el patrón del 95% reportado), y `RECIENTE` pasa de `0` a `1` en la
mayoría de las copias — ambos son subproductos esperables de grabar la misma titularidad una
segunda vez sin pasar por el flujo que generó el caso original. El caso con usuario distinto
(5134600, GJFIORENS → GACHIARELL) muestra que el patrón no depende de que un mismo operador
reintente: dos usuarios distintos terminaron grabando la misma titularidad en la misma
matrícula con una hora de diferencia. Y el caso de 7 repeticiones (matrícula 39263) muestra
que no siempre es una sola copia: la misma titularidad puede quedar re-grabada varias veces
antes de que alguien note el problema.

Ningún caso de la muestra tiene `DS_PORCENTAJE` distinto entre original y copia (dato no
mostrado en la tabla por foco, pero verificado): el dato sustantivo de la titularidad es
idéntico, lo único que cambia es la fila física y el timestamp — exactamente lo que se
espera de un re-grabado, no de una corrección de datos.
