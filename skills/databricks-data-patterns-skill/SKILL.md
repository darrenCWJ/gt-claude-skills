---
name: databricks-data-patterns
description: >
  Generates project-specific query modules for Databricks Lakebase after
  connection and security are in place. Discovers entities, asks about required
  operations, then writes typed query files using real table names.
  TRIGGER when: databricks-connection and databricks-security are complete;
  user is ready to write data access code against Lakebase.
  SKIP: connection and security layers not yet in place — invoke those first.
version: 2.0.0
tags: [databricks, lakebase, queries, data-access, postgrest]
---

# Databricks Data Patterns Skill

## Purpose

Generate project-specific query files — not generic examples.
Run after `databricks-connection` and `databricks-security` are complete.

---

## Step 1 — Discover Entities

Scan the project for existing schema files, models, or migrations to identify
table names automatically. Look for:
- `prisma/schema.prisma` — model names
- `models.py`, `models/*.py` — Django or SQLAlchemy model class names
- `db/migrations/` — table names from CREATE TABLE statements
- `types/`, `interfaces/` — existing TypeScript interfaces

If nothing found, ask:

> "What are the main tables or entities in your Lakebase project?
> List them with their key columns if you know them, e.g.:
> - users (id, name, email, created_at)
> - orders (id, user_id, total, status)"

---

## Step 2 — Identify Required Operations

For each entity, ask:

> "For each entity, which operations do you need?
> 1. Read-only (list + get by ID)
> 2. Full CRUD (read + insert + update + delete)
> 3. Specific queries (describe what you need — e.g. filter by status, search by name)"

---

## Step 3 — Generate Query Files

Use the app type from `databricks-architecture` classification to choose the path.

---

### Frontend path → TypeScript query modules

For each entity, write `lib/api/[entity]-queries.ts`:

```typescript
// lib/api/[entity]-queries.ts
import { dataApiFetch } from '@/lib/api/lakebase-client'
import { tokenManager } from '@/auth/token-manager'
import type { [Entity] } from '@/types/[entity]'

const BASE = import.meta.env.VITE_DATA_API_BASE_URL

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

// Insert
export async function create[Entity](data: Omit<[Entity], 'id'>): Promise<[Entity]> {
  const token = await tokenManager.getAccessToken()
  const res = await fetch(`${BASE}/public/[entity]`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      Prefer: 'return=representation',
    },
    body: JSON.stringify(data),
  })
  if (!res.ok) throw new Error(`Create [entity] failed: ${res.status}`)
  const [created] = await res.json() as [Entity][]
  return created
}

// Update — always filtered, never unguarded PATCH
export async function update[Entity](id: number, data: Partial<Omit<[Entity], 'id'>>): Promise<void> {
  const token = await tokenManager.getAccessToken()
  const res = await fetch(`${BASE}/public/[entity]?id=eq.${id}`, {
    method: 'PATCH',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(data),
  })
  if (!res.ok) throw new Error(`Update [entity] failed: ${res.status}`)
}

// Delete — always filtered, never unguarded DELETE
export async function delete[Entity](id: number): Promise<void> {
  const token = await tokenManager.getAccessToken()
  const res = await fetch(`${BASE}/public/[entity]?id=eq.${id}`, {
    method: 'DELETE',
    headers: { Authorization: `Bearer ${token}` },
  })
  if (!res.ok) throw new Error(`Delete [entity] failed: ${res.status}`)
}
```

Also generate `types/[entity].ts` for each entity:

```typescript
// types/[entity].ts
export interface [Entity] {
  id: number
  [column]: [type]  // fill in from actual table schema
}
```

---

### Backend path → Python query modules

For each entity, write `db/queries/[entity].py`:

```python
# db/queries/[entity].py
from db.connection import get_conn


def get_all_[entities](*, after_id: int = 0, limit: int = 20) -> list[dict]:
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute(
            "SELECT id, [columns] FROM [entity] WHERE id > %s ORDER BY id LIMIT %s",
            (after_id, limit),
        )
        cols = [d.name for d in cur.description]
        return [dict(zip(cols, row)) for row in cur.fetchall()]


def get_[entity]_by_id([entity]_id: int) -> dict | None:
    with get_conn() as conn, conn.cursor() as cur:
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
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute(
            f"INSERT INTO [entity] ({col_names}) VALUES ({placeholders}) RETURNING id",
            tuple(data[c] for c in cols),
        )
        new_id: int = cur.fetchone()[0]
        conn.commit()
        return new_id


def update_[entity]([entity]_id: int, data: dict) -> None:
    if not data:
        return
    cols = list(data.keys())
    set_clause = ", ".join(f"{c} = %s" for c in cols)
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute(
            f"UPDATE [entity] SET {set_clause} WHERE id = %s",
            (*[data[c] for c in cols], [entity]_id),
        )
        conn.commit()


def delete_[entity]([entity]_id: int) -> None:
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute("DELETE FROM [entity] WHERE id = %s", ([entity]_id,))
        conn.commit()
```

---

## Step 4 — Mark State Done

After all query files are written, run:

```bash
python3 -c "import json,time; s=json.load(open('/tmp/databricks-state.json')); s['data_patterns_applied']=True; s['last_updated']=int(time.time()); open('/tmp/databricks-state.json','w').write(json.dumps(s))"
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
