---
name: implement-feature
description: This skill should be used when implementing a feature ticket end-to-end — "implement TICKET-123", "work on this ticket", "pick up TICKET-123", "take this ticket to PR", "start the feature", "build this feature", "do this ticket", or any request that pairs a ticket key/link with implementation work. Orchestrates the full pipeline (intake → parallel exploration → design → alignment gate → sliced execution → test gate → PR), and hands off to author-tests then validate-change before create-pr. Invoke at the START of ticket work, before fetching the ticket or writing any code. Do NOT use for bug/defect tickets or regressions (debug-issue), to validate an already-built change (validate-change), or for test authoring alone (author-tests); this skill builds new behavior.
---

# Implement Feature (conductor)

## Overview

This skill is a **conductor**. It decides sequence, fan-out width, and verification depth, then invokes existing skills and agents by name. It does not restate what the repo's auto-loaded rules already say — those load with the repo. But **subagents inherit none of that context**, so every fact a subagent needs must be embedded in its prompt (see Execution).

The shape of every ticket: **intake → parallel exploration → design → alignment gate → execution in small verified steps → test gate → validation → PR**. Keep conclusions in the main context; push file-dumps, page snapshots, and long transcripts into subagents.

Project facts (exact commands, paths, URLs, traps, skill-name roster) live in a local `references/<project>-specifics.md` overlay next to this skill — read it before intake when one exists for the repo you're in; otherwise derive the equivalents from the project's rules. Runnable multi-agent templates (Claude Code Workflow tool only) live in `references/workflow-templates.md` — read only when you decide to fan out (see "Fan-out mechanics" at the end).

## Phase 1 — Intake (before any code)

1. **Fetch the ticket** via the project's ticket-fetch skill when one exists (named in the specifics roster — typically an inline CLI fetch, ~2s). Never dispatch a heavyweight tracker subagent for a routine fetch — it costs minutes for the same data. If the raw ticket JSON ends up in a file (tracker dumps can exceed 100KB), parse the description with a small script instead of reading the raw JSON (a parse snippet belongs in the specifics overlay when the tracker uses a rich-text AST).

2. **Distrust ticket prose — verify named things against code.** Tickets are written from memory and rot: real history includes tickets naming nonexistent permissions and assuming router APIs the codebase doesn't have. Any permission, label, API shape, or hook a ticket names by string: grep it first — the specifics reference maps each claim type to the file that verifies it.

3. **Inspect linked Figma BEFORE planning.** Implementing from the ticket's textual description alone misses states and copy. Pull ONE `get_screenshot` inline for your own visual judgment; where the harness supports subagents, delegate the `get_metadata` / `get_design_context` / `get_variable_defs` sweep to the **`figma-reader` agent** (cheaper model) — the raw payloads are large and don't belong in the main thread. It returns a distilled spec: frames/states/viewports found (and missing), layout, exact copy, load-bearing tokens, desktop-vs-mobile diffs. It knows the design canvas may sit on a *different page* than the feature. If it reports "Figma MCP unavailable" (or no subagents exist), inspect inline with the Figma MCP tools yourself (exact names in specifics; in Claude Code, ToolSearch loads them) — **NEVER open figma.com in a browser** (main thread or subagent): the canvas is unreadable to a browser and the snapshots burn the tokens this delegation exists to save. If ticket AC and Figma conflict: **follow the ticket AC, flag the conflict to the PO** in the plan and the PR description. If the design shows only desktop, flag the mobile question rather than silently shipping desktop-only.

4. **Check blocker tickets' actual status** with the tracker CLI (command in specifics). A "blocked by BE" note may already be Ready for Testing — that changes scope decisions (wire the feature now vs. display-only stub).

## Phase 2 — Exploration (fan out, then spot-check)

- Launch **1–3 read-only exploration subagents in parallel** (Claude Code: `Explore`), each with a precise scope, the exact questions to answer, and the instruction "report file paths + key code excerpts (props, signatures, column defs)". One very thorough agent covering the feature usually beats three vague ones. Exploration agents *locate* code; they do not judge it. Where the harness supports per-dispatch model selection, downgrade them to a cheaper model (smallest tier only for pure enumeration — list call sites, grep usages); the personal spot-check below is what makes the downgrade safe. No subagents in the harness → do one focused exploration pass yourself before planning.
- **Personally read the 2–3 load-bearing files afterwards.** Explore reports are frequently right about *where* and wrong about *what it means*. One session's "rebuild the bottom bar" ticket turned out mostly already built — caught only by reading the component before planning, which collapsed the estimate.
- **Search for existing implementations before proposing new code**: shared packages, sibling features with the same pattern, existing helpers. Reuse locations are listed in the specifics reference.
- When the project ships a feature-context skill for the touched area (specifics roster), invoke it — it reads the feature's README/business docs so the plan respects local conventions.
- For a big ticket spanning several subsystems, use the **understand-sweep** template (see workflow-templates reference) instead of ad-hoc Explore calls.

## Phase 3 — Design

- Launch a **planning subagent** (Claude Code: `Plan`) with comprehensive context: the exact paths discovered, decisions already made, constraints, and **numbered concrete questions** ("1. Read X and Y and decide whether to reuse the header injection or keep the local reimplementation"). Make it read the actual files — do not let it plan from your summary alone. **No model downgrade here** — planning is judgment-dense, and one wrong load-bearing claim wastes the whole execution phase, which dwarfs the tokens saved. (No subagents in the harness → do the planning pass yourself with the same rigor.)
- The plan must **pre-slice the work into small conventional commits** (one logical unit each: styling, new component, translations, wiring). This slicing drives Phase 5.
- **Spot-check the plan's load-bearing claims** before committing to it — the one prop the whole approach hinges on, the memo-deps gotcha, the "this component already supports X" assertion. A plan built on one wrong claim wastes the whole execution phase.
- For a **genuinely wide solution space** (multiple viable architectures, real trade-offs), run the **judge-panel** template: N independent design attempts from different stances, scored, synthesized. Don't use it for tickets with one obvious approach — it triples cost for nothing.

## Phase 4 — Alignment gate (hard user preference)

Before non-trivial code, present a short plan (files to touch, key decisions, trade-offs) — via the harness's plan mode if it has one (Claude Code: EnterPlanMode) — and wait for sign-off. This is a hard preference — one short pause beats restarting after a redirect. Only skip for single-line/typo/obvious-bug fixes.

**AFK protocol**: if the user is away at a genuine decision point, pick the **ticket-AC-literal option**, proceed, and flag every deviation and judgment call prominently in the plan and PR so it can be redirected cheaply.

## Phase 5 — Execution

Branch = the ticket key, created from the default branch. Never commit on the default branch. Commits are conventional (`feat:`/`fix:`/`chore:`) with **no ticket id in the subject** — this personal convention beats any project rule that says otherwise; the branch name already carries the key. Use the `commit` skill per pre-sliced unit.

Per-unit loop — this is the **convention block**: follow it yourself AND embed it (with the exact commands from the specifics file) in every implementation-subagent prompt (rows restate auto-loaded rules precisely because subagents don't get them):

| Step | Action |
| --- | --- |
| After every edit | Run the project's fast lint gate on the changed files (exact command in specifics; skip redundant standalone typechecks). |
| Translations | ALL operations via the project's translation tooling (MCP tools or skills named in the specifics roster) — never hand-edit locale JSON. Run the consistency check after key changes; locale set in the specifics overlay. |
| Responsive UI | Cross-check the Figma mobile frame via the `responsive-design` skill before picking a breakpoint layer/hook. |
| New view component | Stories are mandatory where the project mandates them (story-authoring skill named in the specifics roster). |
| Before each commit | Run the project's formatter exactly as the specifics file prescribes — non-idempotent-formatter traps exist; details there. |
| Before the FINAL commit | Run the specifics file's final-commit format order verbatim, gate on its check command, then commit. |

**Dispatching implementation subagents** (where the harness supports them): only when units touch **disjoint files** — overlapping units are implemented inline, in order (worktree isolation, where offered, does NOT compose with committing on the shared branch: a worktree can't check out a branch the main tree holds, and its commits wouldn't land there). Subagents don't inherit your conversation, your memory, or the auto-loaded rules — embed in each prompt: the branch name, the commit-message convention, absolute paths, what NOT to touch, the relevant traps from the specifics overlay (e.g. locale traps and import rules), and a request for a structured report back. A subagent prompt missing the branch name commits to the wrong place; one missing the locale trap writes wrong-locale selectors into the suite. **Parallel-dispatched subagents must NOT commit** — concurrent `git add`/`git commit` on the shared branch race (index.lock contention, and one agent's commit can silently absorb another's staged files). Have them edit + lint + format and report back; commit sequentially yourself afterwards. Only a solo, sequentially-run subagent may commit.

**Model per unit**: where per-dispatch model selection exists, dispatch mechanical, precisely-spec'd units (translations wiring, stories, components with an exact plan slice) on a cheaper model; keep core/tricky units inline on the session model. Downgrade only when acceptance is mechanical (lint + tests + matches the plan slice) — a rework loop diagnosing a cheap model's miss costs more than the tokens saved.

After each later commit on a branch with an open PR, refresh the PR description via `create-pr` so it reflects all commits.

## Phase 6 — Test gate and validation

1. **Hand off to the `author-tests` skill** before declaring implementation complete. It owns the layer decision (e2e vs unit vs stories) and sequences `write-e2e-test` / `unit-test` / `test-layer-review` / `create-storybook-story`. Do not improvise the gate inline.
2. **Then hand off to the `validate-change` skill** for final validation. It orchestrates the AC matrix (the project's AC-verify skill), adversarial code review (`adversarial-review`), and the verification gates.
3. The project's full read-only CI gate must pass before the PR (exact command + resource caveats in specifics). Report outcomes faithfully: failing tests with output, skipped steps named as skipped. Never fake-green a legacy-data-gated behavior — classify it with a fresh-data experiment and ship an honest note instead.
4. Optional depth for risky diffs: the `ui-design-reviewer` agent after view-component changes (inject the project's conventions block from the validate-change specifics); the `polish-code` skill for post-implementation cleanup; the project's Sonar/quality-gate agent once the PR exists (roster in specifics).
5. **Cost routing for this phase** (where per-dispatch model selection exists): test-authoring subagents run on a cheaper model (the project traps must be embedded in the prompt regardless of model); review finder agents on a cheaper model with a coverage-first prompt ("report everything, tag confidence + severity") and the filtering/verdicts done inline on the session model. Layer decisions (`test-layer-review`) stay on the session model. Reserve adversarial verify fan-outs for explicit audit-grade asks — cheap finders + session-model judge is the cost-optimal shape for a routine ticket.

## Phase 7 — PR

- Invoke the `create-pr` skill — when the project ships a package-scoped variant for the touched package, prefer it (details in the specifics overlay).
- **Follow the project's tracker-linking etiquette** (specifics overlay; projects with tracker↔VCS integration often want NO manual PR comment — the integration links it, and a comment can nudge merge automation).
- **The ticket-automation trap: never put another ticket's key** in the branch, commit subjects, or PR title (e.g. when the work includes a characterization spec for someone else's bug) — tracker↔VCS integrations auto-march *that* ticket forward with no fix shipped. Reference foreign tickets only inside file contents. (Canonical write-up: the `author-tests` skill's specifics.)
- Projects with stacked PRs need the real base branch resolved before computing the diff for the description (recipe in the specifics overlay).

## Fan-out mechanics

**Default: direct subagent fan-out** where the harness supports it (Claude Code: multiple Agent calls in one message run concurrently) — that covers Phases 2–3 and disjoint-file execution for routine tickets, with zero ceremony. In a harness without subagents, run the same prompts as sequential passes yourself and skip the cost-routing advice.

**Model routing principle** (harnesses with per-dispatch model selection): subagents inherit the session model unless you say otherwise — so an un-annotated fan-out runs at full session-model price. Downgrade where verification is cheap (exploration, Figma reading, mechanical slices, review finders — mid tier; pure enumeration — smallest tier); keep the session model where a wrong output propagates (plan, synthesis, review verdicts, alignment). Delegation also only pays when the payload the agent consumes exceeds its spin-up overhead — a 2s inline call (e.g. a ticket fetch) is cheaper than any subagent.

**The Workflow tool is Claude Code-only, requires explicit user opt-in** ("use a workflow", "ultracode", or a skill that mandates it), **and must be present in the session's tool inventory** — verify at use time; subagent sessions in particular lack it, and when it is absent the templates' prompts work as plain subagent prompts. Reach for it when the task is audit/migration/review-scale — many similar items, multi-stage pipelines, adversarial verification loops — AND the user has opted in. If a ticket genuinely warrants it and the user hasn't opted in, briefly offer it and proceed with direct fan-out on decline. The three templates (understand-sweep, design judge-panel, implement→review pipeline) are in `references/workflow-templates.md` — read it only when actually reaching for the Workflow tool, and reuse its prompts as plain subagent prompts otherwise.

## Self-check before the PR

- [ ] Ticket claims (permissions, labels, APIs) verified against code, not trusted
- [ ] Figma inspected before the plan; AC-vs-design conflicts flagged to PO
- [ ] Alignment gate passed (or AFK protocol deviations flagged prominently)
- [ ] Branch = ticket key; commits small, conventional, no ticket id in subject
- [ ] Translations via the project's translation tooling only; consistency check clean
- [ ] Final-commit format order (per specifics) run and clean
- [ ] `author-tests` and `validate-change` (or manual equivalent) run; the project's CI gate green
- [ ] PR via `create-pr`; tracker etiquette followed; no foreign ticket keys in branch/commits/title
