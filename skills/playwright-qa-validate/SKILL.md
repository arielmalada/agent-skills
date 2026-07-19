---
name: playwright-qa-validate
description: >
  Use to validate a ticket / feature in a live browser with Playwright while
  keeping token cost low. Triggers on "validate this ticket with playwright",
  "QA test it in the browser", "run browser validation", "check the feature on the
  dev/feature env", "verify the new feature in playwright", "playwright QA". It
  resolves the spec, builds a checklist, and DELEGATES the browser driving to the
  cost-isolated `playwright-qa` subagent (cheaper model), then synthesises the
  result. Do NOT use for authoring Playwright spec files (that is an authoring
  skill's domain, e.g. write-e2e-test).
---

# Playwright QA Validation (cost-aware)

Validate a feature in a real browser without paying the Playwright-MCP context tax.

## Why this exists
Driving Playwright from the main thread is expensive: each `browser_snapshot` is
huge and gets **re-sent every subsequent turn**. So we keep the browsing in a
subagent on a cheaper model, with strict snapshot hygiene, and only the final
report returns to the main thread. Net: a large multiple cheaper than driving the
browser inline, with a small quality cost on nuanced judgment calls (which this
skill keeps in the main thread).

## Workflow

### 1. Resolve the spec
Get the ticket's description / acceptance criteria, the feature/test-env URL, and
any Figma link. Reuse the project's ticket-fetch skill if one exists (named in the
specifics overlay), or the user's pasted spec. Capture the **feature env URL**
and the **Figma node** (fileKey + nodeId) if present.

### 2. Build a concrete checklist
Turn the spec into testable, one-line behaviours (placement, each interaction,
states, query integration, edge cases). Mark spec-optional items as **optional**.
This checklist is what you hand the agent — be specific; the cheaper model executes
literally.

### 3. Login is mostly a non-issue (read project specifics first)
Read the project's specifics overlay (`references/<project>-specifics.md`, local-only,
next to this skill) — it carries the **canonical browser-QA injection block** to embed
verbatim in the agent dispatch. Where the Playwright MCP is
**pre-authenticated via storageState**, the agent usually just navigates and is
logged in. Decision rule:
- **Default pre-authenticated session** → let the agent navigate; it may self-recover
  from token expiry via the project's auth-recovery recipe **only for the default
  storage-state user** (recipe + limits in the injection block).
- **Non-default user established in the main thread** → the agent must NOT run any
  auth-recovery (it clobbers the shared auth state back to the default user); the
  dispatch prompt must say which case applies.
- **Only if storageState is gone/unconfigured** → do the email + user-typed-password
  fallback **in the main thread first**, then dispatch the agent to reuse the shared
  browser session. A subagent cannot type a password interactively.

### 4. Delegate the browsing to the `playwright-qa` agent
If the harness supports subagents, dispatch the `playwright-qa` subagent with: the
URL, the checklist, the login/injection block from the specifics file (verbatim),
the Figma node, and any viewport. It runs on the cheaper model where the harness
supports per-dispatch model selection, drives the browser with snapshot hygiene,
and returns a structured report. For long runs, prefer a background dispatch when
available. If the harness has no subagents, drive the browser inline yourself,
applying the cost-hygiene rules below strictly.

### 5. Synthesise (main thread = the judgment layer)
Review the agent's report. Apply higher-order judgment the cheap model may miss:
re-classify ambiguous findings, cross-check Figma for "real bug vs imprecise spec
wording," and sanity-check the network-level claims. Produce the final verdict.

### 6. Offer next actions
Offer to post a Jira comment, file bug tickets, or hand findings to the PR author.
Confirm before any outward-facing action.

## Cost hygiene reminders (apply even if you ever drive the browser yourself)
- `browser_evaluate` for targeted reads (text/attrs/URL/counts) — cheapest.
- `browser_take_screenshot({ element, ref, filename })` and
  `browser_snapshot({ filename })` — save to disk, don't return inline.
- One bootstrap snapshot, then act on refs; re-snapshot only on material change.
- Confirm behaviour via `browser_network_requests` rather than inferring from a
  (often mocked / empty) rendered list.

## Project specifics
- `references/<project>-specifics.md` — local-only overlay, never committed: env URLs,
  the canonical browser-QA injection block (login/recovery/accounts/do-not-touch rules),
  data caveats, app landmarks. Canonical copy for browser-QA facts — other skills'
  overlays point here.
