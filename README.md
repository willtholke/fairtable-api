# Fairtable API Documentation

Base URL: `https://fairtable.willtholke.com`

## Authentication

All requests require an API key passed via the `X-API-Key` header.

```bash
curl -H "X-API-Key: YOUR_API_KEY" "https://fairtable.willtholke.com/records?base_id=base_google&table_name=tasks"
```

## Endpoint

### `GET /records`

Single endpoint for all data. Differentiate by `base_id` and `table_name`.

#### Required Parameters

| Param | Description |
|---|---|
| `base_id` | Tenant identifier: `base_google`, `base_xai`, or `base_anthropic` |
| `table_name` | Table to query: `tasks`, `submissions`, or `reviews` |

#### Optional Parameters

| Param | Type | Default | Description |
|---|---|---|---|
| `status` | string | — | Filter by status (values depend on table) |
| `assigned_to` | integer | — | Filter by PHD tasker ID (tasks and submissions only) |
| `created_after` | ISO timestamp | — | Records after this timestamp |
| `created_before` | ISO timestamp | — | Records before this timestamp |
| `limit` | integer | 100 | Results per page (1–1000) |
| `offset` | integer | 0 | Pagination offset |

## Response Shapes

### Tasks (`table_name=tasks`)

```json
{
  "record_id": "rec_2ef008c0d84d",
  "base_id": "base_google",
  "task_name": "Assess pharmacological interaction analysis",
  "task_type": "domain_qa",
  "assigned_to": 8,
  "status": "reviewed",
  "created_at": "2026-02-06T05:03:07.754934",
  "due_date": "2026-02-21"
}
```

Status values: `todo`, `in_progress`, `done`, `reviewed`

### Submissions (`table_name=submissions`)

```json
{
  "record_id": "rec_464bdea675cc",
  "base_id": "base_xai",
  "task_record_id": "rec_7ae43237089b",
  "submitted_by": 5,
  "submitted_at": "2026-02-12T22:14:58.291701",
  "hours_logged": 2.36,
  "status": "pending"
}
```

Status values: `pending`, `approved`, `rejected`

Note: `hours_logged` is in **hours**.

### Reviews (`table_name=reviews`)

```json
{
  "record_id": "rec_9b5de368f8f6",
  "base_id": "base_anthropic",
  "submission_record_id": "rec_f654118ddeb9",
  "reviewed_by": "Soo-Jin Park",
  "score": 66.5,
  "status": "conditional_pass",
  "comments": "Good attempt, needs clarification on key points.",
  "reviewed_at": "2026-02-01T08:40:09.343032"
}
```

Status values: `pass`, `fail`, `conditional_pass`

Note: `score` is 0–100 float. `comments` may be `null`.

## Examples

**Get all Google tasks:**
```bash
curl -H "X-API-Key: YOUR_API_KEY" \
  "https://fairtable.willtholke.com/records?base_id=base_google&table_name=tasks"
```

**Get done tasks for tasker 7:**
```bash
curl -H "X-API-Key: YOUR_API_KEY" \
  "https://fairtable.willtholke.com/records?base_id=base_google&table_name=tasks&status=done&assigned_to=7"
```

**Get xAI submissions after a date:**
```bash
curl -H "X-API-Key: YOUR_API_KEY" \
  "https://fairtable.willtholke.com/records?base_id=base_xai&table_name=submissions&created_after=2025-01-01T00:00:00"
```

**Get Anthropic reviews with pagination:**
```bash
curl -H "X-API-Key: YOUR_API_KEY" \
  "https://fairtable.willtholke.com/records?base_id=base_anthropic&table_name=reviews&limit=50&offset=50"
```

**Python:**
```python
import requests

resp = requests.get(
    "https://fairtable.willtholke.com/records",
    headers={"X-API-Key": "YOUR_API_KEY"},
    params={"base_id": "base_google", "table_name": "tasks", "limit": 10},
)
tasks = resp.json()
```

## Base IDs

| base_id | Customer |
|---|---|
| `base_google` | Google |
| `base_xai` | xAI |
| `base_anthropic` | Anthropic |
