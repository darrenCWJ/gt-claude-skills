---
name: databricks-data-patterns
description: >
  Read and write patterns for Databricks Lakebase — PostgREST query patterns
  for the Data API (frontend), parameterized queries, transactions, pagination,
  batch operations, and error handling for direct PostgreSQL backends.
  TRIGGER when: databricks-connection and databricks-security are set up;
  writing any SQL query, read, write, upsert, delete, or transaction against
  Databricks/Lakebase; user asks how to query Databricks data; building data
  fetching logic that targets Databricks or Lakebase; implementing pagination,
  batch operations, or error handling for Databricks queries.
  SKIP: connection and security layers not yet in place — invoke those first.
version: 1.0.0
tags: [databricks, lakebase, read, write, patterns, queries, postgrest]
---

# Databricks Data Patterns Skill

## When to Invoke

**Auto-invoke this skill when ANY of these signals appear:**
- `databricks-connection` and `databricks-security` are already set up
- Writing SQL queries, reads, writes, upserts, or deletes against Databricks/Lakebase
- User asks "how do I query Databricks?" or "how do I read/write Lakebase data?"
- Building data-fetching hooks, API routes, or server actions that hit Databricks
- Implementing pagination, batch inserts, transactions, or bulk loads for Databricks
- Handling errors from Databricks SQL or Lakebase Data API responses

**Invoke order**: `databricks-architecture` → `databricks-connection` → `databricks-security` → **`databricks-data-patterns`**

---

## Purpose

Apply correct read/write patterns after connection is established. Covers both
the frontend Data API (PostgREST) and backend direct PostgreSQL paths.

---

## Frontend — Data API Read Patterns (PostgREST)

```typescript
import { tokenManager } from '@/auth/token-manager'

const BASE = import.meta.env.VITE_DATA_API_BASE_URL

async function apiFetch<T>(path: string, params?: Record<string, string>): Promise<T> {
  const token = await tokenManager.getAccessToken()
  const url = new URL(`${BASE}/${path}`)
  if (params) Object.entries(params).forEach(([k, v]) => url.searchParams.set(k, v))
  const res = await fetch(url.toString(), {
    headers: { Authorization: `Bearer ${token}` },
  })
  if (!res.ok) throw new Error(`Data API ${res.status}: ${await res.text()}`)
  return res.json() as Promise<T>
}

// Select specific columns only — never select *
const users = await apiFetch<User[]>('public/users', { select: 'id,name,email' })

// Filter rows (operators: eq, neq, gt, gte, lt, lte, like, ilike, in)
const active = await apiFetch<Order[]>('public/orders', {
  status: 'eq.active',
  created_at: 'gte.2024-01-01',
})

// Cursor-based pagination (preferred over offset for large tables)
const page = await apiFetch<User[]>('public/users', {
  select: 'id,name',
  order: 'id.asc',
  id: `gt.${lastSeenId}`,
  limit: '20',
})

// Embed related table (join)
const orders = await apiFetch<Order[]>('public/orders', {
  select: 'id,total,user:users(name,email)',
})

// Full-text search
const results = await apiFetch<Product[]>('public/products', {
  name: 'ilike.*laptop*',
})
```

---

## Frontend — Data API Write Patterns (PostgREST)

```typescript
const token = await tokenManager.getAccessToken()
const headers = {
  Authorization: `Bearer ${token}`,
  'Content-Type': 'application/json',
  Prefer: 'return=representation',
}

// Insert
const res = await fetch(`${BASE}/public/users`, {
  method: 'POST',
  headers,
  body: JSON.stringify({ name: 'Jane', email: 'jane@example.com' }),
})
const [created] = await res.json() as User[]

// Update — always include a filter, never patch without WHERE
await fetch(`${BASE}/public/users?id=eq.${userId}`, {
  method: 'PATCH',
  headers,
  body: JSON.stringify({ name: 'Jane Smith' }),
})

// Upsert
await fetch(`${BASE}/public/users`, {
  method: 'POST',
  headers: { ...headers, Prefer: 'resolution=merge-duplicates,return=representation' },
  body: JSON.stringify({ id: userId, name: 'Jane', email: 'jane@example.com' }),
})

// Delete — always include a filter, never delete without WHERE
await fetch(`${BASE}/public/users?id=eq.${userId}`, {
  method: 'DELETE',
  headers: { Authorization: `Bearer ${token}` },
})
```

**Rules:**
- Always filter on PATCH and DELETE — unfiltered operations affect every row
- Use `Prefer: return=representation` to get the mutated row without a second request
- Use cursor-based pagination (`id > lastId`) instead of `offset`
- Bulk writes and transactions are not supported via Data API — use a backend

---

## Backend — Read Patterns (PostgreSQL)

```python
# Always use parameterized queries — never format SQL with string concatenation
with get_conn() as conn, conn.cursor() as cur:
    cur.execute("SELECT id, name FROM users WHERE id = %s", (user_id,))
    row = cur.fetchone()

# Cursor-based pagination (OFFSET degrades at scale — avoid it)
with get_conn() as conn, conn.cursor() as cur:
    cur.execute(
        "SELECT id, name FROM users WHERE id > %s ORDER BY id LIMIT %s",
        (last_seen_id, page_size),
    )
    rows = cur.fetchall()

# Batch read by list of IDs
with get_conn() as conn, conn.cursor() as cur:
    cur.execute(
        "SELECT id, name FROM users WHERE id = ANY(%s)",
        (user_ids,),
    )
    rows = cur.fetchall()
```

---

## Backend — Write Patterns (PostgreSQL)

```python
# Single insert with RETURNING
with get_conn() as conn, conn.cursor() as cur:
    cur.execute(
        "INSERT INTO users (name, email) VALUES (%s, %s) RETURNING id",
        (name, email),
    )
    new_id = cur.fetchone()[0]
    conn.commit()

# Transaction — all-or-nothing across multiple statements
with get_conn() as conn:
    try:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO orders (user_id, total) VALUES (%s, %s)", (user_id, total)
            )
            cur.execute(
                "UPDATE inventory SET qty = qty - 1 WHERE product_id = %s", (product_id,)
            )
        conn.commit()
    except Exception:
        conn.rollback()
        raise

# Batch insert — far faster than inserting in a loop
with get_conn() as conn, conn.cursor() as cur:
    cur.executemany(
        "INSERT INTO events (user_id, type, data) VALUES (%s, %s, %s)",
        [(row.user_id, row.type, row.data) for row in events],
    )
    conn.commit()

# Upsert
with get_conn() as conn, conn.cursor() as cur:
    cur.execute(
        """
        INSERT INTO users (id, name, email) VALUES (%s, %s, %s)
        ON CONFLICT (id) DO UPDATE
          SET name  = EXCLUDED.name,
              email = EXCLUDED.email
        """,
        (user_id, name, email),
    )
    conn.commit()

# Bulk load via COPY — fastest for large datasets
from io import StringIO
with get_conn() as conn, conn.cursor() as cur:
    buf = StringIO()
    for row in rows:
        buf.write(f"{row.user_id},{row.type},{row.data}\n")
    buf.seek(0)
    cur.copy_expert("COPY events (user_id, type, data) FROM STDIN CSV", buf)
    conn.commit()
```

---

## Error Handling

**Frontend — retry once on 401:**
```typescript
async function dataApiFetch<T>(path: string, params?: Record<string, string>): Promise<T> {
  try {
    return await apiFetch<T>(path, params)
  } catch (err: unknown) {
    if (err instanceof Error && err.message.includes('401')) {
      await tokenManager.getAccessToken()
      return apiFetch<T>(path, params)
    }
    throw err
  }
}
```

**Backend — handle constraint violations explicitly:**
```python
from psycopg2 import errors

try:
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute(...)
        conn.commit()
except errors.UniqueViolation:
    raise
except errors.ForeignKeyViolation:
    raise
except Exception:
    conn.rollback()
    raise
```

---

## Pattern Quick Reference

| Need | Frontend (Data API) | Backend (PostgreSQL) |
|---|---|---|
| Fetch rows | `GET /schema/table?col=eq.val` | `SELECT ... WHERE col = %s` |
| Paginate | `?order=id.asc&id=gt.X&limit=20` | `WHERE id > %s ORDER BY id LIMIT %s` |
| Insert | `POST /schema/table` | `INSERT ... RETURNING id` |
| Update | `PATCH /schema/table?id=eq.X` | `UPDATE ... WHERE id = %s` |
| Upsert | `POST` + `Prefer: resolution=merge-duplicates` | `INSERT ... ON CONFLICT DO UPDATE` |
| Delete | `DELETE /schema/table?id=eq.X` | `DELETE FROM ... WHERE id = %s` |
| Bulk write | Not supported — use backend | `executemany` or `COPY` |
| Transaction | Not supported — use backend | `conn.commit()` / `conn.rollback()` |
