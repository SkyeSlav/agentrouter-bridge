#!/data/data/com.termux/files/usr/bin/bash
# toggle-bridge.sh — Termux:Widget entry point.
# Runs with NO terminal attached: must not prompt, must log everything.
HOME_DIR="${HOME:-/data/data/com.termux/files/home}"
APPDIR="$HOME_DIR/agentrouter-bridge"
LOG="$APPDIR/widget.log"
ENVF="$HOME_DIR/.agentrouter-env"

mkdir -p "$APPDIR" 2>/dev/null || true
log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"; }

notify() {
  command -v termux-notification >/dev/null 2>&1 && \
    termux-notification --title "$1" --content "$2" --id bridge-widget 2>/dev/null || true
}

is_up() {
  # Two checks, because a bare 200 is not proof:
  #  1. explicit HTTP status (a `curl -s -o /dev/null` can exit 0 on empty reply)
  #  2. identity - the bridge announces itself in the Server header, so a
  #     stray process squatting on :8787 cannot masquerade as a healthy start.
  local hdr code
  # GET (not HEAD): the bridge has no do_HEAD and answers 501 to it.
  hdr="$(curl -s -D - -o /dev/null --max-time 5 \
         "http://127.0.0.1:8787/v1/models" 2>/dev/null | tr -d '\r')"
  code="$(printf '%s' "$hdr" | sed -n '1s/.* \([0-9][0-9][0-9]\).*/\1/p')"
  [ "$code" = "200" ] || return 1
  printf '%s' "$hdr" | grep -qi '^Server: agentrouter-bridge' || {
    log "port 8787 answered 200 but is NOT our bridge (Server header mismatch)"
    return 1
  }
  return 0
}

RUNNING=0
pgrep -f "bridge.py --port 8787" >/dev/null 2>&1 && RUNNING=1

log "--- widget invoked (running=$RUNNING)"

if [ "$RUNNING" = "1" ]; then
  # STOP
  pkill -f "bridge.py --port 8787" 2>/dev/null
  command -v tmux >/dev/null 2>&1 && tmux kill-session -t bridge 2>/dev/null
  sleep 1
  if pgrep -f "bridge.py --port 8787" >/dev/null 2>&1; then
    log "STOP FAILED - still running"
    notify "Bridge" "Stop failed - still running"
  else
    log "stopped"
    notify "Bridge" "Stopped"
  fi
  exit 0
fi

# START
if [ ! -f "$ENVF" ]; then
  log "ABORT: $ENVF missing"
  notify "Bridge" "No .agentrouter-env - cannot start"
  exit 1
fi

BAD=$(grep -vE '^\s*(export\s+[A-Z_]+=.*)?\s*$' "$ENVF" | head -3)
if [ -n "$BAD" ]; then
  log "ABORT: env file corrupted: $BAD"
  notify "Bridge" "Env file corrupted - see widget.log"
  exit 1
fi

log "starting"
[ -x "$HOME_DIR/start-bridge.sh" ] || chmod +x "$HOME_DIR/start-bridge.sh" 2>/dev/null
"$HOME_DIR/start-bridge.sh" >> "$LOG" 2>&1
RC=$?
sleep 2

if is_up; then
  log "started OK (health 200)"
  notify "Bridge" "Running on :8787"
else
  log "start FAILED (rc=$RC) - see log above"
  notify "Bridge" "Failed to start - see widget.log"
fi
exit 0
