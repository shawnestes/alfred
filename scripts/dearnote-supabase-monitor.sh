#!/bin/bash
# Dearnote Supabase Health Monitor — pure code, no LLM
# Checks: auth config, edge functions, recent signups, database health
# Posts alerts to #dearnote only if problems found
# Run via cron every 30 min or heartbeat

set -euo pipefail

SUPABASE_TOKEN="sbp_3757ffdfb9e4e15d77771f93af8fbb4a937fce31"
PROJECT_REF="hjmqayhzptdvgsjyxnms"
SLACK_TOKEN="${SLACK_TOKEN:-}"
CHANNEL="C0ACSM5LDLJ"  # #dearnote
API="https://api.supabase.com/v1/projects/${PROJECT_REF}"
ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhqbXFheWh6cHRkdmdzanl4bm1zIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg2ODIzMTQsImV4cCI6MjA4NDI1ODMxNH0.uoYjSLyBVC_hQiW_huLrbFi6wESTmx47a39C5SOC2zQ"

ALERTS=""
WARNINGS=""

add_alert() { ALERTS="${ALERTS}\n:rotating_light: $1"; }
add_warning() { WARNINGS="${WARNINGS}\n:warning: $1"; }

# ─── 1. Auth config health ───
AUTH_CONFIG=$(curl -s -H "Authorization: Bearer $SUPABASE_TOKEN" "$API/config/auth")

SITE_URL=$(echo "$AUTH_CONFIG" | python3 -c "import sys,json; print(json.load(sys.stdin).get('site_url',''))" 2>/dev/null)
HOOK_ENABLED=$(echo "$AUTH_CONFIG" | python3 -c "import sys,json; print(json.load(sys.stdin).get('hook_send_email_enabled', False))" 2>/dev/null)
SMTP_HOST=$(echo "$AUTH_CONFIG" | python3 -c "import sys,json; print(json.load(sys.stdin).get('smtp_host','None'))" 2>/dev/null)

if [[ "$SITE_URL" == *"localhost"* ]]; then
  add_alert "site_url is set to localhost — auth redirects broken"
fi

if [[ "$HOOK_ENABLED" == "True" ]]; then
  # Test if hook actually works
  RECOVER_RESULT=$(curl -s -X POST \
    -H "apikey: $ANON_KEY" \
    -H "Content-Type: application/json" \
    -d '{"email":"health-check-probe@test.invalid"}' \
    "https://${PROJECT_REF}.supabase.co/auth/v1/recover" 2>&1)
  
  if echo "$RECOVER_RESULT" | grep -q "unexpected_failure\|500"; then
    add_alert "Send email hook is BROKEN — returning 500. Auth emails failing silently."
  fi
fi

# ─── 2. Edge function health ───
FUNCTIONS=$(curl -s -H "Authorization: Bearer $SUPABASE_TOKEN" "$API/functions")

echo "$FUNCTIONS" | python3 -c "
import sys, json
funcs = json.load(sys.stdin)
for f in funcs:
    if f.get('status') != 'ACTIVE':
        print(f'ALERT:Edge function {f[\"slug\"]} is {f.get(\"status\",\"UNKNOWN\")}')
" 2>/dev/null | while read -r line; do
  if [[ "$line" == ALERT:* ]]; then
    add_alert "${line#ALERT:}"
  fi
done

# ─── 3. Test critical edge functions ───
# Test send-email function (without triggering actual email)
FUNC_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" \
  -X OPTIONS \
  "https://${PROJECT_REF}.supabase.co/functions/v1/send-email" 2>&1)

# Test generate-message function
GEN_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" \
  -X OPTIONS \
  "https://${PROJECT_REF}.supabase.co/functions/v1/generate-message" 2>&1)

if [[ "$FUNC_HEALTH" != "200" && "$FUNC_HEALTH" != "204" ]]; then
  add_warning "send-email function OPTIONS returned $FUNC_HEALTH"
fi

if [[ "$GEN_HEALTH" != "200" && "$GEN_HEALTH" != "204" ]]; then
  add_warning "generate-message function OPTIONS returned $GEN_HEALTH"
fi

# ─── 4. Database health ───
DB_RESULT=$(curl -s -H "Authorization: Bearer $SUPABASE_TOKEN" \
  "$API/database/query" \
  -X POST -H "Content-Type: application/json" \
  -d '{"query": "SELECT count(*) as user_count FROM auth.users"}' 2>&1)

USER_COUNT=$(echo "$DB_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['user_count'])" 2>/dev/null || echo "ERROR")

if [[ "$USER_COUNT" == "ERROR" ]]; then
  add_alert "Database query failed — cannot reach auth.users"
fi

# ─── 5. Recent failed signups (users with no email_confirmed_at) ───
UNCONFIRMED=$(curl -s -H "Authorization: Bearer $SUPABASE_TOKEN" \
  "$API/database/query" \
  -X POST -H "Content-Type: application/json" \
  -d "{\"query\": \"SELECT count(*) as cnt FROM auth.users WHERE email_confirmed_at IS NULL AND created_at > now() - interval '24 hours'\"}" 2>&1)

UNCONFIRMED_COUNT=$(echo "$UNCONFIRMED" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['cnt'])" 2>/dev/null || echo "0")

if [[ "$UNCONFIRMED_COUNT" -gt 3 ]]; then
  add_warning "$UNCONFIRMED_COUNT unconfirmed signups in last 24h — possible email delivery issue"
fi

# ─── 6. Check Supabase project health ───
PROJECT_STATUS=$(curl -s -H "Authorization: Bearer $SUPABASE_TOKEN" \
  "https://api.supabase.com/v1/projects/$PROJECT_REF" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','UNKNOWN'))" 2>/dev/null)

if [[ "$PROJECT_STATUS" != "ACTIVE_HEALTHY" ]]; then
  add_alert "Supabase project status: $PROJECT_STATUS (expected ACTIVE_HEALTHY)"
fi

# ─── Report ───
if [[ -n "$ALERTS" || -n "$WARNINGS" ]]; then
  REPORT=":stethoscope: *Dearnote Supabase Health Check*\n_$(date -u '+%Y-%m-%d %H:%M UTC')_\n"
  
  if [[ -n "$ALERTS" ]]; then
    REPORT="${REPORT}\n*Critical:*${ALERTS}\n"
  fi
  
  if [[ -n "$WARNINGS" ]]; then
    REPORT="${REPORT}\n*Warnings:*${WARNINGS}\n"
  fi

  REPORT="${REPORT}\n*Stats:* ${USER_COUNT} users | site_url: ${SITE_URL} | hook: ${HOOK_ENABLED} | project: ${PROJECT_STATUS}"

  # Post to Slack
  python3 -c "
import json, urllib.request
data = json.dumps({
    'channel': '$CHANNEL',
    'text': '''$(echo -e "$REPORT")'''
}).encode()
req = urllib.request.Request('https://slack.com/api/chat.postMessage', data=data, headers={
    'Authorization': 'Bearer $SLACK_TOKEN',
    'Content-Type': 'application/json'
})
urllib.request.urlopen(req)
" 2>/dev/null
  
  echo "ALERTS POSTED to #dearnote"
  exit 1
else
  echo "OK — no issues found (users: $USER_COUNT, project: $PROJECT_STATUS)"
  exit 0
fi
