#!/bin/bash
# Detects Databricks/Lakebase references in code Claude is about to write
# and instructs it to invoke the appropriate skill(s) — once per session (2hr TTL).

SESSION_FLAG="/tmp/databricks-skill-invoked"
TTL=7200  # 2 hours

if [ -f "$SESSION_FLAG" ]; then
  age=$(($(date +%s) - $(date -r "$SESSION_FLAG" +%s 2>/dev/null || echo 0)))
  if [ "$age" -lt "$TTL" ]; then
    exit 0
  fi
fi

input=$(cat)

tool_name=$(echo "$input" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('tool_name', ''))
except Exception:
    print('')
" 2>/dev/null)

# Only scan Write and Edit tool calls
if [[ "$tool_name" != "Write" && "$tool_name" != "Edit" ]]; then
  exit 0
fi

# Extract the content being written
content=$(echo "$input" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    tool_input = data.get('tool_input', {})
    # Write uses 'content', Edit uses 'new_string'
    text = tool_input.get('content', '') + ' ' + tool_input.get('new_string', '')
    print(text)
except Exception:
    print('')
" 2>/dev/null)

# Databricks-specific keywords only (excludes generic PySpark)
if echo "$content" | grep -qiE "databricks|lakebase|dbutils|dbfs:|DeltaTable|delta_table"; then
  touch "$SESSION_FLAG"
  echo "SKILL TRIGGER: The code being written contains Databricks/Lakebase references. Invoke the appropriate skill(s) before completing this write:
- skill='databricks-architecture'   — if app type has not been classified yet
- skill='databricks-connection'     — if connection boilerplate is missing
- skill='databricks-security'       — if token rotation or security checklist is incomplete
- skill='databricks-data-patterns'  — if read/write patterns have not been applied
Do not skip this step."
fi
