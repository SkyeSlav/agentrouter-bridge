#!/data/data/com.termux/files/usr/bin/bash
# whereami.sh — prove what 9Router actually calls
HOME_DIR="${HOME:-/data/data/com.termux/files/home}"
LOG="$HOME_DIR/agentrouter-bridge/bridge.log"
BEFORE=$(wc -l < "$LOG" 2>/dev/null || echo 0)

printf '\n\033[1;36m== bridge is listening on 8787?\033[0m\n'
pgrep -af "bridge.py" | sed 's/--[a-z-]*key [^ ]*/--key ***/g' || echo "  NOT RUNNING"

printf '\n\033[1;36m== watching %s for 25s — now send ONE request from 9Router\033[0m\n' "$LOG"
printf '  (waiting...)\n'
sleep 25

AFTER=$(wc -l < "$LOG" 2>/dev/null || echo 0)
printf '\n\033[1;36m== lines added: %s\033[0m\n' "$((AFTER-BEFORE))"
if [ "$AFTER" -gt "$BEFORE" ]; then
  tail -n "$((AFTER-BEFORE))" "$LOG" | sed 's/^/  /'
  printf '\n\033[1;32m  -> 9Router IS reaching the bridge\033[0m\n'
else
  printf '\n\033[1;31m  -> NOTHING arrived. 9Router is not calling this bridge.\033[0m\n'
  printf '     Check the provider Base URL in 9Router:\n'
  printf '       should be  http://127.0.0.1:8787   (no trailing /v1)\n'
fi
printf '\n'
