# gt-claude-skills

GovTech's Claude Code skills collection. Install once to get all skills — updates automatically when the repo is updated.

## Skills included

| Skill | Invoked by | Description |
|---|---|---|
| `databricks-architecture` | Auto on Databricks/Lakebase keywords | Classifies app type (frontend/full-stack/migration), shapes architecture, orchestrates follow-up skills |
| `databricks-connection` | `databricks-architecture` → step 1 | Connection boilerplate — Data API client (frontend) or PostgreSQL driver/ORM (backend, OAuth only) |
| `databricks-security` | `databricks-architecture` → step 2 | OAuth PKCE silent refresh (frontend), mandatory token rotation (backend), security checklist |
| `databricks-data-patterns` | `databricks-architecture` → step 3 | PostgREST read/write patterns (frontend), parameterized queries, transactions, pagination (backend) |

## Install

```bash
claude plugin install https://github.com/darrenCWJ/gt-claude-skills
```

## Update

```bash
claude plugin update gt-claude-skills
```

## Usage

Skills activate automatically when your message contains Databricks/Lakebase keywords.
The `databricks-architecture` skill runs first and orchestrates the rest.

You can also invoke any skill directly:

```
/databricks-architecture
/databricks-connection
/databricks-security
/databricks-data-patterns
```

## How it works

Two hooks are registered automatically on install:

| Hook | Fires when | Does |
|---|---|---|
| `UserPromptSubmit` | You type "databricks" or "lakebase" | Triggers `databricks-architecture` to classify and plan |
| `PreToolUse` | Claude is about to write Databricks code | Safety net — triggers relevant skill(s) if not already run |

Both hooks share a 2-hour session flag so skills trigger once per session, not on every message.
