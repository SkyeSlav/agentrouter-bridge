#!/data/data/com.termux/files/usr/bin/bash
# diag.sh — find out why AgentRouter returned "upstream error"
set -uo pipefail
HOME_DIR="${HOME:-/data/data/com.termux/files/home}"
APPDIR="$HOME_DIR/agentrouter-bridge"

printf '\n\033[1;36m== 1. models your key can see (authoritative list)\033[0m\n'
curl -s --max-time 30 http://127.0.0.1:8787/v1/models \
  -H "Authorization: Bearer x" | head -c 1200
printf '\n'

printf '\n\033[1;36m== 2. a plain chat completion with a DIFFERENT model\033[0m\n'
if [ -n "${TEST_MODEL:-}" ]; then M="$TEST_MODEL"; else
  printf 'Model name to try (from the list above): '; read -r M
fi
if [ -n "$M" ]; then
  printf '\n-- POST /v1/messages model=%s\n' "$M"
  curl -s --max-time 60 -X POST http://127.0.0.1:8787/v1/messages \
    -H 'Content-Type: application/json' \
    -d "{\"model\":\"$M\",\"max_tokens\":24,\"messages\":[{\"role\":\"user\",\"content\":\"say ok\"}]}" | head -c 600
  printf '\n\n-- POST /v1/chat/completions model=%s (different endpoint)\n' "$M"
  curl -s --max-time 60 -X POST http://127.0.0.1:8787/v1/chat/completions \
    -H 'Content-Type: application/json' \
    -d "{\"model\":\"$M\",\"max_tokens\":24,\"messages\":[{\"role\":\"user\",\"content\":\"say ok\"}]}" | head -c 600
  printf '\n'
fi

printf '\n\033[1;36m== 3. last 15 lines of the bridge log\033[0m\n'
tail -15 "$APPDIR/bridge.log" 2>/dev/null || echo "(no log)"

cat <<'EOF'

────────────────────────────────────────────────────────────
 How to read this

  A model list in step 1  -> your key works; the model name was
                             the problem. Pick a name from that
                             list and try it in step 2.

  "upstream error" again  -> the model is fine but AgentRouter
                             cannot serve it (no channel). Try a
                             model from ps.air-outer.com/pricing.

  still "invalid token"   -> BRIDGE_API_KEY did not survive the
                             export into the running process.
────────────────────────────────────────────────────────────
EOF
