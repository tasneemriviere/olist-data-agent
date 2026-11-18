"""Charge les CSV Olist dans le schéma RAW de Snowflake.

Pour chaque fichier de data/ :
  1. PUT       : envoi du CSV dans un stage interne (compressé en gzip)
  2. CREATE    : table RAW.<nom> créée à partir de l'en-tête du CSV, colonnes en VARCHAR
  3. COPY INTO : chargement du stage vers la table, avec deux colonnes techniques
                 (_source_file, _loaded_at)

Le typage est volontairement laissé aux modèles dbt de staging : RAW reste une copie
fidèle de la source. Le script est rejouable (CREATE OR REPLACE), ce qui permet de
l'appeler depuis Airflow.

Usage :
    python ingestion/load_raw.py                 # tous les fichiers de data/
    python ingestion/load_raw.py --data-dir ./data
"""

from __future__ import annotations

import argparse
import csv
import logging
import os
import re
import sys
import time
from pathlib import Path

import snowflake.connector
from dotenv import load_dotenv

PROJECT_ROOT = Path(__file__).resolve().parent.parent
RAW_SCHEMA = "RAW"
STAGE = "OLIST_STAGE"
FILE_FORMAT = "OLIST_CSV"

log = logging.getLogger("load_raw")


def table_name_from_file(path: Path) -> str:
    """olist_order_items_dataset.csv -> ORDER_ITEMS"""
    name = path.stem
    name = re.sub(r"^olist_", "", name)
    name = re.sub(r"_dataset$", "", name)
    return name.upper()


def read_header(path: Path) -> list[str]:
    # utf-8-sig retire le BOM présent dans product_category_name_translation.csv
    with path.open(encoding="utf-8-sig", newline="") as f:
        header = next(csv.reader(f))
    columns = [re.sub(r"\W+", "_", col.strip()).upper() for col in header]
    if len(set(columns)) != len(columns):
        raise ValueError(f"Colonnes en double dans {path.name} : {columns}")
    return columns


def connect():
    load_dotenv(PROJECT_ROOT / ".env")
    required = [
        "SNOWFLAKE_ACCOUNT",
        "SNOWFLAKE_USER",
        "SNOWFLAKE_ROLE",
        "SNOWFLAKE_WAREHOUSE",
        "SNOWFLAKE_DATABASE",
        "SNOWFLAKE_PRIVATE_KEY_PATH",
    ]
    missing = [var for var in required if not os.getenv(var)]
    if missing:
        sys.exit(f"Variables manquantes dans .env : {', '.join(missing)}")

    return snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ["SNOWFLAKE_USER"],
        role=os.environ["SNOWFLAKE_ROLE"],
        warehouse=os.environ["SNOWFLAKE_WAREHOUSE"],
        database=os.environ["SNOWFLAKE_DATABASE"],
        schema=RAW_SCHEMA,
        authenticator="SNOWFLAKE_JWT",
        private_key_file=os.path.expanduser(os.environ["SNOWFLAKE_PRIVATE_KEY_PATH"]),
        session_parameters={"QUERY_TAG": "olist_ingestion"},
    )


def setup_stage(cur) -> None:
    cur.execute(f"""
        CREATE FILE FORMAT IF NOT EXISTS {FILE_FORMAT}
          TYPE = CSV
          SKIP_HEADER = 1
          FIELD_OPTIONALLY_ENCLOSED_BY = '"'
          EMPTY_FIELD_AS_NULL = TRUE
          SKIP_BYTE_ORDER_MARK = TRUE
          ENCODING = 'UTF8'
    """)
    cur.execute(f"CREATE STAGE IF NOT EXISTS {STAGE} FILE_FORMAT = {FILE_FORMAT}")


def load_file(cur, path: Path) -> int:
    table = table_name_from_file(path)
    columns = read_header(path)
    start = time.time()

    # 1. Envoi dans le stage
    cur.execute(
        f"PUT 'file://{path.as_posix()}' @{STAGE}/{table}/ "
        "AUTO_COMPRESS = TRUE OVERWRITE = TRUE"
    )

    # 2. Table RAW : tout en texte + colonnes techniques
    col_defs = ",\n  ".join(f"{col} VARCHAR" for col in columns)
    cur.execute(f"""
        CREATE OR REPLACE TABLE {table} (
          {col_defs},
          _SOURCE_FILE VARCHAR,
          _LOADED_AT TIMESTAMP_LTZ
        )
    """)

    # 3. Chargement
    selected = ", ".join(f"${i}" for i in range(1, len(columns) + 1))
    cur.execute(f"""
        COPY INTO {table} ({", ".join(columns)}, _SOURCE_FILE, _LOADED_AT)
        FROM (
          SELECT {selected}, METADATA$FILENAME, CURRENT_TIMESTAMP()
          FROM @{STAGE}/{table}/
        )
        FILE_FORMAT = (FORMAT_NAME = {FILE_FORMAT})
        ON_ERROR = ABORT_STATEMENT
        FORCE = TRUE
    """)

    cur.execute(f"SELECT COUNT(*) FROM {table}")
    rows = cur.fetchone()[0]
    log.info("%-35s %10s lignes  (%.1fs)", f"{RAW_SCHEMA}.{table}", f"{rows:,}", time.time() - start)
    return rows


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--data-dir", type=Path, default=PROJECT_ROOT / "data")
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

    files = sorted(args.data_dir.resolve().glob("*.csv"))
    if not files:
        sys.exit(f"Aucun CSV trouvé dans {args.data_dir}")

    log.info("%d fichiers à charger depuis %s", len(files), args.data_dir)
    conn = connect()
    try:
        with conn.cursor() as cur:
            setup_stage(cur)
            total = sum(load_file(cur, path) for path in files)
        log.info("Terminé : %s lignes chargées dans %d tables", f"{total:,}", len(files))
    finally:
        conn.close()


if __name__ == "__main__":
    main()
