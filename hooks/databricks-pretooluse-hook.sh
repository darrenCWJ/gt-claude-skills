#!/bin/bash
# Detects Databricks/Lakebase references in code Claude is about to write.
# Checks granular setup state and triggers the relevant skill(s) for any
# incomplete component that matches the code being written.

STATE_FILE="/tmp/databricks-state.json"
TTL=7200  # 2 hours

read_state() {
  python3 -c "
import json, time

STATE_FILE = '$STATE_FILE'
TTL = $TTL
defaults = {
    'architecture_classified': False,
    'connection_configured': False,
    'security_checklist_done': False,
    'data_patterns_applied': False,
    'last_updated': int(time.time())
}

try:
    with open(STATE_FILE) as f:
        s = json.load(f)
    if int(time.time()) - s.get('last_updated', 0) >= TTL:
        raise ValueError('expired')
    print(json.dumps(s))
except Exception:
    with open(STATE_FILE, 'w') as f:
        json.dump(defaults, f)
    print(json.dumps(defaults))
" 2>/dev/null
}

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

content=$(echo "$input" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    tool_input = data.get('tool_input', {})
    text = tool_input.get('content', '') + ' ' + tool_input.get('new_string', '')
    print(text)
except Exception:
    print('')
" 2>/dev/null)

# Only proceed if code has Databricks-specific keywords
if ! echo "$content" | grep -qiE "databricks|lakebase|dbutils|dbfs:|DeltaTable|delta_table"; then
  exit 0
fi

state=$(read_state)

conn=$(echo "$state" | python3 -c "import json,sys; print(json.load(sys.stdin).get('connection_configured', False))" 2>/dev/null)
sec=$(echo "$state" | python3 -c "import json,sys; print(json.load(sys.stdin).get('security_checklist_done', False))" 2>/dev/null)
data=$(echo "$state" | python3 -c "import json,sys; print(json.load(sys.stdin).get('data_patterns_applied', False))" 2>/dev/null)

# Detect which concerns are present in the code being written
has_connection=$(echo "$content" | grep -qiE "SparkSession|databricks_host|databricks_token|DATABRICKS_|DatabricksSession|pat_token|personal_access_token|\.connect\(" && echo "True" || echo "False")
has_security=$(echo "$content" | grep -qiE "token|secret|credential|password|oauth|access_key|client_secret" && echo "True" || echo "False")
has_data_ops=$(echo "$content" | grep -qiE "\.read\.|\.write\.|saveAsTable|insertInto|spark\.sql|DeltaTable\.|\.merge\(" && echo "True" || echo "False")

triggers=""
instructions=""

if [ "$conn" = "False" ] && [ "$has_connection" = "True" ]; then
  triggers="$triggers\n  - connection_configured=false but code has connection patterns"
  instructions="$instructions\n- Invoke skill='databricks-connection' then run:\n    python3 -c \"import json,time; s=json.load(open('$STATE_FILE')); s['connection_configured']=True; s['last_updated']=int(time.time()); open('$STATE_FILE','w').write(json.dumps(s))\""
fi

if [ "$sec" = "False" ] && [ "$has_security" = "True" ]; then
  triggers="$triggers\n  - security_checklist_done=false but code has auth/credential patterns"
  instructions="$instructions\n- Invoke skill='databricks-security' then run:\n    python3 -c \"import json,time; s=json.load(open('$STATE_FILE')); s['security_checklist_done']=True; s['last_updated']=int(time.time()); open('$STATE_FILE','w').write(json.dumps(s))\""
fi

if [ "$data" = "False" ] && [ "$has_data_ops" = "True" ]; then
  triggers="$triggers\n  - data_patterns_applied=false but code has data read/write operations"
  instructions="$instructions\n- Invoke skill='databricks-data-patterns' then run:\n    python3 -c \"import json,time; s=json.load(open('$STATE_FILE')); s['data_patterns_applied']=True; s['last_updated']=int(time.time()); open('$STATE_FILE','w').write(json.dumps(s))\""
fi

if [ -n "$triggers" ]; then
  printf "DATABRICKS CODE WRITE INCOMPLETE SETUP DETECTED:%b\n\n" "$triggers"
  printf "BEFORE completing this write, you MUST:%b\n\n" "$instructions"
  printf "Do not proceed with the write until each applicable skill has been invoked and its state marked done.\n"
fi
