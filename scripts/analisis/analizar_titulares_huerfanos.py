"""
Análisis de patrones de las titularidades ACTIVAS (DIG_DOC_R00_B2) de personas
físicas que apuntan a un ID_MATRICULA inexistente en DIG_DOC_R00.

Entrada:
  docs/Titulares_activos_con_matricula_inexistente.csv   (volcado del usuario, solo lectura)
  scripts/out/titularidad_huerfana_cruces_2026-09-24_bloque2.csv
      (sale de scripts/queries/titularidad_huerfana_cruces.sql — opcional)
  scripts/out/titularidad_huerfana_clave_alternativa_2026-09-24_bloque2.csv
      (sale de scripts/queries/titularidad_huerfana_clave_alternativa.sql — opcional)

Salida (scripts/out/):
  reporte_patrones_titulares_huerfanos_<fecha>.md
  titulares_huerfanos_clasificados_<fecha>.csv   (BOM UTF-8, separador ';')

Uso:  python scripts/analisis/analizar_titulares_huerfanos.py
Requiere pandas. Gemelo sin dependencias: analizar_titulares_huerfanos.js (misma lógica).
"""
from datetime import date
from pathlib import Path

import pandas as pd

RAIZ = Path(__file__).resolve().parents[2]
CSV_ORIGEN = RAIZ / "docs" / "Titulares_activos_con_matricula_inexistente.csv"
CSV_CRUCES = RAIZ / "scripts" / "out" / "titularidad_huerfana_cruces_2026-09-24_bloque2.csv"
CSV_CLAVE = RAIZ / "scripts" / "out" / "titularidad_huerfana_clave_alternativa_2026-09-24_bloque2.csv"
OUT = RAIZ / "scripts" / "out"
HOY = date.today().isoformat()

# Rangos de ID_MATRICULA que existen en DIG_DOC_R00 (bloque 1 de
# titularidad_huerfana_clave_alternativa.sql, 24/09/2026).
MAX_ID_R00 = 6_396_110


def banda_id(i: int) -> str:
    if i <= 253_249:
        return "A - rango bajo con R00 (hueco)"
    if i < 1_400_001:
        return "B - 253.250 a 1.400.000 (rango sin ninguna fila en R00)"
    if i <= 1_736_177:
        return "C - 1,4M a 1,74M (hueco)"
    if i < 5_000_000:
        return "D - 1,74M a 5M (rango sin R00)"
    if i <= MAX_ID_R00:
        return "E - 5M a 6,4M (hueco, rango actual)"
    return "F - mayor al máximo ID (formato NU_MATRICULA)"


def md_tabla(df: pd.DataFrame) -> str:
    cols = [str(c) for c in df.columns]
    filas = ["| " + " | ".join(cols) + " |", "|" + "---|" * len(cols)]
    for _, r in df.iterrows():
        filas.append("| " + " | ".join("" if pd.isna(v) else str(v) for v in r.values) + " |")
    return "\n".join(filas)


def conteo(serie: pd.Series, nombre: str) -> pd.DataFrame:
    t = serie.value_counts(dropna=False).rename_axis(nombre).reset_index(name="FILAS")
    t["%"] = (t["FILAS"] / t["FILAS"].sum() * 100).round(1)
    return t


def cargar() -> pd.DataFrame:
    df = pd.read_csv(CSV_ORIGEN, dtype=str, keep_default_na=False, encoding="utf-8-sig")
    # El volcado trae columnas repetidas (pandas les agrega ".1"): la primera es de
    # B2, la segunda de R62 / repetición de B2.
    df = df.rename(columns={
        "CD_USER_STORE": "CD_USER_STORE_B2", "CD_USER_STORE.1": "CD_USER_STORE_R62",
        "CD_SITUACION.1": "CD_SITUACION_DUP",
    })
    df["ID_MATRICULA_N"] = df["ID_MATRICULA"].astype("int64")
    df["DT_ALTA_TS"] = pd.to_datetime(df["DT_ALTA"].str[:19], errors="coerce")
    df["TM_DESDE_TS"] = pd.to_datetime(df["TM_DESDE"].str[:19], errors="coerce")
    df["_KEY"] = (df["ID_MATRICULA"] + "|" + df["CD_PERSONA"] + "|" +
                  df["DT_ALTA"].str[:19] + "|" + df["NU_CASO_ORIGEN"])
    df["_N"] = df.groupby("_KEY").cumcount()

    if CSV_CRUCES.exists():
        x = pd.read_csv(CSV_CRUCES, sep=";", dtype=str, keep_default_na=False, encoding="utf-8-sig")
        x["_KEY"] = (x["ID_MATRICULA"] + "|" + x["CD_PERSONA"] + "|" +
                     x["DT_ALTA"] + "|" + x["NU_CASO_ORIGEN"])
        x["_N"] = x.groupby("_KEY").cumcount()
        keep = ["_KEY", "_N", "NU_SEQUENCE", "MIG_FHPI_ID", "PERSONA_EN_MAT_EXISTENTE",
                "DOC_EN_MAT_EXISTENTE", "CASO_EN_MAT_EXISTENTE", "CASO_ID_MAT_EXISTENTE",
                "ID_ES_UN_NU_MATRICULA", "FILAS_B4_MISMO_ID"]
        df = df.merge(x[keep], on=["_KEY", "_N"], how="left", validate="one_to_one")
    if CSV_CLAVE.exists():
        c = pd.read_csv(CSV_CLAVE, sep=";", dtype=str, keep_default_na=False, encoding="utf-8-sig")
        df = df.merge(c[["ID_MATRICULA", "CD_PERSONA", "DOC_TITULAR_EN_CANDIDATA", "ID_CANDIDATA"]],
                      on=["ID_MATRICULA", "CD_PERSONA"], how="left", validate="many_to_one")
    for col in ["PERSONA_EN_MAT_EXISTENTE", "DOC_EN_MAT_EXISTENTE", "CASO_EN_MAT_EXISTENTE",
                "ID_ES_UN_NU_MATRICULA", "FILAS_B4_MISMO_ID", "DOC_TITULAR_EN_CANDIDATA"]:
        if col in df:
            df[col] = pd.to_numeric(df[col], errors="coerce").fillna(0).astype(int)
    return df


def marcar_regrabados(df: pd.DataFrame) -> pd.DataFrame:
    """Dentro de cada (matrícula, persona) elige la fila 'original' y marca el resto
    como copia. Original = la que tiene NU_CASO_ORIGEN; si ninguna o varias, la de
    DT_ALTA más vieja."""
    df = df.sort_values(["ID_MATRICULA_N", "CD_PERSONA", "DT_ALTA_TS"], na_position="first")
    df["_TIENE_CASO"] = (df["NU_CASO_ORIGEN"] != "").astype(int)
    g = df.groupby(["ID_MATRICULA", "CD_PERSONA"], sort=False)
    df["FILAS_MISMA_MAT_PERSONA"] = g["CD_PERSONA"].transform("size")
    orden = df.sort_values(["_TIENE_CASO", "DT_ALTA_TS"], ascending=[False, True], na_position="last")
    orig_idx = orden.groupby(["ID_MATRICULA", "CD_PERSONA"]).head(1).index
    df["ES_ORIGINAL"] = df.index.isin(orig_idx)
    orig = df.loc[orig_idx, ["ID_MATRICULA", "CD_PERSONA", "DT_ALTA_TS", "CD_USER_STORE_B2"]]
    orig = orig.rename(columns={"DT_ALTA_TS": "_ALTA_ORIG", "CD_USER_STORE_B2": "_USER_ORIG"})
    df = df.merge(orig, on=["ID_MATRICULA", "CD_PERSONA"], how="left")
    df["MIN_DESDE_ORIGINAL"] = ((df["DT_ALTA_TS"] - df["_ALTA_ORIG"]).dt.total_seconds() / 60).round(1)
    df["MISMO_USUARIO_ORIGINAL"] = df["CD_USER_STORE_B2"] == df["_USER_ORIG"]
    return df


def clasificar(r) -> tuple[str, str]:
    """Heurística propuesta (en orden de precedencia). Devuelve (categoría, acción)."""
    if r.get("ID_ES_UN_NU_MATRICULA", 0) > 0 and r.get("DOC_TITULAR_EN_CANDIDATA", 0) > 0:
        return ("1-CLAVE_EQUIVOCADA", "BORRAR: se cargó el NU_MATRICULA como ID; la titularidad ya existe en la matrícula real")
    if r.get("CASO_EN_MAT_EXISTENTE", 0) > 0:
        return ("2-BORRADOR_DE_TRAMITE", "BORRAR tras verificar: el mismo caso terminó creando otra matrícula que sí existe")
    if not r["ES_ORIGINAL"]:
        return ("3-COPIA_REGRABADO", "BORRAR: copia de la misma titularidad en la misma matrícula")
    if pd.isna(r["DT_ALTA_TS"]):
        return ("4-LEGADO_SIN_ALTA", "REVISAR: sin DT_ALTA ni usuario (origen previo al WORKFLOW)")
    if r.get("DOC_EN_MAT_EXISTENTE", 0) > 0:
        return ("5-ORIGINAL_CON_TITULARIDAD_EN_OTRA", "REVISAR (probable borrado): la persona/documento es titular vivo de otra matrícula existente")
    return ("6-ORIGINAL_UNICO", "NO BORRAR: única evidencia de titularidad de esa persona; investigar la matrícula")


def main() -> None:
    df = marcar_regrabados(cargar())
    df["BANDA_ID"] = df["ID_MATRICULA_N"].map(banda_id)
    df["ORIGEN_FILA_B2"] = df.apply(
        lambda r: "MIGRACION (MIG_FHPI_ID)" if r.get("MIG_FHPI_ID", "") != "" else
        ("SIN ALTA / SIN USUARIO" if r["CD_USER_STORE_B2"] == "" else "WORKFLOW (usuario)"), axis=1)
    df[["CATEGORIA", "ACCION"]] = df.apply(lambda r: pd.Series(clasificar(r)), axis=1)

    L = [f"# Patrones — titulares activos PF con matrícula inexistente ({HOY})", "",
         f"Fuente: `{CSV_ORIGEN.relative_to(RAIZ)}` + cruces contra la base de desarrollo.", ""]
    L += ["## 0. Estructura", "",
          f"- Filas: **{len(df)}** · matrículas distintas: **{df.ID_MATRICULA.nunique()}** · "
          f"personas (`CD_PERSONA`): **{df.CD_PERSONA.nunique()}** · documentos: **{df.NU_DOCUMENTO.nunique()}**",
          "- Columnas repetidas en el volcado: `CD_USER_STORE` (B2 vs R62), `CD_SITUACION` "
          "(idéntica), `DESDE` = `DT_DESDE` truncado. Constantes: `TP_PERSONA=PF`, `ELIMINADO=0`.", ""]
    L += ["## 1. Origen", "", md_tabla(conteo(df.ORIGEN_FILA_B2, "ORIGEN_FILA_B2")), "",
          md_tabla(pd.crosstab(df.ORIGEN_FILA_B2, df.CD_USER_STORE_R62).reset_index()), ""]
    L += ["## 2. Distribución temporal (DT_ALTA de la fila B2)", "",
          md_tabla(conteo(df.DT_ALTA_TS.dt.year.astype("Int64").astype(str), "AÑO").sort_values("AÑO")), "",
          "Días con más filas (¿carga en bloque?):", "",
          md_tabla(df.dropna(subset=["DT_ALTA_TS"]).groupby(df.DT_ALTA_TS.dt.date)
                   .agg(FILAS=("CD_PERSONA", "size"), MATRICULAS=("ID_MATRICULA", "nunique"),
                        USUARIOS=("CD_USER_STORE_B2", "nunique"))
                   .sort_values("FILAS", ascending=False).head(10).reset_index()), "",
          "Usuarios (top 10):", "", md_tabla(conteo(df.CD_USER_STORE_B2.replace("", "(vacío)"), "USUARIO").head(10)), ""]
    grupos = df.groupby(["ID_MATRICULA", "CD_PERSONA"]).size()
    copias = df[~df.ES_ORIGINAL]
    L += ["## 3. Re-grabado de la misma titularidad", "",
          f"- (matrícula, persona) con más de una fila: **{(grupos > 1).sum()}** de {len(grupos)}; "
          f"filas copia: **{len(copias)}**",
          f"- Copias con el mismo usuario que la original: **{copias.MISMO_USUARIO_ORIGINAL.mean() * 100:.1f}%**",
          f"- Copias sin `NU_CASO_ORIGEN`: **{(copias.NU_CASO_ORIGEN == '').mean() * 100:.1f}%** · "
          f"con `RECIENTE=1`: **{(copias.RECIENTE == '1').mean() * 100:.1f}%**",
          f"- Mediana de minutos entre la original y la copia: **{copias.MIN_DESDE_ORIGINAL.median()}** "
          f"(p90: {copias.MIN_DESDE_ORIGINAL.quantile(.9)})",
          f"- `TM_DESDE` igual a `DT_ALTA` en copias: **{(copias.TM_DESDE_TS == copias.DT_ALTA_TS).mean() * 100:.1f}%** "
          f"vs originales: {(df[df.ES_ORIGINAL].TM_DESDE_TS == df[df.ES_ORIGINAL].DT_ALTA_TS).mean() * 100:.1f}%", ""]
    pd_doc = df.groupby(["ID_MATRICULA", "NU_DOCUMENTO"]).CD_PERSONA.nunique()
    L += ["## 4. Persona duplicada en R62 (mismo documento, distinto CD_PERSONA, misma matrícula)", "",
          md_tabla(conteo(pd_doc, "CD_PERSONA_DISTINTOS")), ""]
    L += ["## 5. Rango del ID_MATRICULA huérfano", "",
          md_tabla(df.groupby("BANDA_ID").agg(FILAS=("CD_PERSONA", "size"),
                                              MATRICULAS=("ID_MATRICULA", "nunique")).reset_index()), ""]
    if "PERSONA_EN_MAT_EXISTENTE" in df:
        L += ["## 6. Cruces contra la base", "",
              f"- Persona (`CD_PERSONA`) titular viva en otra matrícula existente: **{(df.PERSONA_EN_MAT_EXISTENTE > 0).sum()}** filas",
              f"- Documento titular vivo en otra matrícula existente: **{(df.DOC_EN_MAT_EXISTENTE > 0).sum()}** filas",
              f"- Mismo `NU_CASO_ORIGEN` en una matrícula existente: **{(df.CASO_EN_MAT_EXISTENTE > 0).sum()}** filas",
              f"- ID coincide con un `NU_MATRICULA` real: **{(df.ID_ES_UN_NU_MATRICULA > 0).sum()}** filas "
              f"(y la persona es titular ahí: **{(df.get('DOC_TITULAR_EN_CANDIDATA', 0) > 0).sum()}**)",
              f"- ID huérfano con filas también en B4: **{(df.FILAS_B4_MISMO_ID > 0).sum()}** filas", ""]
    L += ["## 7. Clasificación heurística propuesta", "",
          md_tabla(df.groupby(["CATEGORIA", "ACCION"]).agg(FILAS=("CD_PERSONA", "size"),
                   MATRICULAS=("ID_MATRICULA", "nunique")).reset_index()), ""]

    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / f"reporte_patrones_titulares_huerfanos_{HOY}.md").write_text("\n".join(L), encoding="utf-8")
    cols = ["ID_MATRICULA", "CD_PERSONA", "NU_DOCUMENTO", "NM_APELLIDO", "NM_NOMBRE", "NU_CASO_ORIGEN",
            "DT_ALTA", "CD_USER_STORE_B2", "RECIENTE", "DS_PORCENTAJE", "BANDA_ID", "ORIGEN_FILA_B2",
            "FILAS_MISMA_MAT_PERSONA", "ES_ORIGINAL", "MIN_DESDE_ORIGINAL", "CATEGORIA", "ACCION"]
    df.sort_values(["ID_MATRICULA_N", "CD_PERSONA", "DT_ALTA_TS"])[cols].to_csv(
        OUT / f"titulares_huerfanos_clasificados_{HOY}.csv", sep=";", index=False, encoding="utf-8-sig")
    print("\n".join(L))


if __name__ == "__main__":
    main()
