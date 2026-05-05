#!/bin/bash
# Detects Databricks/Lakebase references in code Claude is about to write.
# Only fires in confirmed Databricks projects (.lakebase marker must exist).
# Also detects frontend→fullstack transition and forces architecture re-run.

input=$(cat)

if [ ! -f ".lakebase" ]; then
  exit 0
fi

tool_name=$(echo "$input" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('tool_name', ''))
except Exception:
    print('')
" 2>/dev/null)

if [[ "$tool_name" != "Write" && "$tool_name" != "Edit" ]]; then
  exit 0
fi

file_path=$(echo "$input" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    tool_input = data.get('tool_input', {})
    print(tool_input.get('file_path', '') + tool_input.get('path', ''))
except Exception:
    print('')
" 2>/dev/null)

# Detect frontend→fullstack transition:
# .lakebase says 'frontend' but a backend entrypoint is being written
app_type=$(python3 -c "
import json
try:
    with open('.lakebase') as f:
        print(json.load(f).get('app_type', ''))
except Exception:
    print('')
" 2>/dev/null)

if [[ "$app_type" == "frontend" ]]; then
  if echo "$file_path" | grep -qiE "(^|/)((server|app|main|index)\.(ts|js|py|go)|Dockerfile|wsgi\.py|asgi\.py|manage\.py)$"; then
    printf "App type transition detected: .lakebase says 'frontend' but you are writing a backend entrypoint (%s).\n" "$file_path"
    printf "Re-run the 'databricks-architecture' skill to reclassify this project before continuing.\n"
    exit 0
  fi
fi

content=$(echo "$input" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    tool_input = data.get('tool_input', {})
    print(tool_input.get('content', '') + ' ' + tool_input.get('new_string', ''))
except Exception:
    print('')
" 2>/dev/null)

if echo "$content" | grep -qiE "databricks|lakebase|dbutils|dbfs:|DeltaTable|delta_table"; then
  printf "Databricks/Lakebase code detected in write.\n"
  printf "Check the Databricks Skill Activation Policy (rules/databricks/activation.md) to determine which skill(s) to invoke before completing this write.\n"
fi
