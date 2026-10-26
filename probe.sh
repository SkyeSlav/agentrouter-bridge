#!/data/data/com.termux/files/usr/bin/bash
# probe.sh [model] [url]  — bodies + timing, no /tmp
HOME_DIR="${HOME:-/data/data/com.termux/files/home}"
. "$HOME_DIR/.agentrouter-env" 2>/dev/null
M="${1:-${BRIDGE_MODEL:-gpt-6.1-sol}}"
URL="${2:-http://127.0.0.1:8787/v1/messages}"
B="$HOME_DIR/.probe-body.json"
W="$HOME_DIR/.probe-meta.txt"

run() {  # label, url, extra-curl-args...
  local label="$1" url="$2"; shift 2
  curl -s -o "$B" -w '%{http_code} %{time_connect} %{time_appconnect} %{time_total}' \
       --max-time 90 "$@" "$url" > "$W" 2>/dev/null
  local meta; meta="$(cat "$W" 2>/dev/null)"
  printf '  %-8s HTTP %s  (conn %ss / tls %ss / total %ss)\n' \
    "$label" "$(printf '%s' "$meta" | cut -d' ' -f1)" \
    "$(printf '%s' "$meta" | cut -d' ' -f2)" \
    "$(printf '%s' "$meta" | cut -d' ' -f3)" \
    "$(printf '%s' "$meta" | cut -d' ' -f4)"
  if [ -s "$B" ]; then printf '           %s\n' "$(head -c 300 "$B")"
  else printf '           (empty body)\n'; fi
}

REQ="{\"model\":\"$M\",\"max_tokens\":12,\"messages\":[{\"role\":\"user\",\"content\":\"say ok\"}]}"

printf '\n\033[1;36m== through the bridge (%s)\033[0m\n' "$URL"
for i in 1 2 3; do
  run "try $i" "$URL" -X POST -H 'Content-Type: application/json' -d "$REQ"
done

printf '\n\033[1;36m== direct to AgentRouter (no bridge)\033[0m\n'
if [ -n "${BRIDGE_API_KEY:-}" ]; then
  for i in 1 2 3; do
    run "try $i" "https://agentrouter.org/v1/messages" -X POST \
      -A "claude-cli/2.1.0 (external, cli)" -H 'content-type: application/json' \
      -H "Authorization: Bearer $BRIDGE_API_KEY" -d "$REQ"
  done
else
  echo "  BRIDGE_API_KEY not set - skipped"
fi

printf '\n\033[1;36m== bridge log tail\033[0m\n'
tail -12 "$HOME_DIR/agentrouter-bridge/bridge.log" 2>/dev/null | sed 's/^/  /'
printf '\n'
