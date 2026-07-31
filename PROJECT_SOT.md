# Project SOT (Source of Truth)

Authoritative state of the EOXS AI project. Governed by `BUILDING_GUIDELINES.md`.
Every code change, config change, decision, and checkpoint is recorded here in
the session it happens. If this file disagrees with reality, this file is wrong.

**Last updated:** 2026-07-31

---

## 1. What we are building

An internal AI assistant for EOXS leadership that answers questions across the
company's scattered records — email, call transcripts, clients, invoices,
tickets, prospects, and an internal wiki — through one chat interface.

- **Phase now:** internal use at EOXS.
- **Phase later:** sold to other companies (multi-tenant).
- **A second departmental AI project is being scoped** — details pending;
  requirements not yet gathered.

---

## 2. Architecture

```
Browser ──► Open WebUI frontend (SvelteKit, :5173 dev)
                 │
                 ▼
         Open WebUI backend (FastAPI, :8080)
            │                    │
            │                    └──► Anthropic API (claude-sonnet-5 / claude-opus-5)
            ▼
       MCP tool server
            │
     [TEMPORARY local bridge :9090, streamable HTTP]
            │
            ▼
   raj-vault-mcp-server (Render, SSE transport, FastMCP/uvicorn)
            → 21 vault tools over email / calls / clients / invoices /
              tickets / prospects / wiki
```

### Components

| Component | Location | State |
|---|---|---|
| Open WebUI | `c:\Users\91623\Desktop\EOXS\open-webui` (v0.11.0) | Dev only, SQLite |
| Frontend | `npm run dev` → :5173 | Running |
| Backend | uvicorn → 127.0.0.1:8080 | Running |
| Python env | `.venv` (Python 3.12) | Backend requires >=3.11,<3.13 |
| MCP bridge | `<scratchpad>/vault_bridge.py` → :9090 | **Temporary**, session-scoped |
| Vault MCP server | `raj-vault-mcp-server.onrender.com` | Render free tier, SSE only |

---

## 3. Configuration in place

- **Anthropic connection:** `https://api.anthropic.com/v1`, added under the
  OpenAI-compatible connections. Backend auto-detects `api.anthropic.com` and
  uses Anthropic's native protocol. 11 Claude models load.
- **MCP tool server:** registered as `server:mcp:eoxs-vault`, type `mcp`,
  auth `none`, pointing at the local bridge. Verifies with 21 tools.
- **Workspace models (both with vault tools attached, native function calling,
  `reasoning_effort: high`, executive system prompt):**
  - `eoxs-vault-assistant` → `claude-sonnet-5` (default)
  - `eoxs-vault-assistant-opus` → `claude-opus-5` (quality comparison)
- **Admin user:** `ijassandhu.dev@gmail.com`
- **`WEBUI_SECRET_KEY`:** dev placeholder — **must be replaced before any
  deployment.**

---

## 4. Decisions taken

| Date | Decision | Reasoning |
|---|---|---|
| 2026-07-29 | Open WebUI as the product shell | Native MCP + native Anthropic support; avoids building a chat UI |
| 2026-07-29 | Internal-first, sell later | Real usage before productisation |
| 2026-07-29 | Sonnet 5 default, Opus 5 available | Cost/quality comparison on real queries |
| 2026-07-29 | Skip Docker for local dev | Rebuild per change slows iteration; Docker for deployment |
| 2026-07-29 | Rebrand allowed under ≤50 users | Open WebUI licence clause 4(i) |

---

## 5. Open issues

| # | Issue | Impact | Fix |
|---|---|---|---|
| 1 | Vault server speaks **SSE**, Open WebUI requires **streamable HTTP** | Requires a bridge; fragile | Serve streamable HTTP from FastMCP (`transport="http"`); delete bridge |
| 2 | Bridge is session-scoped and local | Dies with the session; not deployable | Resolved by #1 |
| 3 | Render **free tier** sleeps | 30–60s cold start reads as broken | Move to paid instance |
| 4 | Auth token embedded in the MCP **URL path** | Cannot rotate per user; leaks to logs/proxies | Bearer header or OAuth 2.1, one token per customer |
| 5 | `search_wiki` returns "No results" for queries whose data exists | Assistant answers thin | Improve server-side search, or prompt the model to `get_index` then fetch by name |
| 6 | SQLite backend | Single-writer; dev only | PostgreSQL + Redis for deployment |
| 7 | No per-user data scoping in the vault | Anyone who can chat can read CEO email | Enforce scoping in the MCP server, not the UI |
| 8 | Licence cap ambiguity for multi-customer deployments | Legal exposure when selling | Get written confirmation from Open WebUI (clause 4(ii)) |

---

## 6. Resolved issues

| Date | Issue | Resolution |
|---|---|---|
| 2026-07-29 | All outbound HTTPS failed: `Could not contact DNS servers` | `aiodns` (c-ares) cannot read DNS config on Windows. Uninstalled; aiohttp falls back to the threaded resolver. Linux/Docker unaffected. |
| 2026-07-29 | Every chat with tools returned HTTP 500, `RuntimeError: Attempted to exit cancel scope in a different task` | `mcp-proxy --stateless` triggered the MCP/anyio teardown bug. Ran stateful. |
| 2026-07-29 | `tools/list` worked but **every** `tools/call` returned `isError` with an empty body | `mcp-proxy` chained mode does not forward tool calls. Replaced with a purpose-built bridge (fresh upstream session per request). |
| 2026-07-29 | Tool calls rejected: "outputSchema defined but no structured output returned" | Vault tools declare `outputSchema`; proxied payloads carry no structured content. Bridge strips `outputSchema` and passes structured content through when present. |

---

## 7. Checkpoints

### 2026-07-29 — Environment stood up, vault connected end to end

- Installed frontend deps (1121 packages) and a Python 3.12 venv; ran backend
  from `backend/requirements-min.txt` plus the modules the app imports at
  startup. `sentence-transformers`/`torch` deliberately skipped (multi-GB; only
  needed for local embeddings/RAG).
- Frontend on :5173, backend on :8080, admin account created.
- Anthropic connection added; 11 models load.
- Vault MCP server connected via bridge; 21 tools verified.
- Two workspace models created with tools, prompt, and inference params.
- Verified Claude emits correct tool calls (`eoxs-vault_list_clients`,
  `finish_reason: tool_calls`).
- Verified `get_index` returns 114 KB, including 40 per-employee HR pages —
  employee data exists in the vault.
- **Not yet verified:** a full answer rendered in the UI. Open WebUI delivers
  chat responses over socket.io to the browser, so it cannot be observed from
  the HTTP API. Requires a manual check in the UI.

---

## 7b. White-label front-end requirements (captured 2026-07-29, brainstorming — nothing built)

Goal: replace the Claude front end with a shippable white-label front end that
serves the same functionality against an API key.

| # | Requirement | Native support | Notes |
|---|---|---|---|
| R1 | Skills, Claude-style (may be backend-configurable, no UI needed) | **Yes** | `routers/skills.py`, full CRUD; `{name, description, content, tags}`. Attach per model (`meta.skillIds`), per request (`skill_ids`), or by `<$skillId\|label>` mention. `view_skill` builtin gives progressive disclosure. **Gap:** skill body is a single text field — no bundled files or executable scripts. |
| R2 | Configurable MCP connection, parity with the Claude front end | **Yes, with gaps** | Per-server URL/auth (`none`/`bearer`/`session`/`oauth_2.1`/`oauth_2.1_static`), enable toggle, group access grants. **Gaps:** streamable HTTP only; no large-tool-output offloading (see below); session opened per request. |
| R3 | Auto-save every thread to a second Obsidian vault ("thread vault") — new thread creates an MD file, follow-ups update it | **No — must be built** | Hook exists: `outlet_filter_handler` (`utils/middleware.py:3412`) runs after each completion with `chat_id`, `message_id`, and the full message list. Implemented as a filter Function (Python plugin). **Open design question: the write path into the vault.** |

### Finding: no large-tool-output handling

Open WebUI passes tool results into the model context **in full** — no
truncation, no offload to file. `get_index` returns 114 KB (~28k tokens), so
every call to it consumes a large share of the context window and is billed as
input tokens on every subsequent turn of that conversation. The Claude front end
offloads oversized tool results to a file and hands the model a preview plus a
path. **This is the single biggest functional gap for parity** and is fixable on
the MCP server side (paginate/summarise `get_index`, return IDs rather than
whole documents).

### R3 revised after reading the vault schemas (2026-07-29)

The thread vault **already exists** — `claude-notes-vault` ("Claude OV"), a
separate Render service and GitHub repo, with `save_chat_transcript` writing
`raw/claude-chat-queries/<user>_<created-date>_<thread_name>.md` and pushing to
its own repo. Nothing needs to be built to store threads. Two things change when
the front end moves off claude.ai:

**1. Identity must be re-sourced.** Today identity comes from *which secret URL*
the user connects with (`CLAUDE_OV_USERS` map → `_IdentityMiddleware`). Open WebUI
holds **one** server-wide MCP connection, so every user would share one URL and
all threads would collapse into a single identity.

Open WebUI already forwards per-request identity to MCP servers — verified at
`utils/middleware.py:2222` → `build_tool_server_headers` → `utils/headers.py:37`.
With `ENABLE_FORWARD_USER_INFO_HEADERS` on, every MCP call carries either a
**signed JWT** (when `FORWARD_USER_INFO_HEADER_JWT_SECRET` is set) or
`X-OpenWebUI-User-{Id,Email,Name,Role}`, **plus `chat_id` and `message_id`**.
`_IdentityMiddleware` gains a second resolution path: verify the JWT → username.
Server-resolved, never model-supplied — consistent with the vault's existing rule.
One URL for all users; adding a user becomes an Open WebUI account, not an env-var edit.

**2. Auto-save becomes deterministic.** Claude OV's own docs call the current
auto-save "a best-effort instruction to the model, not a system-enforced
guarantee." Open WebUI's `outlet` filter fires server-side after every completion,
so capture no longer depends on the model choosing to call the tool.

### Known gap: SYNTHESIZE has no execution path in the new front end

Claude OV's chat-summary pages are "written by the SYNTHESIZE workflow (agent
file-write tools), not a dedicated save tool." Open WebUI has no filesystem
access to that repo. SYNTHESIZE and parts of CROSS-LINK therefore cannot run from
the white-label front end as currently designed. Options: add MCP write tools to
`claude-notes-vault`, keep SYNTHESIZE as an operator task in Claude Code, or run
it as a scheduled job.

### Answers received 2026-07-29 (numbering spanned two question sets — items 4, 5, 9 unconfirmed)

**Confirmed:**
- Thread vault lives in the **same GitHub account and on Render**.
- Transcript writes go through a **separate MCP server** (Claude OV), not OV2.
  Treating OV2's `raw/claude-chat-queries/` as legacy pending confirmation.
- **5-minute batched writes** — not per-message. The outlet filter queues; a
  worker flushes every 5 min. Chat latency is never coupled to a git push.
- **Past threads must be searchable** from the chat.
- **Per-user thread isolation is required.**

**Resolved 2026-07-29 (second pass):**
- **No write path from the front end into OV2.** Chat is read-only against OV2.
  Thread summaries reach OV2 through the backend ingest job (SYNTHESIZE +
  CROSS-LINK), never from a chat session. Enforced per connection with
  `function_name_filter_list` (allow/block, `!` prefix blocks) **and** a
  write-scopeless credential — note the matcher is suffix-based, so blocklist the
  dangerous names explicitly rather than relying on the allow-list.
- **SYNTHESIZE is retained** — it is the mechanism that feeds OV2.
- **Thread filenames use the Open WebUI chat ID** (deterministic; one
  conversation always maps to exactly one file):
  `raw/claude-chat-queries/<user>_<YYYY-MM-DD>_<chat_id>.md`
- **Frontmatter schema — delegated to Claude, decided as:**
  ```yaml
  ---
  title: "<conversation title>"
  type: chat-transcript
  user: <server-resolved username>
  chat_id: <Open WebUI chat id>      # stable key for updates
  model: <model id>                  # which model answered
  turns: <n>                         # integrity check for the batch writer
  tools_used: [tool names]           # lets SYNTHESIZE cluster by vault area
  source: open-webui                 # distinguishes from legacy claude.ai files
  created: YYYY-MM-DD
  updated: YYYY-MM-DDTHH:MM:SSZ
  ---
  ```
- **Parked until deployment:** user authentication method, and naming the
  department this serves.

**Governance decision (2026-07-29):** CROSS-LINK moves to the backend ingest job,
staged as a **pull request** against OV2's `data` branch. A **scored verification
gate** decides whether the PR auto-merges or waits for a human.

### Gate design

Two stages — cheap deterministic validators first, LLM judge only for what
genuinely needs judgement.

| Stage | Check | Method |
|---|---|---|
| 1 | Target OV2 page exists | Deterministic — hard fail |
| 1 | Source chat-summary page exists and is cited | Deterministic — hard fail |
| 1 | Pointer line ≤ 2 sentences | Deterministic — hard fail |
| 1 | Diff touches only the intended page/section | Deterministic — hard fail |
| 1 | No secrets/credentials in the added text | Regex + entropy — hard fail |
| 2 | Claim is supported by the cited transcript | LLM judge |
| 2 | Information is genuinely new to the target page | LLM judge (needs page content) |
| 2 | No sensitive content that shouldn't propagate | LLM judge against policy |

Anything failing stage 1 never reaches the judge. Stage 2 returns a structured
verdict — per-criterion pass/fail plus evidence — not a bare number.

### Rules

- **The judge must not be the writer.** Separate call, fresh context, no
  knowledge of having authored the line. Self-review inflates scores.
- **Bias toward human review.** A false approve pollutes the vault every future
  answer reads and compounds through later synthesis; a false reject costs one
  review. Set the threshold accordingly.
- **Tag provenance.** Auto-merged lines carry a marker so they are findable,
  auditable, and revertable in bulk.
- **Always escalate** changes touching client, financial, or personnel pages,
  regardless of score.
- **Cap auto-merges per run** so a prompt regression cannot land 200 bad lines.
- **Log every decision** — inputs, per-criterion verdict, score, outcome — so the
  threshold is tuned from real data.

### Rollout

1. **Shadow mode:** gate scores every candidate, but 100% still go to human
   review. No auto-merge.
2. **Calibrate:** after ~50–100 reviewed candidates, compare human decisions to
   scores and set the threshold where false-approve is acceptably rare.
3. **Enable** auto-merge above the threshold; keep sampling ~10% of auto-merges
   for audit.

Amend Claude OV's `CLAUDE.md` once enabled so the documented rule and the system
agree.

### Consequence: thread read tools need enforcement, not filtering

Claude OV currently treats the `user` argument on `search_claude_chat_queries` /
`list_claude_chat_queries` as "a convenience filter only, not an identity claim."
With searchable threads **and** required isolation, that argument must become
server-enforced: scope every read to the identity resolved from the forwarded
JWT, and ignore any model-supplied `user`. Otherwise one user can read another's
threads by passing a different value.

### Finding: Open WebUI has no per-tool approval gate

Verified — tools carry access grants (who may use them) but there is **no
runtime "ask before executing"** mechanism. CROSS-LINK's "explicit itemized
approval before `apply_ov2_xref`" therefore cannot be enforced by the platform;
in chat it degrades to the model interpreting a text reply. Write tools should be
separated from client-facing read tools by access grants, with approval handled
outside the chat surface.

### Contradiction to resolve

OV2's `CLAUDE.md` documents `raw/claude-chat-queries/` as written by *OV2's* MCP
`save_chat_transcript` ("the one sanctioned write path into `raw/`"), while
Claude OV's `CLAUDE.md` states transcripts must never bloat OV2 and live in
`claude-notes-vault`. Both servers appear to expose `save_chat_transcript`.
Unresolved: which is current, and which the front end should call.

---

## 7c. OV2 MCP server code review (2026-07-29)

Source: local reference copy of `raj-wiki-vault` (context only — production is the
Render MCP service; the folder is gitignored and never linked locally).

| # | Finding | Severity | Location |
|---|---|---|---|
| S1 | **Path traversal in 4 tools.** `get_email`/`get_call`/`get_fathom`/`get_client_file` do `VAULT_ROOT / file_path` with no containment check. Any relative path — including `../` — is read and returned. Reaches `/proc/self/environ` (all env vars: `MCP_URL_SECRET`, API keys, tokens) and any file on the container. | **High** | `mcp_server.py:159, 211, 239, 280` |
| S2 | **Search matches the whole query as one substring, per line** (`if q in line.lower()`). A multi-word query only hits when that exact phrase appears verbatim on a single line. This is the root cause of "No results" for content that demonstrably exists. | **High** (quality) | `mcp_server.py:64` |
| S3 | **`get_index()` returns `index.md` verbatim** — ~114 KB / ~30k tokens, mostly changelog prose. | High (cost) | `mcp_server.py:93-96` |
| S4 | **Every search reads every file.** `_search` → `_all_md()` → `rglob` + full read of all matching `.md`. `search_emails(account="all")` scans ~26k files per call. No index, no cache. | Medium (latency/cost) | `mcp_server.py:53-74` |
| S5 | **Silent truncation.** `max_results=12`, 3 matches per file, list caps of 100–150, with no total count or cursor. The model cannot tell it is seeing 12 of 500. | Medium (quality) | `mcp_server.py:57, 71, 149` |
| S6 | **`save_chat_transcript` does not exist in this server.** OV2's `CLAUDE.md` documents it as "the one sanctioned write path into `raw/`" — the code has no such tool. Documentation is stale. | Doc bug | — |

Also: `requirements.txt` pins nothing (`mcp` unversioned) — the deployed protocol
behaviour can change on any rebuild. Pin it.

### Transport fix is trivial

Verified against the installed SDK: `FastMCP.__init__` accepts
`streamable_http_path`, and `run()` accepts `transport="streamable-http"`.
Work item #1 is a three-line change, not a rewrite.

## 7d. Cost findings and usage tracking (2026-07-30)

**Claude Max/Pro cannot be used.** Subscriptions authorise Anthropic's own
surfaces (claude.ai, Claude Code) only; they are not credentials for third-party
apps and cannot be pointed at the API. Spend is per-token, so the lever is token
volume, not billing source.

**No prompt caching on the outbound path.** `utils/anthropic.py` only *preserves*
`cache_control` on the inbound compat endpoint; nothing sets it on requests going
out to Anthropic, and there is no config for it. **Every turn re-sends the whole
conversation at full price**, which compounds the `get_index` problem — a 30k-token
tool result is re-billed on every subsequent turn of that conversation.

Illustrative 5-turn conversation, Sonnet 5: ≈ $0.46 with a 30k-token index;
≈ $0.12 if the index returned ~4k. Roughly 4× for no quality loss.

**Usage tracking enabled (2026-07-30).** Open WebUI never adds
`stream_options.include_usage`, so streaming responses returned no token counts and
nothing was persisted to chat records. Verified that setting it as a **model
param** works end to end — usage is now returned and recorded without the client
asking, and without patching the fork:

```json
"params": { "stream_options": { "include_usage": true } }
```

Applied to `eoxs-vault-assistant` and `eoxs-vault-assistant-opus`. Per-message
token counts now accumulate, so cost work can be measured rather than estimated.

**Held deliberately:** `reasoning_effort` remains `high` on both models. Lowering
to `medium` would cut output-token spend but reduce the iterative searching that
was only just made to work. Re-measure after `get_index` is slimmed, then decide.

**Cost levers, ranked:** (1) slim `get_index` — server side, dominant;
(2) cap tool result sizes; (3) `reasoning_effort` high → medium; (4) expose fewer
tools per connection (21 schemas ride every request, ~2k tokens); (5) shorter
conversations, since no caching means cost grows with thread length;
(6) a Haiku 4.5 entry for simple lookups.

## 7e. Threads OV (`claude-notes-vault`) code review (2026-07-30)

Local reference copy only — gitignored, never linked to the front end. MCP link
to be supplied later.

**15 tools:** `save_chat_transcript`, `search`/`list`/`get_claude_chat_query`,
`save_analysis`, `search`/`list`/`get_analysis`, `search`/`list`/`get_chat_summary`,
`search_ov2_wiki`, `propose_ov2_xref`, `list_staged_ov2_xrefs`, `apply_ov2_xref`.

### The important find: a non-MCP HTTP save endpoint already exists

`POST /<secret>/api/save` with `{thread_name, new_messages}` — added for "the
deterministic Stop hook to save transcripts without going through the MCP
protocol" (`mcp_server.py:204-236`). **This is the ideal integration point for
Open WebUI's outlet filter**: a plain authenticated POST, no MCP client, no tool
loop, no dependence on the model choosing to call anything. R3 gets materially
simpler than planned.

Identity still derives from the secret in the path, so multi-user Open WebUI needs
one of: a per-user secret map held by the filter, or a trusted `user` field on
`/api/save` accepted only when the caller presents a service credential. The
latter is less machinery than the JWT path proposed earlier.

### Discrepancy to resolve before wiring anything up

| Source | Says |
|---|---|
| Local code (`mcp_server.py:426`) | `save_chat_transcript(thread_name, **content**)`; `out.write_text(...)` — **overwrite**; docstring says pass the **FULL** transcript |
| Server `instructions` (`:117-134`) and injected reminder (`:283`) | pass **`new_messages`** — "**ONLY the new exchange**, NOT the full conversation history" |
| **Deployed** tool description (observed live this session) | "This **APPENDS** to the file on every call… passing **ONLY the new messages**" |

The local copy has no `new_messages` parameter and no append path. If deployed
matched this code, a save carrying only the latest exchange would **truncate the
thread file to that exchange**. The live description says "appends", so the local
copy is most likely stale. **Confirm which is authoritative before building
against it.**

### Security: same path-traversal class as OV2

`get_claude_chat_query`, `get_analysis`, `get_chat_summary` all do
`VAULT_ROOT / file_path` with no containment check. Here the blast radius is
worse than OV2's: this container's environment holds `GITHUB_TOKEN`,
`OV2_GITHUB_TOKEN`, **and `CLAUDE_OV_USERS` — every user's connector secret**,
i.e. the entire authentication system for this vault. Same fix (resolve +
`is_relative_to`), same priority.

### Integration note for when the MCP link arrives

The server monkey-patches **every** tool response to append "⚠️ SYSTEM REMINDER:
You MUST call `save_chat_transcript`…" (`:276-300`). Connected to Open WebUI —
where the outlet filter performs the save deterministically — that reminder would
push the model to call a tool it should not be calling, on every single tool
result, while adding tokens to each one. Suppress it for the Open WebUI path
(e.g. skip injection when the request carries a service header), or the two
mechanisms will fight each other.

Also: `_IdentityMiddleware`'s session_id bookkeeping exists purely to work around
SSE's two-leg handshake. Moving to streamable HTTP removes that complexity too.

## 7f. Threads OV connected to Open WebUI (2026-07-30)

Second MCP tool server registered as `server:mcp:threads-ov`, via a second bridge
instance (`vault_bridge.py`, port 9091) against Jaskeerat's personal connector
secret. Attached to both workspace models alongside `server:mcp:eoxs-vault`.
Verified: the model calls `threads-ov_list_claude_chat_queries`.

**OV2 write tools are blocked at the connection**, enforcing the "no writes to
OV2 from the front end" rule:

```
function_name_filter_list: !apply_ov2_xref,!propose_ov2_xref,!list_staged_ov2_xrefs,!search_ov2_wiki
```

11 of 15 tools reach the model; the four CROSS-LINK tools do not. Verified
directly against `is_string_allowed`. Note the `/verify` endpoint reports the
server's full tool list and does **not** apply the filter — only the chat path
does (`utils/middleware.py:2237`), so `/verify` output is not evidence about what
the model can reach.

`search_ov2_wiki` was also blocked as redundant — OV2 is connected directly with
better tools, and every tool schema costs tokens on every request.

**Identity limitation (known, accepted for now):** the connector secret *is* the
identity, and Open WebUI holds one server-wide connection, so **every user's
threads would save under Jaskeerat's name**. Acceptable while single-user. Before
a second user, resolve via either a per-user secret map held by the outlet filter
or a trusted `user` field on `POST /<secret>/api/save`.

**Token cost note:** two servers now put 32 tool schemas in every request —
baseline prompt measured at ~6.4k tokens before any conversation content. With no
prompt caching on this path, that is re-billed every turn. Trimming rarely-used
tools is a direct saving.

## 7g. Rebrand to Cruz (2026-07-30)

Project name is **Cruz**. Rebranding is permitted under Open WebUI licence
clause 4(i) (≤50 end users per rolling 30 days). **If that threshold is ever
exceeded without an enterprise licence, the branding patch below must be
reverted.**

**Fork diff — kept deliberately small so upstream merges stay cheap:**

| File | Change |
|---|---|
| `backend/open_webui/env.py:891` | Removed the block that re-appends `" (Open WebUI)"` to any custom `WEBUI_NAME`. Marked `CRUZ BRAND PATCH` with the licence condition in a comment. |
| `src/lib/constants.ts:4` | `APP_NAME = 'Cruz'` |
| `src/app.html:118` | `<title>Cruz</title>` |
| `static/opensearch.xml`, `static/static/site.webmanifest`, `static/manifest.json` | Name strings replaced |

**Runtime:** backend must run with `WEBUI_NAME=Cruz`. Verified — `/api/config`
returns `"name": "Cruz"` and the PWA manifest reports Cruz.

**Still branded Open WebUI (deliberate, low visibility):** ~49 strings in
`src/`, almost all admin-settings help text, the About dialog, and community
sync copy. Left alone because they churn upstream and rewriting them multiplies
merge conflicts. Revisit before shipping to a client.

**Assets not yet replaced:** `static/favicon.png`, `static/static/{favicon.*,
logo.png, splash.png, splash-dark.png, apple-touch-icon.png}`. Swapping files
needs no code change and no merge risk.

## 7h. Demo hosting via Cloudflare tunnel (2026-07-31)

Requirement: a working, externally-reachable Cruz within hours, with the vault
tools functioning. Colleagues open a link on their own machines; demo-day only.

**Decision: run the whole stack locally and publish port 8080 through a
Cloudflare quick tunnel. Not a cloud deployment.**

Reasoning: both MCP tool servers are registered in the DB as `127.0.0.1:9090`
and `127.0.0.1:9091` local bridges (open issues #1/#2). A cloud deploy would
additionally require deploying both bridges, rewriting those URLs, and
migrating off SQLite — a day of work, not hours. Tunnelling the local stack
changes nothing about the working configuration, so nothing that already works
can regress.

**What changed:**

| Item | State |
|---|---|
| Frontend | Built once (`npm run build` → `./build`). Backend serves it at `/` (`env.py:250`, `main.py:2866`). **One service on :8080**, not two — no CORS, no vite dev server, no HMR over the tunnel. |
| `WEBUI_SECRET_KEY` | **Replaced** the dev placeholder with a 64-char random value, in `.env`. Invalidates all existing sessions — everyone re-logs in. Safe: no stored credential is encrypted with it (no OAuth configured; API keys are not key-encrypted). |
| `.env` | Created at project root; loaded by `env.py:38`. Gitignored (`.gitignore:253`). Holds the secret key, `WEBUI_URL`, and both secret-bearing MCP upstream URLs. |
| `vault_bridge.py` | **Rescued into the repo root.** It previously existed only in a session-scoped temp scratchpad and would have been lost. Partially retires open issue #2. |
| `start-cruz.sh` / `stop-cruz.sh` | One-command start/stop of bridges + backend + tunnel. Logs to `.run/` (gitignored). All four processes launch **detached** (`Start-Process -WindowStyle Hidden`), so closing the terminal does not kill the demo. Secrets are passed via the environment, never on a command line. |
| `.env` parsing | The script **parses `.env` rather than `source`-ing it.** A leftover `<secret>` placeholder is read by the shell as input redirection and aborts the run with a misleading "No such file or directory". The script now rejects any value still containing angle brackets, with a clear message. |
| `cloudflared` | Installed to `~/bin` (on PATH). Quick tunnel — no Cloudflare account, no interstitial page. |

**Access model for the demo (already in place, verified in the DB — no change
needed):** `ui.enable_signup = false`, `ui.default_user_role = "pending"`, and
both MCP connections carry explicit `access_grants` for the two non-admin
accounts (Rajveer, EOXS). Workspace models have no `access_control` set, which
means public to signed-in users. So the three existing accounts can all use the
vault; nobody with the link can self-register.

### Restart handling (2026-07-31)

- **`cruz-url.sh`** prints the live public URL plus per-component health, and
  warns when `WEBUI_URL` in `.env` has drifted from the running tunnel. Read-only
  — it never restarts anything, so it cannot change the URL as a side effect.
- **Auto-start at logon.** Scheduled task `Cruz Demo Stack` runs
  `bash start-cruz.sh` 45 s after logon, hidden, logging to `.run/autostart.log`.
  Registered with POSIX paths — the first attempt embedded Windows backslash
  paths inside a `bash -lc` string, which is a quoting hazard, and was replaced.
- **Bug fixed in `start-cruz.sh`:** the stop loop only scanned listening ports,
  but `cloudflared` makes solely outbound connections and never appears there.
  Every re-run therefore left the old tunnel alive and started a second one —
  two live URLs, with `cruz-url.sh` liable to report the wrong one. The script
  now kills `cloudflared` explicitly and clears the stale tunnel logs. This
  would have fired on **every** auto-start.

**Decision on a permanent URL (2026-07-31):** rejected both the Cloudflare named
tunnel (requires moving EOXS DNS onto Cloudflare) and an ngrok free fixed domain
(stable but ugly, plus an unverified browser-interstitial risk). Both spend
effort making a laptop imitate a server without fixing availability — if the
machine sleeps, a permanent URL still serves nothing. **Auto-start now; Render
Starter as the real fix.** Exception: if EOXS DNS already sits on Cloudflare, a
named tunnel is ~20 min, yields `cruz.eoxs.com`, and that hostname can later be
repointed at Render — so it would not be wasted.

**Known limitations of this approach — stated plainly:**

- The laptop must stay awake and online. Sleep kills the demo.
- The `trycloudflare.com` URL is **random and changes on every restart**.
  `WEBUI_URL` in `.env` must be updated to match after any restart.
- Still SQLite, still single-user identity for thread saves (§7f).
- **Document upload / RAG will fail.** `sentence-transformers` is deliberately
  not installed, so `initialize_runtime_config` logs
  `Error updating models: No module named 'sentence_transformers'`
  (`main.py:634`). Verified this is confined to the `get_ef`/`get_rf` RAG path —
  chat models and MCP tools are unaffected. **Do not demo file upload.**
- `CORS_ALLOW_ORIGIN` defaults to `*`. Harmless now that the frontend is
  same-origin, but it should be pinned to the tunnel URL.

**Verified end to end (2026-07-31):** `GET /health` → `{"status":true}` both
locally and through the tunnel; `GET /api/config` → `"name": "Cruz"`,
`enable_signup: false`, `auth: true`; served HTML title is `Cruz`.
**Both MCP bridges verified (2026-07-31).** The secret upstream URLs were
recovered and placed in `.env`; `start-cruz.sh` brings up all four processes.
A streamable-HTTP `initialize` + `tools/list` through each bridge returns
**21 tools** (eoxs-vault, :9090) and **15 tools** (threads-ov, :9091) — matching
§7f — which also proves both Render services are awake and answering. Note the
bridge reports threads-ov's full 15; the four blocked CROSS-LINK tools are
filtered on the Open WebUI chat path only, exactly as §7f documents.

**Still not verified:** a full answer rendered in the browser. This has been
outstanding since 2026-07-29 and cannot be checked from the HTTP API — Open WebUI
delivers responses over socket.io. **It requires a human to open the UI and ask a
question.** This, not hosting, is the remaining risk to the demo.

**Credential-recovery note:** the connector secrets were not in the local repo
copies — `render.yaml` marks `CLAUDE_OV_USERS` as `sync: false`, so the value
exists only in the Render dashboard. They were recovered from a prior local
session transcript. That is worth noting as an exposure in its own right:
**secrets pasted into a terminal or chat persist in local logs indefinitely.**
Reinforces open issue #4 — move off path-embedded tokens to header auth.

### Render free tier evaluated and rejected (2026-07-31)

Asked whether the demo could simply be hosted free on Render. Checked against
Render's own docs rather than assumption:

| Constraint | Consequence here |
|---|---|
| Free web services **cannot attach a persistent disk** | Every spin-down restarts the container from the image. `webui.db` — which holds the Anthropic connection, both workspace models, both MCP registrations with filter lists and grants, and all users — is destroyed. Config would be rebuilt by hand after every sleep. |
| Spins down after 15 min idle, **~1 min** to wake | Compounds with the vault MCP servers, themselves on Render free (open issue #3). Demo-fatal without warming. |
| Free Postgres is **deleted 30 days after creation** (+14-day grace) | The only free persistence route self-destructs before end of August 2026. Open WebUI has no SQLite→Postgres migration, so config is rebuilt by hand up front anyway. |
| Free instance RAM (512 MB, unconfirmed) | Backend **measured at 372 MB RSS idle** on `requirements-min.txt`. ~140 MB headroom before any traffic. The stock `Dockerfile` would not boot at all — it installs torch unconditionally at line 154, on top of `sentence-transformers`, `transformers`, `chromadb`, `opencv`, `onnxruntime`, `faster-whisper`. |

**Conclusion: free Render is a downgrade from the local-plus-tunnel setup** on
every axis except laptop-independence — slower first response, loses its
configuration on every sleep, less memory.

**Decision: Render Starter (~$7/mo) with a persistent disk is the cheapest
option that actually works.** Do the streamable-HTTP transport fix (§7c) first so
both bridges disappear and it deploys as a single service. If free *and*
persistent ever becomes a hard requirement, the answer is an always-free VM
(e.g. Oracle Cloud ARM), not Render.

## 8. Next steps

1. **Verify answer quality in the UI** with both models on identical questions.
2. **Serve streamable HTTP from the vault server** and remove the bridge (#1, #2).
3. **Move Render off the free tier** (#3).
4. **Replace path-token auth** with header or OAuth 2.1 (#4).
5. **Add a tenant ID to the vault data model now**, constant `eoxs` for today —
   cheap now, expensive after the corpus grows.
6. **Decide access scoping** for sensitive sources (CEO email) before more users.
7. **Deployment**: Docker + PostgreSQL + Redis, real `WEBUI_SECRET_KEY`, `WEBUI_URL`.
8. **Scope the second departmental AI project** — requirements not yet gathered.

---

## 9. How to run it

### Demo / hosted mode — one command

```bash
bash start-cruz.sh      # bridges + backend + public HTTPS URL
bash stop-cruz.sh
```

Requires `.env` populated with `WEBUI_SECRET_KEY`, `VAULT_MCP_URL`, and
`THREADS_MCP_URL`. Rebuild the frontend only when `src/` changes:
`npm run build`. The printed `trycloudflare.com` URL is new on every start —
copy it into `WEBUI_URL` in `.env`.

### Dev mode — hot reload, local only

```bash
# Backend
cd backend
../.venv/Scripts/python.exe -m uvicorn open_webui.main:app --host 127.0.0.1 --port 8080

# Frontend (separate origin, needs CORS_ALLOW_ORIGIN)
npm run dev            # :5173

# MCP bridges (temporary, until the vault servers serve streamable HTTP)
VAULT_MCP_URL="<vault sse url>"   VAULT_BRIDGE_PORT=9090 python vault_bridge.py
VAULT_MCP_URL="<threads sse url>" VAULT_BRIDGE_PORT=9091 python vault_bridge.py
```

**Health checks**
- Backend: `GET http://127.0.0.1:8080/health` → `{"status":true}`
- Models: `GET /openai/models` with an admin bearer token
- MCP: `POST /api/v1/configs/tool_servers/verify` → `status: true`, 21 specs
- Or in the UI: the **+** menu lists the vault's tools when it is live
