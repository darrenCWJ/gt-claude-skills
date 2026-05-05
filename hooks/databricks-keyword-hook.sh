#!/bin/bash
# Detects Databricks/Lakebase keywords in user prompts.
# Reminds Claude to check the activation policy rules before proceeding.

input=$(cat)
prompt=$(echo "$input" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('prompt', ''))
except Exception:
    print('')
" 2>/dev/null)

if echo "$prompt" | grep -qiE "databricks|lakebase|lakebase postgres|lakebase db"; then
  printf "Databricks/Lakebase detected in prompt.\n"
  printf "Check the Databricks Skill Activation Policy (rules/databricks/activation.md) to determine which skill(s) to invoke before proceeding.\n"
fi
