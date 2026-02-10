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
    expected = os.environ.get("API_KEY")
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

    return [_serialize_row(r) for r in rows]


@app.get("/records/submissions_enriched")
def get_submissions_enriched(
    base_id: str = Query(..., description="Tenant identifier (e.g. base_google)"),
    submitted_by: int = Query(None, description="Filter by tasker ID"),
    created_after: str = Query(None, description="Filter submissions after this ISO timestamp"),
    created_before: str = Query(None, description="Filter submissions before this ISO timestamp"),
    limit: int = Query(1000, ge=1, le=5000),
    offset: int = Query(0, ge=0),
    x_api_key: str = Header(..., alias="X-API-Key"),
):
    verify_api_key(x_api_key)

    query = """
        SELECT
            s.record_id,
            s.base_id,
            s.task_record_id,
            s.submitted_by,
            s.submitted_at,
            s.hours_logged,
            s.status AS submission_status,
            t.task_name,
            t.task_type,
            t.assigned_to,
            t.status AS task_status,
            COALESCE(rev_agg.review_count, 0) AS review_count,
            COALESCE(rev_agg.avg_score, 0) AS avg_score,
            COALESCE(rev_agg.median_score, 0) AS median_score,
            COALESCE(rev_agg.min_score, 0) AS min_score,
            COALESCE(rev_agg.max_score, 0) AS max_score
        FROM submissions s
        JOIN tasks t ON s.task_record_id = t.record_id
        LEFT JOIN LATERAL (
            SELECT
                COUNT(*)::int AS review_count,
                AVG(r.score) AS avg_score,
                PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY r.score) AS median_score,
                MIN(r.score) AS min_score,
                MAX(r.score) AS max_score
            FROM reviews r
            WHERE r.submission_record_id = s.record_id
        ) rev_agg ON TRUE
        WHERE s.base_id = %s
    """
    params: list = [base_id]

    if submitted_by is not None:
        query += " AND s.submitted_by = %s"
        params.append(submitted_by)
    if created_after:
        query += " AND s.submitted_at >= %s"
        params.append(created_after)
    if created_before:
        query += " AND s.submitted_at <= %s"
        params.append(created_before)

    query += " ORDER BY s.submitted_at DESC LIMIT %s OFFSET %s"
    params.extend([limit, offset])

    conn = get_db()
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(query, params)
            rows = cur.fetchall()
    finally:
        conn.close()

    return [_serialize_row(r) for r in rows]


@app.get("/records/reviews_enriched")
def get_reviews_enriched(
    base_id: str = Query(..., description="Tenant identifier (e.g. base_google)"),
    reviewed_by: str = Query(None, description="Filter by reviewer name"),
    created_after: str = Query(None, description="Filter reviews after this ISO timestamp"),
    created_before: str = Query(None, description="Filter reviews before this ISO timestamp"),
    limit: int = Query(1000, ge=1, le=5000),
    offset: int = Query(0, ge=0),
    x_api_key: str = Header(..., alias="X-API-Key"),
):
    verify_api_key(x_api_key)

    query = """
        SELECT
            r.record_id AS review_record_id,
            r.base_id,
            r.submission_record_id,
            r.reviewed_by,
            r.score,
            r.status AS review_status,
            r.comments,
            r.reviewed_at,
            s.record_id AS submission_record_id,
            s.submitted_by,
            s.submitted_at,
            s.hours_logged,
            s.status AS submission_status,
            t.record_id AS task_record_id,
            t.task_name,
            t.task_type,
            t.status AS task_status
        FROM reviews r
        JOIN submissions s ON r.submission_record_id = s.record_id
        JOIN tasks t ON s.task_record_id = t.record_id
        WHERE r.base_id = %s
    """
    params: list = [base_id]

    if reviewed_by:
        query += " AND r.reviewed_by = %s"
        params.append(reviewed_by)
    if created_after:
        query += " AND r.reviewed_at >= %s"
        params.append(created_after)
    if created_before:
        query += " AND r.reviewed_at <= %s"
        params.append(created_before)

    query += " ORDER BY r.reviewed_at DESC LIMIT %s OFFSET %s"
    params.extend([limit, offset])

    conn = get_db()
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(query, params)
            rows = cur.fetchall()
    finally:
        conn.close()

    return [_serialize_row(r) for r in rows]


def _serialize_row(row):
    record = {}
    for key, value in row.items():
        if hasattr(value, "isoformat"):
            record[key] = value.isoformat()
        else:
            record[key] = value
    return record
