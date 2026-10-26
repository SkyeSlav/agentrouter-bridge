#!/usr/bin/env python3
"""
agentrouter-bridge — present as an allowlisted client while serving from a local upstream.

Flow:  client --> this proxy (spoofed UA) --> agentrouter.org --> ...
       ...or, with --upstream, everything is served by your own 9Router instead.

Two useful modes:

1. PASSTHROUGH (default)
   Forwards to https://agentrouter.org with an allowlisted User-Agent, so
   requests from clients that are NOT on the allowlist get through.

2. SHIM (--upstream http://127.0.0.1:20128)
   Does not contact agentrouter.org at all. The client believes it is talking
   to AgentRouter; responses come from your 9Router. Useful to keep a client's
   config unchanged while you migrate it onto local routing.

Run:
   python3 bridge.py --port 8787 --profile claude-cli
   python3 bridge.py --port 8787 --upstream http://127.0.0.1:20128
"""

import argparse
import json
import os
import sys
import urllib.request
import urllib.error
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VERSION = "1.0.0"

# Allowlisted identities, taken from the vendor's own supported-client list.
PROFILES = {
    # CLI / terminal
    "claude-cli": "claude-cli/2.1.0 (external, cli)",
    "codex": "codex-cli/0.52.0",
    "qwen": "QwenCode/0.8.4 (linux; x64)",
    "opencode": "opencode/0.15.2",
    "openclaw": "OpenClaw/1.2.0",
    "hermes": "hermes-agent/1.0.3",
    "pi": "pi/0.4.1",
    "crush": "crush/0.20.2",
    # VS Code extensions
    "cline": "Cline/3.36.0",
    "roo": "Roo-Code/3.28.0",
    "kilo": "Kilo-Code/4.98.0",
    # IDE / desktop
    "claude-app": "claude-app/1.0 (desktop)",
    "trae": "Trae/2.1.0",
    "zcode": "ZCode/1.0.0",
    "workbuddy": "WorkBuddy/1.0.0",
    "craft": "Craft-Agents/1.0.0",
}

DEFAULT_TARGET = "https://agentrouter.org"

# Never forward these to the upstream: they identify the real hop.
HOP_BY_HOP = {
    "host", "connection", "content-length", "transfer-encoding", "user-agent",
    "accept-encoding", "x-forwarded-for", "x-forwarded-host", "x-real-ip",
    "forwarded", "via", "keep-alive", "proxy-connection", "te", "trailer",
    "upgrade", "cookie",
}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "agentrouter-bridge/" + VERSION

    # --- helpers -----------------------------------------------------------
    def _drop_self_headers(self):
        for h in ("Server", "X-Powered-By"):
            if h in self.headers:
                del self.headers[h]

    def _upstream_url(self):
        target = self.server.upstream or self.server.origin
        path = self.path
        return target.rstrip("/") + path

    def _read_body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(n) if n else b""

    def _rewrite_body(self, body):
        """If a model alias map is configured, swap the model name."""
        if not self.server.model_map or not body:
            return body
        try:
            data = json.loads(body)
        except Exception:
            return body
        if isinstance(data, dict):
            changed = False
            if "model" in data and data["model"] in self.server.model_map:
                data["model"] = self.server.model_map[data["model"]]
                changed = True
            # the Messages API also carries model in some betas/streams
            if changed:
                return json.dumps(data).encode()
        return body

    def _proxy(self):
        body = self._rewrite_body(self._read_body())

        fwd = {}
        for k, v in self.headers.items():
            if k.lower() in HOP_BY_HOP:
                continue
            fwd[k] = v

        # The whole point: a convincing client identity.
        fwd["User-Agent"] = self.server.ua
        # Optionally supply the upstream credential ourselves, replacing whatever
        # the caller sent. Needed when the thing in front of us (e.g. 9Router)
        # forwards its own token or nothing at all.
        if self.server.api_key:
            fwd["Authorization"] = "Bearer " + self.server.api_key
            if self.server.auth_scheme == "both":
                fwd["x-api-key"] = self.server.api_key
            elif self.server.auth_scheme == "x-api-key":
                fwd.pop("Authorization", None)
                fwd["x-api-key"] = self.server.api_key
        # Belt and braces: some harnesses are also sniffed via this.
        fwd.setdefault("x-app", "cli")
        fwd.setdefault("accept-encoding", "identity")

        req = urllib.request.Request(
            self._upstream_url(),
            data=body if body else None,
            headers=fwd,
            method=self.command,
        )
        try:
            with urllib.request.urlopen(req, timeout=600) as resp:
                self._relay(resp.status, resp.headers, resp)
        except urllib.error.HTTPError as e:
            self._relay(e.code, e.headers, e)
        except Exception as e:  # network / TLS / timeout
            payload = json.dumps({
                "error": {
                    "message": f"bridge upstream failure: {e}",
                    "type": "bridge_error",
                }
            }).encode()
            self.send_response(502)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

    def _relay(self, status, headers, src):
        self.send_response(status)
        passthrough = (
            "content-type", "cache-control", "request-id", "x-request-id",
            "x-oneapi-request-id", "anthropic-ratelimit-requests-limit",
            "anthropic-ratelimit-requests-remaining",
            "anthropic-ratelimit-tokens-remaining",
            "x-ratelimit-limit-requests", "x-ratelimit-remaining-requests",
            "x-ratelimit-limit-tokens", "x-ratelimit-remaining-tokens",
            "retry-after", "x-should-retry",
        )
        for k, v in headers.items():
            if k.lower() in passthrough:
                self.send_header(k, v)

        ctype = headers.get("Content-Type", "")
        # Streamed responses (SSE) must be flushed as they arrive.
        if "text/event-stream" in ctype or getattr(self.server, "force_stream", False):
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "close")
            self.end_headers()
            try:
                while True:
                    chunk = src.read(1)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError):
                pass
            self.close_connection = True
            return

        data = src.read()
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    # --- verbs -------------------------------------------------------------
    def do_GET(self):
        self._proxy()

    def do_POST(self):
        self._proxy()

    def do_DELETE(self):
        self._proxy()

    def do_PUT(self):
        self._proxy()

    def log_message(self, fmt, *args):
        if self.server.verbose:
            sys.stderr.write("[bridge] %s %s\n" % (self.address_string(), fmt % args))


def main():
    ap = argparse.ArgumentParser(description="AgentRouter allowlist-spoofing bridge")
    ap.add_argument("--port", type=int, default=8787)
    ap.add_argument("--bind", default="127.0.0.1")
    ap.add_argument("--profile", default="claude-cli", help=", ".join(sorted(PROFILES)))
    ap.add_argument("--ua", help="override User-Agent verbatim")
    ap.add_argument("--origin", default=DEFAULT_TARGET, help="real gateway to forward to")
    ap.add_argument("--upstream", help="serve from this URL instead (e.g. your 9Router)")
    ap.add_argument("--model-map", default=os.environ.get("BRIDGE_MODEL_MAP", ""),
                    help='JSON map, e.g. {"gpt-6-astra":"deepseek-chat"}')
    ap.add_argument("--stream", action="store_true", help="always stream responses")
    ap.add_argument("--api-key", default=os.environ.get("BRIDGE_API_KEY", ""),
                    help="upstream credential to INJECT, replacing the caller's. "
                         "Prefer --api-key-file: a value on the command line is "
                         "visible to every process on the device.")
    ap.add_argument("--api-key-file", default="",
                    help="read the injected credential from this file (first line). "
                         "Keeps the key out of `ps` and shell history.")
    ap.add_argument("--auth-scheme", default="bearer",
                    choices=["bearer", "x-api-key", "both"],
                    help="how to send --api-key (default: bearer)")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    if args.ua:
        ua = args.ua
    elif args.profile in PROFILES:
        ua = PROFILES[args.profile]
    else:
        sys.exit(f"unknown profile '{args.profile}'; choose from: {', '.join(sorted(PROFILES))}")

    srv = ThreadingHTTPServer((args.bind, args.port), Handler)
    srv.daemon_threads = True
    srv.ua = ua
    srv.origin = args.origin
    srv.upstream = args.upstream
    srv.verbose = args.verbose
    srv.force_stream = args.stream
    srv.model_map = json.loads(args.model_map) if args.model_map.strip() else {}
    srv.api_key = args.api_key
    srv.auth_scheme = args.auth_scheme

    where = args.upstream or args.origin
    print(f"bridge   http://{args.bind}:{args.port}  ->  {where}")
    print(f"identity UA  {ua}")
    if srv.model_map:
        print(f"model map    {srv.model_map}")
    sys.stdout.flush()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped")


if __name__ == "__main__":
    main()
