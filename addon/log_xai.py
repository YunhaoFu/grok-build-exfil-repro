# mitmdump addon: log every request to xAI/Google hosts (method, host, path,
# response status, request byte size) and SAVE the raw request bodies so we can
# later reconstruct what left the machine. Run via: mitmdump -s addon/log_xai.py
import os, time

OUT = os.environ.get("XAI_CAPTURE_DIR", os.path.expanduser("~/grok-exfil-capture"))
BODIES = os.path.join(OUT, "bodies")
HOSTS = ("grok.com", "xai", "googleapis", "amazonaws", "mixpanel")
os.makedirs(BODIES, exist_ok=True)


def response(flow):
    host = flow.request.pretty_host
    if not any(k in host for k in HOSTS):
        return
    status = flow.response.status_code if flow.response else "NORESP"
    body = flow.request.raw_content or b""
    path = flow.request.path.split("?")[0]
    with open(os.path.join(OUT, "wire.log"), "a") as log:
        log.write(f"{int(time.time())} {flow.request.method} {host}{path[:70]} -> {status} req={len(body)}b\n")
    # Save bodies of storage/upload calls so verify.sh can find the git bundle.
    if body and ("/v1/storage" in path or "storage" in host):
        fn = f"{int(time.time()*1000)}_{flow.request.method}_{len(body)}.bin"
        with open(os.path.join(BODIES, fn), "wb") as f:
            f.write(body)
