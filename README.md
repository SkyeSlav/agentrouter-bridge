# agentrouter-bridge

A small dependency-free Python bridge that lets **9Router use AgentRouter as an Anthropic-compatible provider**, even though AgentRouter rejects unrecognised clients with `401 unauthorized_client_error`.

Tested end to end on Termux:

```text
client → 9Router :20128 → bridge :8787 → agentrouter.org
```

9Router result after configuration:

```text
FMT: openai→claude · JSON · ACC:Bridge
DONE 5710ms · IN 24 · OUT 15
```

> AgentRouter is an unstable upstream: during testing it intermittently returned JSON and HTML `502` responses. The bridge retries known transient failures and always exposes final errors as JSON so 9Router can parse them.

## What the bridge changes

- Announces an allowlisted client identity such as `claude-cli`.
- Injects your own AgentRouter API key without exposing it in `ps`.
- Accepts both `/messages` and `/v1/messages` and normalises common API paths.
- Retries connection failures and AgentRouter's transient `5xx upstream error` responses.
- Converts final HTML/plain-text error pages into JSON.
- Relays ordinary JSON and SSE streaming responses.
- Optionally rewrites model names.

## Termux quick start: 9Router → bridge → AgentRouter

### 1. Install the basics

```bash
pkg install -y python curl tmux
```

### 2. Download the project

```bash
mkdir -p ~/agentrouter-bridge
curl -fsSL https://raw.githubusercontent.com/SkyeSlav/agentrouter-bridge/main/bridge.py -o ~/agentrouter-bridge/bridge.py
curl -fsSL https://raw.githubusercontent.com/SkyeSlav/agentrouter-bridge/main/start-bridge.sh -o ~/start-bridge.sh
chmod +x ~/start-bridge.sh
```

### 3. Store your AgentRouter key

Get a key from the AgentRouter console, then create the local configuration file:

```bash
printf "export BRIDGE_API_KEY='YOUR_AGENTROUTER_KEY'\nexport BRIDGE_MODEL='gpt-6.1-sol'\n" > ~/.agentrouter-env
chmod 600 ~/.agentrouter-env
```

Do not put other shell commands in `.agentrouter-env`. The launcher rejects contaminated files instead of executing them.

### 4. Start the bridge

```bash
bash ~/start-bridge.sh
```

Expected output:

```text
started in tmux session 'bridge'
health check: HTTP 200 (200 = good)
```

Verify that the key is not visible in the process list:

```bash
pgrep -af bridge.py
```

### 5. Configure 9Router

Add an **Anthropic-compatible / Claude-compatible** provider or account:

| 9Router field | Value |
|---|---|
| Name | `Bridge` |
| Provider type | Anthropic-compatible / Claude-compatible |
| Base URL | `http://127.0.0.1:8787` |
| API key | Any non-empty placeholder; the bridge replaces it |
| Model | `gpt-6.1-sol` or another model returned by `/v1/models` |
| Timeout | At least 60 seconds; 90 seconds is safer |

9Router sends `POST /messages`; the bridge converts it to AgentRouter's required `POST /v1/messages`.

A successful 9Router console entry looks like:

```text
POST .../gpt-6.1-sol · FMT: openai→claude · JSON · ACC:Bridge
DONE ... · IN ... · OUT ...
```

### 6. Check available models

```bash
curl -s http://127.0.0.1:8787/v1/models
```

The model list is dynamic. A model appearing in the list does not guarantee that AgentRouter currently has a healthy backend for it.

## Test and troubleshooting commands

Download any helper you need:

```bash
curl -fsSL https://raw.githubusercontent.com/SkyeSlav/agentrouter-bridge/main/probe.sh -o ~/probe.sh
curl -fsSL https://raw.githubusercontent.com/SkyeSlav/agentrouter-bridge/main/status.sh -o ~/status.sh
curl -fsSL https://raw.githubusercontent.com/SkyeSlav/agentrouter-bridge/main/whereami.sh -o ~/whereami.sh
```

### Test bridge versus direct access

```bash
bash ~/probe.sh
```

This sends three calls through the bridge and three directly to AgentRouter, with response bodies and timings. A transient direct `502` that becomes `200` through the bridge means the retry logic is working.

### Inspect local state

```bash
bash ~/status.sh
```

### Prove that 9Router reaches the bridge

```bash
bash ~/whereami.sh
```

While it waits, send one request from 9Router. A healthy result includes:

```text
[bridge] path /messages -> /v1/messages
[bridge] 127.0.0.1 "POST /messages HTTP/1.1" 200 -
```

### Read the bridge log

```bash
tail -50 ~/agentrouter-bridge/bridge.log
```

Useful lines include:

```text
[bridge] path /messages -> /v1/messages
[bridge] upstream 502 (backend hiccup), retry 1/3
```

### Restart after updating

Downloading a new `bridge.py` does not change an already running process. Restart it:

```bash
pkill -f bridge.py
bash ~/start-bridge.sh
```

## Common errors

### `Unexpected token '<', "<!doctype "... is not valid JSON`

The upstream returned an HTML error page, or the bridge is running old code. Update and restart:

```bash
curl -fsSL https://raw.githubusercontent.com/SkyeSlav/agentrouter-bridge/main/bridge.py -o ~/agentrouter-bridge/bridge.py
pkill -f bridge.py
bash ~/start-bridge.sh
```

Current releases retry non-JSON `5xx` responses and convert a final non-JSON error into a JSON envelope.

### `POST /messages` fails but `/v1/messages` works

Update and restart the bridge. Current releases normalise:

- `/messages` → `/v1/messages`
- `/chat/completions` → `/v1/chat/completions`
- `/models` → `/v1/models`
- `/responses` → `/v1/responses`
- `/v1/v1/*` → `/v1/*`

### `upstream error [trace_id=...]`

AgentRouter's backend failed after accepting the key and request. The bridge retries this response by default. If all attempts fail, try again later or select another currently available model.

### `Invalid 'max_output_tokens' ... expected >= 16`

Use at least 16 output tokens. The included tests use 64.

### `unauthorized_client_error`

The request did not arrive with a recognised client identity. Confirm that traffic goes through the bridge and that the selected profile is valid. The default `claude-cli` profile was verified against the live gate.

### `invalid token` / `无效的令牌`

The client-identity gate passed, but AgentRouter rejected the key. Replace the key in `~/.agentrouter-env` and restart the bridge.

### Termux says `/tmp/...: Permission denied`

Termux does not provide a normal writable `/tmp`. Current helper scripts store temporary output under `$HOME`; update old copies.

## Other operating modes

### Unsupported client → bridge → AgentRouter

Run the bridge without 9Router:

```bash
export BRIDGE_API_KEY='YOUR_AGENTROUTER_KEY'
python ~/agentrouter-bridge/bridge.py \
  --port 8787 \
  --profile claude-cli \
  --origin https://agentrouter.org \
  --auth-scheme both
```

Client configuration:

| Client type | Base URL |
|---|---|
| Anthropic-compatible | `http://127.0.0.1:8787` |
| OpenAI-compatible | `http://127.0.0.1:8787/v1` |

AgentRouter may restrict individual models to particular endpoint families. For example, during testing `gpt-6.1-sol` worked on `/v1/messages` but rejected `/v1/chat/completions` and requested `/v1/responses` instead.

### Client → bridge → local 9Router shim

This mode simply makes the bridge serve from your local 9Router:

```bash
python bridge.py \
  --port 8787 \
  --upstream http://127.0.0.1:20128 \
  --model-map '{"gpt-6-astra":"your-9router-model"}'
```

AgentRouter is not contacted in this mode. If a client can use 9Router directly, pointing it at `http://127.0.0.1:20128` is simpler.

## CLI options

```text
--bind ADDRESS             Listen address; default 127.0.0.1
--port PORT                Listen port; default 8787
--profile NAME             Allowlisted identity; default claude-cli
--ua STRING                Override User-Agent directly
--origin URL               Gateway target; default https://agentrouter.org
--upstream URL             Alternate target used by shim mode
--api-key KEY              Inject a key (visible in process arguments; avoid)
--api-key-file FILE        Read the key from the first line of a file
--auth-scheme MODE         bearer, x-api-key, or both
--model-map JSON           Rewrite request model names
--retries N                Transient retry attempts; default 3
--retry-delay SECONDS      Delay between retries; default 0.4
--stream                   Force response streaming
--verbose                  Log requests and retries
```

The launcher reads `BRIDGE_API_KEY` from the environment so the key does not appear in `ps`. Treat a key previously exposed in a command line, terminal transcript, screenshot, or chat as compromised and rotate it.

## Supported identity profiles

`claude-cli` (default), `codex`, `qwen`, `opencode`, `openclaw`, `hermes`, `pi`, `crush`, `cline`, `roo`, `kilo`, `claude-app`, `trae`, `zcode`, `workbuddy`, `craft`.

Any client-supplied `User-Agent` is discarded and replaced by the selected profile.

## Changes made during real 9Router testing

Every item below corresponds to an observed failure rather than a hypothetical feature:

1. **Client allowlist spoofing:** confirmed that a recognised `User-Agent` passes the client gate while an unrecognised one returns `401 unauthorized_client_error`.
2. **Fixed key injection:** added bridge-side credential replacement for routers that send a placeholder or their own key.
3. **Credential hygiene:** removed keys from launcher command lines; added environment/file loading and contaminated-env validation.
4. **Termux support:** removed unwritable `/tmp` assumptions from the installer and diagnostic scripts.
5. **Durable launcher:** added `tmux` startup and an immediate live health check.
6. **Model diagnostics:** added model listing and direct-versus-bridge probes with bodies and timings.
7. **Connection retries:** transient DNS, TLS, reset, and other connection-level failures are retried.
8. **AgentRouter backend retries:** JSON `5xx` bodies containing `upstream error` are retried.
9. **HTML error handling:** non-JSON `5xx` pages are retried and final errors are converted to JSON so 9Router does not crash on `<!doctype ...>`.
10. **API path normalisation:** 9Router's `/messages` is mapped to AgentRouter's `/v1/messages`; duplicate `/v1/v1/*` paths are collapsed.
11. **SSE relay:** event-stream responses are flushed progressively rather than buffered until completion.
12. **Model aliases:** optional model rewriting lets a public model name map to a different upstream name.
13. **Observability:** verbose logs show path rewrites, retries, request paths, and final HTTP statuses.
14. **Arrival detector:** `whereami.sh` proves whether a 9Router request actually reached the bridge.
15. **Verified integration:** a real 9Router request completed through the bridge using `FMT: openai→claude`, with token usage recorded by 9Router.

## Security and operational notes

- Keep the listener on `127.0.0.1` unless another device must connect. `--bind 0.0.0.0` exposes the bridge to your network.
- Use your own AgentRouter key. Do not share or resell credentials.
- AgentRouter models and backend capacity change dynamically.
- `tmux` keeps the process attached to a terminal session, but Android may still kill Termux under memory or battery pressure. Exempt Termux from battery optimisation if long-running availability matters.
- Any real signed client attestation or cryptographic verification will invalidate UA-based identity spoofing.

---

## Disclaimer

This project is provided for **educational and interoperability research purposes only**, and to illustrate how a naive client-identification filter can be defeated.

- **Not affiliated.** This project is not affiliated with, endorsed by, or supported by AgentRouter, Anthropic, 9Router, or any third-party client listed above. Product names and trademarks belong to their respective owners.
- **No authorisation is granted.** Impersonating a client you are not running is not a documented or permitted use of the upstream service. It may breach the service's terms and can result in throttling, suspension, or a permanent ban. Do not use the bridge against a service unless you are authorised to do so.
- **Use your own credentials.** Never route someone else's API key, OAuth token, or subscription through this bridge. Credential sharing and resale of upstream access are out of scope.
- **No warranty.** The software is supplied “as is,” without express or implied warranty. The author is not liable for claims, damages, account action, lost usage, or other consequences arising from its use.
- **It can break without notice.** A signature, nonce, endpoint attestation, or other real client-verification mechanism will invalidate this approach.
- **Compliance is your responsibility.** You are responsible for compliance with applicable terms and local law. If the upstream provider asks you to stop, stop.
