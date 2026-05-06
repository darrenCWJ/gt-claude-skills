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
- Enter at Phase 5 only

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

- Answer 3 → jump to Phase 5
- Answer 4 → ask what's broken, provide targeted fix (no full pipeline)

### Question 2 — Workspace (ask only if not determinable from .env)

> "Is this your personal Databricks workspace, or a shared team/org workspace?
> This determines auth approach — PAT for personal, service principal for teams."

### Auto-inferred (never ask):

- **App type** — inferred from project structure
- **Stack** — inferred from package manager / entrypoint
- **Driver preference** — asked later in Phase 3 (backend only)

### After intent is clear:

Write `.lakebase` marker:

```json
{"app_type": "<type>", "stack": "<stack>", "personal": <bool>}
```

---

## Phase 2 — Plan Presentation

Present what will be generated. Wait for confirmation before writing any files.

> **Lakebase Integration Plan**
>
> | | |
> |---|---|
> | App type | [frontend / fullstack / script / migration] |
> | Stack | [TypeScript / Python / Java / Kotlin] |
> | Auth | [PKCE (frontend) / PAT auto-rotate (personal) / M2M (team)] |
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

## Phase 3 — Connection Setup

### Frontend — Lakebase Data API Client

No PostgreSQL driver needed. Auth via Databricks OAuth PKCE.

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
2. Navigate to **Lakebase Postgres** → select project → **Data API** tab → copy base URL
3. Register OAuth application:
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
VITE_DATA_API_BASE_URL=https://your-workspace.databricks.com/api/2.0/lakebase/v1/projects/PROJECT_ID/data-api
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

## Phase 5 — Data Patterns

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
  return dataApiFetch<[Entity][]>('public/[entity]', params)
}

export async function get[Entity]ById(id: number): Promise<[Entity] | null> {
  const rows = await dataApiFetch<[Entity][]>('public/[entity]', {
    id: `eq.${id}`,
    limit: '1',
  })
  return rows[0] ?? null
}

export async function create[Entity](data: Omit<[Entity], 'id'>): Promise<[Entity]> {
  const [created] = await dataApiMutate<[Entity][]>(
    'public/[entity]',
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
  await dataApiMutate('public/[entity]?id=eq.' + id, 'PATCH', data)
}

export async function delete[Entity](id: number): Promise<void> {
  await dataApiMutate('public/[entity]?id=eq.' + id, 'DELETE')
}
```

**Bulk insert:**
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
