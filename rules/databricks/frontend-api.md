---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
---
# Databricks Frontend Patterns

> Applies when writing frontend-only apps that access Databricks Lakebase data.
> Complements [common/patterns.md](../common/patterns.md) and [databricks/patterns.md](./patterns.md).

## Architecture

```
Frontend only application
  └─ Data API needed (PostgREST-compatible)
       └─ get token from OIDC (Databricks OAuth)
            └─ postgres (Lakebase)
```

The frontend obtains a short-lived Databricks OAuth token via the OIDC flow, then
calls the Lakebase Data API directly. PostgreSQL row-level security enforces what
each identity can access — no separate backend required.

## Core Rules (CRITICAL)

- NEVER use hardcoded PAT tokens — always use OIDC OAuth tokens
- NEVER connect to Postgres directly from the frontend — use the Data API only
- NEVER expose the REST endpoint URL as a hardcoded string — read from config/env
- Token storage: memory or httpOnly cookie only — never `localStorage`

## Authentication — OIDC Token Flow

```typescript
// lib/auth/databricks-token.ts
// Obtain a short-lived OAuth token via Databricks OIDC flow
export async function getDatabricksOAuthToken(): Promise<string> {
  // Use your OIDC provider SDK (e.g. @azure/msal-browser, oidc-client-ts)
  const token = await oidcClient.getAccessToken({ scope: "databricks" })
  return token
}

// WRONG — hardcoded PAT
const token = "dapi1234abcd..."

// WRONG — token from localStorage (XSS risk)
const token = localStorage.getItem("databricks_token")
```

## API Client Pattern

Use a typed client wrapping the PostgREST Data API — never raw `fetch` in components:

```typescript
// lib/api/lakebase-client.ts
const DATA_API_URL = import.meta.env.VITE_LAKEBASE_DATA_API_URL // e.g. https://<workspace>/lakebase/api/public

async function dataApiFetch(path: string, options?: RequestInit): Promise<Response> {
  const token = await getDatabricksOAuthToken()
  const response = await fetch(`${DATA_API_URL}${path}`, {
    ...options,
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      ...options?.headers,
    },
  })
  if (!response.ok) throw new Error(`Data API error: ${response.status}`)
  return response
}

export async function fetchClients(filters?: { minId?: number }): Promise<Client[]> {
  const params = new URLSearchParams()
  if (filters?.minId) params.set("id", `gte.${filters.minId}`)
  const response = await dataApiFetch(`/clients?${params}`)
  return response.json()
}
```

## PostgREST Query Patterns

The Data API follows PostgREST conventions — use query params, not SQL:

```typescript
// Filtering
GET /public/tasks?status=eq.open
GET /public/tasks?due_date=lte.2024-12-31
GET /public/clients?id=gte.2

// Selecting specific columns + related rows
GET /public/clients?select=id,name,projects(id,name)

// Pagination
GET /public/tasks?limit=20&offset=0

// Sorting
GET /public/tasks?order=due_date.desc

// Insert
POST /public/clients
Body: { "name": "Acme Corp", "email": "contact@acme.com" }

// Update
PATCH /public/clients?id=eq.1
Body: { "phone": "+1-555-0199" }
```

NEVER build SQL strings — use PostgREST filter operators (`eq`, `gte`, `lte`, `like`, `in`).

## Error Handling

Never expose raw Databricks or Postgres error messages to users:

```typescript
async function loadClients(filters: ClientFilters): Promise<Result<Client[], string>> {
  try {
    const clients = await fetchClients(filters)
    return { ok: true, value: clients }
  } catch (error) {
    console.error("Data API fetch failed:", error)
    return { ok: false, error: "Failed to load data. Please try again." }
  }
}
```

## What Belongs Where

| Concern | Frontend | Notes |
|---------|----------|-------|
| Databricks OAuth token | Obtained via OIDC flow | Short-lived, in memory only |
| Data API base URL | Config / env var | Never hardcoded |
| PostgREST filter params | Yes | Use operators, not SQL |
| SQL queries | NEVER | Use PostgREST API only |
| Row-level access control | NEVER | Enforced by Postgres RLS |
| Data formatting / display | Yes | After fetch |

## Code Smells to Avoid

| Pattern | Problem |
|---------|---------|
| Hardcoded PAT (`dapi...`) | Exposed to all users via devtools |
| Token in `localStorage` | XSS risk — use memory or httpOnly cookie |
| Direct Postgres connection from frontend | Bypasses Data API auth layer |
| Hardcoded Data API URL | Use `VITE_LAKEBASE_DATA_API_URL` env var |
| Raw SQL strings in frontend | Use PostgREST filter operators |
| Fetching all rows then filtering in JS | Push filters to API with query params |
