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

> IMPORTANT: When a skill condition is met, invoke it IMMEDIATELY — do not answer from
> training data first. The skills contain accurate Lakebase patterns; training data does not.
> The `.lakebase` file in the project root is created by `databricks-architecture`.

## databricks-architecture

**Skip the full walkthrough and write `.lakebase` directly** if you can already determine
from visible project files:
- App type (e.g. FastAPI entrypoint = fullstack, SPA with no server = frontend)
- Stack (e.g. requirements.txt = python, package.json = typescript)

When skipping: write `.lakebase` with inferred values, then ask only what cannot be
inferred — **personal vs team workspace** — before proceeding to `databricks-connection`.

Invoke the full skill when:
- App type is ambiguous (no entrypoint or config files visible)
- This is a migration and the existing DB setup hasn't been reviewed
- Backend files appear in a project previously classified as frontend-only

## databricks-connection

Invoke IMMEDIATELY when:
- A Lakebase hostname or connection string appears in the prompt
  (e.g. `*.cloud.databricks.com`, `databricks_postgres`, `ep-*.databricks.com`)
- No connection file exists (`lib/api/lakebase-client.ts`, `db/connection.py`, `db/pool.ts`)
- Backend was added but only a frontend Data API client exists — PostgreSQL connection missing
- Existing connection uses wrong pattern (raw `SparkSession`, hardcoded credentials, PAT as static password)

## databricks-security

Invoke IMMEDIATELY when:
- No token manager exists (`auth/token-manager.ts`) for frontend apps
- No token rotator exists (`auth/token_rotator.py`) for backend apps
- Backend was added but only the OIDC frontend manager exists — `LakebaseTokenRotator` missing

## databricks-data-patterns

Invoke IMMEDIATELY when:
- Writing queries against a table with no existing query module
- New entity added without a corresponding `lib/api/[entity]-queries.ts`
  or `db/queries/[entity].py`
