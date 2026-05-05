#!/bin/bash
# Detects Databricks/Lakebase keywords in user prompts and checks setup completion state.
# Silent when all setup steps are complete. Resets on reboot or manual: rm /tmp/databricks-state.json

STATE_FILE="/tmp/databricks-state.json"

read_state() {
  python3 -c "
import json, time

STATE_FILE = '$STATE_FILE'
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
    print(json.dumps(s))
except Exception:
    with open(STATE_FILE, 'w') as f:
        json.dump(defaults, f)
    print(json.dumps(defaults))
" 2>/dev/null
}

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

state=$(read_state)

# All steps complete — stay silent
all_complete=$(echo "$state" | python3 -c "
import json, sys
s = json.load(sys.stdin)
done = all([
    s.get('architecture_classified', False),
    s.get('connection_configured', False),
    s.get('security_checklist_done', False),
    s.get('data_patterns_applied', False),
])
print('True' if done else 'False')
" 2>/dev/null)

if [ "$all_complete" = "True" ]; then
  exit 0
fi

arch=$(echo "$state" | python3 -c "import json,sys; print(json.load(sys.stdin).get('architecture_classified', False))" 2>/dev/null)

if [ "$arch" = "False" ]; then
  printf "DATABRICKS SETUP REQUIRED: architecture_classified=false.\n"
  printf "You MUST invoke the Skill tool with skill='databricks-architecture' BEFORE responding.\n"
  printf "After the skill completes, mark it done by running this Bash command:\n"
  printf "  python3 -c \"import json,time; s=json.load(open('%s')); s['architecture_classified']=True; s['last_updated']=int(time.time()); open('%s','w').write(json.dumps(s))\"\n" "$STATE_FILE" "$STATE_FILE"
  exit 0
fi

conn=$(echo "$state" | python3 -c "import json,sys; print(json.load(sys.stdin).get('connection_configured', False))" 2>/dev/null)
sec=$(echo "$state" | python3 -c "import json,sys; print(json.load(sys.stdin).get('security_checklist_done', False))" 2>/dev/null)
data=$(echo "$state" | python3 -c "import json,sys; print(json.load(sys.stdin).get('data_patterns_applied', False))" 2>/dev/null)

incomplete=""
[ "$conn" = "False" ] && incomplete="$incomplete\n  - connection_configured (databricks-connection)"
[ "$sec" = "False" ] && incomplete="$incomplete\n  - security_checklist_done (databricks-security)"
[ "$data" = "False" ] && incomplete="$incomplete\n  - data_patterns_applied (databricks-data-patterns)"

if [ -n "$incomplete" ]; then
  printf "NOTE: Databricks architecture is classified but these setup steps are still incomplete:%b\n" "$incomplete"
  printf "These will be enforced when you write Databricks code.\n"
fi
