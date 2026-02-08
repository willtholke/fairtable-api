import os
from fastapi import FastAPI, Query, HTTPException, Header
from fastapi.middleware.cors import CORSMiddleware
import psycopg2
from psycopg2.extras import RealDictCursor

app = FastAPI(title="Fairtable API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET"],
    allow_headers=["*"],
)

VALID_TABLES = {"tasks", "submissions", "reviews"}

TIMESTAMP_COLUMN = {
    "tasks": "created_at",
    "submissions": "submitted_at",
    "reviews": "reviewed_at",
}


def get_db():
    conn = psycopg2.connect(os.environ["DATABASE_URL"])
    return conn


def verify_api_key(x_api_key: str):
    expected = os.environ.get("FAIRTABLE_API_KEY")
    if not expected or x_api_key != expected:
        raise HTTPException(status_code=401, detail="Invalid API key")


@app.get("/")
def root():
    return {"service": "fairtable-api", "status": "ok"}


@app.get("/records")
def get_records(
    base_id: str = Query(..., description="Tenant identifier (e.g. base_google)"),
    table_name: str = Query(..., description="Table to query: tasks, submissions, reviews"),
    status: str = Query(None, description="Filter by status"),
    assigned_to: int = Query(None, description="Filter by tasker ID (tasks/submissions only)"),
    created_after: str = Query(None, description="Filter records after this ISO timestamp"),
    created_before: str = Query(None, description="Filter records before this ISO timestamp"),
    limit: int = Query(100, ge=1, le=1000),
    offset: int = Query(0, ge=0),
    x_api_key: str = Header(..., alias="X-API-Key"),
):
    verify_api_key(x_api_key)

    if table_name not in VALID_TABLES:
        raise HTTPException(status_code=400, detail=f"Invalid table_name. Must be one of: {', '.join(VALID_TABLES)}")

    ts_col = TIMESTAMP_COLUMN[table_name]

    query = f"SELECT * FROM {table_name} WHERE base_id = %s"
    params: list = [base_id]

    if status:
        query += " AND status = %s"
        params.append(status)

    if assigned_to is not None:
        if table_name == "tasks":
            query += " AND assigned_to = %s"
            params.append(assigned_to)
        elif table_name == "submissions":
            query += " AND submitted_by = %s"
            params.append(assigned_to)

    if created_after:
        query += f" AND {ts_col} >= %s"
        params.append(created_after)

    if created_before:
        query += f" AND {ts_col} <= %s"
        params.append(created_before)

    query += f" ORDER BY {ts_col} DESC LIMIT %s OFFSET %s"
    params.extend([limit, offset])

    conn = get_db()
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(query, params)
            rows = cur.fetchall()
    finally:
        conn.close()

    # Convert datetime objects to ISO strings
    results = []
    for row in rows:
        record = {}
        for key, value in row.items():
            if hasattr(value, "isoformat"):
                record[key] = value.isoformat()
            else:
                record[key] = value
        results.append(record)

    return results
