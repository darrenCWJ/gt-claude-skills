# claude-databricks-skill

GovTech's Claude Code skills for Databricks/Lakebase integration — best-practice patterns
for connection, security, and data access across all app types.

## Install

```bash
git clone git@sgts.gitlab-dedicated.com:darren_chua/claude-databricks-skill.git
claude plugin install ./claude-databricks-skill
```

## Update

```bash
cd claude-databricks-skill && git pull
claude plugin install ./claude-databricks-skill
```

---

## What's included

### Skills

| Skill | Description |
|---|---|
| `databricks-lakebase` | Unified Databricks/Lakebase integration — intent discovery, connection setup, security (PKCE + token rotation), and typed data access patterns for all app types and stacks |

### Rules (auto-loaded on matching files)

| File | Applies to | Purpose |
|---|---|---|
| `rules/databricks/activation.md` | `.py`, `.ts`, `.tsx`, `.js`, `.jsx`, `.sql`, `.ipynb` | Tells Claude to invoke `databricks-lakebase` based on project state |
| `rules/databricks/patterns.md` | `.py`, `.ipynb`, `.sql` | Coding constraints: connection patterns, parameterized queries, upserts, secrets |
| `rules/databricks/frontend-api.md` | `.ts`, `.tsx`, `.js`, `.jsx` | Frontend constraint: OIDC OAuth → Data API only, never direct PostgreSQL |

### Hooks (auto-registered)

| Hook | Fires when | Does |
|---|---|---|
| `UserPromptSubmit` | Message shows intent to integrate with Databricks/Lakebase | Routes to `databricks-lakebase` with context (marker_exists, hostname_detected, or keyword_intent) |
| `PreToolUse` | Writing code with Databricks keywords (in confirmed projects) | Routes to `databricks-lakebase` with context (transition or code_write) |

---

## How it works

### Project marker

When `databricks-lakebase` runs, it creates a `.lakebase` file in the project root:

```json
{ "app_type": "frontend", "stack": "typescript", "personal": false }
```

This file:
- Scopes hooks to confirmed Databricks projects (prevents false positives in unrelated projects)
- Stores classification so the skill skips questions already answered
- Enables the transition hook to detect when a frontend app becomes fullstack

### Setup flow

```
User mentions Databricks with setup intent
  └─ Hook fires → invoke databricks-lakebase
       └─ Phase 0: Scans project (silent — no questions)
       └─ Phase 1: Asks 1-2 questions (intent + workspace type)
       └─ Phase 2: Presents plan, gets confirmation
       └─ Phase 3: Generates connection boilerplate for your stack
       └─ Phase 4: Adds security — PKCE login or token rotation
       └─ Phase 5: Generates typed query modules for your entities
       └─ Phase 6: Verification script + security checklist
```

### Internal router

The skill automatically determines where to start based on project state:
- **First time** (no `.lakebase`) → full Phase 0-6
- **Gap fill** (`.lakebase` exists, some layers missing) → starts at first gap
- **Fast path** (user requests specific output) → jumps directly to relevant phase
- **Re-entry** (connection + security exist, user wants new queries) → Phase 5 only

### Skill vs rules responsibility

| Layer | Responsibility |
|---|---|
| **Rules** | Passive always-on constraints — how to write Databricks code correctly |
| **Hooks** | Detection gates — ensure the skill runs before code is written |
| **Skill** | Active setup wizard — discovers intent, plans, generates project files |

---

## Manual skill invocation

```
/databricks-lakebase
```

## Reset project classification

```bash
rm .lakebase
```
