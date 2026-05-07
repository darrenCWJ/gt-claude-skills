---
name: databricks-connector-install
description: >
  Full Databricks development environment bootstrap — from zero to working
  connection. Installs prerequisites (git, Databricks CLI, uv), runs the AI Dev
  Kit installer, configures workspace authentication, and verifies connectivity.
  Handles multiple workspaces with org-detection (surfaces existing profiles from
  ~/.databrickscfg). TRIGGER when: user says "install databricks", "set up
  databricks", "databricks connector", "connect to databricks", "set up my dev
  environment for Databricks", or asks how to get started with Databricks.
  Also triggers when adding a new workspace to an existing setup.
  SKIP: user only wants to switch profiles (use databricks-config), query data
  (use databricks-lakebase), or run SQL (use databricks-dbsql).
version: 1.0.0
tags: [databricks, install, connector, cli, sdk, auth, ai-dev-kit, setup]
---

# Databricks Connector Install Skill

## Internal Router

Evaluate from top to bottom. Enter at the FIRST matching condition.

### Already Fully Installed

If `~/.ai-dev-kit/` exists AND `~/.databrickscfg` has profiles AND `databricks`
CLI is on PATH with version >= 0.278.0:
- Report current state (installed version, profiles, default workspace)
- Ask: "Everything looks good. Do you want to add another workspace, update the
  AI Dev Kit, or verify your connection?"
- Route to Phase 2 (add workspace), Phase 3 (update), or Phase 4 (verify)

### Partially Installed

If some tools exist but others are missing (e.g., CLI installed but no AI Dev Kit):
- Skip to first missing phase
- Do NOT re-install what already works

### Fresh Install

If nothing exists:
- Start at Phase 0

---

## Phase 0 — Environment Scan (Silent)

Scan the system WITHOUT asking questions. Check:

| Target | How to check |
|--------|--------------|
| OS | `uname -s` (Darwin/Linux) or detect Windows |
| git | `which git` |
| Databricks CLI | `which databricks && databricks --version` |
| uv | `which uv && uv --version` |
| Homebrew (macOS) | `which brew` |
| `~/.databrickscfg` | Read file, parse `[profile]` sections |
| `~/.ai-dev-kit/` | Check directory exists, read `version` file |
| AI coding tools | Check for `.claude/`, `.cursor/`, `.github/copilot/` |

Produce internal state (do not show to user):

```
os: darwin | linux | windows
has_git: bool
has_cli: bool
cli_version: string | null
has_uv: bool
has_brew: bool (macOS only)
has_ai_dev_kit: bool
ai_dev_kit_version: string | null
existing_profiles: list[{name, host, auth_type}]
detected_tools: list[string]  # claude, cursor, copilot, codex, gemini
```

Use this state to determine which phases to skip.

---

## Phase 1 — Install Prerequisites

Install ONLY what's missing. For each missing tool, provide the install command
and run it (with user confirmation for commands requiring sudo).

### 1a — uv (Python package manager, required by AI Dev Kit)

If `uv` not found:

> "Installing uv (Python package manager required by the AI Dev Kit)..."

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

After install, verify: `uv --version`

If already installed, report version and skip.

### 1b — Databricks CLI

If `databricks` not found OR version < 0.278.0:

**macOS (Homebrew available):**
```bash
brew tap databricks/tap
brew install databricks
```

**macOS (no Homebrew) or Linux:**
```bash
curl -fsSL https://raw.githubusercontent.com/databricks/setup-cli/main/install.sh | sudo sh
```

**Windows (PowerShell):**
```powershell
winget install Databricks.DatabricksCLI
```

After install, verify: `databricks --version`

Minimum required version: **0.278.0**

If version is below minimum:
```bash
# macOS
brew upgrade databricks

# Linux
curl -fsSL https://raw.githubusercontent.com/databricks/setup-cli/main/install.sh | sudo sh
```

### 1c — Shell Completions (optional, macOS + zsh)

After CLI install on macOS:

> "For tab completion in zsh, add this to your ~/.zshrc:
> ```
> fpath+=$(brew --prefix)/share/zsh/site-functions
> autoload -Uz compinit && compinit
> ```
> Then open a new terminal. Want me to add this? (y/n)"

Only offer — do not auto-modify shell config without confirmation.

### Prerequisites Summary

After all installs, show:

> **Prerequisites ready:**
> | Tool | Version | Status |
> |------|---------|--------|
> | git | 2.x.x | OK |
> | Databricks CLI | 0.299.0 | OK |
> | uv | 0.11.x | OK |

---

## Phase 2 — Workspace Authentication

### 2a — Detect Existing Profiles

If `~/.databrickscfg` exists and has profiles:

> "I found existing Databricks profiles:
>
> | # | Profile | Host | Auth |
> |---|---------|------|------|
> | 1 | DEFAULT | https://your-workspace.cloud.databricks.com | token |
> | 2 | My Profile | https://your-workspace.cloud.databricks.com | databricks-cli |
>
> What would you like to do?
> 1. **Use existing** — verify and continue with one of these
> 2. **Add new workspace** — connect to a different Databricks workspace
> 3. **Skip** — I'll configure auth later"

If user picks "Use existing" → verify with `databricks workspace list / --profile <name>`,
then skip to Phase 3.

### Org Detection

When listing profiles, highlight workspaces from the same organization:

- Group profiles by host domain (e.g., all `*.cloud.databricks.com` profiles)
- If multiple profiles share a domain pattern, note: "These appear to be from the
  same organization"
- Surface organization-specific workspaces (e.g., UAT, staging, production) so the
  user can identify which environment they need

### 2b — New Workspace Setup

If no profiles exist OR user wants to add a new one:

> "Let's connect to your Databricks workspace.
>
> What's your workspace URL?
> (It looks like: `https://your-workspace.cloud.databricks.com`)
>
> If you don't know it, ask your Databricks admin or check your browser URL
> when logged into Databricks."

Once URL provided:

> "How would you like to authenticate?
> 1. **OAuth (recommended)** — browser-based login, tokens auto-refresh
> 2. **Personal Access Token (PAT)** — paste a token, simpler but expires
> 3. **Service Principal** — M2M auth for automation/CI (client ID + secret)"

#### Option 1 — OAuth login:

```bash
databricks auth login --host <workspace-url> -p "<profile-name>"
```

This opens a browser. After auth completes, the CLI stores credentials.

> "A browser window will open. Log in with your Databricks credentials.
> Once complete, the CLI will confirm your profile is saved."

Note: This is an interactive command. Provide it to the user and explain what
will happen. Suggest they run it with `! databricks auth login --host <url> -p "<name>"`
so the output lands in the conversation.

#### Option 2 — PAT:

> "Create a Personal Access Token:
> 1. Log into Databricks → click your profile (top right) → **Settings**
> 2. Go to **Developer → Access tokens**
> 3. Click **Generate new token**
> 4. Name it (e.g., `cli-dev`) and set expiry
> 5. Copy the token"

```bash
databricks configure --token --profile "<profile-name>"
# Prompts for: host URL and token
```

#### Option 3 — Service Principal:

> "For service principal auth, you need:
> - **Client ID** (application ID of the service principal)
> - **Client Secret** (generated in Databricks)
>
> These are typically provided by your Databricks admin."

```bash
databricks auth login --host <workspace-url> \
  --client-id <client-id> \
  --client-secret <client-secret> \
  -p "<profile-name>"
```

### 2c — Set Default Profile

If multiple profiles exist after setup:

> "Which profile should be the default?
> (This is used when no `--profile` flag is specified)"

Update `~/.databrickscfg`:
```ini
[__settings__]
default_profile = <chosen-profile>
```

### 2d — Verify Authentication

After any auth method:

```bash
databricks workspace list / --profile "<profile-name>"
```

If successful → show workspace root listing.
If failed → diagnose:
- 401: token expired or invalid
- 403: insufficient permissions
- Network error: check URL, VPN, proxy

---

## Phase 3 — AI Dev Kit Installation

### 3a — Check Existing Installation

If `~/.ai-dev-kit/` exists:

```bash
cat ~/.ai-dev-kit/version
```

Compare with latest release:
```bash
curl -s https://api.github.com/repos/databricks-solutions/ai-dev-kit/releases/latest | grep tag_name
```

If current → report and skip:
> "AI Dev Kit v0.1.10 is installed and up to date."

If outdated → offer update:
> "AI Dev Kit v0.1.8 is installed. Latest is v0.1.10. Update? (y/n)"

Update command:
```bash
bash <(curl -sL https://raw.githubusercontent.com/databricks-solutions/ai-dev-kit/main/install.sh) --force
```

### 3b — Fresh Installation

If no AI Dev Kit found:

> "The Databricks AI Dev Kit installs skills, MCP server, and tool
> configurations. Run this command:
>
> ```bash
> bash <(curl -sL https://raw.githubusercontent.com/databricks-solutions/ai-dev-kit/main/install.sh)
> ```
>
> The installer will ask you to choose. Here are the **recommended settings**:
>
> | Step | Recommended Choice | Why |
> |------|-------------------|-----|
> | Release channel | **Stable** | Proven, fewer breaking changes |
> | Tools | **Claude Code** | Other tools (Cursor, Copilot, Codex, Gemini) are selectable but Claude Code is recommended |
> | Databricks profile | **DEFAULT** (or the profile you just configured) | Simplest setup |
> | Scope | **Global** | Skills available in all projects, not just one |
> | Skill profile | **All Skills** (34 skills) | Full access — you can always ignore ones you don't need |
> | MCP server path | **~/.ai-dev-kit** (default) | Standard location, shared across projects |
>
> Ready to run the installer?"

Note: The installer is interactive (TUI with arrow keys). The skill provides the
command and explains choices but cannot run it non-interactively.

### 3c — Silent/Scripted Install (CI or advanced users)

For non-interactive installation with recommended settings:

```bash
bash <(curl -sL https://raw.githubusercontent.com/databricks-solutions/ai-dev-kit/main/install.sh) \
  --tools claude \
  --profile DEFAULT \
  --global \
  --skills-profile all
```

Or via environment variables:
```bash
DEVKIT_TOOLS=claude \
DEVKIT_PROFILE=DEFAULT \
DEVKIT_SCOPE=global \
DEVKIT_SKILLS_PROFILE=all \
DEVKIT_MCP_PATH=~/.ai-dev-kit \
bash <(curl -sL https://raw.githubusercontent.com/databricks-solutions/ai-dev-kit/main/install.sh) --force
```

---

## Phase 4 — Verification

Run all checks and report results:

### 4a — Auth Check

```bash
databricks auth profiles
```

Show active profiles and their status.

### 4b — Workspace Access

```bash
databricks workspace list /
```

Confirm workspace is reachable and user has access.

### 4c — Unity Catalog (if available)

```bash
databricks unity-catalog catalogs list
```

Or via REST API:
```bash
curl -s -H "Authorization: Bearer $(databricks auth token --profile <name> | jq -r .access_token)" \
  "https://<host>/api/2.1/unity-catalog/catalogs"
```

### 4d — MCP Server (if AI Dev Kit installed)

Verify MCP server is configured in Claude Code:
```bash
grep -l "databricks" ~/.claude.json 2>/dev/null
```

### 4e — Summary

> **Databricks Development Environment — Ready**
>
> | Component | Status | Details |
> |-----------|--------|---------|
> | Databricks CLI | v0.299.0 | OK |
> | uv | v0.11.11 | OK |
> | Auth profile | `<name>` | Connected to `<host>` |
> | Workspace access | OK | Can list files |
> | Unity Catalog | X catalogs available | `main`, `common`, ... |
> | AI Dev Kit | v0.1.10 | MCP server + 34 skills |
>
> **Next steps:**
> - Try: "List my SQL warehouses" or "Show tables in catalog X"
> - To add another workspace: re-invoke this skill
> - To switch profiles: use the `databricks-config` skill

---

## Phase 5 — Adding Additional Workspaces

Re-entry point when user already has a working setup and wants to connect to
another workspace.

### 5a — Show Current State

> "Current Databricks profiles:
>
> | Profile | Host | Default |
> |---------|------|---------|
> | DEFAULT | https://workspace-1.cloud.databricks.com | * |
> | staging | https://workspace-2.cloud.databricks.com | |
>
> Let's add a new workspace."

### 5b — Add New Profile

Same flow as Phase 2b:
1. Ask for workspace URL
2. Ask for auth method (OAuth / PAT / Service Principal)
3. Run auth command
4. Verify connection
5. Ask if this should become the default

### 5c — Profile Naming

> "What should I name this profile?
> (Tip: use descriptive names like `prod`, `uat`, `sandbox`, or
> `team-analytics`)"

---

## Troubleshooting

### CLI install fails (permission denied)

```bash
# Try with sudo
curl -fsSL https://raw.githubusercontent.com/databricks/setup-cli/main/install.sh | sudo sh

# Or install to user-local bin
mkdir -p ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/databricks/setup-cli/main/install.sh | sh -s -- --install-dir ~/.local/bin
export PATH="$HOME/.local/bin:$PATH"
```

### Auth login fails (browser doesn't open)

- Check if you're in a headless/SSH environment
- Use PAT auth instead: `databricks configure --token --profile <name>`
- Or set `BROWSER=` env var to your browser path

### Workspace list returns 401

- Token may have expired: re-run `databricks auth login --host <url> -p <profile>`
- PAT may be revoked: generate a new one in Databricks UI
- Service principal secret may have expired: regenerate in admin settings

### AI Dev Kit installer hangs

- Ensure `uv` is installed and on PATH
- Check internet connectivity (needs GitHub access)
- Try with `--force` flag to overwrite existing installation
- Check firewall/proxy settings if behind corporate network

### MCP server not working after install

- Restart Claude Code / your editor
- Check `~/.claude.json` for `databricks` MCP server entry
- Verify Python venv: `~/.ai-dev-kit/.venv/bin/python --version`
- Re-run installer with `--force` to recreate venv
