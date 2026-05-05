---
paths:
  - "**/*.py"
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
  - "**/*.ipynb"
  - "**/*.sql"
---
# Databricks Skill Activation Policy

> Check project state before writing any Databricks/Lakebase code.
> Invoke the relevant skill when its condition is met — no need to invoke all skills every time.
> The `.lakebase` file in the project root confirms this is a Databricks/Lakebase project and is created by `databricks-architecture`.

## databricks-architecture

Invoke when:
- No Databricks connection layer exists in the project (first-time setup)
- Backend files (`server.ts`, `app.py`, `main.go`, `Dockerfile`) appear in a project
  that only has frontend Data API setup — app type has changed

## databricks-connection

Invoke when:
- No connection file exists (`lib/api/lakebase-client.ts`, `db/connection.py`, `db/pool.ts`)
- Backend was added but only a frontend Data API client exists — PostgreSQL connection missing
- Existing connection uses wrong pattern (raw `SparkSession`, hardcoded credentials)

## databricks-security

Invoke when:
- No token manager exists (`auth/token-manager.ts`) for frontend apps
- No token rotator exists (`auth/token_rotator.py`) for backend apps
- Backend was added but only the OIDC frontend manager exists — `LakebaseTokenRotator` missing

## databricks-data-patterns

Invoke when:
- Writing queries against a table with no existing query module
- New entity added without a corresponding `lib/api/[entity]-queries.ts`
  or `db/queries/[entity].py`
