# db-tools — acceso de solo lectura para Claude

`RunQuery.java` corre las queries de `scripts/queries/*.sql` directamente,
reusando el mismo túnel SSH que ya abre DBeaver (jump host).

**Por qué Java y no Node:** se probó primero con `oracledb` (Node) en modo
Thin (JS puro, sin Oracle Instant Client) y falló con `NJS-138: connections
to this database server version are not supported by node-oracledb in Thin
mode` — la base de SIRCLAN es demasiado vieja para ese driver. El JDBC Thin
driver de Oracle (Java, el mismo tipo de driver que usa DBeaver por dentro)
sí soporta esta versión, y no requiere instalar Oracle Instant Client nativo
— es un solo `.jar` puro Java (`lib/ojdbc11.jar`, bajado de Maven Central).

## Setup (una vez)

1. Con DBeaver **conectado**, encontrar el puerto local real del túnel SSH:
   no es necesariamente el 1521 de la pestaña SSH de DBeaver — en esta
   máquina resultó ser otro puerto, encontrado revisando qué puertos tiene
   escuchando el proceso `dbeaver.exe` (`netstat -ano` + `tasklist`).
2. Copiar `.env.example` a `.env` y completarlo con `DB_CONNECT_STRING`
   (`localhost:<puerto real>/<service_name>`), `DB_USER` y `DB_PASSWORD` —
   el mismo usuario que usás en DBeaver. **Nunca commitear `.env` ni pegar su
   contenido en el chat.**
3. Compilar: `javac RunQuery.java`.

⚠️ **El puerto NO es estable entre sesiones.** Cada vez que DBeaver reabre el
túnel SSH (por ejemplo, al reconectar o al cambiar el usuario de la sesión
SSH) puede asignarle un puerto local distinto — pasó el 17/09/2026 (de 10825
a 40008) después de cambiar el usuario SSH. Si `RunQuery` falla con
`ORA-12541: No se puede conectar. No hay ningún listener...`, no es
necesariamente que DBeaver esté desconectado: repetir el paso 1 (`netstat`
+ `tasklist` sobre el PID de `dbeaver.exe`, filtrando por `LISTENING`) y
probar cada puerto candidato hasta encontrar el que responde — dbeaver.exe
tiene varios puertos abiertos por otras razones, no todos son el túnel a
Oracle.

## Uso

Con DBeaver conectado (el túnel abierto):

```
java -cp "lib/ojdbc11.jar;." RunQuery ../queries/censo_matriculas_r00.sql
```

Imprime cada bloque `SELECT`/`WITH` del archivo como tabla Markdown. Ese es el formato
que consume `EvaluadorLote.java`.

Para exportar a CSV en vez de a Markdown:

```
java -cp "lib/ojdbc11.jar;." RunQuery ../queries/loquesea.sql --csv ../out/nombre_salida
```

Escribe un archivo por bloque (`nombre_salida_bloque1.csv`, `_bloque2.csv`, …) y por
stdout deja solo el conteo de filas de cada uno — útil para cruzar el total contra las
cifras de `CLAUDE.md` §3 sin abrir el archivo.

El CSV sale con **BOM UTF-8 y separador `;`**, que es lo que Excel en español necesita
para abrirlo con doble clic sin el asistente de importación y sin romper acentos. Los
valores van comillados según RFC 4180, así que un `DS_INMUEBLE` con `;` o con saltos de
línea incrustados queda contenido en una sola celda.

⚠️ **Al contar filas de esos CSV con `awk`/`grep`, respetar el comillado.** Un campo con
salto de línea ocupa dos líneas físicas y se cuenta de más si se cuentan líneas a secas
(pasó el 18/09 con el export de doble titular: 3.362 filas lógicas en 3.366 líneas
físicas). El conteo autoritativo es el que imprime `RunQuery`.

⚠️ La salida es UTF-8 siempre, en ambos modos. Antes usaba el charset default de Windows
y los acentos de los campos de texto libre salían como `?` al redirigir a un archivo.

⚠️ En esta máquina el `java` del PATH resuelve por default a un JDK Oracle
viejísimo bundleado en `C:\orant\jdk` (versión 1.1), que no sirve para
correr esto. Hay que usar el JDK 21 real
(`/c/Users/mevera/java/jdk-21.0.2/bin/java`) o ajustar el PATH. `javac` sí
resuelve bien porque `orant` no tiene `javac`.

## Guardrails

- `RunQuery` quita los comentarios (todo lo que sigue a `--` en cada línea)
  y recién ahí separa por `;`, y rechaza cualquier statement resultante que
  no empiece con `SELECT` o `WITH` **antes** de conectarse — no depende de
  que el usuario de Oracle tenga permisos de solo lectura a nivel de grants
  (no los tiene, es el mismo usuario de DBeaver, ver CLAUDE.md §0).
- Sigue valiendo todo lo de CLAUDE.md §0: nada de `UPDATE`/`DELETE`/`MERGE`,
  y las salidas van a `scripts/out/` o al scratchpad, nunca a `docs/`.
- Si el túnel de DBeaver se cae (DBeaver desconectado), la conexión falla
  con un error de red — no hay reintentos automáticos ni túnel propio.
- El split de statements por `;` es ingenuo (no entiende `;` dentro de un
  literal de string) — no es un problema para las queries `SELECT` simples
  de este proyecto, pero no usarlo con SQL que tenga literales con `;`.
