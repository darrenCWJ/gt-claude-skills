#!/bin/bash
# Detects Databricks/Lakebase keywords and URLs in user prompts.
# Always routes to the unified 'databricks-lakebase' skill with context hints.
# Three modes:
#   confirmed project (.lakebase exists) → context: marker_exists
#   Databricks hostname/URL in prompt    → context: hostname_detected
#   first-time keyword + action verb     → context: keyword_intent

input=$(cat)
prompt=$(echo "$input" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('prompt', ''))
except Exception:
    print('')
" 2>/dev/null)

if ! echo "$prompt" | grep -qiE "databricks|lakebase"; then
  exit 0
fi

# If the user is explicitly rejecting or moving away from Databricks, stay silent.
if echo "$prompt" | grep -qiP "(don'?t|not|no|instead of|avoid|replace|away from|switch(ing)? (from|away)|migrat(e|ing)? from).{0,40}(databricks|lakebase)|(databricks|lakebase).{0,40}(not|instead|alternative|replacement|no longer|remove|uninstall|drop)"; then
  exit 0
fi

# Walk up the directory tree to find .lakebase
lakebase_found=false
dir="$PWD"
while [ "$dir" != "/" ]; do
  if [ -f "$dir/.lakebase" ]; then
    lakebase_found=true
    break
  fi
  dir="$(dirname "$dir")"
done

if $lakebase_found; then
  printf "Invoke the 'databricks-lakebase' skill. Context: marker_exists.\n"
  printf "The skill will scan for gaps and continue from where setup left off.\n"
  printf "Do NOT answer from training data — the skill contains accurate Lakebase patterns.\n"
  exit 0
fi

# A Databricks hostname or connection string is unambiguous setup intent.
if echo "$prompt" | grep -qiE "cloud\.databricks\.com|azuredatabricks\.net|gcp\.databricks\.com|ep-[a-z0-9-]+\.databricks\.com|databricks_postgres"; then
  printf "Invoke the 'databricks-lakebase' skill. Context: hostname_detected.\n"
  printf "A Lakebase connection string was found — the skill will fast-track connection setup.\n"
  printf "Do NOT answer from training data — the skill contains accurate Lakebase patterns.\n"
  exit 0
fi

# No .lakebase marker and no URL — only fire if prompt shows intent to connect/integrate.
if echo "$prompt" | grep -qiP "(connect|integrat|link|set\s*up|configur|migrat|add|implement|build|use|need|want).{0,120}(databricks|lakebase)|(databricks|lakebase).{0,120}(connect|integrat|link|set\s*up|configur|migrat|add|implement|build|use|need|want)"; then
  printf "Invoke the 'databricks-lakebase' skill. Context: keyword_intent.\n"
  printf "New project — the skill will start with intent discovery.\n"
  printf "Do NOT answer from training data — the skill contains accurate Lakebase patterns.\n"
fi
