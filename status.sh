#!/data/data/com.termux/files/usr/bin/bash
# status.sh — where things currently stand, no assumptions
HOME_DIR="${HOME:-/data/data/com.termux/files/home}"
APPDIR="$HOME_DIR/agentrouter-bridge"
ENVF="$HOME_DIR/.agentrouter-env"

printf '\n\033[1;36m== env file\033[0m\n'
if [ -f "$ENVF" ]; then
  printf '  path  : %s\n' "$ENVF"
  printf '  perms : %s\n' "$(stat -c '%a' "$ENVF" 2>/dev/null || echo '?')"
  k=$(grep -o "BRIDGE_API_KEY=.*" "$ENVF" 2>/dev/null | sed "s/BRIDGE_API_KEY=//;s/['\"]//g")
  printf '  key   : len=%s prefix=%s\n' "${#k}" "$(printf '%s' "$k" | cut -c1-6)"
  grep -o "BRIDGE_MODEL=.*" "$ENVF" 2>/dev/null || echo "  model : (unset, defaults to gpt-6.1-sol)"
else
  printf '  MISSING - create it with:  printf "export BRIDGE_API_KEY=%%s\\\\n" '"'"'sk-your-key'"'"' > %s\n' "$ENVF"
fi

printf '\n\033[1;36m== bridge process\033[0m\n'
pgrep -af bridge.py | sed 's/--api-key [^ ]*/--api-key ***/g' || echo "  NONE running"

printf '\n\033[1;36m== listening\033[0m\n'
curl -s -o /dev/null -w '  /v1/models -> HTTP %{http_code}\n' --max-time 8 http://127.0.0.1:8787/v1/models

printf '\n\033[1;36m== scripts present\033[0m\n'
for f in bridge.py; do
  [ -f "$APPDIR/$f" ] && printf '  %-18s ok\n' "$f" || printf '  %-18s MISSING\n' "$f"
done
for f in probe.sh start-bridge.sh check.sh; do
  if [ -f "$HOME_DIR/$f" ]; then printf '  %-18s ok (~/)\n' "$f"
  elif [ -f "$APPDIR/$f" ]; then printf '  %-18s ok (appdir)\n' "$f"
  else printf '  %-18s MISSING\n' "$f"; fi
done
printf '\n'
