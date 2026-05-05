#!/bin/bash
# Detects Databricks/Lakebase keywords in user prompts.
# Two-mode: first-time (no .lakebase) → suggest architecture skill;
#           confirmed project (.lakebase exists) → check activation policy.

input=$(cat)
prompt=$(echo "$input" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('prompt', ''))
except Exception:
    print('')
" 2>/dev/null)

if ! echo "$prompt" | grep -qiE "databricks|lakebase|lakebase postgres|lakebase db"; then
  exit 0
fi

if [ ! -f ".lakebase" ]; then
  printf "Databricks/Lakebase keyword detected — no .lakebase marker found.\n"
  printf "If this is a Databricks/Lakebase project, invoke the 'databricks-architecture' skill first to classify the app and create the project marker.\n"
else
  printf "Databricks/Lakebase detected in prompt.\n"
  printf "Check the Databricks Skill Activation Policy (rules/databricks/activation.md) to determine which skill(s) to invoke before proceeding.\n"
fi
