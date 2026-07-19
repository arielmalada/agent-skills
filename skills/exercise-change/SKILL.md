---
name: exercise-change
description: This skill should be used to prove a code change actually works by exercising it end-to-end at runtime — "verify this change works", "does this actually work", "run it and check", "confirm the fix in the real app", before committing any nontrivial change. Identifies the diff's runtime surface, drives it with the cheapest faithful driver (unit execution, existing spec, live browser, HTTP), observes real behavior, and reports honestly. Do NOT use for static gates alone (lint/typecheck prove nothing about behavior), for ticket-level validation against acceptance criteria (validate-change), or for authoring tests (that is an authoring skill's domain).
---

# Exercise Change

A change is not verified because it compiles, lints, or "looks right" — it is verified when the changed behavior was **driven at runtime and observed**. This skill exists because the most common verification failure is inference: declaring success from a green typecheck or from reading the code you just wrote.

## Step 1 — Identify the runtime surface

Read the diff and name what actually runs:

| Diff touches | Runtime surface |
| --- | --- |
| UI components / hooks / routing | A user-visible flow in the running app |
| API client / server endpoint | A request/response pair |
| CLI / script / job | A command invocation |
| Pure functions / adapters / formatting | Direct execution of the function |
| Only tests, docs, config-with-no-behavior | **No runtime surface — say so and stop.** There is nothing to exercise. |

## Step 2 — Project bootstrap (first run in a repo)

Before deriving anything yourself, look for what already exists:

1. A project run/e2e skill (named in the project's specifics overlay when one exists; the conductor skills' overlays also carry run-command tables).
2. Launch docs: README dev-server sections, `package.json` scripts, Makefiles.
3. If nothing documented exists, derive the launch recipe from the repo — and propose persisting it to the project's rules or a project skill so the next run is cheap.

## Step 3 — Pick the cheapest FAITHFUL driver

Cheapest first, but never cheaper than faithful — a driver that mocks away the changed layer proves nothing:

| Driver | Use when | Watch out |
| --- | --- | --- |
| Direct unit execution (test runner scratch test, node/REPL) | Pure logic, adapters, formatting | Fine to keep or discard the scratch test afterwards — its purpose here is observation, not coverage |
| Existing automated spec covering the flow | The changed behavior already has e2e/integration coverage | Run the SPEC that encodes the expectation, not the whole suite |
| Live browser | UI flows | If the harness supports subagents, delegate to the `playwright-qa` agent with the project's login injection block; otherwise drive inline with strict snapshot hygiene |
| Direct HTTP (curl / http client) | Endpoints, API contracts | Include auth the way the project's tooling does — check the project specifics for token recipes |

## Step 4 — Drive the changed path SPECIFICALLY

- Exercise the new/changed behavior with inputs that hit the changed lines.
- Also exercise the **nearest unchanged neighbor** (the sibling variant, the previously-working flow) as a regression sentinel — the change working and the neighbor breaking is a failed verification.
- For data-gated behavior (only manifests with certain records): run a **fresh-data discriminating experiment** — seed a well-formed instance and drive the flow. If only legacy/malformed data triggers the behavior, classify honestly (general vs data-gated) instead of faking the state.

## Step 5 — Observe, don't infer

- Quote concrete outputs: rendered values, response bodies, exit codes, log lines, network traffic.
- "The code should now do X" is not an observation. "Navigated to /orders, the chip rendered `PAID — 42,90 €`" is.
- A screenshot or copied response beats a summary.

## Step 6 — Report honestly

- **Exercised**: what was driven, with the observed evidence.
- **Not exercised**: every path skipped, with the reason (env limit, unseedable data, time) — a report that omits what wasn't run is a false green.
- **Verdict**: works / broken (with the failing output verbatim) / partially verified.
- Never fake green. A behavior you could not exercise is "not verified", not "probably fine".
