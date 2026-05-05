---
name: databricks-architecture
description: >
  Classifies the app type (frontend-only, full-stack, migration), shapes the
  architecture for Databricks/Lakebase integration, and orchestrates which
  implementation skills to invoke next.
version: 1.0.0
tags: [databricks, lakebase, architecture, migration]
---

# Databricks Architecture Skill

## Purpose

Shape the architecture before any code is written. Always run this skill first.
After classification, invoke the appropriate follow-up skills in order.

---

## Step 0 — Finding Lakebase Credentials

Guide the user to find credentials in the Databricks workspace UI.

### Navigation path

1. Log in to your Databricks workspace
2. Click the **grid icon (⋮⋮⋮)** in the **top-right corner** (app-switcher)
3. Click **Lakebase Postgres** from the dropdown
4. Select your project → click **Connect** (top-right)
5. Copy these four values:

| Field | Example |
|---|---|
| **Host** | `ep-abc-123.databricks.com` |
| **Database** | `databricks_postgres` |
| **User / Role** | `my_role` |
| **Password** | Click "Generate password" |

### Official docs
- https://docs.databricks.com/aws/en/oltp/projects/postgres-clients
- https://docs.databricks.com/aws/en/oltp/

---

## Step 1 — Classify the App

Determine which category applies before generating any code.

**Frontend-only signals:**
- Pure SPA (React, Vue, Angular, Svelte) with no server files
- Only `index.html` / `vite.config.ts` / `next.config.js` with `output: 'export'`
- No `server.ts`, `app.py`, `main.go`, or backend entrypoint

**Full-stack signals:**
- Backend entrypoint present (FastAPI, Django, Express, Spring Boot, etc.)
- Dockerfile exposes a server port
- Database migrations exist
- `api/` routes or server-side rendering

**Migration signals:**
- Existing `DATABASE_URL` pointing to a non-Databricks host
- Existing ORM models, migrations, or schema files for another database
- References to PostgreSQL, MySQL, or other databases in config files
- User mentions "migrate", "move", or "switch" to Databricks/Lakebase

If migration signals detected, ask:

> "Are you migrating an existing application to Lakebase? If yes, share your
> current database config (without credentials) so I can plan the migration
> path and adapt your existing connection code."

If classification is ambiguous, ask:

> "Is this app frontend-only (no backend server at all), or does it have a
> backend component that runs server-side code?"

---

## Step 2 — Orchestrate Follow-up Skills

After classification, invoke skills in this order:

**Frontend-only path:**
1. Invoke `databricks-connection` — Data API client setup
2. Invoke `databricks-security` — OAuth PKCE + silent refresh
3. Invoke `databricks-data-patterns` — PostgREST read/write patterns

**Full-stack path:**
1. Invoke `databricks-connection` — PostgreSQL connection setup (ask: driver or ORM?)
2. Invoke `databricks-security` — OAuth token rotation (mandatory)
3. Invoke `databricks-data-patterns` — query, write, and transaction patterns

**Migration path:**
1. Assess existing connection code, map it to Lakebase equivalent
2. Identify schema or driver changes needed
3. Follow frontend-only or full-stack path above

---

## Decision Tree

```
User wants Databricks/Lakebase integration
          │
          ├─ Migration? (existing DB signals)
          │         └─ Ask: share current DB config (no credentials)
          │                   └─ Map existing → Lakebase, then continue ↓
          │
          ├─ Frontend only? (SPA, no server-side code)
          │         └─ Path: Lakebase Data API (PostgREST)
          │                   └─ Skills: connection → security → data-patterns
          │
          └─ Has a backend?
                    └─ Path: Direct Lakebase PostgreSQL (OAuth always)
                              └─ Skills: connection → security → data-patterns
```
