# grok-build-exfil-repro

**Reproduce it yourself:** show that xAI's **Grok Build** CLI uploads your *entire repository* — every tracked file **plus full git history** — to xAI's cloud (`POST /v1/storage`, routed to the GCS bucket `grok-code-session-traces`), **independent of what the agent reads**, and that turning off *"Improve the model"* does **not** stop it.

This harness runs on **your own machine, your own throwaway account, with fake canary secrets** — no real credentials involved. It captures Grok's own traffic with `mitmproxy` and then reconstructs the uploaded repo from the wire.

> Full wire-level writeup + SHA-256 evidence appendix: https://gist.github.com/cereblab/dc9a40bc26120f4540e4e09b75ffb547

---

## The one-line claim you'll verify

With the prompt literally **"reply OK, do not open any files,"** Grok still uploads a **git bundle of the whole repo**. `git clone`-ing the captured bundle recovers a file the agent was **told not to open** — verbatim — along with your full commit history.

---

## Requirements

- macOS or Linux, `mitmproxy` (`brew install mitmproxy`), `git`, `python3`
- Grok Build CLI installed (`curl -fsSL https://x.ai/cli/install.sh | bash`) and logged in (throwaway account recommended)

## Steps

```bash
# 1. Trust mitmproxy's CA (one-time) and start the capture proxy
./scripts/setup-proxy.sh

# 2. Plant a canary repo (fake .env + a file marked "never read")
./scripts/make-canary-repo.sh   # creates ./canary/

# 3. Run Grok through the proxy, telling it NOT to open anything
./scripts/run-capture.sh ./canary

# 4. Reconstruct what left the machine
./scripts/verify.sh
```

`verify.sh` scans the captured request bodies for a **git bundle** (`# v2 git bundle`), `git clone`s it, and greps for the canary marker that was in the file you told Grok **not** to open. If it prints the marker, the whole repo — including that never-read file and full history — left your machine.

## What "success" looks like

```
[+] found git bundle in captured POST /v1/storage body
[+] git clone recovered: canary/src/_probe/never_read_canary.txt
[+] marker present: CANARY-XR47P2-NEVERREAD   <-- the file you told it NOT to open
[+] full history recovered: N commits
```

## Deny blocks reads, not the upload

A common pushback is *"you told it not to read the file — this is on you."* It
isn't. **A permission deny stops the agent READING a file into the chat; it does
NOT stop the whole-repo git-bundle upload.**

- CLI `--deny "Read(secret.txt)"` -> the agent refuses to read it (`blocked by a
  permission policy`). But the **same tracked file is still in the uploaded git
  bundle** (`POST /v1/storage`). `git clone` the captured body and it's there.
- A settings-file deny (`.claude/settings.json` or `.grok/settings.json`,
  `{"permissions":{"deny":["Read(secret.txt)"]}}`) also blocks the read — **but
  `--always-approve` bypasses it.** Pattern must be `Read(file)`/`Read(**/file)`,
  not `Read(./file)`.
- The **only** thing that keeps a file out of the bundle is **gitignoring** it
  (the bundle carries tracked files only).

Reproducible artifacts + transcripts + the two captured bundles are in
[`evidence/`](evidence/).

## Ethics / scope

- Everything runs locally against **your own** traffic. The "secrets" are fake canary strings.
- This proves **transmission + storage** to xAI, not that xAI trains on it (that's a separate policy question — see the writeup).
- Version-specific to `grok 0.2.93` (July 2026). Behavior may change.

## Files

| Path | Role |
|---|---|
| `scripts/setup-proxy.sh` | install/trust mitmproxy CA + start the logging proxy |
| `scripts/make-canary-repo.sh` | build a throwaway git repo with a fake `.env` + a never-read canary file |
| `scripts/run-capture.sh` | run Grok routed through the proxy with the "do not open" prompt |
| `addon/log_xai.py` | mitmdump addon: logs method/host/path/status/size + saves xAI request bodies |
| `scripts/verify.sh` | find the git bundle in the capture, clone it, recover the never-read canary |
