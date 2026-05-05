---
name: databricks-security
description: >
  Security patterns for Databricks/Lakebase: frontend OAuth PKCE silent
  refresh, mandatory backend token rotation, secret management rules, and
  pre-completion security checklist.
  TRIGGER when: databricks-connection has been set up; writing any auth,
  token, or credential code for Databricks/Lakebase; user asks about
  Databricks OAuth, token expiry, or token rotation; DATABRICKS_TOKEN or
  OAuth appears in Databricks context; any Databricks connection file is
  being written or reviewed; before marking any Databricks integration complete.
  SKIP: connection layer has not been set up yet — invoke databricks-connection
  first.
version: 1.0.0
tags: [databricks, lakebase, security, oauth, token-rotation]
---

# Databricks Security Skill

## When to Invoke

**Auto-invoke this skill when ANY of these signals appear:**
- `databricks-connection` has just generated connection boilerplate
- Writing or reviewing auth/token code for Databricks or Lakebase
- User asks about OAuth, token expiry, token rotation, or session refresh
- `DATABRICKS_TOKEN` or OAuth flow appears in any Databricks context
- Any file storing Databricks credentials is being created
- Pre-completion checklist needed for a Databricks integration

**Invoke order**: `databricks-architecture` → `databricks-connection` → **`databricks-security`** → `databricks-data-patterns`

---

## Purpose

Apply security patterns after connection setup. Covers token rotation for both
frontend and backend, secret management, and a final security checklist.

---

## Frontend — OAuth PKCE Silent Refresh

Frontend tokens expire in ~1 hour. Silent refresh uses the OAuth refresh token
to get a new access token without requiring the user to log in again.

**Rules:**
- Store tokens in `sessionStorage` only — never `localStorage` (persists across tabs/restarts)
- Deduplicate concurrent refresh calls to avoid token race conditions
- On refresh failure, clear tokens and redirect to login

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
    return raw ? JSON.parse(raw) : null
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

  private async silentRefresh(refreshToken: string): Promise<string> {
    if (!this.refreshPromise) {
      this.refreshPromise = this.doRefresh(refreshToken).finally(() => {
        this.refreshPromise = null
      })
    }
    return this.refreshPromise
  }

  private async doRefresh(refreshToken: string): Promise<string> {
    const res = await fetch('/api/auth/refresh', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ refresh_token: refreshToken }),
    })
    if (!res.ok) {
      sessionStorage.removeItem('databricks_tokens')
      throw new Error('Session expired. Please log in again.')
    }
    const { access_token, expires_in } = await res.json()
    this.setState({
      accessToken: access_token,
      refreshToken,
      expiresAt: Date.now() + expires_in * 1000,
    })
    return access_token
  }

  clearTokens(): void {
    sessionStorage.removeItem('databricks_tokens')
  }
}

export const tokenManager = new DatabricksTokenManager()
```

```typescript
// Usage in Data API client — replace direct sessionStorage access
import { tokenManager } from '@/auth/token-manager'

export async function dataApiGet<T>(
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
```

---

## Backend — OAuth Token Rotation (Mandatory)

All backend connections use Databricks OAuth. Tokens expire in ~1 hour.
Token rotation is mandatory for every backend implementation.

**Rules:**
- Never use a static token — always use the rotator
- Refresh 60 seconds before expiry to avoid mid-request failures
- Use a thread lock to prevent concurrent rotation race conditions
- Do not use connection poolers (PgBouncer) — incompatible with OAuth

```python
# auth/token_rotator.py
import time
import threading
from databricks.sdk import WorkspaceClient

class LakebaseTokenRotator:
    """Thread-safe Databricks OAuth token rotator for Lakebase connections."""

    def __init__(self) -> None:
        self._client = WorkspaceClient()
        self._token: str | None = None
        self._expiry: float = 0.0
        self._lock = threading.Lock()

    def get_token(self) -> str:
        with self._lock:
            if time.time() >= self._expiry - 60:
                cred = self._client.postgres.generate_database_credential(
                    parent="projects/YOUR_PROJECT_NAME/branches/production"
                )
                self._token = cred.token
                self._expiry = time.time() + 3600
        return self._token  # type: ignore[return-value]

_rotator = LakebaseTokenRotator()

def get_lakebase_token() -> str:
    return _rotator.get_token()
```

```python
# Usage — pass fresh token as password on each connection
import psycopg2, os
from auth.token_rotator import get_lakebase_token

def get_conn():
    return psycopg2.connect(
        host=os.environ["LAKEBASE_HOST"],
        port=int(os.environ.get("LAKEBASE_PORT", "5432")),
        dbname=os.environ["LAKEBASE_DB"],
        user=os.environ["LAKEBASE_USER"],
        password=get_lakebase_token(),
        sslmode="require",
    )
```

---

## Secret Management Rules

- Never commit `.env` — add to `.gitignore`
- Always create `.env.example` with placeholder values only
- Load all credentials from environment variables at runtime
- Scope Databricks roles to minimum required permissions
- Rotate any exposed credential immediately

---

## Security Checklist

Before marking any Databricks integration complete:

- [ ] No tokens or passwords committed to source control
- [ ] `.env` added to `.gitignore`
- [ ] `.env.example` created with placeholder values
- [ ] SSL enforced on all connections (`sslmode=require`)
- [ ] Frontend tokens in `sessionStorage` only (never `localStorage`)
- [ ] Frontend silent refresh implemented (`DatabricksTokenManager`)
- [ ] Backend token rotation implemented (`LakebaseTokenRotator`)
- [ ] Backend credentials loaded from environment variables only
- [ ] Minimum required permissions scoped per Databricks role
- [ ] No connection poolers used with OAuth backend connections

---

## Handoff

After implementing token rotation and completing the checklist, present this
prompt to the user verbatim before invoking `databricks-data-patterns`:

> "Security layer done — token rotation and credential management are in place.
> The **data patterns** step is next — this covers how to write safe,
> paginated queries, upserts, transactions, and error handling against
> Lakebase. Want to continue?"

If the user confirms, invoke `databricks-data-patterns` immediately.
If they decline, the integration is functional but queries will need to be
written without the safety patterns (parameterisation, pagination limits, etc).
