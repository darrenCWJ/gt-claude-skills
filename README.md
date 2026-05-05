# databricks-connection-skill

A Claude Code plugin that adds best-practice Databricks/Lakebase connection patterns as a skill.

## What it does

Automatically routes your app to the correct Databricks connection method:

| App type | Connection |
|---|---|
| Frontend-only (SPA) | Lakebase Data API (PostgREST, OAuth OIDC) |
| Full-stack (has backend) | Lakebase direct PostgreSQL |

## Install

```bash
claude plugin install https://github.com/<your-username>/databricks-connection-skill
```

## Update

```bash
claude plugin update databricks-connection-skill
```

## Usage

Once installed, the skill activates when your message contains keywords like `databricks` or `lakebase`. You can also invoke it directly:

```
/databricks-connection
```
