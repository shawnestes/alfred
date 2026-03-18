#!/bin/bash
# Quickdraw Daily Trade Report — pure code, no LLM
# Reads .paper-portfolio.json, formats report, posts to #quickdraw
# Meant to run as a cron job (e.g., daily 10pm ET)

set -euo pipefail

PORTFOLIO="/root/.openclaw/agents/quickdraw/workspace/repo/.paper-portfolio.json"
LIVE_LOG="/var/log/quickdraw-live.log"
SLACK_TOKEN="${SLACK_TOKEN:-}"
CHANNEL="C0ACL9Q55EX"

if [ ! -f "$PORTFOLIO" ]; then
  echo "ERROR: Portfolio file not found" >&2
  exit 1
fi

# Generate report via Python (structured data → formatted output)
REPORT=$(python3 << 'PYEOF'
import json, sys
from datetime import datetime, timedelta, timezone

with open("/root/.openclaw/agents/quickdraw/workspace/repo/.paper-portfolio.json") as f:
    data = json.load(f)

sol_balance = data["solBalance"]
starting_sol = data["startingSol"]
pnl_sol = sol_balance - starting_sol
pnl_pct = (pnl_sol / starting_sol) * 100
positions = data.get("positions", {})
trades = data.get("trades", [])

# Today's trades (last 24h)
now = datetime.now(timezone.utc)
cutoff = now - timedelta(hours=24)
today_trades = []
for t in trades:
    try:
        ts = datetime.fromisoformat(t["timestamp"].replace("Z", "+00:00"))
        if ts >= cutoff:
            today_trades.append(t)
    except:
        pass

# Count buys/sells
buys = [t for t in today_trades if t["type"] == "BUY"]
sells = [t for t in today_trades if t["type"] == "SELL"]

# Calculate today's realized P&L from sells
today_pnl = 0
for s in sells:
    # Rough P&L: output SOL - input cost basis
    today_pnl += s.get("outputAmount", 0) - s.get("inputAmount", 0) if s.get("outputSymbol") == "SOL" else 0

# Strategy breakdown from live log
import subprocess
try:
    result = subprocess.run(
        ["grep", "Strategy Performance", "-A", "10", "/var/log/quickdraw-live.log"],
        capture_output=True, text=True, timeout=5
    )
    log_lines = result.stdout.strip().split("\n")
    # Get the last performance block
    strat_lines = []
    for i, line in enumerate(log_lines):
        if "Strategy Performance" in line:
            strat_lines = log_lines[i+1:i+10]
    strategy_block = "\n".join(l for l in strat_lines if any(s in l for s in ["rsi", "momentum", "mean-reversion", "mfi", "TOTAL"]))
except:
    strategy_block = "unavailable"

# Format positions
pos_lines = []
for mint, p in positions.items():
    sym = p["symbol"]
    amt = p["amount"]
    cost = p["totalCostSol"]
    pos_lines.append(f"  • {sym}: {amt:,.2f} tokens (cost: {cost:.3f} SOL)")

if not pos_lines:
    pos_lines = ["  • No open positions"]

# Build report
arrow = "📈" if pnl_sol >= 0 else "📉"
report = f""":bar_chart: *Quickdraw Daily Trade Report*
_{now.strftime('%B %d, %Y')}_

*Portfolio*
  • Balance: {sol_balance:.2f} SOL ({pnl_pct:+.2f}% all-time)
  • Starting: {starting_sol:.2f} SOL
  • P&L: {pnl_sol:+.4f} SOL {arrow}

*Today's Activity* (24h)
  • Trades: {len(today_trades)} ({len(buys)} buys, {len(sells)} sells)
  • Total trades all-time: {len(trades):,}

*Open Positions*
{chr(10).join(pos_lines)}

*Strategy Performance* (current session)
```{strategy_block}```

_Automated report — no tokens burned_ :robot_face:"""

print(report)
PYEOF
)

if [ -z "$REPORT" ]; then
  echo "ERROR: Failed to generate report" >&2
  exit 1
fi

# Post to Slack
curl -s -X POST "https://slack.com/api/chat.postMessage" \
  -H "Authorization: Bearer $SLACK_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$(python3 -c "import json; print(json.dumps({'channel': '$CHANNEL', 'text': '''$REPORT'''}))" 2>/dev/null || python3 -c "
import json, sys
report = sys.stdin.read()
print(json.dumps({'channel': '$CHANNEL', 'text': report}))
" <<< "$REPORT")" > /dev/null

echo "Report posted to #quickdraw"
