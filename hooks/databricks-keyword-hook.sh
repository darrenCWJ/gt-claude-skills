#!/bin/bash
# Detects Databricks/Lakebase keywords and URLs in user prompts.
# Three-mode:
#   confirmed project (.lakebase exists) → check activation policy on any mention
#   Databricks hostname/URL in prompt    → fire immediately (unambiguous setup intent)
#   first-time keyword only              → require action verb near keyword

input=$(cat)
prompt=$(echo "$input" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('prompt', ''))
except Exception:
    print('')
" 2>/dev/null)

if ! echo "$prompt" | grep -qiE "databricks|lakebase"; then
  exit 0
fi

if [ -f ".lakebase" ]; then
  printf "Databricks/Lakebase detected in prompt.\n"
  printf "Check the Databricks Skill Activation Policy (rules/databricks/activation.md) to determine which skill(s) to invoke before proceeding.\n"
  exit 0
fi

# A Databricks hostname or connection string is unambiguous setup intent —
# fire immediately without requiring action verbs.
if echo "$prompt" | grep -qiE "cloud\.databricks\.com|\.databricks\.com/|ep-[a-z0-9-]+\.databricks\.com|databricks_postgres"; then
  printf "Databricks Lakebase hostname or connection string detected.\n"
  printf "Invoke 'databricks-connection' immediately to generate correct connection boilerplate.\n"
  printf "Do NOT answer from training data — the skill contains the accurate pattern for Lakebase OAuth tokens.\n"
  exit 0
fi

# No .lakebase marker and no URL — only fire if prompt shows intent to connect/integrate,
# not just a passing mention or question about Databricks.
if echo "$prompt" | grep -qiP "(connect|integrat|link|set\s*up|configur|migrat|add|implement|build|use|need|want).{0,60}(databricks|lakebase)|(databricks|lakebase).{0,60}(connect|integrat|link|set\s*up|configur|migrat|add|implement|build|use|need|want)"; then
  printf "Databricks/Lakebase integration intent detected — no .lakebase marker found.\n"
  printf "Invoke the 'databricks-architecture' skill first to classify the app and create the project marker.\n"
fi
