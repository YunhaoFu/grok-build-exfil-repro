# CLI codebase-upload comparison: Grok vs Claude Code vs Codex vs Gemini

**What this tests:** when you run each coding CLI inside a git repo, does it upload
your **whole repository** (every tracked file + git history) to its cloud, or only
the specific files it actually reads? Method: identical canary repo per tool, an
all-hosts `mitmproxy` capture (trusted CA), two prompts per tool —
(a) an idle control `"reply OK, do not read any files"` and
(b) a realistic task `"what does this project do?"` — run headless, in its own
capture dir. Each canary repo has a tracked file, a **planted never-read file**
with a unique marker, a **gitignored** `.env` (fake canary secret), and a secret
**committed then deleted** (to test the git-history angle).

Versions: `claude 2.1.204`, `codex-cli` (gpt-5.5), `gemini 0.38.2`, `grok 0.2.93`.
Captured 2026-07-13 on one macOS machine, author's own accounts, fake canary secrets.

## Result

| Tool | Whole-repo / git-bundle upload? | Never-read canary leaves? | `.env` / deleted-history secret? | What leaves the machine |
|---|---|---|---|---|
| **Claude Code** 2.1.204 | **No** | **No** — not even read on the real task | No | only `POST api.anthropic.com/v1/messages` (the model turn) |
| **Codex** (gpt-5.5, `codex exec`) | **No** | No | No | model turn over a WebSocket to `chatgpt.com` + telemetry |
| **Gemini** 0.38.2 (api-key) | **No** (idle capture) | No | No | model turn to `generativelanguage.googleapis.com` |
| **Grok** 0.2.93 | **Historically YES; server-disabled as of 2026-07-13** | Yes (via read on the real task) | historically carried in the bundle | reads whole repo into `/v1/responses` + telemetry |

### Verdicts

- **Claude Code — stays local.** Uploads only the model turn; reads files on demand
  as visible tool-calls. On the real task it summarized the project **without ever
  reading** the never-read canary — the marker never left the machine.
- **Codex — stays local.** Model turn over a WebSocket; read-on-demand; no repo
  bundle, no never-read canary, no `.env`, no deleted-history secret.
- **Gemini — stays local (as captured).** Standard `generateContent` API call; no
  repo bundle in the idle capture. (Real-task run was quota-blocked — see caveats.)
- **Grok — was the outlier.** It uploaded the **whole repo + full git history** as a
  git bundle to Google Cloud Storage (proven; see the `evidence/` bundles). As of
  **2026-07-13** that is turned **off by a server flag** and did not reproduce.

## Honest caveats (read these before quoting anything above)

1. **Grok's whole-repo upload is proven HISTORICALLY, not reproduced today.** The
   captured git bundles in `evidence/` still `git clone` to recover the never-read
   canary verbatim — that happened and is real. But in 6 capture runs on
   2026-07-13 (idle + real task, 4-file and 303-file repos) grok made **zero**
   `POST /v1/storage` uploads. The reason is visible on the wire: grok's
   `/v1/settings` **today** returns `trace_upload_enabled: false` **and a new flag
   `disable_codebase_upload: true`**, whereas the original capture had
   `trace_upload_enabled: true`. Same client version (`0.2.93`) — this is a
   **server-side** change. Evidence: `evidence/grok_settings_2026-07-13_raw.bin`
   (+ decoded `_flags.txt`, `_CHANGE_note.txt`).
2. **We cannot prove causation.** We are **not** claiming the exposé forced this
   change. The only defensible statement is the **timeline**: the whole-repo upload
   was captured when the article was written; after publication, `/v1/settings`
   returns the upload disabled. "The behavior changed after we published" —
   **not** "we made them change it."
3. **Single account.** All captures are from one machine and one account per tool.
   The grok flag flip **may be account-scoped or a gradual rollout**, not global.
   We have not verified it on a second account.
4. **Gemini ran in api-key mode, and its real-task run was rate-limited.** Gemini
   authenticated via `GEMINI_API_KEY` (the `generativelanguage.googleapis.com`
   path), **not** a Google Code-Assist OAuth path, which we could not exercise
   headless and which could behave differently. The idle capture cleanly shows a
   model-turn-only request (no repo upload); the real-task run returned HTTP 429
   (quota) before completing, so read-selectivity was not captured live for Gemini.
5. **"Whole repo uploaded" = a git bundle of tracked files + history.** A gitignored
   file that was **never committed** is not in the bundle; a file that was **ever
   committed** is (even if later deleted). This is git mechanics, tested separately
   (see the earlier permission-deny evidence).

## Reproduce it

Harness under `harness/` (`capture_all.py`, `make_canary.sh`, `run_one.sh`). Trust
the mitmproxy CA, then run each tool through the proxy on its canary repo and grep
the captured bodies for the unique marker. See the top-level README for the grok
bundle reproduction.
