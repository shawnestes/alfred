#!/bin/bash
# Quickdraw Hourly Trade Report — pure code, no LLM
# Reads .paper-portfolio.json, formats report with per-strategy breakdown, posts to #quickdraw
# Runs hourly to catch problems early

set -euo pipefail

PORTFOLIO="/root/.openclaw/agents/quickdraw/workspace/repo/.paper-portfolio.json"
SLACK_TOKEN="${SLACK_TOKEN:-}"
CHANNEL="C0ACL9Q55EX"

if [ ! -f "$PORTFOLIO" ]; then
  echo "ERROR: Portfolio file not found" >&2
  exit 1
fi

REPORT=$(python3 << 'PYEOF'
import json, sys
from datetime import datetime, timedelta, timezone
from collections import defaultdict

with open("/root/.openclaw/agents/quickdraw/workspace/repo/.paper-portfolio.json") as f:
    data = json.load(f)

sol_balance = data["solBalance"]
starting_sol = data["startingSol"]
pnl_sol = sol_balance - starting_sol
pnl_pct = (pnl_sol / starting_sol) * 100
positions = data.get("positions", {})
trades = data.get("trades", [])

now = datetime.now(timezone.utc)
cutoff_1h = now - timedelta(hours=1)
cutoff_24h = now - timedelta(hours=24)

def parse_ts(t):
    try:
        return datetime.fromisoformat(t["timestamp"].replace("Z", "+00:00"))
    except:
        return None

# Partition trades
trades_1h = []
trades_24h = []
for t in trades:
    ts = parse_ts(t)
    if ts and ts >= cutoff_1h:
        trades_1h.append(t)
    if ts and ts >= cutoff_24h:
        trades_24h.append(t)

def strategy_breakdown(trade_list):
    """Returns per-strategy stats."""
    by_strat = defaultdict(lambda: {"buys": 0, "sells": 0, "sol_in": 0.0, "sol_out": 0.0})
    for t in trade_list:
        strat = t.get("strategy", "unknown")
        if strat in ("unknown", "debug-test"):
            strat = "unknown"
        s = by_strat[strat]
        if t["type"] == "BUY":
            s["buys"] += 1
            if t.get("inputSymbol") == "SOL":
                s["sol_in"] += t.get("inputAmount", 0)
        else:
            s["sells"] += 1
            if t.get("outputSymbol") == "SOL":
                s["sol_out"] += t.get("outputAmount", 0)
    return dict(by_strat)

def format_strat_table(breakdown):
    if not breakdown:
        return "  _No trades_"
    lines = []
    total_buys = total_sells = 0
    total_in = total_out = 0.0
    for strat, s in sorted(breakdown.items()):
        total = s["buys"] + s["sells"]
        net = s["sol_out"] - s["sol_in"]
        sign = "+" if net >= 0 else ""
        lines.append(f"  • *{strat}*: {total} trades ({s['buys']}B/{s['sells']}S) | net: {sign}{net:.4f} SOL")
        total_buys += s["buys"]
        total_sells += s["sells"]
        total_in += s["sol_in"]
        total_out += s["sol_out"]
    total_net = total_out - total_in
    sign = "+" if total_net >= 0 else ""
    lines.append(f"  ——")
    lines.append(f"  *Total*: {total_buys + total_sells} trades ({total_buys}B/{total_sells}S) | net: {sign}{total_net:.4f} SOL")
    return "\n".join(lines)

strat_1h = strategy_breakdown(trades_1h)
strat_24h = strategy_breakdown(trades_24h)

# Positions
pos_lines = []
for mint, p in positions.items():
    sym = p["symbol"]
    amt = p["amount"]
    cost = p["totalCostSol"]
    pos_lines.append(f"  • {sym}: {amt:,.2f} tokens (cost: {cost:.3f} SOL)")
if not pos_lines:
    pos_lines = ["  • No open positions"]

# Alerts
alerts = []
if not trades_1h:
    alerts.append(":warning: No trades in the last hour — strategy may be idle")
for strat, s in strat_1h.items():
    net = s["sol_out"] - s["sol_in"]
    if net < -0.5:
        alerts.append(f":rotating_light: *{strat}* lost {abs(net):.4f} SOL in the last hour")

alert_block = "\n".join(alerts) if alerts else ""

arrow = ":chart_with_upwards_trend:" if pnl_sol >= 0 else ":chart_with_downwards_trend:"
et_now = now - timedelta(hours=4)  # rough ET offset

report = f""":bar_chart: *Quickdraw Trade Report*
_{et_now.strftime('%B %d, %Y — %I:%M %p')} ET_

*Portfolio*
  • Balance: {sol_balance:.2f} SOL ({pnl_pct:+.2f}% all-time) {arrow}
  • Starting: {starting_sol:.2f} SOL | P&L: {pnl_sol:+.4f} SOL

*Last Hour*
{format_strat_table(strat_1h)}

*Last 24 Hours*
{format_strat_table(strat_24h)}

*Open Positions* ({len(positions)})
{chr(10).join(pos_lines)}"""

if alert_block:
    report += f"\n\n{alert_block}"

report += "\n\n_Hourly automated report_ :robot_face:"

print(report)
PYEOF
)

if [ -z "$REPORT" ]; then
  echo "ERROR: Failed to generate report" >&2
  exit 1
fi

# Post to Slack
python3 -c "
import json, urllib.request
data = json.dumps({'channel': '$CHANNEL', 'text': '''$(echo "$REPORT" | sed "s/'/\\\\'/g")'''}).encode()
req = urllib.request.Request('https://slack.com/api/chat.postMessage', data=data, headers={
    'Authorization': 'Bearer $SLACK_TOKEN',
    'Content-Type': 'application/json'
})
resp = urllib.request.urlopen(req)
" 2>/dev/null

echo "Report posted to #quickdraw"
