#!/bin/bash
# Detects Databricks/Lakebase references in code Claude is about to write.
# Only fires in confirmed Databricks projects (.lakebase marker must exist).
# Also detects frontend→fullstack transition and forces reclassification.
# Always routes to the unified 'databricks-lakebase' skill.

input=$(cat)

# Walk up the directory tree to find .lakebase
lakebase_path=""
dir="$PWD"
while [ "$dir" != "/" ]; do
  if [ -f "$dir/.lakebase" ]; then
    lakebase_path="$dir/.lakebase"
    break
  fi
  dir="$(dirname "$dir")"
done

if [ -z "$lakebase_path" ]; then
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
    with open('$lakebase_path') as f:
        print(json.load(f).get('app_type', ''))
except Exception:
    print('')
" 2>/dev/null)

if [[ "$app_type" == "frontend" ]]; then
  if echo "$file_path" | grep -qiE "(^|/)((server|app|main|index|application|run|start|handler|function|api|routes|worker)\.(ts|js|mts|mjs|py|go)|Dockerfile(\..*)?|wsgi\.py|asgi\.py|manage\.py|lambda_function\.py|serverless\.yml)$"; then
    printf "Invoke the 'databricks-lakebase' skill. Context: transition.\n"
    printf "App type change detected — .lakebase says 'frontend' but a backend entrypoint (%s) is being written.\n" "$file_path"
    printf "Reclassification needed before continuing.\n"
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
  printf "Invoke the 'databricks-lakebase' skill. Context: code_write.\n"
  printf "Databricks/Lakebase code detected — verify the correct patterns are being used.\n"
fi
