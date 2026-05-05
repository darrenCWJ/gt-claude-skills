---
name: databricks-data-patterns
description: >
  Generates project-specific query modules for Databricks Lakebase after
  connection and security are in place. Discovers entities, asks about required
  operations, then writes typed query files using real table names.
  TRIGGER when: databricks-connection and databricks-security are complete;
  user is ready to write data access code against Lakebase.
  SKIP: connection and security layers not yet in place — invoke those first.
version: 3.0.0
tags: [databricks, lakebase, queries, data-access, postgrest, transactions]
---

# Databricks Data Patterns Skill

## Purpose

Generate project-specific query files — not generic examples.
Run after `databricks-connection` and `databricks-security` are complete.

---

## Step 1 — Discover Entities

Scan the project for existing schema files, models, or migrations. Look for:
- `prisma/schema.prisma` — model names
- `models.py`, `models/*.py` — Django or SQLAlchemy model class names
- `db/migrations/` — table names from CREATE TABLE statements
- `types/`, `interfaces/` — existing TypeScript interfaces

If nothing found, ask:

> "What are the main tables or entities in your Lakebase project?
> List them with key columns, e.g.:
> - users (id, name, email, created_at)
> - orders (id, user_id, total, status)"

---

## Step 2 — Identify Required Operations

For each entity, ask:

> "For each entity, which operations do you need?
> 1. Read-only (list + get by ID)
> 2. Full CRUD (read + insert + update + delete)
> 3. Bulk insert
> 4. Multi-table transactions
> 5. Specific queries (describe — e.g. filter by status, search by name)"

---

## Step 3 — Generate Query Files

Use the app type from `.lakebase` to choose the path.

---

### Frontend path → TypeScript query modules

For each entity, generate `lib/api/[entity]-queries.ts` and `types/[entity].ts`.

```typescript
// types/[entity].ts
export interface [Entity] {
  id: number
  [column]: [type]  // fill from actual table schema
}
```

```typescript
// lib/api/[entity]-queries.ts
import { dataApiFetch, dataApiMutate } from '@/lib/lakebase-client'
import type { [Entity] } from '@/types/[entity]'

// List with cursor-based pagination
export async function getAll[Entities](filters?: {
  limit?: number
  afterId?: number
}): Promise<[Entity][]> {
  const params: Record<string, string> = {
    select: 'id,[columns]',
    order: 'id.asc',
    limit: String(filters?.limit ?? 20),
  }
  if (filters?.afterId) params['id'] = `gt.${filters.afterId}`
  return dataApiFetch<[Entity][]>('public/[entity]', params)
}

// Get single record
export async function get[Entity]ById(id: number): Promise<[Entity] | null> {
  const rows = await dataApiFetch<[Entity][]>('public/[entity]', {
    id: `eq.${id}`,
    limit: '1',
  })
  return rows[0] ?? null
}

// Insert — returns the created record
export async function create[Entity](data: Omit<[Entity], 'id'>): Promise<[Entity]> {
  const [created] = await dataApiMutate<[Entity][]>(
    'public/[entity]',
    'POST',
    data,
    'return=representation'
  )
  return created
}

// Update — always filtered, never unguarded PATCH
export async function update[Entity](
  id: number,
  data: Partial<Omit<[Entity], 'id'>>
): Promise<void> {
  await dataApiMutate('public/[entity]?id=eq.' + id, 'PATCH', data)
}

// Delete — always filtered, never unguarded DELETE
export async function delete[Entity](id: number): Promise<void> {
  await dataApiMutate('public/[entity]?id=eq.' + id, 'DELETE')
}
```

**Bulk insert (frontend):**
```typescript
export async function bulkCreate[Entities](
  items: Omit<[Entity], 'id'>[]
): Promise<[Entity][]> {
  return dataApiMutate<[Entity][]>(
    'public/[entity]',
    'POST',
    items,
    'return=representation'
  )
}
```

---

### PostgREST filter operator reference

Use these as values in the `params` object:

| Operator | Meaning | Example |
|---|---|---|
| `eq.value` | = value | `status: 'eq.active'` |
| `neq.value` | ≠ value | `status: 'neq.deleted'` |
| `gt.value` | > value | `id: 'gt.100'` |
| `gte.value` | ≥ value | `created_at: 'gte.2024-01-01'` |
| `lt.value` | < value | `price: 'lt.50'` |
| `lte.value` | ≤ value | `score: 'lte.100'` |
| `like.*term*` | LIKE '%term%' | `name: 'like.*john*'` |
| `ilike.*term*` | ILIKE (case-insensitive) | `email: 'ilike.*@gmail*'` |
| `in.(a,b,c)` | IN list | `status: 'in.(active,pending)'` |
| `is.null` | IS NULL | `deleted_at: 'is.null'` |
| `not.is.null` | IS NOT NULL | `email: 'not.is.null'` |

---

### Frontend error handling

Distinguish error types so the UI shows meaningful messages:

```typescript
// lib/lakebase-client.ts — add this class and update dataApiFetch
export class DataApiError extends Error {
  constructor(public readonly status: number, message: string) {
    super(message)
    this.name = 'DataApiError'
  }
  get isNotFound() { return this.status === 404 }
  get isConflict() { return this.status === 409 }      // unique constraint violated
  get isUnauthorized() { return this.status === 401 }  // token expired
  get isValidation() { return this.status === 422 }    // malformed filter
}

// In dataApiFetch, replace the throw with:
if (!res.ok) {
  const body = await res.text()
  throw new DataApiError(res.status, body)
}
```

Usage:
```typescript
try {
  await createUser({ email })
} catch (e) {
  if (e instanceof DataApiError && e.isConflict) {
    setError('Email already in use')
  } else if (e instanceof DataApiError && e.isUnauthorized) {
    tokenManager.clearTokens()
    router.push('/login')
  } else {
    throw e
  }
}
```

---

### Backend path → Python query modules

For each entity, generate `db/queries/[entity].py`.

```python
# db/queries/[entity].py
from db.connection import get_conn


def get_all_[entities](*, after_id: int = 0, limit: int = 20) -> list[dict]:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, [columns] FROM [entity] WHERE id > %s ORDER BY id LIMIT %s",
                (after_id, limit),
            )
            cols = [d.name for d in cur.description]
            return [dict(zip(cols, row)) for row in cur.fetchall()]


def get_[entity]_by_id([entity]_id: int) -> dict | None:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, [columns] FROM [entity] WHERE id = %s",
                ([entity]_id,),
            )
            row = cur.fetchone()
            if row is None:
                return None
            cols = [d.name for d in cur.description]
            return dict(zip(cols, row))


def create_[entity](data: dict) -> int:
    cols = list(data.keys())
    placeholders = ", ".join(["%s"] * len(cols))
    col_names = ", ".join(cols)
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                f"INSERT INTO [entity] ({col_names}) VALUES ({placeholders}) RETURNING id",
                tuple(data[c] for c in cols),
            )
            new_id: int = cur.fetchone()[0]
        # conn.__exit__ commits here; rolls back on exception
    return new_id


def update_[entity]([entity]_id: int, data: dict) -> None:
    if not data:
        return
    cols = list(data.keys())
    set_clause = ", ".join(f"{c} = %s" for c in cols)
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                f"UPDATE [entity] SET {set_clause} WHERE id = %s",
                (*[data[c] for c in cols], [entity]_id),
            )


def delete_[entity]([entity]_id: int) -> None:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM [entity] WHERE id = %s", ([entity]_id,))
```

---

### Backend — bulk insert (Python)

```python
# db/queries/[entity].py — add this function
from psycopg2.extras import execute_values

def bulk_create_[entities](items: list[dict]) -> None:
    """Insert many rows in a single round-trip."""
    if not items:
        return
    cols = list(items[0].keys())
    col_names = ", ".join(cols)
    with get_conn() as conn:
        with conn.cursor() as cur:
            execute_values(
                cur,
                f"INSERT INTO [entity] ({col_names}) VALUES %s",
                [tuple(item[c] for c in cols) for item in items],
            )
```

---

### Backend — multi-table transactions (Python)

```python
# db/queries/[entity].py — multi-step atomic operation
def create_[parent]_with_[children](
    parent_data: dict,
    children: list[dict],
) -> int:
    """Both inserts succeed or both are rolled back."""
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO [parent] ([cols]) VALUES ([placeholders]) RETURNING id",
                tuple(parent_data.values()),
            )
            parent_id: int = cur.fetchone()[0]

            if children:
                execute_values(
                    cur,
                    "INSERT INTO [child] ([parent]_id, [cols]) VALUES %s",
                    [(parent_id, *tuple(c.values())) for c in children],
                )
        # conn.__exit__ commits atomically; any exception above triggers rollback
    return parent_id
```

---

### Backend — JOIN queries (Python)

Always use parameterized queries — never f-strings for user-supplied values.

```python
def get_[entities]_with_[related](user_id: int) -> list[dict]:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT e.id, e.[col], r.[col] AS [related_col]
                FROM [entity] e
                JOIN [related] r ON r.[entity]_id = e.id
                WHERE e.user_id = %s
                ORDER BY e.id
                """,
                (user_id,),
            )
            cols = [d.name for d in cur.description]
            return [dict(zip(cols, row)) for row in cur.fetchall()]
```

---

## Handoff

> "Data access layer complete. Generated query modules for: [entity list].
>
> Files created:
> [list files written]
>
> All four Databricks setup steps are now done:
> architecture → connection → security → data patterns.
>
> Want help wiring these into your components or API routes?"
