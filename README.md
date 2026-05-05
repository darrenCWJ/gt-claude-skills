# gt-claude-skills

GovTech's Claude Code skills collection. Includes Databricks/Lakebase best-practice patterns
for connection, security, and data access across all app types.

## Install

```bash
git clone https://github.com/darrenCWJ/gt-claude-skills
claude plugin install ./gt-claude-skills
```

## Update

```bash
cd gt-claude-skills && git pull
claude plugin install ./gt-claude-skills
```

---

## What's included

### Skills

| Skill | Description |
|---|---|
| `databricks-architecture` | Classifies app type (frontend / fullstack / script / migration), guides credential setup per path, orchestrates follow-up skills |
| `databricks-connection` | Generates stack-specific connection boilerplate — Data API client (frontend) or PostgreSQL driver/ORM (backend) |
| `databricks-security` | PKCE login flow, silent refresh, backend token rotation, M2M service principal setup, security checklist |
| `databricks-data-patterns` | Discovers project entities and generates typed query modules with transactions, bulk insert, and error handling |

### Rules (auto-loaded on matching files)

| File | Applies to | Purpose |
|---|---|---|
| `rules/databricks/activation.md` | `.py`, `.ts`, `.tsx`, `.js`, `.jsx`, `.sql`, `.ipynb` | Tells Claude which skill to invoke based on project state |
| `rules/databricks/patterns.md` | `.py`, `.ipynb`, `.sql` | Coding constraints: connection patterns, parameterized queries, upserts, secrets |
| `rules/databricks/frontend-api.md` | `.ts`, `.tsx`, `.js`, `.jsx` | Frontend constraint: OIDC OAuth → Data API only, never direct PostgreSQL |

### Hooks (auto-registered)

| Hook | Fires when | Does |
|---|---|---|
| `UserPromptSubmit` | Message shows intent to integrate with Databricks/Lakebase | First-time: prompts `databricks-architecture`; confirmed project: checks activation policy |
| `PreToolUse` | Writing code with Databricks keywords (in confirmed projects) | Checks activation policy; detects frontend→fullstack transition |

---

## How it works

### Project marker

When `databricks-architecture` runs, it creates a `.lakebase` file in the project root:

```json
{ "app_type": "frontend", "stack": "typescript", "personal": false }
```

This file:
- Scopes hooks to confirmed Databricks projects (prevents false positives in unrelated projects)
- Stores classification so downstream skills skip questions already answered
- Enables the transition hook to detect when a frontend app becomes fullstack

### Setup flow

```
User mentions Databricks with setup intent
  └─ Hook fires → invoke databricks-architecture
       └─ Classifies app, asks stack + personal/team, writes .lakebase
            └─ Invokes: databricks-connection
                 └─ Generates connection boilerplate for your stack
                      └─ Invokes: databricks-security
                           └─ PKCE login, token rotation, security checklist
                                └─ Invokes: databricks-data-patterns
                                     └─ Asks about entities → generates typed query modules
```

### Skill vs rules responsibility

| Layer | Responsibility |
|---|---|
| **Rules** | Passive always-on constraints — how to write Databricks code correctly |
| **Hooks** | Enforcement gates — ensure skills run before code is written |
| **Skills** | Active setup wizards — ask questions, generate actual project files |

---

## Manual skill invocation

```
/databricks-architecture
/databricks-connection
/databricks-security
/databricks-data-patterns
```

## Reset project classification

```bash
rm .lakebase
```
