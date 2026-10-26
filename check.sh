#!/data/data/com.termux/files/usr/bin/bash
# check.sh — confirm exactly one bridge is alive and it can reach AgentRouter
HOME_DIR="${HOME:-/data/data/com.termux/files/home}"
APPDIR="$HOME_DIR/agentrouter-bridge"
. "$HOME_DIR/.agentrouter-env" 2>/dev/null
M="${BRIDGE_MODEL:-gpt-6.1-sol}"

printf '\n== processes\n'
pgrep -af "bridge.py" || echo "  NONE RUNNING"
N=$(pgrep -cf "bridge.py" 2>/dev/null || echo 0)
printf '  count: %s\n' "$N"
[ "$N" -gt 1 ] && echo "  !! more than one - run: pkill -f bridge.py && bash $HOME_DIR/start-bridge.sh"

printf '\n== tmux session\n'
if command -v tmux >/dev/null 2>&1; then
  tmux ls 2>/dev/null || echo "  no tmux sessions (nohup mode: dies if Termux is killed)"
else
  echo "  tmux not installed"
fi

printf '\n== listening on 8787\n'
curl -s -o /dev/null -w '  /v1/models -> HTTP %{http_code}\n' --max-time 10 http://127.0.0.1:8787/v1/models

printf '\n== end-to-end (%s via /v1/messages)\n' "$M"
curl -s --max-time 45 -X POST http://127.0.0.1:8787/v1/messages \
  -H 'Content-Type: application/json' \
  -d "{\"model\":\"$M\",\"max_tokens\":12,\"messages\":[{\"role\":\"user\",\"content\":\"say ok\"}]}" \
  | head -c 400
printf '\n'
