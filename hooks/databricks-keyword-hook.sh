#!/bin/bash
# Detects Databricks/Lakebase keywords in user prompts and instructs Claude
# to invoke the databricks-connection skill automatically.

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
  echo "SKILL TRIGGER: The user's message contains Databricks/Lakebase keywords. You MUST invoke the Skill tool with skill='databricks-connection' BEFORE responding. Do not skip this step."
fi
