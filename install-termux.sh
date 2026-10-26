#!/data/data/com.termux/files/usr/bin/bash
# install-termux.sh — set up agentrouter-bridge in Termux
# Run:  bash install-termux.sh
set -euo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME_DIR="${HOME:-/data/data/com.termux/files/home}"
APPDIR="$HOME_DIR/agentrouter-bridge"

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31m!! %s\033[0m\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- prerequisites
say "Checking prerequisites"
if ! command -v python >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
  say "Installing Python"
  pkg install -y python
fi
PY="$(command -v python3 || command -v python)"
"$PY" -V
say "Python OK: $("$PY" -V 2>&1)"

command -v curl >/dev/null 2>&1 || pkg install -y curl
command -v termux-wake-lock >/dev/null 2>&1 || say "note: termux-wake-lock missing (termux-api not installed) — optional"

# ---------------------------------------------------------------- get the script
say "Fetching bridge"
mkdir -p "$APPDIR"
if [ -f "$(dirname "$0")/bridge.py" ]; then
  cp "$(dirname "$0")/bridge.py" "$APPDIR/bridge.py"
else
  curl -fsSL -o "$APPDIR/bridge.py" \
    https://raw.githubusercontent.com/SkyeSlav/agentrouter-bridge/main/bridge.py
fi
[ -s "$APPDIR/bridge.py" ] || die "bridge.py download failed"
chmod +x "$APPDIR/bridge.py"
say "bridge.py -> $APPDIR/bridge.py"

# ---------------------------------------------------------------- find 9router
say "Looking for a running 9Router"
FOUND=""
for port in 20128 20129 3000 8080 8736 11434 4000; do
  if curl -s -o /dev/null --max-time 2 "http://127.0.0.1:$port/v1/models"; then
    FOUND="$port"; break
  fi
done
if [ -n "$FOUND" ]; then
  say "Detected a service on 127.0.0.1:$FOUND"
  UPSTREAM="http://127.0.0.1:$FOUND"
else
  printf 'No service detected on common ports.\n'
  printf 'Enter your 9Router base URL (blank to skip for now): '
  read -r UPSTREAM || true
fi

# ---------------------------------------------------------------- write config
say "Writing config"
cat > "$APPDIR/run.sh" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
# Edit UPSTREAM / PROFILE below to change behaviour.
UPSTREAM="${UPSTREAM:-}"
PROFILE="claude-cli"
PORT="8787"
MODEL_MAP=""

ARGS="--port \$PORT --profile \$PROFILE --bind 127.0.0.1"
[ -n "\$UPSTREAM" ]  && ARGS="\$ARGS --upstream \$UPSTREAM"
[ -n "\$MODEL_MAP" ] && ARGS="\$ARGS --model-map \$MODEL_MAP"

termux-wake-lock 2>/dev/null || true
exec "$PY" "$APPDIR/bridge.py" \$ARGS
EOF
chmod +x "$APPDIR/run.sh"
say "Wrote $APPDIR/run.sh"

# ---------------------------------------------------------------- verify
say "Smoke test"
"$PY" "$APPDIR/bridge.py" --port 8787 --profile claude-cli \
  ${UPSTREAM:+--upstream "$UPSTREAM"} >/tmp/bridge-test.log 2>&1 &
BPID=$!
sleep 2
if curl -s -o /dev/null --max-time 5 http://127.0.0.1:8787/v1/models; then
  say "Bridge responds on http://127.0.0.1:8787"
  RESULT=ok
else
  say "Bridge did not answer — see /tmp/bridge-test.log"
  cat /tmp/bridge-test.log || true
  RESULT=fail
fi
kill $BPID 2>/dev/null || true

cat <<EOF

────────────────────────────────────────────────────────────
 Done.  ($RESULT)

 Start:   bash $APPDIR/run.sh
 Then point your client's base URL at:

   Anthropic / Claude-style :  http://127.0.0.1:8787      (no /v1)
   [OI]-compatible          :  http://127.0.0.1:8787/v1

 Keep Termux in the foreground, or run under tmux:
   pkg install -y tmux && tmux new -s bridge
   bash $APPDIR/run.sh
────────────────────────────────────────────────────────────
EOF
