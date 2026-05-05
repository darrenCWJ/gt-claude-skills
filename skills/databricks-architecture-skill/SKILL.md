---
name: databricks-architecture
description: >
  Classifies the app type (frontend-only, full-stack, script/notebook,
  migration), shapes the architecture for Databricks/Lakebase integration,
  and orchestrates which implementation skills to invoke next.
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
version: 2.0.0
tags: [databricks, lakebase, architecture, migration]
---

# Databricks Architecture Skill

## Purpose

Classify the app and shape the architecture before any code is written.
Always run this skill first. After classification, invoke follow-up skills in order.

---

## Step 1 — Classify the App

Determine which category applies. Ask if ambiguous.

**Frontend-only signals:**
- Pure SPA (React, Vue, Angular, Svelte) with no server files
- Only `index.html` / `vite.config.ts` / `next.config.js` with `output: 'export'`
- No `server.ts`, `app.py`, `main.go`, or backend entrypoint

**Full-stack signals:**
- Backend entrypoint present (FastAPI, Django, Express, Spring Boot, etc.)
- Dockerfile exposes a server port
- Database migrations exist
- `api/` routes or server-side rendering

**Script / Notebook signals:**
- Standalone Python script, Jupyter notebook, or data pipeline
- No web framework or server
- Batch jobs, ETL, ML training, data analysis

**Migration signals:**
- Existing `DATABASE_URL` pointing to a non-Databricks host
- Existing ORM models, migrations, or schema files for another database
- User mentions "migrate", "move", or "switch" to Databricks/Lakebase

If ambiguous, ask:

> "Is this a browser-based app (no backend server), a server-side backend,
> or a standalone script / notebook?"

If migration signals detected, ask:

> "Are you migrating an existing application to Lakebase? If yes, share your
> current database config (without credentials) so I can plan the migration path."

**Also ask the tech stack** to pre-populate the project marker:

> "Which language/framework are you using?
> 1. TypeScript / Node.js (React, Next.js, Express, etc.)
> 2. Python (FastAPI, Django, Flask, script, notebook)
> 3. Java / Kotlin (Spring Boot, JDBC)
> 4. Other — describe briefly"

**Also ask the deployment context** — this changes which auth approach is recommended:

> "Who will use this app?
> 1. Just me — personal tool on my own Databricks workspace
> 2. A team — shared workspace with multiple users or services"

---

## Step 1.5 — Write Project Marker

After classification and stack identification, create `.lakebase` in the project root:

```bash
echo '{"app_type":"CLASSIFIED_TYPE","stack":"STACK","personal":BOOL}' > .lakebase
```

| Field | Values |
|---|---|
| `app_type` | `frontend`, `fullstack`, `script`, `migration` |
| `stack` | `typescript`, `python`, `java`, `kotlin` |
| `personal` | `true` if solo/personal workspace, `false` if team/org |

This file:
- Scopes hooks to confirmed Databricks projects (prevents false positives)
- Records app type so the transition hook can detect frontend → fullstack changes
- Lets downstream skills skip classification questions and tailor auth guidance

---

## Step 2 — Credential Navigation

Guide the user to the credentials they need for their specific path.

### Frontend path — Data API URL + OAuth App

The frontend uses the Lakebase **Data API** (PostgREST), not direct PostgreSQL.

**Data API base URL:**
1. Log in to Databricks workspace
2. Navigate to **Lakebase Postgres** → select your project
3. Click **Data API** tab → copy the base URL

Format:
```
https://your-workspace.databricks.com/api/2.0/lakebase/v1/projects/PROJECT_ID/data-api
```

**OAuth App registration:**
The frontend uses PKCE OAuth. An OAuth application must be registered in the workspace.

If `personal = true` (you own this workspace): do this yourself —
Workspace Settings → Security → OAuth Applications → **Add application**:
- Name: `your-app-name`
- Redirect URIs: `http://localhost:5173/auth/callback` (add production URI too)
- Grant types: `Authorization Code`
- Copy the **Client ID** — no client secret is needed for PKCE.

If `personal = false` (shared workspace): share this with your workspace admin:

> "Please register an OAuth application in Workspace Settings → Security → OAuth Applications:
> - Name: `your-app-name`
> - Redirect URIs: `http://localhost:5173/auth/callback` (add production URI too)
> - Grant types: `Authorization Code`
> - Return the **Client ID** to the developer — no client secret is needed for PKCE."

Add to `.env.local`:
```env
VITE_DATABRICKS_HOST=https://your-workspace.databricks.com
VITE_DATABRICKS_CLIENT_ID=<from OAuth app registration>
VITE_OAUTH_REDIRECT_URI=http://localhost:5173/auth/callback
VITE_DATA_API_BASE_URL=https://your-workspace.databricks.com/api/2.0/lakebase/v1/projects/PROJECT_ID/data-api
```

---

### Full-stack / Script path — PostgreSQL Connection + SDK Credentials

**PostgreSQL connection details (from Lakebase UI):**
1. Log in to Databricks workspace
2. Click **grid icon (⋮⋮⋮)** top-right → **Lakebase Postgres**
3. Select project → click **Connect** (top-right)
4. Configure: **Branch**, **Compute**, **Database**, **Role**
5. Copy connection details:

| What | Where |
|---|---|
| **Host** | Extract from connection string, e.g. `ep-abc-123.ap-southeast-1.cloud.databricks.com` |
| **Database** | Extract from connection string, e.g. `databricks_postgres` |
| **User / Role** | Extract from connection string |
| **Endpoint path** | Format: `projects/{name}/branches/{branch}/endpoints/{endpoint}` |

> The password is a **short-lived OAuth token** (~1 hour) — never hardcode it.
> Token rotation is mandatory and set up by `databricks-security`.

**SDK credentials — choose based on deployment context:**

| Context | Recommended | Why |
|---|---|---|
| Personal workspace (solo) | PAT | You own the account — departure risk is zero; PAT with `postgres` scope is sufficient |
| Team / org workspace | M2M service principal | PAT is tied to your personal account; if you leave, the app breaks |

**Finding your endpoint path:**
```python
from databricks.sdk import WorkspaceClient
w = WorkspaceClient()
for p in w.postgres.list_projects():
    print(p.name)
for b in w.postgres.list_branches(parent='projects/my-project'):
    print(b.name)
for e in w.postgres.list_endpoints(parent='projects/my-project/branches/production'):
    print(e.name)  # typically 'primary'
```

**PAT setup (for personal workspace or dev):**
1. User Settings → Developer → Access tokens → **Generate new token**
2. Scope: `Other APIs` → API scope: **`postgres`** (not `sql` — wrong scope, will fail)
3. Lifetime: 1 year is reasonable for personal production; set a calendar reminder to renew

**M2M service principal (for team/org workspace):**

If `personal = true` (you own this workspace): do this yourself —
1. Settings → Identity & Access → Service principals → **Add service principal**
2. Name it `yourapp-lakebase-prod`
3. On the service principal → **Secrets** → **Generate secret** (save immediately, shown once)
4. Lakebase Postgres → your project → **Manage access** → add service principal with `Can use`

If `personal = false` (shared workspace): share this with your admin:

> "Please create a service principal for Lakebase access:
> 1. Settings → Identity & Access → Service principals → **Add service principal** — name: `yourapp-lakebase-prod`
> 2. Generate a secret (shown once — save it immediately)
> 3. Assign the service principal `Can use` on the Lakebase project
> 4. Return the **Client ID** and **Client Secret** to the developer."

Add to `.env`:
```env
DATABRICKS_HOST=https://your-workspace.databricks.com
DATABRICKS_TOKEN=<PAT>                       # personal workspace / dev
# OR for team/org workspace:
DATABRICKS_CLIENT_ID=<service principal ID>
DATABRICKS_CLIENT_SECRET=<service principal secret>

LAKEBASE_HOST=ep-abc-123.databricks.com
LAKEBASE_PORT=5432
LAKEBASE_DB=databricks_postgres
LAKEBASE_USER=your_role_name
LAKEBASE_ENDPOINT_PATH=projects/my-project/branches/production/endpoints/primary
DATABASE_URL=postgresql://your_role_name@ep-abc-123.databricks.com/databricks_postgres?sslmode=require
```

---

## Step 3 — Orchestrate Follow-up Skills

**Frontend path:**
1. `databricks-connection` — Data API client setup
2. `databricks-security` — PKCE login flow + silent refresh
3. `databricks-data-patterns` — PostgREST read/write patterns

**Full-stack path:**
1. `databricks-connection` — PostgreSQL driver or ORM
2. `databricks-security` — token rotation (mandatory)
3. `databricks-data-patterns` — typed query modules

**Script / Notebook path:**
1. `databricks-connection` — psycopg2 or asyncpg connection
2. `databricks-security` — token rotation
3. `databricks-data-patterns` — query patterns (skip pagination if batch-oriented)

**Migration path:**
1. Assess existing connection code and ORM models
2. Map existing schema to Lakebase equivalent
3. Follow full-stack path above for connection + security
4. Adapt existing query modules using `databricks-data-patterns`

---

## Decision Tree

```
User wants Databricks/Lakebase integration
          │
          ├─ Migration? (existing DB signals)
          │         └─ Map existing → Lakebase → follow fullstack path
          │
          ├─ Frontend only? (SPA, no server-side code)
          │         └─ Data API (PostgREST) + PKCE OAuth
          │
          ├─ Has a backend?
          │         └─ Direct PostgreSQL (OAuth token rotation)
          │
          └─ Script / Notebook?
                    └─ Direct PostgreSQL (OAuth token rotation, no pooling)
```

---

## Handoff

After credential guidance is done, present this verbatim:

> "Architecture classified. Ready to set up the **connection layer** next —
> this generates the Lakebase connection code and environment variables for
> your stack. Want to continue?"

If the user confirms, invoke `databricks-connection` immediately.
