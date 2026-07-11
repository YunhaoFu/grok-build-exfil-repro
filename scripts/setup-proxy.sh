#!/usr/bin/env bash
# One-time: generate + trust mitmproxy's CA, then start the logging proxy.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
export XAI_CAPTURE_DIR="${XAI_CAPTURE_DIR:-$HOME/grok-exfil-capture}"
mkdir -p "$XAI_CAPTURE_DIR"

command -v mitmdump >/dev/null || { echo "install mitmproxy first: brew install mitmproxy"; exit 1; }

# Generate the CA on first run.
[ -f "$HOME/.mitmproxy/mitmproxy-ca-cert.pem" ] || (mitmdump -q & sleep 3; kill %1 2>/dev/null || true)

echo ">>> Trust the mitmproxy CA so Grok's TLS routes through the proxy:"
case "$(uname)" in
  Darwin) security add-trusted-cert -r trustRoot -k "$HOME/Library/Keychains/login.keychain-db" \
            "$HOME/.mitmproxy/mitmproxy-ca-cert.pem" || true ;;
  Linux)  echo "  sudo cp ~/.mitmproxy/mitmproxy-ca-cert.pem /usr/local/share/ca-certificates/mitmproxy.crt && sudo update-ca-certificates" ;;
esac

echo ">>> Starting capture proxy on 127.0.0.1:8080 (Ctrl-C to stop). Capture dir: $XAI_CAPTURE_DIR"
exec mitmdump -q -p 8080 -s "$HERE/addon/log_xai.py"
