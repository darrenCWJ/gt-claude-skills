---
name: databricks-lakebase
description: >
  Unified Databricks/Lakebase integration skill. Handles the full lifecycle:
  codebase scanning, intent discovery, plan presentation, connection setup,
  security (PKCE + token rotation), and data access pattern generation.
  Supports all app types (frontend, fullstack, script, migration) and stacks
  (TypeScript, Python, Java/Kotlin).
  TRIGGER when: user mentions Databricks or Lakebase; DATABRICKS_HOST or
  Lakebase appears in config/env; .lakebase marker exists in project; user
  asks to connect, query, migrate, or integrate with Databricks; Databricks
  appears in ANY user answer during clarifying questions (e.g. selecting it
  as a data source, tech stack, or backend option) even if the original
  request did not mention Databricks.
  SKIP: user is working with a non-Databricks database only (Postgres, MySQL,
  MongoDB) with no Databricks involvement.
version: 1.0.0
tags: [databricks, lakebase, connection, security, data-access, architecture]
---

# Databricks Lakebase Skill

## Internal Router

Evaluate from top to bottom. Enter at the FIRST matching condition.

### Fast Path (Power Users)

If `.lakebase` exists AND the user explicitly requests specific output
(e.g. "give me psycopg3 connection code", "write queries for the orders table"):
- Read `.lakebase` for app_type/stack/personal
- Skip to the relevant phase (3, 4, or 5) directly
- Do NOT re-ask classification questions

### Re-entry (Mid-conversation)

If `.lakebase` exists AND connection + security files already exist AND user asks
for a new entity or query pattern:
- Determine connection type from existing files:
  - `lib/lakebase-client.ts` or `lib/api-client.ts` → Data API patterns
  - `db/connection.py` or `db/pool.ts` → PG wire patterns
- Enter at Phase 5 with matching query style

If `.lakebase` exists AND connection file exists but NO security layer:
- Enter at Phase 4

If `.lakebase` exists but NO connection file:
- Enter at Phase 3 (ask driver preference, then continue through 4-5)

### Transition Detection

If `.lakebase` says `frontend` but a backend entrypoint is being written:
- Re-run Phase 0-1 to reclassify
- Update `.lakebase`
- Continue from Phase 3

### First-time Setup

If NO `.lakebase` exists:
- Start at Phase 0

### Hook Context (Advisory Only)

The hook may pass context: `hostname_detected`, `keyword_intent`, `marker_exists`,
or `transition`. Use as a hint but ALWAYS verify actual file state in Phase 0.
The hook context does NOT override what you discover by scanning.

---

## Phase 0 — Codebase Scan (Silent)

Scan the project WITHOUT asking questions. Check:

| Target | Signal |
|--------|--------|
| `.lakebase` | Existing marker — read app_type, stack, personal |
| `requirements.txt`, `pyproject.toml`, `package.json` | Stack detection |
| `main.py`, `app.py`, `server.ts`, `manage.py`, `Dockerfile` | App type |
| `.env`, `.env.local`, `.env.example` | Configured env vars, existing DB signals |
| ORM models, migration files, `DATABASE_URL` | Migration indicators |
| `lib/lakebase-client.ts`, `db/connection.py`, `db/pool.ts` | Existing connection |
| `auth/token-manager.ts`, `auth/token_rotator.py` | Existing security layer |
| `lib/api/*-queries.ts`, `db/queries/*.py` | Existing data patterns |

Produce internal state (do not show to user):

```
has_marker: bool
app_type: frontend | fullstack | script | migration | unknown
stack: typescript | python | java | kotlin | unknown
personal: bool | unknown
has_connection: bool
has_security: bool
has_data_patterns: list[str]  # entity names with query files
existing_db: string | null    # e.g. "postgres on Neon"
env_vars_configured: list[str]
```

Use this state to determine which phases to skip.

---

## Phase 1 — Intent Discovery

Ask ONLY what cannot be determined from Phase 0. Maximum 2 questions.

### Question 1 — Intent (ask if no .lakebase AND intent unclear from message)

> "What would you like to do with Databricks/Lakebase?
> 1. **New integration** — connect a new or existing app to Lakebase
> 2. **Migrate** — move from another database (Postgres, MySQL, etc.) to Lakebase
> 3. **Add queries** — write data access code for tables (connection already exists)
> 4. **Fix/update** — fix a broken connection, update auth, or resolve an error"

- Answer 2 → ask **Migration Follow-up** (below), then route accordingly
- Answer 3 → jump to Phase 5
- Answer 4 → ask what's broken, provide targeted fix (no full pipeline).
  Recognized scenarios include:
  - Broken connection / auth error → diagnose and fix
  - Switch from Data API to PG wire (e.g. need transactions) → re-run Phase 3 with new method, update `.lakebase`
  - Switch from PG wire to Data API (e.g. want simpler REST) → re-run Phase 3, update `.lakebase`
  - Token rotation not working → fix Phase 4 security layer
  - CORS issues with Data API → guide CORS configuration

### Migration Follow-up (ask only if Answer 2 selected)

> "How do you want to move data to Lakebase?
> 1. **One-time copy** — dump source, load into Lakebase, then decommission the old database
> 2. **Dual-run (replication)** — keep both databases running, sync data continuously or periodically
> 3. **Gradual migration** — move table by table over time, with app reading from both during transition"

**Routing:**

| Choice | What to generate | Also invoke |
|---|---|---|
| One-time copy | Export script, import script, verification queries, cutover checklist | `database-migrations` (for schema adaptation) |
| Dual-run | Sync strategy doc, CDC or cron-based replication pattern, conflict resolution approach | `database-migrations` (for schema parity) |
| Gradual migration | Per-table migration plan, dual-read routing pattern, expand-contract app changes | `database-migrations` (for safe schema changes) |

Update `.lakebase` marker with migration context (keep actual app_type from Phase 0 scan):
```json
{"app_type": "<scanned type>", "intent": "migrate", "migration_type": "one-time|dual-run|gradual", "source_db": "<detected or asked>", ...}
```

### Question 2 — Hosting (ask for ALL app types)

> "Where will this app be hosted?
> 1. **Databricks Apps** — hosted inside the Databricks workspace (credentials auto-injected, user tokens forwarded via headers)
> 2. **External** — hosted outside Databricks (Vercel, AWS, GCP, self-hosted, etc.)"

**Routing:**

| Hosting | What happens next |
|---|---|
| Databricks Apps | Skip most of Phase 4 — platform auto-injects `DATABRICKS_CLIENT_ID` + `DATABRICKS_CLIENT_SECRET` env vars, user tokens arrive in `x-forwarded-access-token` header. No manual auth code needed. |
| External | Ask **Question 2b — Audience** (below) to determine auth approach |

### Question 2b — Audience (ask only if hosting is External)

> "Do the app's end users have Databricks workspace accounts?
> 1. **Yes** — users can authenticate directly with Databricks (e.g. internal team tool)
> 2. **No** — users are external/public (e.g. customers, students) and don't have Databricks accounts"

**Routing:**

| Audience | Auth architecture |
|---|---|
| Yes (internal) | Frontend → Databricks OAuth PKCE → Data API directly. Users log in with their Databricks identity. |
| No (external) | Frontend → your own auth → your backend → Data API via service principal. End users never touch Databricks auth. |

### Question 3 — Workspace (ask if hosting is External)

Ask if hosting is external (both audience types need credential setup):

> "Is this your personal Databricks workspace, or a shared team/org workspace?
> This determines credential setup — PAT for personal dev, service principal for production/teams."

### Question 4 — Connection Method (ask for backend/fullstack/script if hosting is External)

Skip for frontend-only apps (always Data API) and migrations (always PG wire for import).

> "How should your backend connect to Lakebase?
> 1. **PostgreSQL direct (recommended)** — full SQL, transactions, complex queries. Always available.
> 2. **Data API (REST)** — simpler HTTP calls, no connection management, but limited to basic CRUD. Requires Data API enabled.
> 3. **Not sure** — use PostgreSQL (you can switch to Data API later)"

Default: **PostgreSQL direct** for backends. Data API is mainly for frontend-direct access.

### Auto-inferred (never ask):

- **App type** — inferred from project structure (Phase 0 scan)
- **Stack** — inferred from package manager / entrypoint
- **Driver preference** — asked later in Phase 3 (backend only, if PG wire chosen)

### After intent is clear:

Write `.lakebase` marker (always include ALL fields, use `null` for not-applicable):

```json
{
  "app_type": "frontend|fullstack|backend|script",
  "intent": "new|migrate|queries|fix",
  "stack": "typescript|python|java|kotlin",
  "hosting": "databricks-apps|external",
  "audience": "internal|external|null",
  "personal": true|false|null,
  "connection_method": "data-api|pg-wire|both",
  "migration_type": "one-time|dual-run|gradual|null",
  "source_db": "postgres|mysql|sqlite|mongodb|null"
}
```

---

## Phase 2 — Plan Presentation

Present what will be generated. Wait for confirmation before writing any files.

> **Lakebase Integration Plan**
>
> | | |
> |---|---|
> | App type | [frontend / fullstack / script / migration] |
> | Hosting | [Databricks Apps / External] |
> | Audience | [internal / external] (external hosting only) |
> | Stack | [TypeScript / Python / Java / Kotlin] |
> | Auth | [Auto (Databricks Apps) / PKCE (external + internal users) / Backend proxy + service principal (external + external users) / PAT (personal backend) / M2M (team backend)] |
>
> **Files to generate:**
> 1. `[path]` — [purpose]
> 2. `[path]` — [purpose]
> ...
>
> **Env vars to configure:**
> - `VAR_NAME` — [where to find the value]
>
> **Shall I proceed?**

If the user says "skip X" or "I already have Y", remove those from the plan.
Do NOT generate files without confirmation.

---

## Phase 2b — Credential Onboarding (MANDATORY before code generation)

After the user confirms the plan, do NOT generate code yet. First, check what
credentials they already have and walk them through obtaining what's missing.

### Step 1 — Check Prerequisites

Ask:

> "Before I generate the code, let me make sure you have the Databricks/Lakebase
> credentials ready. Do you already have:
> 1. A Databricks workspace? (If no → guide to setup)
> 2. A Lakebase project with tables created? (If no → guide to create)
> 3. The Data API enabled? (If using Data API)
> 4. A service principal or PAT configured? (If external hosting)
> 5. Which **schema** are your tables in? (e.g., `app`, `api`, `myproject` — using `public` is not recommended)"

Do NOT assume they have these. If they say no to any, provide the step-by-step
below before continuing.

### Step 2 — Guided Setup (show only what's missing)

#### If no Databricks workspace:

> "You need a Databricks workspace first. Options:
> - **Free trial:** Go to https://www.databricks.com/try-databricks
> - **Organization account:** Ask your admin for workspace access
> - **GovTech:** Check if your agency has an existing workspace
>
> Once you have workspace access, come back and I'll continue the setup."

**STOP here** — do not generate code without a workspace.

#### If no Lakebase project:

> "Create a Lakebase project in your workspace:
> 1. In Databricks, go to **Lakebase** (left sidebar)
> 2. Click **Create Project**
> 3. Name it (e.g., `hometongue-prod`)
> 4. Once created, you'll see a project dashboard with connection details
>
> Do you have tables already, or do you need to create them too?"

#### If Data API not enabled (frontend/fullstack apps):

> "Enable the Data API on your Lakebase project:
> 1. Go to your Lakebase project
> 2. Click the **Data API** tab
> 3. Click **Enable Data API**
> 4. Copy the **REST endpoint URL** that appears — you'll need this
>
> What's the REST endpoint URL? (Paste it here and I'll wire it into the code)"

#### If no service principal (external hosting + external users):

> "Create a service principal for your app:
> 1. In Databricks, go to **Settings → Identity & Access → Service principals**
> 2. Click **Add service principal** → name it (e.g., `hometongue-app`)
> 3. Click **Generate secret** — save both values immediately:
>    - **Application ID** → this is your `DATABRICKS_CLIENT_ID`
>    - **Client Secret** → this is your `DATABRICKS_CLIENT_SECRET`
>    ⚠️ The secret is shown only once — copy it now!
>
> Then grant the service principal access to your Lakebase project:
> 4. Go to your Lakebase project → **Settings → Permissions**
> 5. Add the service principal with **Can use** permission
>
> Finally, create a Postgres role for it (run in the Lakebase SQL editor):
> ```sql
> CREATE EXTENSION IF NOT EXISTS databricks_auth;
> SELECT databricks_create_role('<application-id>', 'SERVICE_PRINCIPAL');
> GRANT USAGE ON SCHEMA <schema> TO \"<application-id>\";
> GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA <schema> TO \"<application-id>\";
> GRANT USAGE ON ALL SEQUENCES IN SCHEMA <schema> TO \"<application-id>\";
> ```
> ⚠️ Replace `<schema>` with the user's chosen schema (e.g., `app`). Do NOT default to `public`.
>
> Paste your Application ID and I'll include it in the generated code."

#### If no PAT (personal backend/script):

> "Create a Personal Access Token:
> 1. In Databricks, click your profile (top right) → **Settings**
> 2. Go to **Developer → Access tokens**
> 3. Click **Generate new token**
> 4. Set scope to **`postgres`** (NOT `sql` — that's for SQL warehouses)
> 5. Copy the token — this is your `DATABRICKS_TOKEN`
>
> Paste the token value and I'll wire it into the code."

#### If using PKCE (external + internal users):

> "Register an OAuth application for your frontend:
> 1. In Databricks, go to **Settings → App connections** (or ask your admin)
> 2. Click **Add application**
> 3. Fill in:
>    - **Name:** `your-app-name`
>    - **Redirect URIs:** `http://localhost:5173/auth/callback`
>      (add your production URL too, e.g., `https://yourapp.com/auth/callback`)
>    - **Grant types:** Authorization Code
>    - **Client type:** Public (no secret — PKCE handles security)
> 4. Copy the **Client ID** — this is your `VITE_DATABRICKS_CLIENT_ID`
>
> Paste the Client ID and I'll wire it into the code."

#### Schema selection (ask ALL users):

> "Which database schema are your tables in?
> - Best practice is to use a **dedicated schema** (e.g., `app`, `api`, `myproject`)
> - Avoid `public` — it's the default but mixes your application tables with system/extension objects
> - If you haven't created a schema yet, ask your Databricks admin to create one, or if you have permissions, run this in the Lakebase SQL editor:
>   ```sql
>   CREATE SCHEMA app;
>   ```
>   Then create your tables inside it (e.g., `app.users`, `app.orders`)
>
> What schema name should I use in the generated code?
> (If you're unsure or need admin help, let me know and I can provide the SQL for your admin to run.)"

**If the user doesn't know or needs admin help:**
> "No problem. Here's what to send your Databricks admin:
> 1. Ask them to create a schema: `CREATE SCHEMA <your_preferred_name>;`
> 2. Ask them to grant you access: `GRANT ALL ON SCHEMA <name> TO \"<your-role>\";`
> 3. Come back with the schema name once it's ready, or tell me to use `public` for now."

If the user says `public`, accept it but note: "I'll use `public` — consider migrating to a dedicated schema later for cleaner separation."

Store the schema name for use in all generated Data API paths and SQL grants.

### Step 3 — Collect and Confirm Values

Once the user has all credentials, collect them explicitly:

> "Great! Let me confirm the values for your `.env` file:
>
> | Variable | Value | ✓ |
> |---|---|---|
> | `DATABRICKS_HOST` | [their workspace URL] | |
> | `LAKEBASE_DATA_API_URL` | [their REST endpoint] | |
> | `LAKEBASE_SCHEMA` | [their schema name, e.g. `app`] | |
> | `DATABRICKS_CLIENT_ID` | [their service principal ID] | |
> | `DATABRICKS_CLIENT_SECRET` | [their secret] | |
>
> Does this look correct? I'll generate the code with these values wired in."

**Important rules:**
- NEVER generate code with placeholder values like `<your-workspace-url>` without
  first attempting to collect the real values
- **Exception:** If the user explicitly says they'll provide credentials later
  (e.g. "I'll fill those in later", "skip credentials for now", "just generate
  the code"), proceed with `.env.example` placeholders and clear labels showing
  where each value comes from. Do not block progress.
- If the user doesn't want to share secrets in chat, generate `.env.example` with
  clear labels and tell them exactly which value goes where
- If they don't have credentials yet, STOP and help them get set up first —
  unless they say to proceed anyway
- Always explain WHERE each value comes from in the Databricks UI

### Step 4 — Create .env file

After collecting values, create or update the project's `.env` and `.env.example`:

```bash
# .env (NOT committed — add to .gitignore)
DATABRICKS_HOST=https://actual-workspace.cloud.databricks.com
LAKEBASE_DATA_API_URL=https://actual-endpoint.databricks.com/...
DATABRICKS_CLIENT_ID=actual-id-here
DATABRICKS_CLIENT_SECRET=actual-secret-here
```

```bash
# .env.example (committed — shows structure without secrets)
DATABRICKS_HOST=https://your-workspace.cloud.databricks.com
LAKEBASE_DATA_API_URL=                # Lakebase project → Data API tab → REST endpoint
DATABRICKS_CLIENT_ID=                 # Settings → Identity & Access → Service principals → Application ID
DATABRICKS_CLIENT_SECRET=             # Service principal secret (generated once, save immediately)
```

Ensure `.env` is in `.gitignore` before proceeding to Phase 3.

---

## Phase 3 — Connection Setup

### Frontend — Lakebase Data API Client

Choose based on hosting + audience (determined in Phase 1):

- **Databricks Apps** → Skip to **Frontend — Databricks Apps (Auto-Auth)** below
- **External + internal users** → Frontend calls Data API directly via PKCE (below)
- **External + external users** → Frontend calls YOUR backend API, which proxies to Data API. Skip to **Frontend — External App (Backend Proxy)** below.

---

#### Frontend — Databricks Apps (Auto-Auth)

No manual auth code needed. Databricks auto-injects credentials and forwards user tokens.

```typescript
// lib/lakebase-client.ts
// In Databricks Apps, user token arrives via x-forwarded-access-token header.
// For server-side (backend-for-frontend within the app):

const DATA_API_BASE = process.env.LAKEBASE_DATA_API_URL
const SCHEMA = process.env.LAKEBASE_SCHEMA ?? 'public'

export async function dataApiFetch<T>(
  path: string,
  userToken: string,
  params?: Record<string, string>
): Promise<T> {
  const url = new URL(`${DATA_API_BASE}/${SCHEMA}/${path}`)
  if (params) Object.entries(params).forEach(([k, v]) => url.searchParams.set(k, v))
  const res = await fetch(url.toString(), {
    headers: { Authorization: `Bearer ${userToken}` },
  })
  if (!res.ok) throw new Error(`Data API ${res.status}: ${await res.text()}`)
  return res.json() as Promise<T>
}

// In your request handler, extract the forwarded token:
// const userToken = req.headers['x-forwarded-access-token']
// const data = await dataApiFetch('users', userToken)
```

**Env vars (auto-injected by Databricks Apps — no manual setup):**
- `DATABRICKS_CLIENT_ID` — service principal client ID (for app-level operations)
- `DATABRICKS_CLIENT_SECRET` — service principal secret (for app-level operations)

**For user-level operations:** Extract `x-forwarded-access-token` from incoming request headers and pass it to the Data API. This preserves the user's identity for RLS policies.

**For app-level operations (background tasks, shared data):** Use the auto-injected service principal credentials with the token rotator pattern from Phase 4.

---

#### Frontend — External Hosting + Internal Users (Direct Data API via PKCE)

No PostgreSQL driver needed. Auth via Databricks OAuth PKCE.
Users must have Databricks workspace accounts.

> `tokenManager` is generated in Phase 4 — this file will have unresolved imports
> until the security phase completes.

```typescript
// lib/lakebase-client.ts
import { tokenManager } from '@/auth/token-manager'

const DATA_API_BASE = import.meta.env.VITE_DATA_API_BASE_URL

export async function dataApiFetch<T>(
  path: string,
  params?: Record<string, string>
): Promise<T> {
  const token = await tokenManager.getAccessToken()
  const url = new URL(`${DATA_API_BASE}/${path}`)
  if (params) Object.entries(params).forEach(([k, v]) => url.searchParams.set(k, v))
  const res = await fetch(url.toString(), {
    headers: { Authorization: `Bearer ${token}` },
  })
  if (!res.ok) throw new Error(`Data API ${res.status}: ${await res.text()}`)
  return res.json() as Promise<T>
}

export async function dataApiMutate<T>(
  path: string,
  method: 'POST' | 'PATCH' | 'DELETE',
  body?: unknown,
  prefer?: string
): Promise<T> {
  const token = await tokenManager.getAccessToken()
  const headers: Record<string, string> = {
    Authorization: `Bearer ${token}`,
    'Content-Type': 'application/json',
  }
  if (prefer) headers['Prefer'] = prefer
  const res = await fetch(`${DATA_API_BASE}/${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  })
  if (!res.ok) throw new Error(`Data API ${method} ${res.status}: ${await res.text()}`)
  return res.status === 204 ? (undefined as T) : (res.json() as Promise<T>)
}
```

---

#### Frontend — External App (Backend Proxy)

For apps where end users do NOT have Databricks accounts. The frontend uses your
own auth system; a thin backend proxies Data API calls using a service principal.

```
User → Your Auth (Google, email, etc.) → Your Backend → Lakebase Data API
                                              ↓
                                    Service principal OAuth token
```

**Frontend client (calls YOUR backend, not Data API directly):**

```typescript
// lib/api-client.ts
const API_BASE = import.meta.env.VITE_API_BASE_URL // your backend

async function apiFetch<T>(path: string, options?: RequestInit): Promise<T> {
  const res = await fetch(`${API_BASE}/${path}`, {
    ...options,
    headers: {
      ...options?.headers,
      'Content-Type': 'application/json',
      Authorization: `Bearer ${getSessionToken()}`, // YOUR app's auth token
    },
  })
  if (!res.ok) throw new Error(`API ${res.status}: ${await res.text()}`)
  return res.json() as Promise<T>
}

export const api = {
  get: <T>(path: string) => apiFetch<T>(path),
  post: <T>(path: string, body: unknown) =>
    apiFetch<T>(path, { method: 'POST', body: JSON.stringify(body) }),
  patch: <T>(path: string, body: unknown) =>
    apiFetch<T>(path, { method: 'PATCH', body: JSON.stringify(body) }),
  delete: <T>(path: string) => apiFetch<T>(path, { method: 'DELETE' }),
}
```

**Backend proxy (Python/FastAPI example):**

```python
# api/lakebase_proxy.py
import os
import httpx
from fastapi import APIRouter, Depends, HTTPException
from auth.dependencies import get_current_user  # YOUR auth
from auth.databricks_oauth import get_databricks_oauth_token  # see below

router = APIRouter(prefix="/api/data")

DATA_API_BASE = os.environ["LAKEBASE_DATA_API_URL"]
SCHEMA = os.environ.get("LAKEBASE_SCHEMA", "public")

async def proxy_to_data_api(
    method: str,
    path: str,
    params: dict | None = None,
    body: dict | None = None,
):
    token = get_databricks_oauth_token()  # standard OAuth token, NOT PG credential
    async with httpx.AsyncClient() as client:
        res = await client.request(
            method,
            f"{DATA_API_BASE}/{SCHEMA}/{path}",
            params=params,
            json=body,
            headers={"Authorization": f"Bearer {token}"},
        )
    if not res.is_success:
        raise HTTPException(status_code=res.status_code, detail=res.text)
    return res.json() if res.content else None

@router.get("/{table}")
async def list_rows(table: str, user=Depends(get_current_user)):
    return await proxy_to_data_api("GET", table)

@router.post("/{table}")
async def create_row(table: str, body: dict, user=Depends(get_current_user)):
    return await proxy_to_data_api("POST", table, body=body)

@router.patch("/{table}")
async def update_row(table: str, body: dict, id: int, user=Depends(get_current_user)):
    return await proxy_to_data_api("PATCH", f"{table}?id=eq.{id}", body=body)

@router.delete("/{table}")
async def delete_row(table: str, id: int, user=Depends(get_current_user)):
    return await proxy_to_data_api("DELETE", f"{table}?id=eq.{id}")
```

**Databricks OAuth token helper (for Data API — NOT the PG credential rotator):**

```python
# auth/databricks_oauth.py
import os
import time
import threading
from databricks.sdk import WorkspaceClient

_token: str | None = None
_expiry: float = 0.0
_lock = threading.Lock()

def get_databricks_oauth_token() -> str:
    """Get a Databricks OAuth token for Data API calls.
    Uses service principal credentials (DATABRICKS_CLIENT_ID + SECRET).
    This is different from generate_database_credential which is for PG wire protocol."""
    global _token, _expiry
    with _lock:
        if time.time() >= _expiry - 60:
            client = WorkspaceClient(
                host=os.environ["DATABRICKS_HOST"],
                client_id=os.environ["DATABRICKS_CLIENT_ID"],
                client_secret=os.environ["DATABRICKS_CLIENT_SECRET"],
            )
            # The SDK handles OAuth token exchange automatically
            token_response = client.config.authenticate()
            _token = token_response["access_token"]
            _expiry = time.time() + 3600  # tokens typically last 1 hour
    return _token
```

**Backend proxy (TypeScript/Express example):**

```typescript
// routes/data-proxy.ts
import { Router } from 'express'
import { getDatabricksOAuthToken } from '@/auth/databricks-oauth'
import { requireAuth } from '@/middleware/auth' // YOUR auth middleware

const router = Router()
const DATA_API_BASE = process.env.LAKEBASE_DATA_API_URL!
const SCHEMA = process.env.LAKEBASE_SCHEMA ?? 'public'

async function proxyToDataApi(method: string, path: string, body?: unknown) {
  const token = await getDatabricksOAuthToken()
  const res = await fetch(`${DATA_API_BASE}/${SCHEMA}/${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: body ? JSON.stringify(body) : undefined,
  })
  if (!res.ok) throw new Error(`Data API ${res.status}: ${await res.text()}`)
  return res.status === 204 ? null : res.json()
}

router.get('/:table', requireAuth, async (req, res) => {
  const data = await proxyToDataApi('GET', req.params.table + '?' + new URLSearchParams(req.query as any))
  res.json(data)
})

router.post('/:table', requireAuth, async (req, res) => {
  const data = await proxyToDataApi('POST', req.params.table, req.body)
  res.json(data)
})

export default router
```

**Env vars for external app using Data API:**

```env
LAKEBASE_DATA_API_URL=<REST endpoint URL from Lakebase project → Data API tab>
DATABRICKS_HOST=https://your-workspace.databricks.com
DATABRICKS_CLIENT_ID=<service principal ID>
DATABRICKS_CLIENT_SECRET=<service principal secret>
```

> Note: `LAKEBASE_ENDPOINT_PATH` is NOT needed for Data API — that's only for
> PostgreSQL wire protocol connections. The Data API uses standard Databricks
> OAuth tokens obtained via the SDK's `WorkspaceClient`.

> The service principal needs a Postgres role created via
> `SELECT databricks_create_role('<service-principal-application-id>', 'SERVICE_PRINCIPAL');`
> and appropriate GRANT statements on the tables.

---

### Backend — Ask Driver Preference (1 question)

> "For your Lakebase backend, which driver/ORM do you prefer?
> 1. **psycopg3** — Python sync + async (recommended for new projects)
> 2. **psycopg2** — Python sync (existing/legacy projects)
> 3. **asyncpg** — Python async (high-throughput FastAPI)
> 4. **SQLAlchemy** — Python ORM
> 5. **Django ORM** — Django projects
> 6. **pg / node-postgres** — Node.js
> 7. **Prisma** — TypeScript ORM
> 8. **JDBC / HikariCP** — Java / Kotlin"

Generate ONLY the chosen option below.

---

### Why `max_connections = 1`

Lakebase uses OAuth tokens as passwords. Connection poolers reuse connections
across requests — meaning they reuse a token that may have expired. Use 1
connection max or fetch-per-request to guarantee a fresh token.

### Scale-to-zero Reconnection

Lakebase scales to zero when idle. The first connection after cold start may
raise `OperationalError`. All examples include 3-attempt retry with 200ms
backoff to handle this transparently.

---

### Python — psycopg3 (recommended)

> Install: `pip install "psycopg[binary]"`

**Sync:**
```python
# db/connection.py
import os
import time
import psycopg
from auth.token_rotator import get_lakebase_token

_CONNECT_PARAMS = lambda: dict(
    host=os.environ["LAKEBASE_HOST"],
    port=int(os.environ.get("LAKEBASE_PORT", "5432")),
    dbname=os.environ["LAKEBASE_DB"],
    user=os.environ["LAKEBASE_USER"],
    password=get_lakebase_token(),
    sslmode="require",
)

def get_conn() -> psycopg.Connection:
    for attempt in range(3):
        try:
            return psycopg.connect(**_CONNECT_PARAMS())
        except psycopg.OperationalError:
            if attempt == 2:
                raise
            time.sleep(0.2 * (attempt + 1))
```

**Async (FastAPI):**
```python
# db/async_connection.py
import os
import asyncio
import psycopg
from auth.token_rotator import get_lakebase_token

async def get_async_conn() -> psycopg.AsyncConnection:
    for attempt in range(3):
        try:
            return await psycopg.AsyncConnection.connect(
                host=os.environ["LAKEBASE_HOST"],
                port=int(os.environ.get("LAKEBASE_PORT", "5432")),
                dbname=os.environ["LAKEBASE_DB"],
                user=os.environ["LAKEBASE_USER"],
                password=get_lakebase_token(),
                sslmode="require",
            )
        except psycopg.OperationalError:
            if attempt == 2:
                raise
            await asyncio.sleep(0.2 * (attempt + 1))

async def get_db():
    conn = await get_async_conn()
    try:
        yield conn
    finally:
        await conn.close()
```

---

### Python — psycopg2 (legacy)

```python
# db/connection.py
import os
import time
import psycopg2
from auth.token_rotator import get_lakebase_token

def get_conn() -> psycopg2.extensions.connection:
    for attempt in range(3):
        try:
            return psycopg2.connect(
                host=os.environ["LAKEBASE_HOST"],
                port=int(os.environ.get("LAKEBASE_PORT", "5432")),
                dbname=os.environ["LAKEBASE_DB"],
                user=os.environ["LAKEBASE_USER"],
                password=get_lakebase_token(),
                sslmode="require",
            )
        except psycopg2.OperationalError:
            if attempt == 2:
                raise
            time.sleep(0.2 * (attempt + 1))
```

---

### Python — asyncpg (high-throughput)

```python
# db/async_connection.py
import os
import asyncio
import asyncpg
from auth.token_rotator import get_lakebase_token

async def get_async_conn() -> asyncpg.Connection:
    for attempt in range(3):
        try:
            return await asyncpg.connect(
                host=os.environ["LAKEBASE_HOST"],
                port=int(os.environ.get("LAKEBASE_PORT", "5432")),
                database=os.environ["LAKEBASE_DB"],
                user=os.environ["LAKEBASE_USER"],
                password=get_lakebase_token(),
                ssl="require",
            )
        except (asyncpg.TooManyConnectionsError, OSError):
            if attempt == 2:
                raise
            await asyncio.sleep(0.2 * (attempt + 1))

async def get_db():
    conn = await get_async_conn()
    try:
        yield conn
    finally:
        await conn.close()
```

---

### Python — SQLAlchemy

```python
# db/engine.py
import os
import time
from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker, DeclarativeBase
from auth.token_rotator import get_lakebase_token

def get_engine():
    engine = create_engine(
        os.environ["DATABASE_URL"],
        pool_size=1,
        max_overflow=0,
        pool_pre_ping=True,
        connect_args={"sslmode": "require"},
    )

    @event.listens_for(engine, "do_connect")
    def provide_token(dialect, conn_rec, cargs, cparams):
        cparams["password"] = get_lakebase_token()
        for attempt in range(3):
            try:
                return dialect.dbapi.connect(*cargs, **cparams)
            except Exception:
                if attempt == 2:
                    raise
                time.sleep(0.2 * (attempt + 1))
        return None

    return engine

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=get_engine())

class Base(DeclarativeBase):
    pass

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
```

---

### Python — Django ORM

```python
# myapp/lakebase_backend.py
from django.db.backends.postgresql import base
from auth.token_rotator import get_lakebase_token

class DatabaseWrapper(base.DatabaseWrapper):
    def get_new_connection(self, conn_params):
        return super().get_new_connection({**conn_params, "password": get_lakebase_token()})
```

```python
# settings.py
import os

DATABASES = {
    "default": {
        "ENGINE": "myapp.lakebase_backend",
        "HOST": os.environ["LAKEBASE_HOST"],
        "PORT": os.environ.get("LAKEBASE_PORT", "5432"),
        "NAME": os.environ["LAKEBASE_DB"],
        "USER": os.environ["LAKEBASE_USER"],
        "PASSWORD": "",
        "OPTIONS": {"sslmode": "require"},
        "CONN_MAX_AGE": 0,
    }
}
```

---

### TypeScript/Node.js — pg

```typescript
// db/pool.ts
import { Pool } from 'pg'
import { getLakebaseToken } from '@/auth/token-rotator'

export function createPool() {
  return new Pool({
    host: process.env.LAKEBASE_HOST,
    port: Number(process.env.LAKEBASE_PORT ?? 5432),
    database: process.env.LAKEBASE_DB,
    user: process.env.LAKEBASE_USER,
    password: () => getLakebaseToken(),
    ssl: { rejectUnauthorized: true },
    max: 1,
  })
}
```

---

### TypeScript — Prisma

```typescript
// db/prisma.ts
import { PrismaClient } from '@prisma/client'
import { getLakebaseToken } from '@/auth/token-rotator'

function buildDatabaseUrl(): string {
  const token = encodeURIComponent(getLakebaseToken())
  const host = process.env.LAKEBASE_HOST
  const db = process.env.LAKEBASE_DB
  const user = process.env.LAKEBASE_USER
  return `postgresql://${user}:${token}@${host}:5432/${db}?sslmode=require`
}

export function getPrismaClient(): PrismaClient {
  return new PrismaClient({
    datasources: { db: { url: buildDatabaseUrl() } },
  })
}

let _prisma: PrismaClient | null = null
let _prismaExpiry = 0

export function getPersistentPrismaClient(): PrismaClient {
  if (!_prisma || Date.now() > _prismaExpiry) {
    _prisma?.$disconnect()
    _prisma = getPrismaClient()
    _prismaExpiry = Date.now() + 45 * 60 * 1000
  }
  return _prisma
}
```

---

### Java — JDBC with HikariCP

```java
// config/DataSourceConfig.java
import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;

public class DataSourceConfig {
    public static DataSource build() {
        HikariConfig config = new HikariConfig();
        config.setJdbcUrl(String.format(
            "jdbc:postgresql://%s:%s/%s?sslmode=require",
            System.getenv("LAKEBASE_HOST"),
            System.getenv().getOrDefault("LAKEBASE_PORT", "5432"),
            System.getenv("LAKEBASE_DB")
        ));
        config.setUsername(System.getenv("LAKEBASE_USER"));
        config.setPassword(TokenRotator.getToken());
        config.setMaximumPoolSize(1);
        config.addDataSourceProperty("sslmode", "require");
        return new HikariDataSource(config);
    }
}
```

---

## Phase 4 — Security Layer

### Credential Navigation

Guide the user to the credentials they need.

**Frontend path — Data API URL + OAuth App:**

1. Log in to Databricks workspace
2. Navigate to **Lakebase** → select project → **Data API** tab
3. Click **Enable Data API** (if not already enabled — this creates the `authenticator` role and exposes schemas via REST)
4. Copy the **REST endpoint URL** (this is your `VITE_DATA_API_BASE_URL`)
5. Configure **CORS** in Advanced Settings: add your app's domain (empty = allow all for dev)
6. Register OAuth application:
   - If personal workspace: Workspace Settings → Security → OAuth Applications → Add
   - If team workspace: share instructions with admin (below)

**Admin request template (team workspace):**

> "Please register an OAuth application in Workspace Settings → Security → OAuth Applications:
> - Name: `your-app-name`
> - Redirect URIs: `http://localhost:5173/auth/callback` (add production URI too)
> - Grant types: `Authorization Code`
> - Return the **Client ID** — no client secret needed for PKCE."

**Backend path — PostgreSQL connection + SDK credentials:**

1. Lakebase Postgres → select project → **Connect** (top-right)
2. Configure: Branch, Compute, Database, Role
3. Copy: Host, Database, User, Endpoint path

**SDK credential choice (based on `.lakebase` personal field):**

| Context | Recommended | Why |
|---|---|---|
| Personal workspace | PAT | You own the account — departure risk is zero |
| Team/org workspace | M2M service principal | PAT tied to personal account breaks if you leave |

**PAT setup:** User Settings → Developer → Access tokens → scope: **`postgres`** (not `sql`)

**M2M setup (personal workspace):** Settings → Identity & Access → Service principals → Add → Generate secret → Assign `Can use` on Lakebase project

**M2M setup (team workspace — share with admin):**

> "Please create a service principal for Lakebase access:
> 1. Settings → Identity & Access → Service principals → Add (name: `yourapp-lakebase-prod`)
> 2. Generate secret (shown once — save immediately)
> 3. Assign `Can use` on the Lakebase project
> 4. Return Client ID + Client Secret to developer."

---

### Frontend env vars

```env
VITE_DATABRICKS_HOST=https://your-workspace.databricks.com
VITE_DATABRICKS_CLIENT_ID=<from OAuth app>
VITE_OAUTH_REDIRECT_URI=http://localhost:5173/auth/callback
VITE_DATA_API_BASE_URL=<REST endpoint URL from Lakebase project → Data API tab>
```

### Backend env vars

```env
DATABRICKS_HOST=https://your-workspace.databricks.com
DATABRICKS_TOKEN=<PAT>                       # personal / dev
# OR for team:
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

### Frontend — PKCE Login Flow

```typescript
// auth/pkce.ts
function generateCodeVerifier(): string {
  const array = new Uint8Array(32)
  crypto.getRandomValues(array)
  return btoa(String.fromCharCode(...array))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '')
}

async function generateCodeChallenge(verifier: string): Promise<string> {
  const data = new TextEncoder().encode(verifier)
  const digest = await crypto.subtle.digest('SHA-256', data)
  return btoa(String.fromCharCode(...new Uint8Array(digest)))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '')
}

export async function initiateLogin(): Promise<void> {
  const verifier = generateCodeVerifier()
  const challenge = await generateCodeChallenge(verifier)
  const state = crypto.randomUUID()

  sessionStorage.setItem('pkce_verifier', verifier)
  sessionStorage.setItem('oauth_state', state)

  const params = new URLSearchParams({
    response_type: 'code',
    client_id: import.meta.env.VITE_DATABRICKS_CLIENT_ID,
    redirect_uri: import.meta.env.VITE_OAUTH_REDIRECT_URI,
    scope: 'offline_access all-apis',
    code_challenge: challenge,
    code_challenge_method: 'S256',
    state,
  })

  window.location.href =
    `${import.meta.env.VITE_DATABRICKS_HOST}/oidc/v1/authorize?${params}`
}

export async function handleCallback(
  code: string,
  returnedState: string
): Promise<void> {
  const verifier = sessionStorage.getItem('pkce_verifier')
  const expectedState = sessionStorage.getItem('oauth_state')

  if (!verifier) throw new Error('PKCE verifier missing — possible CSRF')
  if (returnedState !== expectedState) throw new Error('OAuth state mismatch — possible CSRF')

  sessionStorage.removeItem('pkce_verifier')
  sessionStorage.removeItem('oauth_state')

  const res = await fetch(
    `${import.meta.env.VITE_DATABRICKS_HOST}/oidc/v1/token`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'authorization_code',
        code,
        redirect_uri: import.meta.env.VITE_OAUTH_REDIRECT_URI,
        client_id: import.meta.env.VITE_DATABRICKS_CLIENT_ID,
        code_verifier: verifier,
      }),
    }
  )
  if (!res.ok) throw new Error(`Token exchange failed: ${res.status}`)

  const { access_token, refresh_token, expires_in } = await res.json()
  sessionStorage.setItem(
    'databricks_tokens',
    JSON.stringify({
      accessToken: access_token,
      refreshToken: refresh_token,
      expiresAt: Date.now() + expires_in * 1000,
    })
  )
}
```

**Callback route** — create a page at `/auth/callback`:
```typescript
const params = new URLSearchParams(window.location.search)
await handleCallback(params.get('code')!, params.get('state')!)
```

---

### Frontend — Silent Refresh (Token Manager)

Tokens expire in ~1 hour. Rules:
- Store in `sessionStorage` only — never `localStorage`
- Deduplicate concurrent refresh calls
- On failure, clear tokens and redirect to login

```typescript
// auth/token-manager.ts
interface TokenState {
  accessToken: string
  refreshToken: string
  expiresAt: number
}

class DatabricksTokenManager {
  private refreshPromise: Promise<string> | null = null

  private getState(): TokenState | null {
    const raw = sessionStorage.getItem('databricks_tokens')
    return raw ? (JSON.parse(raw) as TokenState) : null
  }

  private setState(state: TokenState): void {
    sessionStorage.setItem('databricks_tokens', JSON.stringify(state))
  }

  async getAccessToken(): Promise<string> {
    const state = this.getState()
    if (!state) throw new Error('Not authenticated. Please log in.')
    if (Date.now() >= state.expiresAt - 60_000) {
      return this.silentRefresh(state.refreshToken)
    }
    return state.accessToken
  }

  private silentRefresh(refreshToken: string): Promise<string> {
    if (!this.refreshPromise) {
      this.refreshPromise = this.doRefresh(refreshToken).finally(() => {
        this.refreshPromise = null
      })
    }
    return this.refreshPromise
  }

  private async doRefresh(refreshToken: string): Promise<string> {
    const res = await fetch(
      `${import.meta.env.VITE_DATABRICKS_HOST}/oidc/v1/token`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({
          grant_type: 'refresh_token',
          refresh_token: refreshToken,
          client_id: import.meta.env.VITE_DATABRICKS_CLIENT_ID,
        }),
      }
    )
    if (!res.ok) {
      this.clearTokens()
      throw new Error('Session expired. Please log in again.')
    }
    const { access_token, refresh_token: newRefreshToken, expires_in } =
      await res.json()
    this.setState({
      accessToken: access_token,
      refreshToken: newRefreshToken ?? refreshToken,
      expiresAt: Date.now() + expires_in * 1000,
    })
    return access_token
  }

  isAuthenticated(): boolean {
    return this.getState() !== null
  }

  clearTokens(): void {
    sessionStorage.removeItem('databricks_tokens')
  }
}

export const tokenManager = new DatabricksTokenManager()
```

---

### Backend — Token Rotator (Mandatory)

All backend connections use short-lived OAuth tokens as the PostgreSQL password.
Rotation is mandatory — tokens expire in ~1 hour.

**How it works:**
```
Auth credential (PAT or M2M secret)
  → WorkspaceClient authenticates to Databricks API
    → generate_database_credential(endpoint=...)
      → short-lived Lakebase token (~1 hour)
        → used as psycopg / pg password
```

**Auth modes:**

| Mode | Env vars | Best for |
|---|---|---|
| Static token | `LAKEBASE_OAUTH_TOKEN` | Quick local testing only (~1h expiry) |
| PAT auto-rotate | `DATABRICKS_HOST` + `DATABRICKS_TOKEN` | Personal workspace |
| M2M auto-rotate | `DATABRICKS_HOST` + `DATABRICKS_CLIENT_ID` + `DATABRICKS_CLIENT_SECRET` | Team workspace |

```python
# auth/token_rotator.py
import logging
import os
import time
import threading

logger = logging.getLogger(__name__)

_REFRESH_BUFFER = 60


class LakebaseTokenRotator:
    def __init__(self) -> None:
        from databricks.sdk import WorkspaceClient
        self._client = WorkspaceClient()
        self._endpoint = os.environ["LAKEBASE_ENDPOINT_PATH"]
        self._token: str | None = None
        self._expiry: float = 0.0
        self._lock = threading.Lock()

    def get_token(self) -> str:
        with self._lock:
            if time.time() >= self._expiry - _REFRESH_BUFFER:
                self._refresh()
        return self._token

    def _refresh(self) -> None:
        cred = self._client.postgres.generate_database_credential(
            endpoint=self._endpoint
        )
        self._token = cred.token
        try:
            if cred.expire_time and hasattr(cred.expire_time, 'timestamp'):
                self._expiry = cred.expire_time.timestamp()
            elif cred.expire_time:
                self._expiry = float(cred.expire_time)
            else:
                self._expiry = time.time() + 3600
        except (TypeError, ValueError):
            self._expiry = time.time() + 3600


_rotator: LakebaseTokenRotator | None = None
_rotator_lock = threading.Lock()


def _sdk_credentials_configured() -> bool:
    return bool(
        os.environ.get("DATABRICKS_TOKEN")
        or os.environ.get("DATABRICKS_CLIENT_ID")
    )


def get_lakebase_token() -> str:
    if _sdk_credentials_configured():
        global _rotator
        if _rotator is None:
            with _rotator_lock:
                if _rotator is None:
                    _rotator = LakebaseTokenRotator()
        return _rotator.get_token()

    token = os.environ.get("LAKEBASE_OAUTH_TOKEN", "")
    if not token:
        raise RuntimeError(
            "No Lakebase credentials found. Set either:\n"
            "  DATABRICKS_TOKEN=<pat>          (auto-rotation, dev)\n"
            "  DATABRICKS_CLIENT_ID + SECRET   (auto-rotation, production)\n"
            "  LAKEBASE_OAUTH_TOKEN=<token>    (static, expires ~1h, testing only)"
        )
    logger.warning(
        "Using static LAKEBASE_OAUTH_TOKEN — expires ~1 hour. "
        "Set DATABRICKS_TOKEN for automatic rotation."
    )
    return token
```

### Node.js — Token Rotator

```typescript
// auth/token-rotator.ts
import { WorkspaceClient } from '@databricks/sdk'

let cachedToken: string | null = null
let tokenExpiry = 0
const REFRESH_BUFFER = 60_000

export function getLakebaseToken(): string {
  if (cachedToken && Date.now() < tokenExpiry - REFRESH_BUFFER) {
    return cachedToken
  }
  const client = new WorkspaceClient()
  const cred = client.postgres.generateDatabaseCredential({
    endpoint: process.env.LAKEBASE_ENDPOINT_PATH!,
  })
  cachedToken = cred.token
  tokenExpiry = cred.expireTime
    ? new Date(cred.expireTime).getTime()
    : Date.now() + 3_600_000
  return cachedToken
}
```

---

### Secret Management

- Never commit `.env` — add to `.gitignore`
- Always create `.env.example` with placeholders
- Load credentials from environment variables at runtime

```env
# .env.example — commit this
DATABRICKS_HOST=https://your-workspace.databricks.com
DATABRICKS_TOKEN=                    # dev: personal access token (postgres scope)
DATABRICKS_CLIENT_ID=                # prod: service principal
DATABRICKS_CLIENT_SECRET=            # prod: service principal secret
LAKEBASE_HOST=
LAKEBASE_PORT=5432
LAKEBASE_DB=
LAKEBASE_USER=
LAKEBASE_ENDPOINT_PATH=projects/.../branches/.../endpoints/primary
DATABASE_URL=                        # postgresql://user@host/db?sslmode=require
```

---

## Phase 4b — Data Migration (only if Intent = Migrate)

Skip this phase entirely if the user selected Intent 1, 3, or 4 in Phase 1.
Enter here after Phase 3+4 are complete (connection + auth established to Lakebase).

**Important:** Data migration ALWAYS uses PostgreSQL wire protocol for bulk import,
even if the app will use Data API afterward. The Data API is not designed for bulk
loading (one POST per row is too slow for thousands of rows). After migration
completes, the app connects via its chosen method (Data API or PG wire).

### Detect Source Database

Scan for existing database signals:
- `DATABASE_URL` in `.env` → parse dialect (postgres, mysql, sqlite)
- `docker-compose.yml` → service names (postgres, mysql, mongo)
- ORM config → connection strings, engine declarations
- Existing migration files → tool + dialect

If not detectable, ask:

> "What's your current (source) database?
> 1. **PostgreSQL** (Supabase, Neon, RDS, self-hosted)
> 2. **MySQL / MariaDB**
> 3. **SQLite**
> 4. **MongoDB** (document → relational mapping needed)
> 5. **Other** (describe)"

---

### Path A — One-Time Copy

Full dump-and-load with cutover.

**Step 1: Export from source**

```bash
# PostgreSQL → PostgreSQL (most common for Lakebase)
pg_dump --no-owner --no-privileges --schema-only -f schema.sql "$SOURCE_DATABASE_URL"
pg_dump --no-owner --no-privileges --data-only --format=csv -f data/ "$SOURCE_DATABASE_URL"

# MySQL → PostgreSQL (requires schema translation)
mysqldump --no-create-info --tab=/tmp/export --fields-terminated-by=',' source_db
```

**Step 2: Schema adaptation**

> Invoke `database-migrations` skill for type mapping if source != PostgreSQL.

Common type mappings (MySQL → Lakebase/PostgreSQL):

| MySQL | PostgreSQL |
|---|---|
| `INT AUTO_INCREMENT` | `SERIAL` or `INTEGER GENERATED ALWAYS AS IDENTITY` |
| `TINYINT(1)` | `BOOLEAN` |
| `DATETIME` | `TIMESTAMP` |
| `TEXT` / `LONGTEXT` | `TEXT` |
| `ENUM(...)` | `TEXT CHECK (col IN (...))` or custom enum type |
| `JSON` | `JSONB` |

**Step 3: Import into Lakebase**

```python
# scripts/import_to_lakebase.py
import csv
import os
from pathlib import Path
from db.connection import get_conn

DATA_DIR = Path("data/")

def import_table(table_name: str, csv_path: Path) -> int:
    with get_conn() as conn:
        with conn.cursor() as cur:
            with open(csv_path) as f:
                reader = csv.reader(f)
                headers = next(reader)
                cols = ", ".join(headers)
                placeholders = ", ".join(["%s"] * len(headers))
                rows = list(reader)
                for i in range(0, len(rows), 1000):
                    batch = rows[i:i+1000]
                    cur.executemany(
                        f"INSERT INTO {table_name} ({cols}) VALUES ({placeholders})",
                        batch,
                    )
            conn.commit()
    return len(rows)

# Import tables in dependency order (parents before children)
IMPORT_ORDER = ["users", "orders", "order_items"]  # adjust to your schema

for table in IMPORT_ORDER:
    csv_file = DATA_DIR / f"{table}.csv"
    if csv_file.exists():
        count = import_table(table, csv_file)
        print(f"  {table}: {count} rows imported")
```

**Step 4: Verification**

```python
# scripts/verify_migration.py
from db.connection import get_conn

SOURCE_COUNTS = {
    "users": 15234,       # fill from source: SELECT count(*) FROM users
    "orders": 89012,
    "order_items": 234567,
}

with get_conn() as conn:
    with conn.cursor() as cur:
        for table, expected in SOURCE_COUNTS.items():
            cur.execute(f"SELECT count(*) FROM {table}")
            actual = cur.fetchone()[0]
            status = "PASS" if actual == expected else "FAIL"
            print(f"  [{status}] {table}: expected={expected} actual={actual}")
```

**Step 5: Cutover checklist**

- [ ] All tables imported with correct row counts
- [ ] Foreign key constraints valid (no orphaned references)
- [ ] Sequences reset to max(id) + 1 for each table
- [ ] Application `.env` updated to point to Lakebase
- [ ] Old database connection removed from app config
- [ ] Tested app end-to-end against Lakebase
- [ ] Old database kept read-only for 7 days as rollback safety net
- [ ] Old database decommissioned after verification period

---

### Path B — Dual-Run (Replication)

Both databases stay live. Writes go to source, replicated to Lakebase (or vice versa).

**When to use:** Lakebase is for analytics/read replicas, or you're de-risking a migration by running both in parallel before cutting over.

**Strategy options:**

| Strategy | Latency | Complexity | Best for |
|---|---|---|---|
| CDC (Change Data Capture) | Near real-time | High | Production replication |
| Scheduled sync (cron) | Minutes to hours | Low | Analytics, reporting |
| Dual-write in app | Real-time | Medium | Small tables, critical data |

**Option 1: Scheduled sync (simplest)**

```python
# scripts/sync_to_lakebase.py
"""
Cron-based sync: copies new/updated rows from source to Lakebase.
Run via: cron every 5 min, or as a scheduled task.
"""
import os
from datetime import datetime, timedelta
from db.connection import get_conn as get_lakebase_conn
import psycopg  # source connection

SYNC_WINDOW = timedelta(minutes=10)  # overlap for safety

def get_source_conn():
    return psycopg.connect(os.environ["SOURCE_DATABASE_URL"])

def sync_table(table: str, timestamp_col: str = "updated_at") -> int:
    since = datetime.utcnow() - SYNC_WINDOW
    with get_source_conn() as source:
        with source.cursor() as cur:
            cur.execute(
                f"SELECT * FROM {table} WHERE {timestamp_col} >= %s",
                (since,),
            )
            cols = [d.name for d in cur.description]
            rows = cur.fetchall()

    if not rows:
        return 0

    col_names = ", ".join(cols)
    placeholders = ", ".join(["%s"] * len(cols))
    conflict_cols = ", ".join(f"{c} = EXCLUDED.{c}" for c in cols if c != "id")

    with get_lakebase_conn() as dest:
        with dest.cursor() as cur:
            for row in rows:
                cur.execute(
                    f"INSERT INTO {table} ({col_names}) VALUES ({placeholders}) "
                    f"ON CONFLICT (id) DO UPDATE SET {conflict_cols}",
                    row,
                )
        dest.commit()
    return len(rows)

TABLES_TO_SYNC = ["users", "orders"]  # tables with updated_at column

for table in TABLES_TO_SYNC:
    count = sync_table(table)
    print(f"  {table}: {count} rows synced")
```

**Option 2: Dual-write pattern (application-level)**

```python
# middleware/dual_write.py
from db.connection import get_conn as get_lakebase_conn

def dual_write(source_result, table: str, operation: str, data: dict):
    """Call after successful write to source DB. Fire-and-forget to Lakebase."""
    try:
        with get_lakebase_conn() as conn:
            with conn.cursor() as cur:
                if operation == "insert":
                    cols = ", ".join(data.keys())
                    vals = ", ".join(["%s"] * len(data))
                    cur.execute(
                        f"INSERT INTO {table} ({cols}) VALUES ({vals}) ON CONFLICT (id) DO NOTHING",
                        tuple(data.values()),
                    )
                elif operation == "update":
                    set_clause = ", ".join(f"{k} = %s" for k in data if k != "id")
                    cur.execute(
                        f"UPDATE {table} SET {set_clause} WHERE id = %s",
                        (*[v for k, v in data.items() if k != "id"], data["id"]),
                    )
    except Exception as e:
        # Log but don't fail the primary write
        logger.warning(f"Dual-write to Lakebase failed: {e}")
```

**Conflict resolution:** If both databases accept writes, define a winner:
- Last-write-wins (by `updated_at`)
- Source-is-primary (Lakebase is read-only replica)
- Lakebase-is-primary (source becomes read-only, for gradual cutover)

---

### Path C — Gradual Migration

Move table by table. App reads from both databases during transition.

**Step 1: Migration order**

Prioritize tables with no foreign key dependencies first:

```
Phase 1: Independent tables (users, categories, settings)
Phase 2: Tables with FK to Phase 1 (orders → users)
Phase 3: Join/junction tables (order_items → orders)
```

**Step 2: Dual-read router**

```python
# db/router.py
import os
from db.connection import get_conn as get_lakebase_conn
import psycopg

# Tables that have been migrated to Lakebase
MIGRATED_TABLES = set(os.environ.get("MIGRATED_TABLES", "").split(","))

def get_source_conn():
    return psycopg.connect(os.environ["SOURCE_DATABASE_URL"])

def get_read_conn(table: str):
    """Route reads to Lakebase for migrated tables, source for others."""
    if table in MIGRATED_TABLES:
        return get_lakebase_conn()
    return get_source_conn()

def get_write_conn(table: str):
    """Writes always go to the authoritative database for that table."""
    if table in MIGRATED_TABLES:
        return get_lakebase_conn()
    return get_source_conn()
```

**Step 3: Per-table migration process**

For each table:
1. Copy schema to Lakebase (Phase 3 connection already exists)
2. Bulk import existing data (Path A import script)
3. Enable dual-write for that table
4. Verify row counts match
5. Add table to `MIGRATED_TABLES` env var
6. Remove dual-write (Lakebase is now authoritative)

**Step 4: Completion**

When all tables are in `MIGRATED_TABLES`:
- Remove the router — all reads/writes go to Lakebase
- Remove `SOURCE_DATABASE_URL` from config
- Decommission source database

---

## Phase 4c — Post-Migration Code Cleanup (only if Intent = Migrate)

**When to run this phase:**
- **One-time copy:** Run immediately after data is verified and app is switched over
- **Dual-run:** Run ONLY after the user confirms full cutover to Lakebase (both databases may still be live — do NOT clean up prematurely)
- **Gradual migration:** Run ONLY after ALL tables are migrated and user confirms cutover is complete

Ask before proceeding:
> "Has the migration fully completed? Are you ready to remove all references to the old database?
> (If dual-run or gradual migration is still in progress, skip this phase for now.)"

After data is migrated and verified, clean up the codebase to ensure all code
uses Lakebase and nothing still references the legacy database.

### Step 1 — Scan for Legacy References

Search the codebase for any remaining references to the old database:

```bash
# Find old connection strings, env vars, imports
grep -rn "SOURCE_DATABASE_URL\|OLD_DB_\|legacy.*conn\|old.*pool" --include="*.{py,ts,tsx,js,jsx,env*,yml,yaml,json,toml}" .
grep -rn "psycopg2\|mysql\|sqlite3\|mongoose" --include="*.{py,ts,js}" .  # old driver imports
grep -rn "localhost:5432\|localhost:3306\|127.0.0.1:5432" .  # hardcoded local DB
```

Check for:
- [ ] Old `DATABASE_URL` or source connection env vars
- [ ] Old driver imports (`psycopg2`, `mysql-connector`, `sqlite3`, `mongoose`)
- [ ] Old connection pool files (`db/old_pool.ts`, `db/legacy_connection.py`)
- [ ] Dual-read router code (if gradual migration was used)
- [ ] Dual-write middleware
- [ ] Old migration tool config (`alembic.ini` pointing to old DB, old `DATABASE_URL` in prisma schema)
- [ ] Docker compose services for the old database
- [ ] CI/CD scripts that provision or test against the old DB
- [ ] Hardcoded connection strings in test fixtures

### Step 2 — Replace Old Connections

For each legacy reference found:

| What | Action |
|---|---|
| Old driver imports | Replace with Lakebase connection import |
| `SOURCE_DATABASE_URL` env var | Remove from `.env`, `.env.example`, CI config |
| Old connection files | Delete (e.g. `db/postgres_pool.py`, `db/mysql.ts`) |
| Dual-read router | Replace with direct Lakebase calls |
| Dual-write middleware | Remove entirely |
| Docker compose DB service | Remove old `postgres:` or `mysql:` service |
| Old ORM config | Update to point to Lakebase (or remove if using Data API) |

### Step 3 — Remove Old Dependencies

```bash
# Python — remove old drivers no longer needed
pip uninstall psycopg2 mysql-connector-python pymongo
# Update requirements.txt / pyproject.toml

# Node — remove old drivers
npm uninstall pg mysql2 mongoose better-sqlite3
# Or keep pg if still using it for Lakebase wire protocol
```

Only remove drivers that are fully replaced. If you migrated from `psycopg2` to
`psycopg3` for Lakebase, remove `psycopg2` but keep `psycopg`.

### Step 4 — Update Configuration Files

- [ ] `.env.example` — remove old vars, ensure only Lakebase vars remain
- [ ] `docker-compose.yml` — remove old DB service, volumes, networks
- [ ] CI/CD pipeline — remove old DB provisioning steps, update test DB config
- [ ] ORM schema — update `datasource` URL to Lakebase (Prisma, Django settings, etc.)
- [ ] Health check endpoints — update to check Lakebase, not old DB

### Step 5 — Verify No Orphaned References

Run the app and check:

```bash
# Ensure no runtime errors from missing old connections
# Run tests — they should pass without the old DB running
# Check logs for connection errors to old host/port

# Final grep — should return ZERO results
grep -rn "SOURCE_DATABASE_URL\|OLD_DB_" --include="*.{py,ts,tsx,js,jsx}" .
```

### Step 6 — Cleanup Checklist

- [ ] All code imports use Lakebase connection modules
- [ ] No env vars reference the old database
- [ ] Old driver packages removed from dependencies
- [ ] Docker compose has no old DB services
- [ ] CI/CD provisions Lakebase (or Data API), not old DB
- [ ] Tests pass without old database running
- [ ] `.lakebase` marker updated: remove `source_db` field (migration complete)
- [ ] Old database kept read-only for rollback window (7-14 days recommended)
- [ ] After rollback window: decommission old database

---

## Phase 5 — Data Patterns

### Route by Connection Method

Before generating queries, check `.lakebase` for `connection_method` and `hosting`:

| connection_method | hosting | Generate |
|---|---|---|
| `data-api` | `databricks-apps` | **Databricks Apps Data API queries** — token from `x-forwarded-access-token` header |
| `data-api` | `external` | **Data API queries** — token from `tokenManager` (PKCE) or backend proxy |
| `pg-wire` | `databricks-apps` | **PG queries** — use auto-injected credentials |
| `pg-wire` | `external` | **PG queries** — use token rotator |
| not set in marker | — | Check existing files: `lakebase-client.ts` → Data API; `connection.py`/`pool.ts` → PG wire. If neither exists, ask. |

### Step 1 — Discover Entities

Scan for existing schema files, models, or migrations:
- `prisma/schema.prisma` — model names
- `models.py`, `models/*.py` — Django/SQLAlchemy models
- `db/migrations/` — CREATE TABLE statements
- `types/`, `interfaces/` — TypeScript interfaces

If nothing found, ask:

> "What are the main tables in your Lakebase project?
> List them with key columns, e.g.:
> - users (id, name, email, created_at)
> - orders (id, user_id, total, status)"

### Step 2 — Required Operations

> "For each entity, which operations?
> 1. Read-only (list + get by ID)
> 2. Full CRUD (read + insert + update + delete)
> 3. Bulk insert
> 4. Multi-table transactions
> 5. Specific queries (describe)"

### Step 3 — Generate Query Files

---

### Databricks Apps — Query Modules (hosting = databricks-apps)

Same as the Data API patterns below, but token comes from the request header
instead of a token manager. The key difference in the client:

```typescript
// lib/lakebase-client.ts (Databricks Apps variant)
const DATA_API_BASE = process.env.LAKEBASE_DATA_API_URL
const SCHEMA = process.env.LAKEBASE_SCHEMA ?? 'public'

export async function dataApiFetch<T>(
  path: string,
  userToken: string,  // extracted from x-forwarded-access-token header
  params?: Record<string, string>
): Promise<T> {
  const url = new URL(`${DATA_API_BASE}/${SCHEMA}/${path}`)
  if (params) Object.entries(params).forEach(([k, v]) => url.searchParams.set(k, v))
  const res = await fetch(url.toString(), {
    headers: { Authorization: `Bearer ${userToken}` },
  })
  if (!res.ok) throw new Error(`Data API ${res.status}: ${await res.text()}`)
  return res.json() as Promise<T>
}
```

Query modules are identical to the "Frontend — TypeScript Query Modules" below,
except they pass `userToken` as a parameter instead of calling `tokenManager.getAccessToken()`.

---

### Frontend — TypeScript Query Modules

For each entity, generate `lib/api/[entity]-queries.ts` and `types/[entity].ts`.

```typescript
// types/[entity].ts
export interface [Entity] {
  id: number
  [column]: [type]
}
```

```typescript
// lib/api/[entity]-queries.ts
import { dataApiFetch, dataApiMutate } from '@/lib/lakebase-client'
import type { [Entity] } from '@/types/[entity]'

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
  return dataApiFetch<[Entity][]>('[entity]', params)
}

export async function get[Entity]ById(id: number): Promise<[Entity] | null> {
  const rows = await dataApiFetch<[Entity][]>('[entity]', {
    id: `eq.${id}`,
    limit: '1',
  })
  return rows[0] ?? null
}

export async function create[Entity](data: Omit<[Entity], 'id'>): Promise<[Entity]> {
  const [created] = await dataApiMutate<[Entity][]>(
    '[entity]',
    'POST',
    data,
    'return=representation'
  )
  return created
}

export async function update[Entity](
  id: number,
  data: Partial<Omit<[Entity], 'id'>>
): Promise<void> {
  await dataApiMutate('[entity]?id=eq.' + id, 'PATCH', data)
}

export async function delete[Entity](id: number): Promise<void> {
  await dataApiMutate('[entity]?id=eq.' + id, 'DELETE')
}
```

**Bulk insert:**
```typescript
export async function bulkCreate[Entities](
  items: Omit<[Entity], 'id'>[]
): Promise<[Entity][]> {
  return dataApiMutate<[Entity][]>(
    '[entity]',
    'POST',
    items,
    'return=representation'
  )
}
```

---

### PostgREST Filter Operators

| Operator | Meaning | Example |
|---|---|---|
| `eq.value` | = | `status: 'eq.active'` |
| `neq.value` | != | `status: 'neq.deleted'` |
| `gt.value` | > | `id: 'gt.100'` |
| `gte.value` | >= | `created_at: 'gte.2024-01-01'` |
| `lt.value` | < | `price: 'lt.50'` |
| `lte.value` | <= | `score: 'lte.100'` |
| `like.*term*` | LIKE | `name: 'like.*john*'` |
| `ilike.*term*` | ILIKE | `email: 'ilike.*@gmail*'` |
| `in.(a,b,c)` | IN | `status: 'in.(active,pending)'` |
| `is.null` | IS NULL | `deleted_at: 'is.null'` |
| `not.is.null` | IS NOT NULL | `email: 'not.is.null'` |

---

### Frontend Error Handling

```typescript
// lib/lakebase-errors.ts
export class DataApiError extends Error {
  constructor(public readonly status: number, message: string) {
    super(message)
    this.name = 'DataApiError'
  }
  get isNotFound() { return this.status === 404 }
  get isConflict() { return this.status === 409 }
  get isUnauthorized() { return this.status === 401 }
  get isValidation() { return this.status === 422 }
}
```

---

### Backend — Python Query Modules

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

**Bulk insert:**
```python
from psycopg2.extras import execute_values

def bulk_create_[entities](items: list[dict]) -> None:
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

**Multi-table transactions:**
```python
def create_[parent]_with_[children](
    parent_data: dict,
    children: list[dict],
) -> int:
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
    return parent_id
```

---

## Phase 6 — Verification

### Test Script

Generate for the user's stack:

**Python backend:**
```python
# scripts/verify_lakebase.py
from db.connection import get_conn

with get_conn() as conn:
    with conn.cursor() as cur:
        cur.execute("SELECT version()")
        print("Connected:", cur.fetchone()[0])
        cur.execute("SELECT current_database(), current_user")
        db, user = cur.fetchone()
        print(f"Database: {db}, User: {user}")
print("Lakebase connection verified.")
```

**TypeScript frontend:**
```typescript
// scripts/test-connection.ts
import { dataApiFetch } from '@/lib/lakebase-client'
dataApiFetch('').then(() => console.log('Data API reachable')).catch(console.error)
```

---

### Security Checklist

Before marking integration complete:

**All apps:**
- [ ] No tokens or passwords committed to source control
- [ ] `.env` in `.gitignore`
- [ ] `.env.example` created with placeholders
- [ ] SSL enforced (`sslmode=require`)
- [ ] Credentials loaded from env vars only
- [ ] No connection poolers with OAuth connections
- [ ] Minimum required permissions scoped (`postgres` scope only)

**Backend / script:**
- [ ] Token rotation implemented (`LakebaseTokenRotator`)
- [ ] Personal workspace: PAT scoped to `postgres`, expiry reminder set
- [ ] Team workspace: M2M service principal in use

**Frontend:**
- [ ] Tokens in `sessionStorage` only (never `localStorage`)
- [ ] PKCE login flow implemented
- [ ] Silent refresh implemented
- [ ] Logout clears `sessionStorage`

---

### Completion Summary

> "Lakebase integration complete.
>
> **Files created:** [list]
> **Test:** `[run command]`
>
> All layers in place: connection → security → data access.
> Need help wiring these into your routes or components?"
