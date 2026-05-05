---
name: databricks-security
description: >
  Security patterns for Databricks/Lakebase: frontend PKCE login flow and
  silent refresh, mandatory backend token rotation, M2M service principal
  setup, secret management rules, and pre-completion security checklist.
  TRIGGER when: databricks-connection has been set up; writing any auth,
  token, or credential code for Databricks/Lakebase; user asks about
  Databricks OAuth, token expiry, or token rotation; DATABRICKS_TOKEN or
  OAuth appears in Databricks context; any Databricks connection file is
  being written or reviewed; before marking any Databricks integration complete.
  SKIP: connection layer has not been set up yet — invoke databricks-connection
  first.
version: 2.0.0
tags: [databricks, lakebase, security, oauth, pkce, token-rotation]
---

# Databricks Security Skill

## Purpose

Apply security patterns after connection setup. Covers the complete OAuth
login flow, token rotation for both frontend and backend, M2M service
principal guidance, and a final security checklist.

---

## Frontend — OAuth PKCE Login Flow

Frontend tokens are obtained via PKCE (no client secret). This requires an
OAuth application to be registered in the Databricks workspace (admin required —
covered in `databricks-architecture` Step 2).

### Part A — Login initiation and callback

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

**Callback route** — create a page at `/auth/callback` that calls:
```typescript
// pages/auth/callback.tsx (or equivalent route)
const params = new URLSearchParams(window.location.search)
await handleCallback(params.get('code')!, params.get('state')!)
// then navigate to the app home
```

---

### Part B — Silent refresh (token manager)

Tokens expire in ~1 hour. Silent refresh uses the refresh token to get a
new access token without re-login.

**Rules:**
- Store tokens in `sessionStorage` only — never `localStorage`
- Deduplicate concurrent refresh calls to avoid race conditions
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

**Logout:**
```typescript
// Call on logout button click
tokenManager.clearTokens()
window.location.href = '/login'
```

---

## Backend — OAuth Token Rotation (Mandatory)

All backend connections use Databricks OAuth tokens as the PostgreSQL password.
Tokens expire in ~1 hour — rotation is mandatory.

### How it works

```
Auth credential (PAT or M2M client secret)
  → authenticates WorkspaceClient to Databricks API
    → calls generate_database_credential(endpoint=...)
      → returns short-lived Lakebase token (~1 hour)
        → used as psycopg2 / asyncpg password
```

### Auth modes

| Mode | Env vars | Best for |
|---|---|---|
| Static token | `LAKEBASE_OAUTH_TOKEN` (from Lakebase UI → Copy OAuth token) | Quick local testing only |
| PAT auto-rotate | `DATABRICKS_HOST` + `DATABRICKS_TOKEN` | Dev / personal use |
| M2M auto-rotate | `DATABRICKS_HOST` + `DATABRICKS_CLIENT_ID` + `DATABRICKS_CLIENT_SECRET` | Production |

### PAT setup

1. Databricks → User Settings → Developer → Access tokens → **Generate new token**
2. Scope: `Other APIs` → API scope: **`postgres`** (not `sql` — wrong scope, will fail)
3. Lifetime: 90 days for dev; use M2M in production

### M2M service principal (admin required)

If you don't have workspace admin access, share this with your admin:

> "Please create a Databricks service principal for our app to access Lakebase:
>
> 1. Settings → Identity & Access → Service principals → **Add service principal**
>    - Name: `yourapp-lakebase-prod`
> 2. On the service principal page → **Secrets** → **Generate secret**
>    - Copy the **Client ID** and **Client Secret** immediately (shown once)
> 3. Assign the service principal to the Lakebase project:
>    - Lakebase Postgres → your project → **Manage access**
>    - Add service principal with `Can use` role
> 4. Please return the **Client ID** and **Client Secret** to the developer."

Once received, add to `.env`:
```env
DATABRICKS_HOST=https://your-workspace.databricks.com
DATABRICKS_CLIENT_ID=<from admin>
DATABRICKS_CLIENT_SECRET=<from admin>
LAKEBASE_ENDPOINT_PATH=projects/my-project/branches/production/endpoints/primary
```

---

### Token rotator implementation

```python
# auth/token_rotator.py
import logging
import os
import time
import threading

logger = logging.getLogger(__name__)

_REFRESH_BUFFER = 60  # seconds before expiry to trigger refresh


class LakebaseTokenRotator:
    """Fetches and caches a Lakebase credential token via the Databricks SDK."""

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
        return self._token  # type: ignore[return-value]

    def _refresh(self) -> None:
        cred = self._client.postgres.generate_database_credential(
            endpoint=self._endpoint
        )
        self._token = cred.token
        # expire_time is a datetime object in the Databricks SDK
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
    """Return a fresh OAuth token for Lakebase (used as psycopg2 password).

    Uses auto-rotation via databricks-sdk when PAT or M2M credentials are set.
    Falls back to static LAKEBASE_OAUTH_TOKEN for quick local testing only.
    """
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

> **Django + gunicorn note:** under `--preload`, the singleton `_rotator` is
> created in the master process before fork. Each worker gets its own copy of
> the lock (safe), but `_rotator` may hold a stale token from the master.
> The `_REFRESH_BUFFER` check will re-fetch on first use in each worker.
> This is safe but means each worker fetches a fresh token on startup.

---

## Secret Management Rules

- Never commit `.env` — add to `.gitignore`
- Always create `.env.example` with placeholder values only
- Load all credentials from environment variables at runtime
- Rotate any exposed credential immediately

```bash
# .gitignore
.env
.env.local
.env.*.local
```

```env
# .env.example — commit this
DATABRICKS_HOST=https://your-workspace.databricks.com
DATABRICKS_TOKEN=                    # dev: personal access token (postgres scope)
DATABRICKS_CLIENT_ID=                # prod: from admin-created service principal
DATABRICKS_CLIENT_SECRET=            # prod: from admin-created service principal
LAKEBASE_HOST=
LAKEBASE_PORT=5432
LAKEBASE_DB=
LAKEBASE_USER=
LAKEBASE_ENDPOINT_PATH=projects/.../branches/.../endpoints/primary
DATABASE_URL=                        # postgresql://user@host/db?sslmode=require
```

---

## Security Checklist

Before marking any Databricks integration complete:

- [ ] No tokens or passwords committed to source control
- [ ] `.env` added to `.gitignore`
- [ ] `.env.example` created with placeholder values
- [ ] SSL enforced on all connections (`sslmode=require`)
- [ ] Frontend tokens in `sessionStorage` only (never `localStorage`)
- [ ] Frontend PKCE login flow implemented (`initiateLogin` + `handleCallback`)
- [ ] Frontend silent refresh implemented (`DatabricksTokenManager`)
- [ ] Frontend logout clears `sessionStorage`
- [ ] Backend token rotation implemented (`LakebaseTokenRotator`)
- [ ] Backend credentials loaded from environment variables only
- [ ] Production uses M2M service principal (not a personal PAT)
- [ ] No connection poolers used with OAuth backend connections
- [ ] Minimum required permissions scoped per Databricks role

---

## Handoff

After implementing token rotation and completing the checklist:

> "Security layer done — PKCE login, token rotation, and credential management
> are in place. The **data patterns** step is next — typed queries, pagination,
> upserts, transactions, and error handling against Lakebase. Want to continue?"

If the user confirms, invoke `databricks-data-patterns`.
