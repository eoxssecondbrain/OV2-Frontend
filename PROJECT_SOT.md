# Project Source of Truth (SOT)

Living record of project state. Read this before starting any new session. Update it as part of any work that changes code, decisions, or scope — see `BUILDING_GUIDELINES.md`.

Last updated: 2026-07-29

## 1. Project Summary

Building a white-label AI frontend (this repo, an Open WebUI fork) to replace dependency on Claude's own frontend/MCP client for querying the company's Obsidian-based knowledge vault ("OV2" wiki, built on the Carpathie LLM structure — raw MD files linked into a synthesized "world"). Claude's frontend cannot be shipped white-label to clients, so this product must replicate, independently of Claude:

1. **Skills** — packaged, invocable capability bundles (Claude-Skills-equivalent).
2. **Configurable MCP connectivity** — connect to the OV2 vault (and possibly others) the same way Claude's MCP client does.
3. **Automatic per-thread conversation logging** — every user query + AI response auto-saved into a vault ("Thread Ogil"): new thread → new MD file created; continued thread → same file updated, written into a `raw/` folder.

- **Department this serves:** TBD
- **Core problem being solved:** Claude-frontend dependency blocks white-label shipping to clients.
- **Base platform:** Open WebUI fork (this repo, `ov2-frontend`)

## 2. Current Status

| Area | Status |
|---|---|
| Requirements gathering | In progress — 3 core prerequisites defined, feasibility verified against codebase |
| Architecture decisions | In progress — see Decision Log |
| Implementation | Not started (explicitly deferred by project owner — brainstorming phase only) |

## 3. Decision Log

Chronological. Newest first. Each entry: date, decision, rationale, who/what prompted it.

- **2026-07-29** — Project owner shared the actual schema docs (`CLAUDE.md`) for both live vaults, clarifying the two-vault architecture:
  - **OV2** (`raj-wiki-vault`) — the main knowledge vault (emails, tickets, invoices, calls, client data → synthesized `wiki/`). This is "the world."
  - **Thread vault** (`claude-notes-vault`) — a separate vault whose only purpose is capturing conversations, same `raw/` + `wiki/` pattern. Confirmed: the `test_vault` MCP server seen earlier this session is a clone of this live thread vault, same structure — not a toy prototype.
  - Both vaults are Render-hosted MCP servers, each with its own GitHub repo and credentials (confirmed: never share tokens/repos between the two).
  - **Write-path rule, confirmed strict**: per-turn auto-save writes ONLY the current thread's own file in the thread vault (user message + AI reply, appended/updated on the file already created for that thread). Nothing in the live per-turn path writes to OV2. OV2 only ever receives a short pointer line, and only through a separate, human-approved synthesis step (mirrors the thread vault's existing CROSS-LINK workflow) — not something to build into the automatic write mechanism.
  - **Architecture simplification identified**: the thread vault's own MCP server already exposes the save/append tool and owns the git-commit-and-push mechanics. This means the Open WebUI outlet Function (prerequisite #3) does not need to reimplement git/GitHub logic — it just needs to **call the thread vault's existing MCP save tool** after every response, the same way prerequisite #2's configured MCP connection would call any other tool. This meaningfully shrinks prerequisite #3's scope: it becomes "wire the outlet hook to an MCP tool call," not "build a persistence layer."
  - **Skills clarified**: the "skill" the project owner described (teaches the AI how the vault is structured and how to navigate/query it) is the CLAUDE.md/SKILL.md content itself. Both vaults already have this written down. Porting these into Open WebUI's `Skill` model is close to a direct copy, not a from-scratch authoring task.
  - **Still open**: the project owner stated the MCP connection is "per client, per client is company, one company can have multiple users" — this is the single biggest undecided fork (does each client company get fully isolated vault infrastructure, or one shared deployment with logical isolation added on top of the existing per-user-secret model?). Turned into explicit forced-choice questions rather than assumed — see Open Questions.

- **2026-07-29** — Verified all 3 prerequisites against this actual codebase (Explore-agent research + live MCP tool checks, not assumption):
  - **Skills**: already exists natively. `backend/open_webui/models/skills.py` + `routers/skills.py`. Mechanism mirrors Claude Skills — manifest of available skills, model pulls full content on demand via builtin `view_skill` tool, markdown content, `access_grants`. Fully backend/API-configurable, no frontend change needed to add a skill. **No gap.**
  - **Configurable MCP**: already exists natively, beyond stock Open WebUI. Real MCP client (official MCP SDK, `ClientSession`/`streamablehttp_client`) at `backend/open_webui/utils/mcp/client.py`; registered via `backend/open_webui/routers/tools.py`. Connections stored as a configurable JSON list (`tool_server.connections`) with per-user/per-group `access_grants`, admin-managed via Admin Settings → Integrations UI, env-seedable (`TOOL_SERVER_CONNECTIONS`). Two connection modes: backend-proxied (default, server holds credentials) and per-user direct-from-browser (off by default, permission-gated). **No gap** — decision needed is *which mode* to use (leaning backend-proxied for a shipped product; not yet confirmed with owner).
  - **Thread auto-save to vault**: no built-in per-message webhook/export exists in Open WebUI. However there is a clean, deterministic extension point: `outlet_filter_handler` (`backend/open_webui/utils/middleware.py:3412-3563`) fires after every finalized AI response with `chat_id`/`user`/full message pair in scope, and dispatches to Filter-type Functions (`backend/open_webui/utils/filter.py`, `process_filter_functions(filter_type='outlet')`). A custom `Filter.outlet()` Function is the right place to implement create-on-new-thread / append-on-continuation. **This is the one real build item** among the three prerequisites.
  - Found a live reference implementation of pattern #3 already running elsewhere in the org: the `test_vault` MCP server's `save_chat_transcript` tool appends per-thread conversation exchanges to `raw/claude-chat-queries/<user>_<date>_<thread-name>.md` and pushes to GitHub — structurally identical to the "Thread Ogil" behavior requested. Useful as a template for the outlet-Function's write logic.
  - **Caution noted**: that same `test_vault` MCP server enforces its save-every-turn behavior via text injected into tool results ("mandatory," "do not ask permission"), i.e. it relies on the LLM being coerced rather than a deterministic hook. Flagged to project owner as a prompt-injection pattern to be aware of, and explicitly **not** to replicate in this product — the outlet-hook approach is deterministic and doesn't depend on model compliance, which is the better-engineered version of the same idea.

- **2026-07-29** — Established collaboration ground rules (see `BUILDING_GUIDELINES.md`) and this SOT file, per project owner's request, before any project-specific scoping began.

## 4. Open Questions

Questions that need an answer from the project owner before related work can proceed. (Per Building Guidelines Principle 5 — nothing gets built on assumptions.)

**Resolved this session:**
- ~~Is "Thread Ogil" the same vault/repo as OV2?~~ → No, confirmed separate vault (`claude-notes-vault` pattern), same `raw/`+`wiki/` structure, own repo/credentials.
- ~~Write mechanism for thread auto-save?~~ → Call the thread vault's own MCP save tool from the outlet Function; do not reimplement git logic in Open WebUI.
- ~~Skills content — defined from scratch?~~ → No, port existing CLAUDE.md/SKILL.md content from both vaults.

**Still open, posed as forced-choice questions to the project owner (2026-07-29):**
- Client-vault isolation model: fully separate infra per client company vs. one shared deployment with a company dimension added to the existing per-user-secret model.
- Scope of this workstream: frontend/connection work only (vaults assumed pre-populated) vs. also building the per-client ingestion pipeline.
- Whether cross-link-into-main-vault (pointer lines from thread vault into the knowledge vault) matters for v1, or is fully out of scope for now.
- Whether every client's vault will share OV2's exact folder schema (one generic skill template works for all clients) or schemas may vary per client (bespoke skill per client).

**Still outstanding, not yet asked:**
- What department/use case is the first target — internal EOXS use, or already a specific external client?
- MCP connection mode: confirm backend-proxied (admin-configured, credentials never touch the client) is the intended model, not per-user direct.
- Identity/attribution: thread files should map to real authenticated Open WebUI users — confirm the per-user-secret model (like the existing `CLAUDE_OV_USERS` pattern) is the right analog, or whether Open WebUI's native auth should drive this directly (likely yes, since it already has real user accounts — worth confirming no separate secret-per-user scheme is wanted).
- What does success look like end-to-end? Constraints on hosting, compliance, budget, timeline?

## 5. Scope

### In scope
- Skills (backend-configurable capability bundles)
- Configurable MCP connection to the OV2 vault
- Automatic per-thread conversation logging to a vault ("Thread Ogil")

### Explicitly out of scope
- Using Claude's own frontend/MCP client in the shipped product

## 6. Architecture Notes

- MCP client: `backend/open_webui/utils/mcp/client.py`, `backend/open_webui/routers/tools.py`, `backend/open_webui/utils/tools.py`
- Skills: `backend/open_webui/models/skills.py`, `backend/open_webui/routers/skills.py`, `backend/open_webui/tools/builtin.py` (`view_skill`), mention-parsing in `backend/open_webui/utils/middleware.py`
- Functions (Pipe/Filter/Action): `backend/open_webui/models/functions.py`, `backend/open_webui/routers/functions.py`, loader in `backend/open_webui/utils/plugin.py`
- Chat outlet hook (target for thread auto-save build): `backend/open_webui/utils/middleware.py` (`outlet_filter_handler`), `backend/open_webui/utils/filter.py` (`process_filter_functions`)
- Config storage pattern: JSON blob in key-value `Config` table (`backend/open_webui/models/config.py`), env-seedable

## 7. Change Log (code-level)

Track meaningful code changes here, most recent first, with a one-line "why."

- **2026-07-29** — Added `BUILDING_GUIDELINES.md` and this `PROJECT_SOT.md` file. No application code changed yet.
