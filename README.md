# gt-claude-skills

GovTech's Claude Code skills collection. Install once to get all skills, hooks, and rules — updates automatically when the repo is updated.

## Install

```bash
claude plugin install https://github.com/darrenCWJ/gt-claude-skills
```

## Update

```bash
claude plugin update gt-claude-skills
```

---

## What's included

### Skills

| Skill | Description |
|---|---|
| `databricks-architecture` | Classifies app type (frontend-only / full-stack / migration), guides credential setup, orchestrates follow-up skills |
| `databricks-connection` | Generates stack-specific connection boilerplate — Data API client (frontend) or PostgreSQL driver/ORM (backend) |
| `databricks-security` | Generates OAuth token rotation code, runs security checklist |
| `databricks-data-patterns` | Discovers project entities and generates typed query modules for real tables |

### Rules (auto-loaded)

| File | Applies to | Purpose |
|---|---|---|
| `rules/databricks/patterns.md` | `.py`, `.ipynb`, `.sql` | Always-on coding guidance: connection, Delta read/write, upserts, secrets, error handling |
| `rules/databricks/frontend-api.md` | `.ts`, `.tsx`, `.js`, `.jsx` | Frontend architecture constraint: OIDC OAuth → Data API (PostgREST) → Lakebase only |

### Hooks (auto-registered)

| Hook | Fires when | Does |
|---|---|---|
| `UserPromptSubmit` | Message contains "databricks" or "lakebase" | Triggers `databricks-architecture` if not yet classified; reminds about incomplete steps |
| `PreToolUse` | Claude writes code with Databricks keywords | Enforces relevant setup steps before writing connection, security, or data code |

---

## How it works

### Setup state

Both hooks share a state file at `/tmp/databricks-state.json` that tracks four independent setup steps:

```json
{
  "architecture_classified": false,
  "connection_configured": false,
  "security_checklist_done": false,
  "data_patterns_applied": false
}
```

- Each flag is only set after the corresponding skill completes
- Once all four flags are `true`, both hooks go completely silent
- State resets on reboot or manually: `rm /tmp/databricks-state.json`

### Setup flow

```
User mentions Databricks/Lakebase
  └─ Hook fires → databricks-architecture
       └─ Classifies: frontend-only / full-stack / migration
            └─ Invokes: databricks-connection
                 └─ Generates connection boilerplate for your stack
                      └─ Invokes: databricks-security
                           └─ Generates token rotation code + security checklist
                                └─ Invokes: databricks-data-patterns
                                     └─ Asks about your entities → generates query modules
```

### Skill vs rules responsibility

| Layer | Responsibility |
|---|---|
| **Rules** | Passive always-on guidance — how to write Databricks code correctly |
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

## Reset setup state

```bash
rm /tmp/databricks-state.json
```
