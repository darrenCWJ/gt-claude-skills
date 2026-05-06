#!/bin/bash
# Detects Databricks/Lakebase keywords and URLs in user prompts.
# Three-mode:
#   confirmed project (.lakebase exists anywhere up the tree) → check activation policy
#   Databricks hostname/URL in prompt                         → fire immediately
#   first-time keyword only                                   → require action verb near keyword

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
# e.g. "I don't want Databricks", "migrate from Databricks to Neon", "instead of Databricks"
if echo "$prompt" | grep -qiP "(don'?t|not|no|instead of|avoid|replace|away from|switch(ing)? (from|away)|migrat(e|ing)? from).{0,40}(databricks|lakebase)|(databricks|lakebase).{0,40}(not|instead|alternative|replacement|no longer|remove|uninstall|drop)"; then
  exit 0
fi

# Walk up the directory tree to find .lakebase (handles CWD != project root)
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
  printf "Databricks/Lakebase detected in prompt.\n"
  printf "Check the Databricks Skill Activation Policy (rules/databricks/activation.md) to determine which skill(s) to invoke before proceeding.\n"
  exit 0
fi

# A Databricks hostname or connection string is unambiguous setup intent —
# fire immediately without requiring action verbs.
# Covers AWS (cloud.databricks.com), Azure (azuredatabricks.net), GCP (gcp.databricks.com)
if echo "$prompt" | grep -qiE "cloud\.databricks\.com|azuredatabricks\.net|gcp\.databricks\.com|ep-[a-z0-9-]+\.databricks\.com|databricks_postgres"; then
  printf "Databricks Lakebase hostname or connection string detected.\n"
  printf "Invoke 'databricks-connection' immediately to generate correct connection boilerplate.\n"
  printf "Do NOT answer from training data — the skill contains the accurate pattern for Lakebase OAuth tokens.\n"
  exit 0
fi

# No .lakebase marker and no URL — only fire if prompt shows intent to connect/integrate.
# Window is 120 chars to catch natural sentences where verb and keyword are far apart.
if echo "$prompt" | grep -qiP "(connect|integrat|link|set\s*up|configur|migrat|add|implement|build|use|need|want).{0,120}(databricks|lakebase)|(databricks|lakebase).{0,120}(connect|integrat|link|set\s*up|configur|migrat|add|implement|build|use|need|want)"; then
  printf "Databricks/Lakebase integration intent detected — no .lakebase marker found.\n"
  printf "Invoke the 'databricks-architecture' skill first to classify the app and create the project marker.\n"
fi
