---
name: databricks-connection
description: >
  Best-practice patterns for connecting applications to Databricks Lakebase.
  Routes frontend-only apps to the PostgREST-compatible Data API (OAuth OIDC)
  and full-stack apps to direct Lakebase PostgreSQL connections, with proper
  auth and framework-specific boilerplate generation.
version: 1.0.0
tags: [databricks, lakebase, postgresql, data-api, oauth, postgrest]
---

# Databricks Connection Skill

## Purpose

Generate correct Databricks connection code by detecting whether the app is
**frontend-only** or **full-stack**, then applying the right connection method:

| App type | Connection method | Auth |
|---|---|---|
| Frontend only (no server) | Lakebase Data API (PostgREST REST) | Databricks OAuth OIDC |
| Full-stack (frontend + backend) | Lakebase direct PostgreSQL | OAuth token *or* native PG password |

---

## Step 1 — Classify the App

Before generating any code, determine which category applies. Look at the
project structure, `package.json` scripts, or ask the user directly.

**Frontend-only signals:**
- Pure SPA (React, Vue, Angular, Svelte) with no server files
- Only `index.html` / `vite.config.ts` / `next.config.js` with `output: 'export'`
- No `server.ts`, `app.py`, `main.go`, or backend entrypoint

**Full-stack signals:**
- Backend entrypoint present (FastAPI, Django, Express, Spring Boot, etc.)
- Dockerfile exposes a server port
- Database migrations exist
- `api/` routes or server-side rendering

If classification is ambiguous, ask:

> "Is this app frontend-only (no backend server at all), or does it have a
> backend component that runs server-side code?"

---

## Step 2A — Frontend-Only: Lakebase Data API

The Lakebase Data API is a PostgREST-compatible REST interface available on
Lakebase Autoscaling. No PostgreSQL driver is needed. Authentication uses a
**Databricks OAuth OIDC token**.

### Auth flow (OAuth OIDC)

The token must be obtained through the Databricks OAuth flow — never hardcode
it in frontend code.

```
1. User initiates login → redirect to Databricks OAuth authorization endpoint
2. Databricks authenticates the user (OIDC)
3. Your app receives an OAuth access token (Bearer)
4. Use that token in all Data API request headers: Authorization: Bearer <token>
5. Token expires in ~1 hour — implement silent refresh
```

For a browser-only app, use the **PKCE (Proof Key for Code Exchange)** OAuth
flow so no client secret is needed.

### Data API endpoint pattern

Endpoints are auto-generated from your database schema by Lakebase:

```
GET    {DATA_API_BASE_URL}/{schema}/{table}
POST   {DATA_API_BASE_URL}/{schema}/{table}
PATCH  {DATA_API_BASE_URL}/{schema}/{table}?{filter}
DELETE {DATA_API_BASE_URL}/{schema}/{table}?{filter}
```

PostgREST-compatible query parameters:
- Filter rows: `?column=eq.value`
- Select columns: `?select=id,name`
- Join related table: `?select=id,name,orders(id,total)`
- Order: `?order=created_at.desc`
- Pagination: `?limit=20&offset=0`

The `DATA_API_BASE_URL` is found in the Lakebase project's Connect dialog.

### TypeScript/React — Data API client

```typescript
// lib/databricks-client.ts
const DATA_API_BASE = import.meta.env.VITE_DATA_API_BASE_URL;

async function getOAuthToken(): Promise<string> {
  // Retrieve from your OAuth callback result or session storage
  // NEVER hardcode or embed tokens in source code
  const token = sessionStorage.getItem("databricks_oauth_token");
  if (!token) throw new Error("No Databricks OAuth token. Please log in.");
  return token;
}

export async function dataApiGet<T>(
  path: string,
  params?: Record<string, string>
): Promise<T> {
  const token = await getOAuthToken();
  const url = new URL(`${DATA_API_BASE}/${path}`);
  if (params) {
    Object.entries(params).forEach(([k, v]) => url.searchParams.set(k, v));
  }
  const res = await fetch(url.toString(), {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!res.ok) throw new Error(`Data API ${res.status}: ${await res.text()}`);
  return res.json() as Promise<T>;
}

export async function dataApiPost<T>(path: string, body: unknown): Promise<T> {
  const token = await getOAuthToken();
  const res = await fetch(`${DATA_API_BASE}/${path}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`Data API ${res.status}: ${await res.text()}`);
  return res.json() as Promise<T>;
}
```

```typescript
// Example usage
import { dataApiGet } from "@/lib/databricks-client";

const clients = await dataApiGet<Client[]>("public/clients", {
  select: "id,name,email",
  order: "created_at.desc",
  limit: "20",
});
```

### Environment variables (frontend-only)

```env
# .env.example — commit this; never commit .env with real values
VITE_DATA_API_BASE_URL=https://your-workspace.azuredatabricks.net/api/2.0/lakebase/v1/projects/YOUR_PROJECT_ID/data-api
```

**Security rules for frontend-only:**
- Use PKCE OAuth flow — no client secret required or allowed in browser code
- Store OAuth access tokens in `sessionStorage` only, never `localStorage`
- Tokens expire in ~1 hour; implement silent refresh using the refresh token
- Scope tokens to the minimum required permissions in Databricks

---

## Step 2B — Full-Stack: Lakebase Direct PostgreSQL

The backend connects to Lakebase using a **standard PostgreSQL connection
string**. Lakebase is PostgreSQL-compatible so any standard PG library works —
no Databricks-specific driver is required.

### Ask the user two questions before generating code

**Question 1 — Connection method:**

> "For your Lakebase backend connection, do you prefer:
> 1. **Direct PostgreSQL driver** (psycopg2 / asyncpg for Python, `pg` for
>    Node.js, JDBC for Java/Kotlin)
> 2. **ORM** (SQLAlchemy for Python, Prisma for Node.js, Hibernate/JPA for
>    Java/Kotlin, Django ORM)"

**Question 2 — Authentication method:**

> "Which authentication method do you want?
> 1. **Native PostgreSQL password** — recommended for production; supports
>    connection pooling (PgBouncer), long-running processes
> 2. **Databricks OAuth token** — tokens expire hourly and require rotation;
>    NOT compatible with connection poolers"

### Connection string format

**Native PG password:**
```
postgresql://role_name:password@ep-abc-123.databricks.com/databricks_postgres?sslmode=require
```

**OAuth token:**
```
postgresql://user@example.com:oauth_token@ep-abc-123.databricks.com/databricks_postgres?sslmode=require
```

| Field | Native PG password | OAuth token |
|---|---|---|
| user | `role_name` | `user@example.com` |
| password | PG password (static) | OAuth token (hourly rotation) |
| host | `ep-abc-123.databricks.com` | same |
| database | `databricks_postgres` | same |
| port | `5432` | same |
| SSL | `sslmode=require` | `sslmode=require` |

The host (`ep-abc-123.databricks.com`) is the compute UID from the Lakebase
project's Connect dialog.

### Environment variables (backend)

```env
# .env.example
LAKEBASE_HOST=ep-abc-123.databricks.com
LAKEBASE_PORT=5432
LAKEBASE_DB=databricks_postgres
LAKEBASE_USER=your_role_name
LAKEBASE_PASSWORD=your_pg_password_or_oauth_token
DATABASE_URL=postgresql://your_role_name:your_password@ep-abc-123.databricks.com/databricks_postgres?sslmode=require
```

---

### Python — psycopg2 (direct driver)

```python
# db/connection.py
import os
import psycopg2
from psycopg2.pool import ThreadedConnectionPool

_pool: ThreadedConnectionPool | None = None

def get_pool() -> ThreadedConnectionPool:
    global _pool
    if _pool is None:
        _pool = ThreadedConnectionPool(
            minconn=1,
            maxconn=10,
            host=os.environ["LAKEBASE_HOST"],
            port=int(os.environ.get("LAKEBASE_PORT", "5432")),
            dbname=os.environ["LAKEBASE_DB"],
            user=os.environ["LAKEBASE_USER"],
            password=os.environ["LAKEBASE_PASSWORD"],
            sslmode="require",
        )
    return _pool

def get_conn():
    return get_pool().getconn()

def release_conn(conn):
    get_pool().putconn(conn)
```

> Connection pooling (`ThreadedConnectionPool`, PgBouncer) only works with
> **native PG password** auth. OAuth tokens cannot be pooled.

### Python — SQLAlchemy (ORM)

```python
# db/engine.py
import os
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, DeclarativeBase

DATABASE_URL = os.environ["DATABASE_URL"]  # must include ?sslmode=require

engine = create_engine(
    DATABASE_URL,
    pool_size=5,
    max_overflow=10,
    pool_pre_ping=True,
    connect_args={"sslmode": "require"},
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

class Base(DeclarativeBase):
    pass

# FastAPI dependency
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
```

### Python — Django

```python
# settings.py
import os

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "HOST": os.environ["LAKEBASE_HOST"],
        "PORT": os.environ.get("LAKEBASE_PORT", "5432"),
        "NAME": os.environ["LAKEBASE_DB"],
        "USER": os.environ["LAKEBASE_USER"],
        "PASSWORD": os.environ["LAKEBASE_PASSWORD"],
        "OPTIONS": {"sslmode": "require"},
    }
}
```

---

### TypeScript/Node.js — `pg` (direct driver)

```typescript
// db/pool.ts
import { Pool } from "pg";

export const pool = new Pool({
  host: process.env.LAKEBASE_HOST,
  port: Number(process.env.LAKEBASE_PORT ?? 5432),
  database: process.env.LAKEBASE_DB,
  user: process.env.LAKEBASE_USER,
  password: process.env.LAKEBASE_PASSWORD,
  ssl: { rejectUnauthorized: true },
  max: 10,
  idleTimeoutMillis: 30_000,
});

pool.on("error", (err) => {
  console.error("Unexpected DB pool error", err);
});
```

```typescript
// Usage
import { pool } from "@/db/pool";

const { rows } = await pool.query(
  "SELECT id, name FROM public.clients WHERE id = $1",
  [clientId]
);
```

### TypeScript/Node.js — Prisma (ORM)

```prisma
// prisma/schema.prisma
datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

generator client {
  provider = "prisma-client-js"
}
```

```typescript
// db/prisma.ts
import { PrismaClient } from "@prisma/client";

const globalForPrisma = globalThis as unknown as { prisma: PrismaClient };

export const prisma =
  globalForPrisma.prisma ??
  new PrismaClient({
    log: process.env.NODE_ENV === "development" ? ["query", "error"] : ["error"],
  });

if (process.env.NODE_ENV !== "production") globalForPrisma.prisma = prisma;
```

---

### Java — JDBC with HikariCP

```java
// config/DataSourceConfig.java
import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import javax.sql.DataSource;

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
        config.setPassword(System.getenv("LAKEBASE_PASSWORD"));
        config.setMaximumPoolSize(10);
        config.setConnectionTimeout(30_000);
        config.addDataSourceProperty("ssl", "true");
        config.addDataSourceProperty("sslmode", "require");
        return new HikariDataSource(config);
    }
}
```

### Kotlin — Spring Boot + JPA (`application.yml`)

```yaml
# src/main/resources/application.yml
spring:
  datasource:
    url: jdbc:postgresql://${LAKEBASE_HOST}:${LAKEBASE_PORT:5432}/${LAKEBASE_DB}?sslmode=require
    username: ${LAKEBASE_USER}
    password: ${LAKEBASE_PASSWORD}
    hikari:
      maximum-pool-size: 10
      connection-timeout: 30000
  jpa:
    database-platform: org.hibernate.dialect.PostgreSQLDialect
    hibernate:
      ddl-auto: validate
```

---

## Step 3 — OAuth Token Rotation (backend, if OAuth chosen)

If the user selects OAuth auth for a backend connection, add token rotation
because Databricks OAuth tokens expire in ~1 hour.

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
            if time.time() >= self._expiry - 60:  # refresh 60s before expiry
                cred = self._client.postgres.generate_database_credential(
                    parent="projects/YOUR_PROJECT_NAME/branches/production"
                )
                self._token = cred.token
                self._expiry = time.time() + 3600
        return self._token  # type: ignore[return-value]
```

> **Recommendation:** For production, use **native PG password auth** instead
> of OAuth tokens. It avoids rotation complexity and is compatible with
> connection poolers (PgBouncer).

---

## Step 4 — Security Checklist

Before completing any Databricks connection implementation, verify:

- [ ] No tokens or passwords committed to source control
- [ ] `.env` added to `.gitignore`
- [ ] `.env.example` created with placeholder values only
- [ ] SSL enforced on all connections (`sslmode=require`)
- [ ] Frontend OAuth tokens stored in `sessionStorage` only (not `localStorage`)
- [ ] Backend credentials loaded from environment variables
- [ ] Connection pooling used for backend (requires native PG password auth)
- [ ] OAuth token rotation implemented if OAuth chosen for backend
- [ ] Minimum required permissions scoped in Databricks for each role

---

## Decision Tree

```
User wants to connect to Databricks
          │
          ├─ Frontend only? (SPA, no server-side code)
          │         └─ Use Lakebase Data API (PostgREST over HTTP)
          │                   ├─ Auth: Databricks OAuth OIDC (PKCE flow)
          │                   ├─ Store token: sessionStorage only
          │                   └─ Endpoint: {DATA_API_BASE_URL}/{schema}/{table}
          │
          └─ Has a backend? (server runs code)
                    └─ Use Lakebase direct PostgreSQL
                              ├─ Ask: connection method
                              │         ├─ Direct driver (psycopg2, pg, JDBC)
                              │         └─ ORM (SQLAlchemy, Prisma, Hibernate)
                              └─ Ask: auth method
                                        ├─ Native PG password → pooling OK (recommended)
                                        └─ OAuth token → rotate hourly, no pooling
```
