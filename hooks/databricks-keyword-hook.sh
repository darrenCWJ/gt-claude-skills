#!/bin/bash
# Detects Databricks/Lakebase keywords in user prompts and instructs Claude
# to invoke the databricks-architecture skill — once per session (2hr TTL).

SESSION_FLAG="/tmp/databricks-skill-invoked"
TTL=7200  # 2 hours

if [ -f "$SESSION_FLAG" ]; then
  age=$(($(date +%s) - $(date -r "$SESSION_FLAG" +%s 2>/dev/null || echo 0)))
  if [ "$age" -lt "$TTL" ]; then
    exit 0
  fi
fi

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
  touch "$SESSION_FLAG"
  echo "SKILL TRIGGER: The user's message contains Databricks/Lakebase keywords. You MUST invoke the Skill tool with skill='databricks-architecture' BEFORE responding to classify the app type and orchestrate the correct implementation path. Do not skip this step."
fi
