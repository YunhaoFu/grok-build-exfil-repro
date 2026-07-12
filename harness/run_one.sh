#!/bin/bash
# Capture one CLI's traffic on the canary repo, then analyze.
# Usage: run_one.sh <label> <MARKER> <port> -- <tool invocation...>
set -u
LABEL="$1"; MARKER="$2"; PORT="$3"; shift 3
[ "$1" = "--" ] && shift
ROOT=~/cli-privacy-test
BASE="$ROOT/$LABEL"; REPO="$BASE/repo"; CA=~/.mitmproxy/mitmproxy-ca-cert.pem
if [ "${SKIP_CANARY:-0}" = "1" ]; then
  # reuse an already-built repo at $REPO; just clear prior capture artifacts
  rm -rf "$BASE/bodies" "$BASE/wire.log" "$BASE/mitm.log" "$BASE/tool_stdout.txt"; mkdir -p "$BASE/bodies"
  echo "[canary] reusing existing repo at $REPO ($(cd "$REPO" && git ls-files | wc -l | tr -d ' ') tracked files)"
else
  rm -rf "$BASE"; mkdir -p "$BASE/bodies"
  bash "$ROOT/make_canary.sh" "$REPO" "$MARKER" | sed 's/^/[canary] /'
fi

# start proxy
pkill -x mitmdump 2>/dev/null; sleep 1
CAP_BASE="$BASE" mitmdump -q --listen-host 127.0.0.1 -p "$PORT" -s "$ROOT/capture_all.py" >"$BASE/mitm.log" 2>&1 &
MP=$!; sleep 4
echo "[proxy] mitmdump pid=$MP on :$PORT  base=$BASE"

# run the tool through the proxy, in the repo, headless
echo "[run] $* (cwd=$REPO)"
( cd "$REPO" && \
  HTTPS_PROXY=http://127.0.0.1:$PORT HTTP_PROXY=http://127.0.0.1:$PORT \
  NODE_EXTRA_CA_CERTS=$CA SSL_CERT_FILE=$CA REQUESTS_CA_BUNDLE=$CA \
  "$@" >"$BASE/tool_stdout.txt" 2>&1 ) &
GP=$!
for i in $(seq 1 60); do kill -0 $GP 2>/dev/null || break; sleep 2; done
# drain: give async upload queues (e.g. grok's /v1/storage) time to flush before stopping the proxy
kill $GP 2>/dev/null; sleep 14; kill $MP 2>/dev/null; sleep 1

echo "=====ANALYSIS ($LABEL, marker $MARKER)====="
echo "-- tool said (first/last line) --"; head -1 "$BASE/tool_stdout.txt"; tail -1 "$BASE/tool_stdout.txt"
echo "-- vendor hosts contacted (from wire.log) --"
grep -oE "\[[a-z0-9-]+\] [A-Z]+ [^ ]+" "$BASE/wire.log" 2>/dev/null | sort | uniq -c | sort -rn | head -20
echo "-- total captured request bytes by vendor --"
awk '{for(i=1;i<=NF;i++) if($i ~ /^req=/){gsub(/req=|b/,"",$i); v=$2; s[v]+=$i}} END{for(k in s) printf "  %-14s %d bytes\n", k, s[k]}' "$BASE/wire.log" 2>/dev/null
echo "-- Q2: did the NEVER-READ canary marker leave? --"
if grep -rqa "$MARKER-NEVERREAD" "$BASE/bodies" 2>/dev/null; then echo "  *** YES — never-read marker found in an uploaded body"; grep -rla "$MARKER-NEVERREAD" "$BASE/bodies" | head; else echo "  no — never-read marker NOT in any captured body"; fi
echo "-- .env secret leave? --"
grep -rqa "$MARKER-ENV-APIKEY" "$BASE/bodies" 2>/dev/null && echo "  *** YES — .env secret in an uploaded body" || echo "  no — .env secret not in any body"
echo "-- committed-then-deleted history secret leave? --"
grep -rqa "$MARKER-HISTORY-DELETED" "$BASE/bodies" 2>/dev/null && echo "  *** YES — deleted-from-history secret in an uploaded body" || echo "  no — history secret not in any body"
echo "-- Q1: any git bundle / whole-repo pack uploaded? --"
if grep -rlqa "git bundle" "$BASE/bodies" 2>/dev/null; then echo "  *** YES — a git bundle body was uploaded:"; grep -rla "git bundle" "$BASE/bodies"; else echo "  no '# v2 git bundle' magic in any body"; fi
echo "-- largest captured bodies (bytes) --"
ls -S "$BASE/bodies" 2>/dev/null | head -5 | while read f; do echo "  $(wc -c <"$BASE/bodies/$f") $f"; done
echo "=====END ($LABEL)====="
