---
name: databricks-connection
description: >
  Generates connection boilerplate for Databricks Lakebase — Data API client
  for frontend apps, direct PostgreSQL connection for backends (OAuth only).
  Asks one question (driver vs ORM) for backend path.
  TRIGGER when: databricks-architecture has classified the app type; user needs
  Databricks/Lakebase connection code; user asks how to connect to Databricks
  or Lakebase; writing any db connection file that targets Lakebase; env vars
  LAKEBASE_HOST, LAKEBASE_DB, LAKEBASE_USER, or LAKEBASE_OAUTH_TOKEN are being
  configured; user asks about Lakebase PostgreSQL endpoints.
  SKIP: databricks-architecture has not yet run — invoke that first.
version: 2.0.0
tags: [databricks, lakebase, postgresql, data-api, connection, oauth]
---

# Databricks Connection Skill

## When to Invoke

**Auto-invoke this skill when ANY of these signals appear:**
- `databricks-architecture` has just classified the app type
- User needs connection boilerplate for Databricks or Lakebase
- Env vars `LAKEBASE_HOST`, `LAKEBASE_DB`, `LAKEBASE_USER`, or `LAKEBASE_OAUTH_TOKEN` are being set up
- User asks "how do I connect to Databricks?" or "how do I connect to Lakebase?"
- Writing a database connection file (`db/connection.ts`, `lib/db.ts`, etc.) that targets Lakebase
- User asks about Lakebase PostgreSQL endpoints

**Invoke order**: `databricks-architecture` → **`databricks-connection`** → `databricks-security` → `databricks-data-patterns`

---

## Purpose

Generate the connection layer only. Run after `databricks-architecture` has
classified the app. Then invoke `databricks-security` and `databricks-data-patterns`.

---

## Step 1 — Frontend: Lakebase Data API Client

No PostgreSQL driver needed. Auth via Databricks OAuth OIDC (PKCE flow).

### Environment variables

```env
# .env.example — commit this; never commit .env with real values
VITE_DATA_API_BASE_URL=https://your-workspace.azuredatabricks.net/api/2.0/lakebase/v1/projects/YOUR_PROJECT_ID/data-api
```

### TypeScript/React — Data API client

```typescript
// lib/databricks-client.ts
const DATA_API_BASE = import.meta.env.VITE_DATA_API_BASE_URL

export async function dataApiGet<T>(
  path: string,
  params?: Record<string, string>
): Promise<T> {
  // tokenManager handles silent refresh — see databricks-security skill
  const token = await tokenManager.getAccessToken()
  const url = new URL(`${DATA_API_BASE}/${path}`)
  if (params) Object.entries(params).forEach(([k, v]) => url.searchParams.set(k, v))
  const res = await fetch(url.toString(), {
    headers: { Authorization: `Bearer ${token}` },
  })
  if (!res.ok) throw new Error(`Data API ${res.status}: ${await res.text()}`)
  return res.json() as Promise<T>
}

export async function dataApiPost<T>(path: string, body: unknown): Promise<T> {
  const token = await tokenManager.getAccessToken()
  const res = await fetch(`${DATA_API_BASE}/${path}`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  })
  if (!res.ok) throw new Error(`Data API ${res.status}: ${await res.text()}`)
  return res.json() as Promise<T>
}
```

---

## Step 2 — Backend: Lakebase Direct PostgreSQL

Auth is always Databricks OAuth. Ask one question before generating code:

> "For your Lakebase backend connection, do you prefer:
> 1. **Direct PostgreSQL driver** (psycopg2 for Python, `pg` for Node.js, JDBC for Java/Kotlin)
> 2. **ORM** (SQLAlchemy for Python, Prisma for Node.js, Hibernate/JPA for Java/Kotlin, Django ORM)"

### Environment variables (backend)

```env
# .env.example
LAKEBASE_HOST=ep-abc-123.databricks.com
LAKEBASE_PORT=5432
LAKEBASE_DB=databricks_postgres
LAKEBASE_USER=your_role_name
DATABASE_URL=postgresql://your_role_name@ep-abc-123.databricks.com/databricks_postgres?sslmode=require
```

### Connection string format (OAuth token as password)

```
postgresql://user@example.com:oauth_token@ep-abc-123.databricks.com/databricks_postgres?sslmode=require
```

> Token is fetched fresh per connection via `LakebaseTokenRotator` — see `databricks-security` skill.

---

### Python — psycopg2

```python
# db/connection.py
import os
import psycopg2
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

### Python — SQLAlchemy

```python
# db/engine.py
import os
from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker, DeclarativeBase
from auth.token_rotator import get_lakebase_token

def get_engine():
    engine = create_engine(
        os.environ["DATABASE_URL"],
        pool_size=1,       # OAuth: no persistent pooling
        max_overflow=0,
        pool_pre_ping=True,
        connect_args={"sslmode": "require"},
    )
    # Inject fresh token before each new connection
    @event.listens_for(engine, "do_connect")
    def provide_token(dialect, conn_rec, cargs, cparams):
        cparams["password"] = get_lakebase_token()
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
        "PASSWORD": "",  # set dynamically — see token rotator
        "OPTIONS": {"sslmode": "require"},
    }
}
```

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
    password: () => getLakebaseToken(), // fetched fresh per connection
    ssl: { rejectUnauthorized: true },
    max: 1, // OAuth: no persistent pooling
  })
}
```

### TypeScript/Node.js — Prisma

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
import { PrismaClient } from '@prisma/client'

const globalForPrisma = globalThis as unknown as { prisma: PrismaClient }

export const prisma =
  globalForPrisma.prisma ??
  new PrismaClient({
    log: process.env.NODE_ENV === 'development' ? ['query', 'error'] : ['error'],
  })

if (process.env.NODE_ENV !== 'production') globalForPrisma.prisma = prisma
```

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
        config.setPassword(TokenRotator.getToken()); // fresh token
        config.setMaximumPoolSize(1); // OAuth: no persistent pooling
        config.addDataSourceProperty("sslmode", "require");
        return new HikariDataSource(config);
    }
}
```

### Kotlin — Spring Boot (`application.yml`)

```yaml
# src/main/resources/application.yml
spring:
  datasource:
    url: jdbc:postgresql://${LAKEBASE_HOST}:${LAKEBASE_PORT:5432}/${LAKEBASE_DB}?sslmode=require
    username: ${LAKEBASE_USER}
    password: ${LAKEBASE_OAUTH_TOKEN}  # injected at startup via token rotator
    hikari:
      maximum-pool-size: 1
      connection-timeout: 30000
  jpa:
    database-platform: org.hibernate.dialect.PostgreSQLDialect
    hibernate:
      ddl-auto: validate
```

---

## Handoff

After generating connection boilerplate, present this prompt to the user
verbatim before invoking `databricks-security`:

> "Connection layer done. The **security & token rotation** step is next —
> this adds OAuth token auto-rotation so your Lakebase credentials never
> expire mid-request. Want to continue?"

If the user confirms, invoke `databricks-security` immediately.
If they decline, warn that static tokens will expire (~1 hour) and must be
rotated manually.
