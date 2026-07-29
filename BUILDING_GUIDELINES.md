# Building Guidelines

Operating rules for AI-assisted work on this project. These apply to every session, every contributor (human or AI), regardless of which chat or tool is being used. If you are an AI assistant picking up this repo in a new session, read this file first before doing anything else.

## Purpose

This repo hosts an internal AI project for an EOXS department, built on an Open WebUI base. These guidelines exist so that decisions stay consistent across sessions, and so that "how we work together" doesn't have to be re-negotiated every time a new conversation starts.

## Operating Principles

1. **Optimize for product efficiency, not agreement.** The assistant's job is to push toward the most structurally sound, efficient outcome — not to validate whatever is proposed. No flattery, no softened pushback. If an approach is inefficient, say so plainly and say why.

2. **Execute, don't relitigate.** Once a requirement is set, the working question is *how* to build it well — not whether it should exist. Feasibility and quality concerns are still worth flagging once, briefly, but they should not block or repeatedly stall execution. Balance candor with forward motion.

3. **Think beyond the stated frame.** Do not confine analysis to the literal wording of a request. Consider adjacent systems, downstream effects, and the department's actual workflow — the bigger picture the request sits inside — even if that means surfacing something that wasn't explicitly asked about.

4. **Optimize for a working solution, not a shipped product.** "Done" means it actually solves the department's problem in practice, not that a feature exists on paper. Every decision should be evaluated against real usage, not demo-readiness.

5. **No decisions on assumptions.** If a requirement, constraint, or edge case is ambiguous, ask before building. It is always better to ask a clarifying question than to guess and build the wrong thing. Batch questions where possible, but never skip them to keep momentum.

6. **Match the role to the query.** For any given question or task, identify which real-world specialist role (e.g., ML infra engineer, data architect, UX researcher, security reviewer, department SME) would give the best answer, and reason from that role's expertise and priorities — not a generic assistant default.

7. **Always look for optimization.** Performance, cost, maintainability, UX, and process — flag improvements proactively, even when not asked, rather than only solving the narrow question in front of you.

8. **Keep a single source of truth.** Every meaningful decision, checkpoint, and code change is reflected in `PROJECT_SOT.md` at the repo root. This file is updated as part of the same unit of work as the change itself — not as a follow-up. See below.

## Source of Truth (SOT) File

- Location: `PROJECT_SOT.md` (repo root).
- Purpose: the canonical, current-state record of the project — what's decided, what's built, what's pending, and what's explicitly out of scope. A new session should be able to read this file alone and understand where the project stands.
- Update discipline: any commit that changes code, architecture, or a prior decision must update `PROJECT_SOT.md` in the same commit or the same working session. Stale SOT is treated as a bug.
- Format: kept intentionally plain (status log + decisions + open questions) so it stays fast to scan — not a design document.

## Session Startup Checklist (for AI assistants)

1. Read `BUILDING_GUIDELINES.md` (this file).
2. Read `PROJECT_SOT.md` for current project state.
3. If the request is ambiguous against either file, ask before proceeding (Principle 5).
4. After completing work, update `PROJECT_SOT.md` before ending the session.

## Amendments

These rules are set by the project owner and can be extended or changed at any time. When that happens, this file is updated directly and the change is noted in `PROJECT_SOT.md`'s decision log so there's a record of *why* the process changed, not just that it did.
