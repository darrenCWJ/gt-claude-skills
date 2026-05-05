#!/bin/bash
# Detects Databricks/Lakebase references in code Claude is about to write.
# Only fires in confirmed Databricks projects (.lakebase marker must exist).

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
