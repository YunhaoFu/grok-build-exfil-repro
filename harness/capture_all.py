import os, time
# All-hosts capture addon. BASE set via env CAP_BASE (per-tool capture dir).
BASE = os.environ.get("CAP_BASE", os.path.expanduser("~/cli-privacy-test/_scratch"))
os.makedirs(os.path.join(BASE, "bodies"), exist_ok=True)

# Never save bodies for local/proxy noise; everything else (all cloud hosts) is captured.
SKIP_HOST = ("127.0.0.1", "localhost", "::1")

VENDOR = {
    "anthropic": "anthropic", "claude.ai": "anthropic", "statsig": "anthropic-telem",
    "openai": "openai", "chatgpt": "openai", "oaistatic": "openai", "oaiusercontent": "openai",
    "googleapis": "google", "google.com": "google", "gstatic": "google",
    "generativelanguage": "google", "cloudcode-pa": "google", "gemini": "google",
    "grok.com": "xai", "x.ai": "xai", "xai": "xai",
    "amazonaws": "aws-s3", "googleusercontent": "gcs", "storage.googleapis": "gcs",
    "mixpanel": "telem", "sentry": "telem", "segment": "telem", "datadog": "telem",
}

def _vendor(h):
    for k, v in VENDOR.items():
        if k in h:
            return v
    return "other"

def response(flow):
    h = flow.request.pretty_host
    if any(s == h for s in SKIP_HOST):
        return
    st = flow.response.status_code if flow.response else "NORESP"
    body = flow.request.raw_content or b""
    path = flow.request.path.split("?")[0]
    ven = _vendor(h)
    with open(os.path.join(BASE, "wire.log"), "a") as L:
        L.write(f"{int(time.time())} [{ven}] {flow.request.method} {h}{path[:80]} -> {st} req={len(body)}b\n")
    # also save RESPONSE bodies for grok config/storage endpoints (to inspect upload flags)
    if "grok" in h and any(k in path for k in ("settings", "storage", "bundle", "models", "session")):
        rb = flow.response.raw_content if flow.response else b""
        if rb:
            ts = int(time.time() * 1000)
            rn = os.path.join(BASE, "bodies", f"{ts}_RESP_{path.strip('/').replace('/','_')[:50]}_{st}_{len(rb)}.bin")
            with open(rn, "wb") as f:
                f.write(rb)
    # save body for every non-local host so nothing is missed
    if body:
        safe = (ven + "_" + path.strip("/").replace("/", "_"))[:60]
        ts = int(time.time() * 1000)
        fn = os.path.join(BASE, "bodies", f"{ts}_{safe}_{st}_{len(body)}.bin")
        with open(fn, "wb") as f:
            f.write(body)


def websocket_message(flow):
    # capture client->server websocket frames (the model turn for ws-based CLIs like codex)
    h = flow.request.pretty_host
    if any(s == h for s in SKIP_HOST):
        return
    ven = _vendor(h)
    m = flow.websocket.messages[-1]
    if not m.from_client:
        return
    data = m.content or b""
    path = flow.request.path.split("?")[0]
    with open(os.path.join(BASE, "wire.log"), "a") as L:
        L.write(f"{int(time.time())} [{ven}] WS-> {h}{path[:80]} frame={len(data)}b\n")
    if data:
        ts = int(time.time() * 1000)
        fn = os.path.join(BASE, "bodies", f"{ts}_{ven}_WS_{len(data)}.bin")
        with open(fn, "wb") as f:
            f.write(data)
