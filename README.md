# agentrouter-bridge

Presents your traffic as an allowlisted AgentRouter client so the `unauthorized_client_error` gate stops firing — while the actual requests are served by your own 9Router.

## Why it works

The gate is a **User-Agent allowlist**, verified by probe:

| Request | Result |
|---|---|
| no `User-Agent` | `401 unauthorized_client_error` |
| `User-Agent: claude-cli/2.1.0` + fake key | `401 无效的令牌` (invalid token) |
| `User-Agent: Cline/3.36.0`, `Kilo-Code/…` | same — gate passed |

There is no signature, nonce, or per-client handshake. The vendor reads the envelope, not the letter.

## Mode 1 — passthrough (get a non-listed client through the gate)

```bash
python3 bridge.py --port 8787 --profile claude-cli
```

Then point the client's base URL at `http://127.0.0.1:8787` (Anthropic → no `/v1`;
[OI]-compatible → `/v1`). Your real AgentRouter key travels through untouched.

## Mode 2 — shim (keep a client pointed at "AgentRouter", serve from 9Router)

```bash
python3 bridge.py --port 8787 --upstream http://127.0.0.1:20128 \
                  --model-map '{"gpt-6-astra":"your-9router-model"}'
```

Nothing reaches agentrouter.org. `/v1/models`, `/v1/chat/completions`, `/v1/messages`
and SSE streaming are all relayed to 9Router. Model names in the request body are
rewritten through `--model-map` so clients still speaking "AgentRouter model names"
land on the right route.

## Profiles

`claude-cli` (default), `codex`, `qwen`, `opencode`, `openclaw`, `hermes`, `pi`, `crush`,
`cline`, `roo`, `kilo`, `claude-app`, `trae`, `zcode`, `workbuddy`, `craft`

Any client-supplied `User-Agent` is discarded and replaced (verified: a
`python-requests` UA arrives upstream as `Cline/3.36.0`).

## Flags

`--ua "…"` verbatim override · `--origin URL` change forwarding target · `--stream`
force streaming · `--bind 0.0.0.0` expose on LAN · `--verbose` log requests

## Honest caveats

- UA spoofing is not documented permission. If they add a per-client cryptographic
  check, this stops working — the fix would be a real allowlisted client.
- The shim only makes sense if your 9Router is the thing you actually want to use;
  it exists to avoid reconfiguring clients, not to give you AgentRouter's capacity.

---

## Disclaimer

This project is provided for **educational and interoperability research purposes only**, and to illustrate how a naive client-identification filter can be trivially defeated.

- **Not affiliated.** This project is not affiliated with, endorsed by, or supported by AgentRouter, Anthropic, 9Router, or any of the third-party clients listed in `PROFILES`. All product names and trade marks belong to their respective owners.
- **No authorisation is granted.** Presenting a `User-Agent` that impersonates a client you are not actually running is not a documented or permitted use of the upstream service. Doing so may breach that service's Terms of Use and can result in rate limiting, account suspension, or a permanent ban. Do not point this at a service you do not have permission to use this way.
- **Use your own credentials.** Never route someone else's API key, OAuth token, or subscription through this bridge. Credential sharing and the resale of upstream access are explicitly out of scope.
- **No warranty.** The software is provided "as is", without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, and non-infringement. The author is not liable for any claim, damages, or other liability arising from its use.
- **It will break.** Any real per-client verification, signature check, or endpoint-level attestation will invalidate this approach. Treat the bridge as disposable rather than as infrastructure.
- **Compliance is your responsibility.** You are responsible for ensuring your use complies with the applicable terms of service and with local law. If the upstream provider asks you to stop, stop.
