#!/data/data/com.termux/files/usr/bin/bash
# probe.sh — send the same request 3x and show status + body each time
HOME_DIR="${HOME:-/data/data/com.termux/files/home}"
. "$HOME_DIR/.agentrouter-env" 2>/dev/null
M="${1:-${BRIDGE_MODEL:-gpt-6.1-sol}}"
URL="${2:-http://127.0.0.1:8787/v1/messages}"

printf '\nprobing %s  model=%s  3x\n\n' "$URL" "$M"
for i in 1 2 3; do
  code=$(curl -s -o "$HOME/.probe-last.json" -w '%{http_code}' --max-time 90 -X POST "$URL" \
    -H 'Content-Type: application/json' \
    -d "{\"model\":\"$M\",\"max_tokens\":12,\"messages\":[{\"role\":\"user\",\"content\":\"say ok\"}]}")
  printf 'attempt %s: HTTP %s  %s\n' "$i" "$code" "$(head -c 220 "$HOME/.probe-last.json")"
  sleep 3
done
printf '\n'
if [ -n "${BRIDGE_API_KEY:-}" ]; then
  printf 'direct to AgentRouter (bypassing bridge), same key:\n'
  code=$(curl -s -o "$HOME/.probe-direct.json" -w '%{http_code}' --max-time 90 -X POST https://agentrouter.org/v1/messages \
    -A "claude-cli/2.1.0 (external, cli)" -H 'content-type: application/json' \
    -H "Authorization: Bearer $BRIDGE_API_KEY" \
    -d "{\"model\":\"$M\",\"max_tokens\":12,\"messages\":[{\"role\":\"user\",\"content\":\"say ok\"}]}")
  printf '  HTTP %s  %s\n\n' "$code" "$(head -c 300 "$HOME/.probe-direct.json")"
fi
