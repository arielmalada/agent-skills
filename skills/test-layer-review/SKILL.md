---
name: test-layer-review
description: This skill should be used when reviewing EXISTING test files/suites for layer placement (unit / integration / e2e). Triggers on "review my e2e tests", "should this be e2e or integration", "is this test in the right place", "audit my test suite", "test pyramid review", "move tests to integration", "force: true smell", "Playwright suite is slow", "should I move this to jest". Do NOT use when authoring a new spec from scratch (use write-e2e-test) or when the user is asking which e2e tests to scope for upcoming work — both are write-e2e-test's domain. This skill operates on tests that already exist in the suite.
---

# Test Layer Review

Analyze a test file (or suite) and recommend which tests belong at which layer of the test pyramid. Produce a per-test table with a "real e2e value?" column and lead with a TL;DR that names the action.

This skill is methodology-only. **Read the project's e2e profile** — a rules file cataloguing project-specific smells (library classes that shouldn't be assertion truth, app-specific reachability hazards, language defaults) — if the project has one. Per-project profile locations live in a local `references/<project>-specifics.md` overlay next to this skill, when one exists. The smell _categories_ below are universal; concrete library names per app live in the profile.

## When this skill applies

- User asks whether an existing e2e test should be split, moved, or trimmed
- User pastes or points at a Playwright/Cypress spec and asks for a review
- A test suite shows smells (see below) that suggest tests are at the wrong layer

This is not a generic "write tests" skill — it is specifically for **placement decisions** on tests that already exist.

## The pyramid framing (use this in every output)

- **Unit** — one component or hook in isolation, MSW for network. Sub-100ms. Runs on every save.
- **Integration** — feature slice with real children, real router/query client, MSW for API. Form submit → API call → success/error UI. **Most coverage should live here.**
- **E2E** — real browser, real backend. Critical user journeys, cross-page flows, auth, things that only break in the integrated system.

E2E is expensive and flaky. Every test there should justify hitting the real stack. **If MSW + RTL can prove it, it doesn't belong in `/e2e`.**

## When the pyramid inverts: high-stakes FE-only guardrails

The "MSW + RTL can prove it" heuristic assumes the _backend_ is the actual enforcer of the rule. Ask: _if the frontend check breaks, does the backend also reject the bad action?_ When the answer is **no** AND the bad action has data-integrity / financial / silently-fails-in-prod consequences (especially with prior incident history), the pyramid pressure inverts. Hook-mocked integration tests prove the _component_ renders the gate; only e2e against the real backend catches a regression where the _deployed app's_ gate stops holding (data-layer 404 → perma-undefined, missing dispatch, lib-skew, etc.).

Both qualifiers must hold to invert. "FE-only-enforced" alone isn't enough — the bug surfaces fast in lower layers when stakes are low. "High-stakes" alone isn't enough — backend-enforced rules surface as 4xx errors, not silent corruption. The dangerous combination is FE-sole-enforcer × silently-fails-in-prod × prior-incident-history.

**The output of "stakes invert" is redundancy, not relocation.** Each layer catches a different failure mode:

- **Unit / integration** — logic regressions (filter flip, state-transition off-by-one) and wiring regressions (controller stops passing errors to the dialog). Sub-second feedback in dev watch mode.
- **E2E** — deployed-bundle integrity, real-data-layer behavior, cross-system contracts. Catches regressions like `data !== undefined` perma-undefined when an upstream endpoint 404s in real life — invisible to hook-mocked tests.

For a high-stakes FE-only guardrail, the recommendation is **keep the e2e and add lower-layer coverage**, not "move it down." Picking one when stakes are high is leaving free safety on the table — and conversely, dropping integration coverage because "e2e covers it" gives up sub-second dev feedback for the same regression.

## Step 1: Read the spec AND the page object / helpers

Don't just look at the spec file. The smells live in the helpers. A call like `await filterDrawerPage.toggleFilter('Active')` looks innocent in the spec, but the helper underneath might be holding the test together with `force: true` and conditional `Escape` presses.

Also check what already exists at the unit/integration layer — if the component already has a view test and its hook has a unit test, the e2e is often duplicating coverage.

## Step 2: Hunt for smells

These are the strongest signals a test is at the wrong layer. When you find one, **call it out by name with the file:line** and explain _why_ it's a smell — don't just list it.

The categories below are universal. The project profile may add app-specific entries (e.g. specific calendar/grid library classes that are known fragility hazards in this app).

| Smell                                                                                                                                             | What it means                                                                                                           | Where the test belongs                                                                                              |
| ------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `click({ force: true })`                                                                                                                          | Playwright's actionability checks fail because the DOM is reconciling under the test. The test bypasses the safety net. | Hook test — pure state has no reconciliation race.                                                                  |
| Conditional `Escape` rescue (`if (menu.isVisible()) { keyboard.press('Escape') }`)                                                                | Test compensates for non-deterministic UI state.                                                                        | Integration — jsdom doesn't have async portal close races.                                                          |
| Coupling to library-internal _state_ CSS (e.g. `.Mui-disabled`, `.MuiBadge-invisible`, library-private classes — see project profile for catalog) | Test breaks on lib upgrades unrelated to your code.                                                                     | Either expose a stable `data-testid`/`data-state` and keep e2e, or move to a hook test that asserts state directly. |
| Navigating UI N times to reach state (e.g. `for (let i = 0; i < 52; i++) await nextButton.click()`)                                               | The state is reachable directly, but the test pretends it isn't.                                                        | Integration with state injected, or e2e with direct URL/date navigation.                                            |
| `await page.waitForLoadState('networkidle')`                                                                                                      | Flaky on apps with long-poll/WebSocket. Not a layer issue per se, but a reliability one.                                | Replace with `domcontentloaded` + a specific element assertion.                                                     |
| Asserting "either A or B happened"                                                                                                                | Test admits the UI is non-deterministic. Two valid outcomes for one click means the spec isn't pinned down.             | Talk to the dev who built it; pick one path.                                                                        |
| Test depends on seeded backend data being present (`test.skip(eventCount === 0)`)                                                                 | Real e2e value, but flaky. Acceptable but should be rare.                                                               | Keep e2e, harden via API-seeded setup.                                                                              |
| Text selector in non-primary locale (per project profile)                                                                                         | Translation-coupled and likely to break under locale switch                                                             | `getByRole` with the project's primary-language label                                                               |
| `page.waitForTimeout(...)`                                                                                                                       | A sleep standing in for a condition. Always flaky; not a layer signal on its own.                                        | Replace with `expect().toBeVisible()` polling or `.waitFor({ state })` — wherever the test ends up.                 |
| `locator.isVisible({ timeout })` used as a wait                                                                                                  | Returns immediately; the timeout does nothing, so the test races.                                                        | `waitFor({ state: 'visible' })`, in try/catch when it is a genuine feature-detection guard.                         |

The smell vocabulary is shared with the `author-tests` skill, which holds the canonical catalog (it screens diffs; this skill reads the same signals for placement). Keep the two in step when either changes.

The `force: true` smell is the strongest. **If a test needs `force: true` to be reliable, the test is wrong.** Lead with this when it appears.

## Step 3: Per-test table

Produce a row per test case. Use this exact column set:

| TC | What it tests | Real e2e value? | Where it belongs |

The "Real e2e value?" column is the forcing function. Allowed answers:

- **None — pure state** → unit/hook test
- **None** → integration
- **Real — needs seeded data** → keep e2e
- **Real — cross-feature routing** → keep e2e
- **Real — viewport-dependent CSS** → keep e2e
- **Smoke value** → keep e2e (but cheapest possible version)
- **Real but [caveat]** → keep e2e, note the caveat

Be honest. If 9 of 16 tests say "None — pure state", that's the headline.

## Step 4: Lead with the TL;DR

Skimmers will read the first paragraph. Put the action there:

> **TL;DR — Yes, but [conditional]. [One-sentence reason].**

Before recommending move-to-integration, run the stakes check from "When the pyramid inverts" above. If the FE is the sole enforcer of a high-stakes rule, the recommendation is **keep the e2e and add lower-layer coverage**, not "move it down."

## Step 5: Frame the win as developer feedback loop, not CI time

CI time savings are real but they're the secondary argument. The primary argument:

- **Integration tests run on every save during local dev.** Sub-second feedback in watch mode, regressions caught while context is fresh.
- **E2E runs on push at the earliest.** A regression caught 6 minutes after `git push` is one you've already context-switched away from.

This is the argument that lands when convincing teammates. CI minutes lands when convincing infra.

## Step 6: Note what you should NOT migrate

Some tests are genuinely cheaper in real DOM. Call this out so the reader doesn't try to migrate everything:

- Component-library portals (Menu, Popover, Dialog stacking interactions)
- Drawer animations + ClickAwayListener
- Mobile viewport-dependent CSS (`100vw`, `data-phone` queries)
- Real `StorageEvent` cross-tab sync, quota errors, private-mode quirks (jsdom doesn't model these — if users have actually hit them, keep e2e)
- Component-library default behaviors that have regressed across major versions before (e.g. Dialog/Drawer ESC handling) — keep one-line smoke tests

When recommending a hook test as "equivalent" to an e2e localStorage test, **never claim strict equivalence** — note the jsdom caveat.

## Step 7: The honest counterargument (mandatory, in the TL;DR)

Always include this in the TL;DR or immediately after it — never bury it at the bottom:

> If this suite is stable today (`retries: 1` succeeding without manual intervention) and CI time isn't a complaint, leaving it alone is defensible. **Working code is more valuable than ideal code.** Migrate when you next touch the feature substantially, not as a standalone cleanup.

Without this, the recommendation reads as "do this now" even when the right answer is "schedule it for the next time you're in this code."

## Output structure

Use this template:

```markdown
# [Suite name] — Should we split?

## TL;DR

[One paragraph: the action, the conditional, the reason. Include the counterargument here, not at the bottom.]

## Context

[1-2 sentences: what was reviewed, what already exists at lower layers.]

## The thesis: [strongest single smell]

[If `force: true` or similar appears, paste the actual code with file:line and explain why it's the core argument.]

## Per-test analysis

| TC  | What it tests | Real e2e value? | Where it belongs |
| --- | ------------- | --------------- | ---------------- |
| ... |               |                 |                  |

[Caveats marked with * footnotes — especially for jsdom limits.]

## Why this matters: developer feedback loop

[Sub-second-on-save vs. minutes-after-push framing.]

## Why don't 1:1 migrate everything

[List the categories that genuinely belong in real DOM.]

## Concrete recommendation

**Keep as e2e (~N tests):** ...
**Move to integration (~N tests):** ...
**Drop entirely:** ...

**Net result:** [before] → [after]. [What disappears, e.g. the `force: true` dance.]
```

## What to avoid

- Don't recommend migrating something just because "it could theoretically be lower-layer." There has to be a real cost (flake, slowness, maintenance).
- Don't claim hook tests are strictly equivalent to e2e for anything involving real browser APIs (storage events, viewport CSS, portal stacking).
- Don't pad the recommendation with hedges. Pick a number ("~6 e2e + 7 integration") and own it.
- Don't write a generic "test pyramid" essay. The skill is for _this specific suite_ — every claim should reference an actual test number or filename.
- Don't flag a test as misplaced without naming the smell that proves it. "This feels like integration" is not a review; "TC-7 calls `force: true` because of polling rerender — that's the calendar pushing test logic into the wrong layer" is.

## Calibration

If your output doesn't include at least one direct quote of test code or a `file:line` reference, you haven't read the suite carefully enough. Go back.

If the recommendation is "migrate everything," you're probably wrong — some categories genuinely belong in real DOM. Re-check section 6.

If the recommendation is "keep everything as is" and there are visible smells (`force: true`, library-private state classes, 50+ UI navigations), you're being too conservative.

## Project profiles

A worked example of a project's profile may live in a local `references/<project>-specifics.md` overlay next to this skill — read it when one exists for the repo you're in. Otherwise, look for an equivalent e2e profile in the repo's rules files before reviewing, and state explicitly when none exists (the generic smell catalog above is then the review baseline).
