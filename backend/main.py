from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import psycopg2
import psycopg2.extras
import os
import json
from typing import Any, Optional
from datetime import datetime, date
from decimal import Decimal

app = FastAPI(title="QueryForge API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

DB_CONFIG = {
    "host": os.getenv("DB_HOST", "db"),
    "port": int(os.getenv("DB_PORT", 5432)),
    "dbname": os.getenv("DB_NAME", "queryforge"),
    "user": os.getenv("DB_USER", "forge"),
    "password": os.getenv("DB_PASSWORD", "forge_secret"),
}


def get_connection():
    return psycopg2.connect(**DB_CONFIG)


def serialize_value(val: Any) -> Any:
    """Make psycopg2 types JSON-serializable."""
    if isinstance(val, (datetime, date)):
        return val.isoformat()
    if isinstance(val, Decimal):
        return float(val)
    if isinstance(val, memoryview):
        return val.tobytes().decode("utf-8", errors="replace")
    return val


class QueryRequest(BaseModel):
    sql: str
    params: Optional[list] = None


class QueryResult(BaseModel):
    columns: list[str]
    rows: list[list[Any]]
    row_count: int
    execution_time_ms: float
    query_type: str
    message: Optional[str] = None


# Maps schema names to the SQL source file that creates them
SCHEMA_SOURCE_MAP = {
    "public": "seed.sql",
    "dw": "02_dw.sql",
    "forja": "03_forjaImperial.sql",
}

# System schemas to exclude from listings
SYSTEM_SCHEMAS = ("pg_catalog", "information_schema", "pg_toast")


@app.get("/health")
def health():
    try:
        conn = get_connection()
        conn.close()
        return {"status": "ok", "db": "connected"}
    except Exception as e:
        raise HTTPException(status_code=503, detail=str(e))


@app.post("/query", response_model=QueryResult)
def run_query(req: QueryRequest):
    start = datetime.now()
    sql = req.sql.strip()
    query_type = sql.split()[0].upper() if sql else "UNKNOWN"

    try:
        conn = get_connection()
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        try:
            if req.params:
                cur.execute(sql, req.params)
            else:
                cur.execute(sql.replace('%', '%%'))

            elapsed = (datetime.now() - start).total_seconds() * 1000

            if query_type == "SELECT" or query_type == "WITH":
                raw_rows = cur.fetchall()
                columns = list(raw_rows[0].keys()) if raw_rows else (
                    [desc[0] for desc in cur.description] if cur.description else []
                )
                rows = [
                    [serialize_value(row[col]) for col in columns]
                    for row in raw_rows
                ]
                conn.commit()
                return QueryResult(
                    columns=columns,
                    rows=rows,
                    row_count=len(rows),
                    execution_time_ms=round(elapsed, 2),
                    query_type=query_type,
                )
            else:
                affected = cur.rowcount
                conn.commit()
                return QueryResult(
                    columns=[],
                    rows=[],
                    row_count=affected,
                    execution_time_ms=round(elapsed, 2),
                    query_type=query_type,
                    message=f"{query_type} executed. {affected} row(s) affected.",
                )

        except Exception as e:
            conn.rollback()
            raise HTTPException(status_code=400, detail=str(e))
        finally:
            cur.close()
            conn.close()

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/schemas")
def list_schemas():
    try:
        conn = get_connection()
        cur = conn.cursor()
        cur.execute("""
            SELECT s.schema_name, COUNT(t.table_name) AS table_count
            FROM information_schema.schemata s
            LEFT JOIN information_schema.tables t
                ON t.table_schema = s.schema_name
            WHERE s.schema_name NOT IN %s
              AND s.schema_name NOT LIKE 'pg_%%'
            GROUP BY s.schema_name
            ORDER BY s.schema_name;
        """, (SYSTEM_SCHEMAS,))
        schemas = [
            {
                "name": row[0],
                "source_file": SCHEMA_SOURCE_MAP.get(row[0], "unknown"),
                "table_count": row[1],
            }
            for row in cur.fetchall()
        ]
        cur.close()
        conn.close()
        return {"schemas": schemas}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/tables")
def list_tables(schema: Optional[str] = None):
    try:
        conn = get_connection()
        cur = conn.cursor()
        if schema:
            cur.execute("""
                SELECT table_name, table_type, table_schema
                FROM information_schema.tables
                WHERE table_schema = %s
                ORDER BY table_name;
            """, (schema,))
        else:
            cur.execute("""
                SELECT table_name, table_type, table_schema
                FROM information_schema.tables
                WHERE table_schema NOT IN %s
                  AND table_schema NOT LIKE 'pg_%%'
                ORDER BY table_schema, table_name;
            """, (SYSTEM_SCHEMAS,))
        tables = [{"name": row[0], "type": row[1], "schema": row[2]} for row in cur.fetchall()]
        cur.close()
        conn.close()
        return {"tables": tables}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/tables/{table_name}/schema")
def table_schema(table_name: str, schema: str = "public"):
    try:
        conn = get_connection()
        cur = conn.cursor()
        cur.execute("""
            SELECT column_name, data_type, is_nullable, column_default
            FROM information_schema.columns
            WHERE table_schema = %s AND table_name = %s
            ORDER BY ordinal_position;
        """, (schema, table_name))
        cols = [
            {"name": r[0], "type": r[1], "nullable": r[2], "default": r[3]}
            for r in cur.fetchall()
        ]
        cur.close()
        conn.close()
        return {"table": table_name, "schema": schema, "columns": cols}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/tables/{table_name}/preview")
def table_preview(table_name: str, schema: str = "public", limit: int = 20):
    safe_name = "".join(c for c in table_name if c.isalnum() or c == "_")
    safe_schema = "".join(c for c in schema if c.isalnum() or c == "_")
    return run_query(QueryRequest(sql=f'SELECT * FROM "{safe_schema}"."{safe_name}" LIMIT {limit}'))
