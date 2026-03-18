#!/bin/bash
# Process Compliance Check — run daily by Nexus
# Checks that agents are following the runbook process

echo "=== PROCESS COMPLIANCE CHECK ==="
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

for PROJECT in dearnote noyoupick ghostreel; do
  REPO="shawnestes/$PROJECT"
  echo "--- $PROJECT ---"
  
  # Check: any PRs merged without QA in last 48h?
  echo "Recent merged PRs (last 7 days):"
  gh pr list --repo "$REPO" --state merged --json number,title,mergedAt,labels -L 5 2>/dev/null || echo "  Could not fetch"
  
  # Check: any direct pushes to main (commits not from PR)?
  echo "Last 5 main commits:"
  cd "/root/.openclaw/agents/$PROJECT/workspace/repo" 2>/dev/null && git fetch origin main --quiet 2>/dev/null && git log origin/main --oneline -5 2>/dev/null || echo "  Could not check"
  cd /root/.openclaw/workspace
  
  # Check: open PRs without QA review
  echo "Open PRs (check for QA status):"
  gh pr list --repo "$REPO" --state open --json number,title,reviews -L 5 2>/dev/null || echo "  Could not fetch"
  
  echo ""
done

echo "=== END COMPLIANCE CHECK ==="
