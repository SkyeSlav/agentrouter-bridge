#!/data/data/com.termux/files/usr/bin/bash
# setup-option2.sh — client -> bridge -> AgentRouter  (9Router not involved)
set -euo pipefail
HOME_DIR="${HOME:-/data/data/com.termux/files/home}"
APPDIR="$HOME_DIR/agentrouter-bridge"
PY="$(command -v python3 || command -v python)"

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31m!! %s\033[0m\n' "$*" >&2; exit 1; }

[ -f "$APPDIR/bridge.py" ] || die "bridge.py not found in $APPDIR - run install.sh first"
[ -n "${BRIDGE_API_KEY:-}" ] || die "BRIDGE_API_KEY is not set.
   Run:  export BRIDGE_API_KEY='sk-your-agentrouter-key'"

say "Stopping any old bridge"
pkill -f "bridge.py" 2>/dev/null || true
sleep 1

say "Starting bridge: client -> :8787 -> agentrouter.org"
cd "$APPDIR"
nohup "$PY" "$APPDIR/bridge.py" \
  --port 8787 \
  --profile claude-cli \
  --origin https://agentrouter.org \
  --api-key "$BRIDGE_API_KEY" \
  --auth-scheme both \
  --verbose \
  > "$APPDIR/bridge.log" 2>&1 &
echo $! > "$APPDIR/bridge.pid"
sleep 2

if ! kill -0 "$(cat "$APPDIR/bridge.pid")" 2>/dev/null; then
  die "bridge died on startup. Log:
$(tail -20 "$APPDIR/bridge.log")"
fi
say "Bridge running (pid $(cat "$APPDIR/bridge.pid"))"

say "Testing: does AgentRouter accept us as claude-cli?"
OUT="$(curl -s --max-time 60 -X POST http://127.0.0.1:8787/v1/messages \
  -H 'Content-Type: application/json' \
  -d '{"model":"gpt-6-astra","max_tokens":24,"messages":[{"role":"user","content":"Reply with exactly: bridge ok"}]}')"

case "$OUT" in
  *unauthorized_client_error*)
    printf '%s\n' "$OUT"
    die "STILL BLOCKED: the UA spoof is not passing. Try --profile cline instead." ;;
  *无效的令牌*|*invalid*key*|*new_api_error*)
    printf '%s\n' "$OUT"
    die "GATE PASSED, KEY REJECTED: the spoof works but BRIDGE_API_KEY is wrong or expired." ;;
  *'"content"'*|*'"text"'*)
    say "SUCCESS - AgentRouter answered:"
    printf '%s\n' "$OUT" | head -c 600; printf '\n' ;;
  *)
    say "Unrecognised response:"
    printf '%s\n' "$OUT" | head -c 600; printf '\n' ;;
esac

cat <<EOF

────────────────────────────────────────────────────────────
 CLIENT CONFIG  (9Router is not used)

   Anthropic / Claude-style clients:
     Base URL : http://127.0.0.1:8787
     API key  : anything (the bridge injects the real one)

   [OI]-compatible clients:
     Base URL : http://127.0.0.1:8787/v1
     API key  : anything

 Log   : $APPDIR/bridge.log
 Stop  : kill \$(cat $APPDIR/bridge.pid)
────────────────────────────────────────────────────────────
EOF
