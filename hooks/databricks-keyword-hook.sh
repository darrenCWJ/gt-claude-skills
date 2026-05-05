#!/bin/bash
# Detects Databricks/Lakebase keywords in user prompts.
# Two-mode:
#   confirmed project (.lakebase exists) → check activation policy on any mention
#   first-time (no .lakebase) → only fire when prompt shows setup/integration INTENT

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

# No .lakebase marker — only fire if prompt shows intent to connect/integrate,
# not just a passing mention or question about Databricks.
# Intent signals: action verbs within ~60 chars of the keyword.
if echo "$prompt" | grep -qiP "(connect|integrat|link|set\s*up|configur|migrat|add|implement|build|use|need|want).{0,60}(databricks|lakebase)|(databricks|lakebase).{0,60}(connect|integrat|link|set\s*up|configur|migrat|add|implement|build|use|need|want)"; then
  printf "Databricks/Lakebase integration intent detected — no .lakebase marker found.\n"
  printf "If this is a Databricks/Lakebase project, invoke the 'databricks-architecture' skill first to classify the app and create the project marker.\n"
fi
