#!/data/data/com.termux/files/usr/bin/bash
# start-bridge.sh — idempotent start of the Option-2 bridge under tmux
set -uo pipefail
HOME_DIR="${HOME:-/data/data/com.termux/files/home}"
APPDIR="$HOME_DIR/agentrouter-bridge"
ENVFILE="$HOME_DIR/.agentrouter-env"
PY="$(command -v python3 || command -v python)"

[ -f "$APPDIR/bridge.py" ] || { echo "bridge.py missing - run install.sh"; exit 1; }
[ -f "$ENVFILE" ] || { echo "missing $ENVFILE (see .agentrouter-env.example)"; exit 1; }

# Validate before sourcing: the file must contain ONLY export lines.
# A stray pasted command would otherwise execute here.
BAD=$(grep -vE '^\s*(export\s+[A-Z_]+=.*)?\s*$' "$ENVFILE" | head -5)
if [ -n "$BAD" ]; then
  printf 'REFUSING TO START: %s contains non-assignment lines:\n' "$ENVFILE"
  printf '%s\n' "$BAD" | sed 's/^/    /'
  printf 'Fix it with:  printf "export BRIDGE_API_KEY=%%s\\n" '"'"'your-key'"'"' > %s\n' "$ENVFILE"
  exit 1
fi

# shellcheck disable=SC1090
. "$ENVFILE"
[ -n "${BRIDGE_API_KEY:-}" ] || { echo "BRIDGE_API_KEY empty in $ENVFILE"; exit 1; }
case "$BRIDGE_API_KEY" in
  *[!A-Za-z0-9_-]*) echo "BRIDGE_API_KEY looks malformed (unexpected characters)"; exit 1 ;;
esac
MODEL="${BRIDGE_MODEL:-gpt-6.1-sol}"

pkill -f "bridge.py --port 8787" 2>/dev/null && { echo "stopped old bridge"; sleep 1; }

if command -v tmux >/dev/null 2>&1; then
  tmux kill-session -t bridge 2>/dev/null || true
  # Export inside the session so the key never appears in the process command line.
  tmux new-session -d -s bridge \
    "export BRIDGE_API_KEY='$BRIDGE_API_KEY'; \
     $PY $APPDIR/bridge.py --port 8787 --profile claude-cli \
     --origin https://agentrouter.org \
     --auth-scheme both --verbose >> $APPDIR/bridge.log 2>&1"
  echo "started in tmux session 'bridge'"
else
  # shellcheck disable=SC2086
  BRIDGE_API_KEY="$BRIDGE_API_KEY" nohup "$PY" "$APPDIR/bridge.py" --port 8787 \
    --profile claude-cli --origin https://agentrouter.org \
    --auth-scheme both --verbose >> "$APPDIR/bridge.log" 2>&1 &
  echo "started with nohup (pid $!) - will die if Termux is killed"
fi

sleep 2
CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 -X POST \
  http://127.0.0.1:8787/v1/messages -H 'Content-Type: application/json' \
  -d "{\"model\":\"$MODEL\",\"max_tokens\":8,\"messages\":[{\"role\":\"user\",\"content\":\"ok\"}]}")
echo "health check: HTTP $CODE (200 = good)"
[ "$CODE" = "200" ] || echo "  -> check $APPDIR/bridge.log"
