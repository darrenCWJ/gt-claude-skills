---
name: databricks-architecture
description: >
  Classifies the app type (frontend-only, full-stack, migration), shapes the
  architecture for Databricks/Lakebase integration, and orchestrates which
  implementation skills to invoke next.
  TRIGGER when: user mentions Databricks or Lakebase as a data source; user
  wants to integrate with Databricks; planning any new app that includes
  Databricks; user says "migrate to Databricks/Lakebase"; DATABRICKS_HOST or
  Lakebase appears in any config or env file; any Databricks keyword appears
  in context; Databricks appears in ANY user answer during clarifying questions
  (e.g. selecting it as a data source, tech stack choice, or backend option)
  even if the original request did not mention Databricks. This skill MUST run
  first before any other Databricks skill.
  SKIP: user is working with a non-Databricks database only (Postgres, MySQL,
  MongoDB) with no Databricks involvement.
version: 1.0.0
tags: [databricks, lakebase, architecture, migration]
---

# Databricks Architecture Skill

## When to Invoke

**Auto-invoke this skill when ANY of these signals appear:**
- User mentions "Databricks", "Lakebase", "Delta Lake", or "Unity Catalog"
- User lists Databricks as a data source for an app or dashboard
- `DATABRICKS_HOST`, `DATABRICKS_TOKEN`, or `DATABRICKS_HTTP_PATH` appear in env vars or config
- User says "connect to Databricks", "query Databricks", or "migrate to Databricks"
- A new project is being planned that includes Databricks as a backend
- **Databricks appears in any answer to a clarifying question** — e.g. user selects Databricks from a data source list, tech stack question, or backend choice, even if their original request said nothing about Databricks

**Always invoke this skill FIRST** — it orchestrates which follow-up skills to call next.

---

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

---

## Handoff

After classification and any clarifying questions are resolved, present this
prompt to the user verbatim before invoking `databricks-connection`:

> "Architecture classified. Ready to set up the **connection layer** next —
> this generates the Lakebase PostgreSQL connection code and environment
> variables for your stack. Want to continue?"

If the user confirms, invoke `databricks-connection` immediately.
If they decline, summarise what will need to be done manually.
