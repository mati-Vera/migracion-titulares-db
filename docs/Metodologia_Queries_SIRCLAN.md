# Metodología y Queries — Informe de Estado de Base SIRCLAN

Documento de trazabilidad: registra todas las consultas SQL utilizadas para construir el Informe de Estado de Base SIRCLAN y su Anexo I, organizadas por sección, incluyendo los intentos fallidos y las correcciones aplicadas (por ejemplo, la exclusión de valores "placeholder" como `0`, `00`, `99907804` en documentos, o `30999078040` en CUIT).

Las tablas involucradas:
- `DIG_DOC_R00` — Inmuebles
- `DIG_DOC_R00_B2` — Titulares activos
- `DIG_DOC_R62` — Personas (físicas y jurídicas)

La relación entre titulares y personas se establece mediante `DIG_DOC_R00_B2.CD_PERSONA = DIG_DOC_R62.ID_FORMULARIO`.

---

## 3.1 Personas físicas

### Query 1 — Primer intento de detección de duplicados
*Superado: agrupar también por nombre ocultó el problema de los placeholders.*
```sql
SELECT 
    p.NU_DOCUMENTO, p.NM_APELLIDO, p.NM_NOMBRE,
    COUNT(*) AS cantidad_id_formulario,
    LISTAGG(TO_CHAR(p.ID_FORMULARIO), ', ') WITHIN GROUP (ORDER BY p.ID_FORMULARIO) AS ids_formulario,
    LISTAGG(TO_CHAR(b2.ID_MATRICULA), ', ') WITHIN GROUP (ORDER BY b2.ID_MATRICULA) AS matriculas
FROM DIG_DOC_R00_B2 b2
JOIN DIG_DOC_R62 p ON p.ID_FORMULARIO = b2.CD_PERSONA
WHERE p.NU_DOCUMENTO IS NOT NULL
GROUP BY p.NU_DOCUMENTO, p.NM_APELLIDO, p.NM_NOMBRE
HAVING COUNT(*) > 1
ORDER BY cantidad_id_formulario DESC, p.NU_DOCUMENTO;
```
**Guardado:** nada para el informe final; sirvió para descubrir el patrón de duplicados (caso CANTALEJOS).

### Query 2 — Resumen ejecutivo por tipo de persona
Base compartida entre 3.1 y 3.2.
```sql
WITH personas AS (
    SELECT p.ID_FORMULARIO, p.NU_DOCUMENTO,
        CASE WHEN p.TP_PERSONA = 'PF' THEN 'PERSONA FISICA' ELSE 'PERSONA JURIDICA' END AS TIPO_PERSONA
    FROM DIG_DOC_R62 p
),
conteo_doc AS (
    SELECT TIPO_PERSONA, NU_DOCUMENTO, COUNT(*) AS cant_ids
    FROM personas WHERE NU_DOCUMENTO IS NOT NULL
    GROUP BY TIPO_PERSONA, NU_DOCUMENTO
),
titulares AS (
    SELECT pe.TIPO_PERSONA, COUNT(*) AS total_titulares
    FROM DIG_DOC_R00_B2 b2 JOIN personas pe ON pe.ID_FORMULARIO = b2.CD_PERSONA
    GROUP BY pe.TIPO_PERSONA
),
sin_titularidad AS (
    SELECT pe.TIPO_PERSONA, COUNT(*) AS total
    FROM personas pe
    WHERE NOT EXISTS (SELECT 1 FROM DIG_DOC_R00_B2 b2 WHERE b2.CD_PERSONA = pe.ID_FORMULARIO)
    GROUP BY pe.TIPO_PERSONA
)
SELECT pe.TIPO_PERSONA, COUNT(*) AS total_personas,
    SUM(CASE WHEN pe.NU_DOCUMENTO IS NULL THEN 1 ELSE 0 END) AS personas_sin_documento,
    (SELECT COUNT(*) FROM conteo_doc cd WHERE cd.TIPO_PERSONA = pe.TIPO_PERSONA AND cd.cant_ids > 1) AS grupos_documento_duplicado,
    (SELECT NVL(SUM(cant_ids - 1),0) FROM conteo_doc cd WHERE cd.TIPO_PERSONA = pe.TIPO_PERSONA AND cd.cant_ids > 1) AS registros_redundantes,
    NVL((SELECT total_titulares FROM titulares t WHERE t.TIPO_PERSONA = pe.TIPO_PERSONA),0) AS total_titulares_b2,
    NVL((SELECT total FROM sin_titularidad s WHERE s.TIPO_PERSONA = pe.TIPO_PERSONA),0) AS personas_sin_titularidad
FROM personas pe GROUP BY pe.TIPO_PERSONA ORDER BY pe.TIPO_PERSONA;
```
**Guardado:** total_personas PF = 982.926, total_personas PJ = 56.293 (usado en el informe). El resto de las columnas quedó superado por los ajustes de placeholders que siguen.

### Query 3 — Peor caso PF, primer intento
*Falló: ORA-00907 (FETCH FIRST dentro de subconsulta escalar).*
```sql
SELECT p.ID_FORMULARIO, p.NM_APELLIDO, p.NM_NOMBRE, p.TP_DOCUMENTO, p.NU_DOCUMENTO, ...
FROM DIG_DOC_R62 p
WHERE p.NU_DOCUMENTO = (
    SELECT NU_DOCUMENTO FROM DIG_DOC_R62
    WHERE NU_DOCUMENTO IS NOT NULL AND TP_PERSONA = 'PF'
    GROUP BY NU_DOCUMENTO ORDER BY COUNT(*) DESC
    FETCH FIRST 1 ROWS ONLY
)
ORDER BY p.ID_FORMULARIO;
```

### Query 4 — Mismo query, corregido con ROWNUM
```sql
SELECT p.ID_FORMULARIO, p.NM_APELLIDO, p.NM_NOMBRE, p.TP_DOCUMENTO, p.NU_DOCUMENTO, ...
FROM DIG_DOC_R62 p
WHERE p.NU_DOCUMENTO = (
    SELECT NU_DOCUMENTO FROM (
        SELECT NU_DOCUMENTO FROM DIG_DOC_R62
        WHERE NU_DOCUMENTO IS NOT NULL AND TP_PERSONA = 'PF'
        GROUP BY NU_DOCUMENTO ORDER BY COUNT(*) DESC
    ) WHERE ROWNUM = 1
)
ORDER BY p.ID_FORMULARIO;
```
**Guardado:** reveló que `NU_DOCUMENTO = '0'` es un placeholder (miles de nombres distintos comparten ese "documento").

### Query 5 — Contar personas con documento = 0
*Falló: ORA-01722 (comparó `<> 0` numérico contra columna VARCHAR2).*
```sql
SELECT COUNT(*) FROM DIG_DOC_R62 WHERE TP_PERSONA = 'PF' AND NU_DOCUMENTO = 0;
```

### Query 6 — Corregido con `'0'` string
```sql
SELECT COUNT(*) AS personas_doc_cero FROM DIG_DOC_R62 WHERE TP_PERSONA = 'PF' AND NU_DOCUMENTO = '0';
```
**Guardado:** 7.031.

### Query 7 — KPI excluyendo `'0'`
```sql
WITH conteo AS (
    SELECT NU_DOCUMENTO, COUNT(*) AS cant_ids FROM DIG_DOC_R62
    WHERE TP_PERSONA = 'PF' AND NU_DOCUMENTO IS NOT NULL AND NU_DOCUMENTO <> '0'
    GROUP BY NU_DOCUMENTO
)
SELECT (SELECT COUNT(*) FROM DIG_DOC_R62 WHERE TP_PERSONA='PF' AND NU_DOCUMENTO = '0') AS personas_doc_cero,
    (SELECT COUNT(*) FROM conteo WHERE cant_ids > 1) AS grupos_documento_duplicado,
    (SELECT NVL(SUM(cant_ids-1),0) FROM conteo WHERE cant_ids > 1) AS registros_redundantes
FROM dual;
```
**Guardado (parcial, superado):** grupos=121.670, redundantes=162.287.

### Query 8 — Peor caso PF excluyendo `'0'`
Mismo patrón que Query 4 pero agregando `AND NU_DOCUMENTO <> '0'`.
**Guardado:** reveló que `NU_DOCUMENTO = '00'` es *otro* placeholder distinto.

### Query 9 — Distribución de placeholders "todo ceros"
```sql
SELECT NU_DOCUMENTO, COUNT(*) AS cantidad FROM DIG_DOC_R62
WHERE TP_PERSONA = 'PF' AND REGEXP_LIKE(NU_DOCUMENTO, '^0+$')
GROUP BY NU_DOCUMENTO ORDER BY cantidad DESC;
```
**Guardado:** `0`=7031, `00`=21, `0000000`=4, `000`=3, `00000000`=3, `000000`=2.

### Query 10 — KPI excluyendo cualquier patrón de solo ceros (regex)
```sql
WITH conteo AS (
    SELECT NU_DOCUMENTO, COUNT(*) AS cant_ids FROM DIG_DOC_R62
    WHERE TP_PERSONA = 'PF' AND NU_DOCUMENTO IS NOT NULL AND NOT REGEXP_LIKE(NU_DOCUMENTO, '^0+$')
    GROUP BY NU_DOCUMENTO
)
SELECT (SELECT COUNT(*) FROM DIG_DOC_R62 WHERE TP_PERSONA='PF' AND REGEXP_LIKE(NU_DOCUMENTO, '^0+$')) AS personas_doc_placeholder,
    (SELECT COUNT(*) FROM conteo WHERE cant_ids > 1) AS grupos_documento_duplicado,
    (SELECT NVL(SUM(cant_ids-1),0) FROM conteo WHERE cant_ids > 1) AS registros_redundantes
FROM dual;
```
**Guardado (parcial, superado):** placeholder=7.064, grupos=121.665, redundantes=162.259.

### Query 11 — Peor caso PF excluyendo ceros
**Guardado:** reveló `NU_DOCUMENTO = '99907804'` como *otro* placeholder (migración 2017).

### Query 12 — Top 15 documentos (intento con FETCH FIRST)
*Falló: ORA-00933.*

### Query 13 — Corregido con ROWNUM
```sql
SELECT * FROM (
    SELECT NU_DOCUMENTO, COUNT(*) AS cantidad FROM DIG_DOC_R62
    WHERE TP_PERSONA = 'PF' AND NU_DOCUMENTO IS NOT NULL AND NOT REGEXP_LIKE(NU_DOCUMENTO, '^0+$')
    GROUP BY NU_DOCUMENTO ORDER BY cantidad DESC
) WHERE ROWNUM <= 15;
```
**Guardado:** reveló `99907804`(20) y `1`(16) como placeholders adicionales, y `6824505`(18) como primer caso genuino.

### Query 14 — KPI final (definitivo, usado en el informe)
```sql
WITH conteo AS (
    SELECT NU_DOCUMENTO, COUNT(*) AS cant_ids FROM DIG_DOC_R62
    WHERE TP_PERSONA = 'PF' AND NU_DOCUMENTO IS NOT NULL
      AND NOT REGEXP_LIKE(NU_DOCUMENTO, '^0+$') AND NU_DOCUMENTO NOT IN ('99907804', '1')
    GROUP BY NU_DOCUMENTO
)
SELECT (SELECT COUNT(*) FROM DIG_DOC_R62 WHERE TP_PERSONA='PF' 
        AND (REGEXP_LIKE(NU_DOCUMENTO, '^0+$') OR NU_DOCUMENTO IN ('99907804','1'))) AS personas_doc_placeholder,
    (SELECT COUNT(*) FROM conteo WHERE cant_ids > 1) AS grupos_documento_duplicado,
    (SELECT NVL(SUM(cant_ids-1),0) FROM conteo WHERE cant_ids > 1) AS registros_redundantes
FROM dual;
```
**Guardado (definitivo): placeholder=7.100, grupos=121.663, registros_redundantes=162.225.**

### Query 15 — Detalle completo del caso ELASKAR (para el Anexo I)
```sql
SELECT p.ID_FORMULARIO, p.NM_APELLIDO, p.NM_NOMBRE, p.TP_DOCUMENTO, p.NU_DOCUMENTO,
       p.NU_CUIL_CUIT, p.DS_EMAIL, p.NU_CELULAR, p.NU_TELEFONO, p.DT_NACIMIENTO,
       p.DS_CALLE, p.DS_NUMERO, p.CD_LOCALIDAD, p.CD_ESTADO_CIVIL,
       p.CD_USER_STORE, p.DT_STORE, p.CD_USER_LAST_UPDATE, p.DT_LAST_UPDATE
FROM DIG_DOC_R62 p WHERE p.NU_DOCUMENTO = '6824505' ORDER BY p.ID_FORMULARIO;
```
**Guardado:** los 18 registros de ELASKAR, IBRAHIM ABIB (doc. 6.824.505), usados en el Anexo I.

---

## 3.2 Personas jurídicas

### Query 1 — Duplicados por CUIT, versión completa
*Falló: ORA-01489 (LISTAGG superó 4000 bytes por el placeholder `CUIT='0'`).*

### Query 2 — Diagnóstico top 20 CUIT
```sql
WITH juridicas AS (
    SELECT p.ID_FORMULARIO,
        NVL(NULLIF(TRIM(TO_CHAR(p.NU_CUIL_CUIT)), ''), REGEXP_REPLACE(p.NU_CUIL_CUIT_STR, '[^0-9]', '')) AS CUIT_NORMALIZADO
    FROM DIG_DOC_R62 p WHERE p.TP_PERSONA <> 'PF'
)
SELECT CUIT_NORMALIZADO, COUNT(*) AS cantidad FROM juridicas
WHERE CUIT_NORMALIZADO IS NOT NULL GROUP BY CUIT_NORMALIZADO
ORDER BY cantidad DESC FETCH FIRST 20 ROWS ONLY;
```
**Guardado:** reveló `CUIT='0'` con 11.119 registros (placeholder).

### Query 3 — Detalle con muestra limitada (ROWNUM para evitar overflow de LISTAGG)
```sql
WITH juridicas AS (
    SELECT p.ID_FORMULARIO, p.NM_RAZON_SOCIAL,
        NVL(NULLIF(TRIM(TO_CHAR(p.NU_CUIL_CUIT)), ''), REGEXP_REPLACE(p.NU_CUIL_CUIT_STR, '[^0-9]', '')) AS CUIT_NORMALIZADO
    FROM DIG_DOC_R62 p WHERE p.TP_PERSONA <> 'PF'
),
conteo AS (
    SELECT CUIT_NORMALIZADO, COUNT(*) AS cantidad_id_formulario FROM juridicas
    WHERE CUIT_NORMALIZADO IS NOT NULL GROUP BY CUIT_NORMALIZADO HAVING COUNT(*) > 1
),
muestra AS (
    SELECT j.CUIT_NORMALIZADO, j.ID_FORMULARIO,
        ROW_NUMBER() OVER (PARTITION BY j.CUIT_NORMALIZADO ORDER BY j.ID_FORMULARIO) AS rn
    FROM juridicas j WHERE j.CUIT_NORMALIZADO IN (SELECT CUIT_NORMALIZADO FROM conteo)
)
SELECT c.CUIT_NORMALIZADO, c.cantidad_id_formulario,
    LISTAGG(CASE WHEN m.rn <= 20 THEN TO_CHAR(m.ID_FORMULARIO) END, ', ') WITHIN GROUP (ORDER BY m.ID_FORMULARIO) AS ids_formulario_muestra_20
FROM conteo c JOIN muestra m ON m.CUIT_NORMALIZADO = c.CUIT_NORMALIZADO
GROUP BY c.CUIT_NORMALIZADO, c.cantidad_id_formulario ORDER BY c.cantidad_id_formulario DESC;
```
**Guardado:** listado completo de CUIT duplicados; confirmó `30999078040`(563) como segundo mayor cluster.

### Query 4 — Clasificación final (sin CUIT / CUIT inválido / duplicado real)
```sql
WITH juridicas AS (
    SELECT p.ID_FORMULARIO,
        NVL(NULLIF(TRIM(TO_CHAR(p.NU_CUIL_CUIT)), ''), REGEXP_REPLACE(p.NU_CUIL_CUIT_STR, '[^0-9]', '')) AS CUIT_NORMALIZADO
    FROM DIG_DOC_R62 p WHERE p.TP_PERSONA <> 'PF'
),
clasificado AS (
    SELECT ID_FORMULARIO, CUIT_NORMALIZADO,
        CASE WHEN CUIT_NORMALIZADO IS NULL THEN 'SIN_CUIT'
             WHEN LENGTH(CUIT_NORMALIZADO) <> 11 THEN 'CUIT_INVALIDO'
             ELSE 'VALIDO' END AS clasificacion
    FROM juridicas
),
conteo_validos AS (
    SELECT CUIT_NORMALIZADO, COUNT(*) AS cant_ids FROM clasificado
    WHERE clasificacion = 'VALIDO' GROUP BY CUIT_NORMALIZADO
)
SELECT (SELECT COUNT(*) FROM clasificado WHERE clasificacion = 'SIN_CUIT') AS personas_sin_cuit,
    (SELECT COUNT(*) FROM clasificado WHERE clasificacion = 'CUIT_INVALIDO') AS personas_cuit_invalido,
    (SELECT COUNT(*) FROM conteo_validos WHERE cant_ids > 1) AS grupos_cuit_duplicado,
    (SELECT NVL(SUM(cant_ids - 1),0) FROM conteo_validos WHERE cant_ids > 1) AS registros_redundantes_cuit
FROM dual;
```
**Guardado (usado en el informe, pendiente de re-corrección):** sin_cuit=12.307, cuit_inválido=11.593, grupos=5.803, redundantes=13.295.
> Nota: este número todavía no excluye el placeholder `30999078040` (CUIT válido en longitud pero usado como comodín). Pendiente de recalcular.

### Query 5 — Top 10 CUIT + razones sociales distintas
*Intento con FETCH FIRST en CTE falló (ORA-00907); corregido con ROWNUM.*
```sql
WITH juridicas AS (
    SELECT p.*, NVL(NULLIF(TRIM(TO_CHAR(p.NU_CUIL_CUIT)), ''), REGEXP_REPLACE(p.NU_CUIL_CUIT_STR, '[^0-9]', '')) AS CUIT_NORMALIZADO
    FROM DIG_DOC_R62 p WHERE p.TP_PERSONA <> 'PF'
),
top_cuits AS (
    SELECT CUIT_NORMALIZADO, cnt FROM (
        SELECT CUIT_NORMALIZADO, COUNT(*) AS cnt FROM juridicas
        WHERE LENGTH(CUIT_NORMALIZADO) = 11 GROUP BY CUIT_NORMALIZADO ORDER BY cnt DESC
    ) WHERE ROWNUM <= 10
)
SELECT t.CUIT_NORMALIZADO, t.cnt AS total_registros,
    (SELECT COUNT(DISTINCT j.NM_RAZON_SOCIAL) FROM juridicas j WHERE j.CUIT_NORMALIZADO = t.CUIT_NORMALIZADO) AS razones_sociales_distintas
FROM top_cuits t ORDER BY t.cnt DESC;
```
**Guardado:** confirmó que `30999078040` (563 registros/31 razones distintas) es un CUIT "cajón de sastre", no una empresa real.

### Query 6 — CUIT con pocas razones sociales distintas (candidatos a duplicado genuino)
```sql
WITH juridicas AS (
    SELECT p.ID_FORMULARIO, p.NM_RAZON_SOCIAL,
        NVL(NULLIF(TRIM(TO_CHAR(p.NU_CUIL_CUIT)), ''), REGEXP_REPLACE(p.NU_CUIL_CUIT_STR, '[^0-9]', '')) AS CUIT_NORMALIZADO
    FROM DIG_DOC_R62 p WHERE p.TP_PERSONA <> 'PF'
),
resumen AS (
    SELECT CUIT_NORMALIZADO, COUNT(*) AS total_registros, COUNT(DISTINCT NM_RAZON_SOCIAL) AS razones_distintas
    FROM juridicas WHERE LENGTH(CUIT_NORMALIZADO) = 11 GROUP BY CUIT_NORMALIZADO HAVING COUNT(*) > 1
)
SELECT * FROM (
    SELECT CUIT_NORMALIZADO, total_registros, razones_distintas FROM resumen
    WHERE razones_distintas <= 3 ORDER BY total_registros DESC
) WHERE ROWNUM <= 15;
```
**Guardado:** `30716442086` (32 registros/2 razones) como mejor candidato → MAREU S.A.S.

### Query 7 — Detalle completo MAREU S.A.S. (para el Anexo I)
```sql
SELECT p.ID_FORMULARIO, p.NM_RAZON_SOCIAL, p.TP_SOCIETARIO, p.NU_CUIL_CUIT, p.NU_CUIL_CUIT_STR,
       p.DS_EMAIL, p.NU_CELULAR, p.NU_TELEFONO, p.DS_CALLE, p.DS_NUMERO, p.CD_LOCALIDAD,
       p.CD_USER_STORE, p.DT_STORE, p.CD_USER_LAST_UPDATE, p.DT_LAST_UPDATE
FROM DIG_DOC_R62 p
WHERE p.TP_PERSONA <> 'PF'
  AND NVL(NULLIF(TRIM(TO_CHAR(p.NU_CUIL_CUIT)), ''), REGEXP_REPLACE(p.NU_CUIL_CUIT_STR, '[^0-9]', '')) = '30716442086'
ORDER BY p.ID_FORMULARIO;
```
**Guardado:** los 32 registros de MAREU S.A.S. (CUIT 30-71644208-6), usados en el Anexo I.

### Query 8 — Duplicados por razón social (independiente del CUIT)
```sql
WITH juridicas AS (
    SELECT p.ID_FORMULARIO, p.NM_RAZON_SOCIAL,
        REGEXP_REPLACE(UPPER(TRIM(p.NM_RAZON_SOCIAL)), '[^A-Z0-9]', '') AS RAZON_NORM,
        NVL(NULLIF(TRIM(TO_CHAR(p.NU_CUIL_CUIT)), ''), REGEXP_REPLACE(p.NU_CUIL_CUIT_STR, '[^0-9]', '')) AS CUIT_NORMALIZADO
    FROM DIG_DOC_R62 p WHERE p.TP_PERSONA <> 'PF' AND p.NM_RAZON_SOCIAL IS NOT NULL
),
resumen AS (
    SELECT RAZON_NORM, MAX(NM_RAZON_SOCIAL) AS ejemplo_nombre, COUNT(*) AS total_registros,
        COUNT(DISTINCT CUIT_NORMALIZADO) AS cuits_distintos
    FROM juridicas WHERE LENGTH(RAZON_NORM) >= 5 GROUP BY RAZON_NORM HAVING COUNT(DISTINCT CUIT_NORMALIZADO) > 1
)
SELECT * FROM (SELECT * FROM resumen ORDER BY cuits_distintos DESC, total_registros DESC) WHERE ROWNUM <= 20;
```
**Guardado:** reveló el Instituto Provincial de la Vivienda, Provincia de Mendoza, Dirección General de Escuelas, REIG SA, etc. — casos invisibles al análisis por CUIT.

### Query 9 — Distribución de CUIT del Instituto Provincial de la Vivienda (verificación)
```sql
WITH juridicas AS (
    SELECT p.ID_FORMULARIO,
        NVL(NULLIF(TRIM(TO_CHAR(p.NU_CUIL_CUIT)), ''), REGEXP_REPLACE(p.NU_CUIL_CUIT_STR, '[^0-9]', '')) AS CUIT_NORMALIZADO
    FROM DIG_DOC_R62 p WHERE p.TP_PERSONA <> 'PF'
      AND REGEXP_REPLACE(UPPER(TRIM(p.NM_RAZON_SOCIAL)), '[^A-Z0-9]', '') = 'INSTITUTOPROVINCIALDELAVIVIENDA'
)
SELECT CUIT_NORMALIZADO, COUNT(*) AS cantidad FROM juridicas GROUP BY CUIT_NORMALIZADO ORDER BY cantidad DESC;
```
**Guardado:** confirmó que 529/892 usan el placeholder `30999078040`; descartado como caso nuevo para el anexo.

### Query 10 — Detalle REIG SA (candidato evaluado, no incorporado al anexo)
```sql
SELECT p.ID_FORMULARIO, p.NM_RAZON_SOCIAL, p.TP_SOCIETARIO, p.NU_CUIL_CUIT, p.NU_CUIL_CUIT_STR,
       p.CD_USER_STORE, p.DT_STORE
FROM DIG_DOC_R62 p WHERE p.TP_PERSONA <> 'PF'
  AND REGEXP_REPLACE(UPPER(TRIM(p.NM_RAZON_SOCIAL)), '[^A-Z0-9]', '') = 'REIGSA'
ORDER BY p.ID_FORMULARIO;
```
**Guardado:** 5 registros, 5 CUIT distintos (100% de las cargas con CUIT diferente). Descartado por tener menos registros que MAREU.

### Query 11 y 12 — Verificación de que MAREU no tiene registros "ocultos"
```sql
-- Por nombre exacto normalizado, viendo distribución de CUIT
WITH juridicas AS (
    SELECT p.ID_FORMULARIO,
        NVL(NULLIF(TRIM(TO_CHAR(p.NU_CUIL_CUIT)), ''), REGEXP_REPLACE(p.NU_CUIL_CUIT_STR, '[^0-9]', '')) AS CUIT_NORMALIZADO
    FROM DIG_DOC_R62 p WHERE p.TP_PERSONA <> 'PF'
      AND REGEXP_REPLACE(UPPER(TRIM(p.NM_RAZON_SOCIAL)), '[^A-Z0-9]', '') = 'MAREUSAS'
)
SELECT CUIT_NORMALIZADO, COUNT(*) AS cantidad FROM juridicas GROUP BY CUIT_NORMALIZADO ORDER BY cantidad DESC;

-- Búsqueda amplia por substring, sin exigir sufijo societario ni CUIT
SELECT p.ID_FORMULARIO, p.NM_RAZON_SOCIAL, p.TP_SOCIETARIO, p.NU_CUIL_CUIT, p.NU_CUIL_CUIT_STR,
       p.CD_USER_STORE, p.DT_STORE
FROM DIG_DOC_R62 p WHERE p.TP_PERSONA <> 'PF' AND UPPER(TRIM(p.NM_RAZON_SOCIAL)) LIKE '%MAREU%'
ORDER BY p.ID_FORMULARIO;
```
**Guardado:** confirmado, los mismos 32 registros en ambos casos — no hay variantes adicionales de MAREU.

---

## 3.3 Integridad matrícula-titular

### Query 1 — % de titularidad inválido (versión inicial, sin filtrar por NU_MATRICULA)
*Superado.*
```sql
SELECT b2.ID_MATRICULA, COUNT(*) AS cantidad_titulares,
    ROUND(SUM(b2.NU_NUMERADOR / NULLIF(b2.NU_DENOMINADOR, 0)), 4) AS suma_porcentaje
FROM DIG_DOC_R00_B2 b2
WHERE b2.NU_DENOMINADOR IS NOT NULL AND b2.NU_DENOMINADOR <> 0
GROUP BY b2.ID_MATRICULA
HAVING ROUND(SUM(b2.NU_NUMERADOR / NULLIF(b2.NU_DENOMINADOR, 0)), 4) <> 1
ORDER BY suma_porcentaje DESC;
```

### Query 2 — Resumen inicial (% inválido + sin titular), sin filtrar por NU_MATRICULA
*Superado.*
```sql
SELECT
    (SELECT COUNT(*) FROM (
        SELECT b2.ID_MATRICULA FROM DIG_DOC_R00_B2 b2
        WHERE b2.NU_DENOMINADOR IS NOT NULL AND b2.NU_DENOMINADOR <> 0
        GROUP BY b2.ID_MATRICULA
        HAVING ROUND(SUM(b2.NU_NUMERADOR / NULLIF(b2.NU_DENOMINADOR, 0)), 4) <> 1
    )) AS matriculas_porcentaje_invalido,
    (SELECT COUNT(*) FROM DIG_DOC_R00 r
        WHERE NOT EXISTS (SELECT 1 FROM DIG_DOC_R00_B2 b2 WHERE b2.ID_MATRICULA = r.ID_MATRICULA)
    ) AS matriculas_sin_titular
FROM dual;
```
**Guardado (superado):** 344 / 182.395.

### Query 3 y 4 — Total de matrículas y desglose por estado de las "sin titular"
*Superado.*
```sql
SELECT COUNT(*) AS total_matriculas FROM DIG_DOC_R00;

SELECT r.CD_ESTADO, COUNT(*) AS cantidad
FROM DIG_DOC_R00 r
WHERE NOT EXISTS (SELECT 1 FROM DIG_DOC_R00_B2 b2 WHERE b2.ID_MATRICULA = r.ID_MATRICULA)
GROUP BY r.CD_ESTADO ORDER BY cantidad DESC;
```
**Guardado (superado):** total=800.341; MIG 165.295 / BAJ 15.139 / ACT 1.824 / CRE 137.

### Query 5 — Chequeo del usuario: ¿NU_MATRICULA siempre está cargado?
Este query disparó la corrección de todo el punto 3.3.
```sql
SELECT COUNT(*) AS total_filas, COUNT(NU_MATRICULA) AS total_con_matricula,
    COUNT(*) - COUNT(NU_MATRICULA) AS filas_sin_matricula
FROM DIG_DOC_R00;
```
**Guardado:** total=800.347, con matrícula=**523.058**, sin matrícula=277.289.

### Query 6 — Muestra de filas sin NU_MATRICULA
*Intento con FETCH FIRST falló (ORA-00933); corregido con ROWNUM.*
```sql
SELECT * FROM DIG_DOC_R00 WHERE NU_MATRICULA IS NULL AND ROWNUM <= 20
```
**Guardado:** confirmó que son inmuebles del sistema legado (Tomo/Folio), sin `DS_INMUEBLE` ni ubicación cargada.

### Query 7 y 8 — Desglose por estado, con y sin NU_MATRICULA
```sql
SELECT CD_ESTADO, COUNT(*) AS cantidad FROM DIG_DOC_R00 WHERE NU_MATRICULA IS NULL GROUP BY CD_ESTADO ORDER BY cantidad DESC;
SELECT CD_ESTADO, COUNT(*) AS cantidad FROM DIG_DOC_R00 WHERE NU_MATRICULA IS NOT NULL GROUP BY CD_ESTADO ORDER BY cantidad DESC;
```
**Guardado:** sin matrícula → MIG 275.230 / BAJ 1.799 / CRE 260 (ningún ACT); con matrícula → MIG 267.019 / ACT 242.291 / BAJ 13.356 / CRE 394.

### Query 9 — Matrículas sin titular, recalculado (definitivo)
```sql
SELECT COUNT(*) AS matriculas_sin_titular
FROM DIG_DOC_R00 r
WHERE r.NU_MATRICULA IS NOT NULL
AND NOT EXISTS (SELECT 1 FROM DIG_DOC_R00_B2 b2 WHERE b2.ID_MATRICULA = r.ID_MATRICULA);
```
**Guardado (definitivo): 40.831.**

### Query 10 — Desglose por estado (definitivo)
```sql
SELECT r.CD_ESTADO, COUNT(*) AS cantidad
FROM DIG_DOC_R00 r
WHERE r.NU_MATRICULA IS NOT NULL
AND NOT EXISTS (SELECT 1 FROM DIG_DOC_R00_B2 b2 WHERE b2.ID_MATRICULA = r.ID_MATRICULA)
GROUP BY r.CD_ESTADO ORDER BY cantidad DESC;
```
**Guardado (definitivo): MIG 25.601 / BAJ 13.345 / ACT 1.825 / CRE 60.**

### Query 11 — % de titularidad inválido, recalculado (definitivo)
```sql
SELECT COUNT(*) AS matriculas_porcentaje_invalido
FROM (
    SELECT b2.ID_MATRICULA
    FROM DIG_DOC_R00_B2 b2
    JOIN DIG_DOC_R00 r ON r.ID_MATRICULA = b2.ID_MATRICULA
    WHERE r.NU_MATRICULA IS NOT NULL
      AND b2.NU_DENOMINADOR IS NOT NULL AND b2.NU_DENOMINADOR <> 0
    GROUP BY b2.ID_MATRICULA
    HAVING ROUND(SUM(b2.NU_NUMERADOR / NULLIF(b2.NU_DENOMINADOR, 0)), 4) <> 1
);
```
**Guardado (definitivo): 309.**

---

## Pendientes

1. Actualizar el informe principal (`Informe_Estado_Base_SIRCLAN.docx`) con el número definitivo de personas físicas: **162.225** registros redundantes (en vez de 169.315).
2. Recalcular el KPI de personas jurídicas excluyendo el placeholder `30999078040` (y sus variantes de typo), ya que el 13.295 actual todavía lo incluye.
