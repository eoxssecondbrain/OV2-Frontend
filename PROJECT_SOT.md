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

- **2026-07-29** — Verified all 3 prerequisites against this actual codebase (Explore-agent research + live MCP tool checks, not assumption):
  - **Skills**: already exists natively. `backend/open_webui/models/skills.py` + `routers/skills.py`. Mechanism mirrors Claude Skills — manifest of available skills, model pulls full content on demand via builtin `view_skill` tool, markdown content, `access_grants`. Fully backend/API-configurable, no frontend change needed to add a skill. **No gap.**
  - **Configurable MCP**: already exists natively, beyond stock Open WebUI. Real MCP client (official MCP SDK, `ClientSession`/`streamablehttp_client`) at `backend/open_webui/utils/mcp/client.py`; registered via `backend/open_webui/routers/tools.py`. Connections stored as a configurable JSON list (`tool_server.connections`) with per-user/per-group `access_grants`, admin-managed via Admin Settings → Integrations UI, env-seedable (`TOOL_SERVER_CONNECTIONS`). Two connection modes: backend-proxied (default, server holds credentials) and per-user direct-from-browser (off by default, permission-gated). **No gap** — decision needed is *which mode* to use (leaning backend-proxied for a shipped product; not yet confirmed with owner).
  - **Thread auto-save to vault**: no built-in per-message webhook/export exists in Open WebUI. However there is a clean, deterministic extension point: `outlet_filter_handler` (`backend/open_webui/utils/middleware.py:3412-3563`) fires after every finalized AI response with `chat_id`/`user`/full message pair in scope, and dispatches to Filter-type Functions (`backend/open_webui/utils/filter.py`, `process_filter_functions(filter_type='outlet')`). A custom `Filter.outlet()` Function is the right place to implement create-on-new-thread / append-on-continuation. **This is the one real build item** among the three prerequisites.
  - Found a live reference implementation of pattern #3 already running elsewhere in the org: the `test_vault` MCP server's `save_chat_transcript` tool appends per-thread conversation exchanges to `raw/claude-chat-queries/<user>_<date>_<thread-name>.md` and pushes to GitHub — structurally identical to the "Thread Ogil" behavior requested. Useful as a template for the outlet-Function's write logic.
  - **Caution noted**: that same `test_vault` MCP server enforces its save-every-turn behavior via text injected into tool results ("mandatory," "do not ask permission"), i.e. it relies on the LLM being coerced rather than a deterministic hook. Flagged to project owner as a prompt-injection pattern to be aware of, and explicitly **not** to replicate in this product — the outlet-hook approach is deterministic and doesn't depend on model compliance, which is the better-engineered version of the same idea.

- **2026-07-29** — Established collaboration ground rules (see `BUILDING_GUIDELINES.md`) and this SOT file, per project owner's request, before any project-specific scoping began.

## 4. Open Questions

Questions that need an answer from the project owner before related work can proceed. (Per Building Guidelines Principle 5 — nothing gets built on assumptions.)

- What department is this for, and what is their current workflow/pain point?
- Is "Thread Ogil" the same underlying vault/repo as OV2 (different folder, e.g. `raw/` vs `wiki/`), or a fully separate repo dedicated to client-facing conversations?
- Write mechanism for thread auto-save: live `git push` per message (like `test_vault` does today), or an API/DB layer that syncs to markdown asynchronously? Direct git push from client-facing traffic has real failure modes (concurrency/push conflicts, rate limits, repo bloat, backend needing a GitHub token reachable from client traffic).
- MCP connection mode: confirm backend-proxied (admin-configured, credentials never touch the client) is the intended model, not per-user direct.
- Multi-tenancy: one deployment per client (own MCP/vault/skills config each), or one shared instance serving multiple clients with isolation?
- Skills content: specific skills already defined/portable from Claude's own skill format, or defined from scratch for this product?
- Identity/attribution: thread files should map to real authenticated Open WebUI users (not connector-URL-inferred identity like `test_vault` does) — confirm.
- What does success look like end-to-end? What data sources beyond OV2 need integrating? Constraints on hosting, compliance, budget, timeline?

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
