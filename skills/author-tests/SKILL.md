---
name: author-tests
description: This skill should be used when authoring or reviewing tests for a change — "write tests for this change", "add a regression test for TICKET-123", "review the tests I wrote", "is this change tested at the right layer" — and at the end of ANY ticket implementation before declaring it complete. Orchestrates the test gate (which behaviors need which layer), sequences the authoring skills (write-e2e-test, unit-test, create-storybook-story, test-layer-review), then runs an adversarial review verifying each test would actually catch the regression it claims to guard. Invoke proactively when an implementation is about to be committed without test evaluation. Authors and reviews tests ONLY — full ticket validation (AC matrix, adversarial code review, verification gates) is validate-change, which runs after this skill; root-causing a defect is debug-issue.
---

# Author Tests (conductor)

## Overview

This skill is a **conductor**, not a methodology. It decides *which* tests a change needs, *sequences* the existing authoring skills, and *adversarially reviews* the output. The per-layer methodology lives elsewhere and must not be re-derived here:

- `write-e2e-test` — authors Playwright specs, POMs, fixtures (reads the project's e2e profile itself)
- `unit-test` — Jest + RTL with Equivalence Partitioning
- `test-layer-review` — decides/audits layer placement for tests that already exist or when the layer is genuinely unclear
- `create-storybook-story` — stories for `.view.tsx` components
- The project's e2e run skill — runs/debugs what was authored (named in the specifics roster; package-scoped skills may not be loadable from the current directory — use the overlay's run-commands table then)

Invoke those by name via the Skill tool; do not paraphrase their content into inline instructions (paraphrase drifts; skills get maintained).

Project facts (paths, run commands, seeding traps, locale trap, unit-test tooling traps, skill-name roster) live in a local `references/<project>-specifics.md` overlay next to this skill — when one exists for the repo you're in, read it before authoring or reviewing any test work (e2e, unit, or Storybook) and before dispatching any test-authoring subagent (you must embed its facts in their prompts); otherwise derive the equivalents from the project's rules. Fan-out templates (Claude Code Workflow tool only) live in `references/workflow-templates.md`.

## Phase 0 — The test gate (run before declaring ANY implementation complete)

Developers do not naturally evaluate regression coverage; the gate is required, not optional. It mirrors the repo's dev-testing rule — apply it even when the rule didn't auto-load (subagent contexts, other checkouts). If the repo's auto-loaded rules and this mirror disagree, the repo rules win — update this skill.

First, list the **test-worthy behavior clusters** in the diff: each user-observable behavior that could regress independently. Then classify each cluster:

| Cluster shape                                                     | Action                                                             |
| ----------------------------------------------------------------- | ------------------------------------------------------------------ |
| Bug fix (regression risk)                                         | E2E regression spec in the project's issues folder (exact path in the specifics overlay) → `write-e2e-test` |
| Cross-page flow, auth, or real backend contract                   | E2E → `write-e2e-test`                                             |
| Pure UI state, validation, rendering variants                     | Unit/integration → `unit-test`. NOT e2e.                           |
| High-stakes FE-only-enforced rule (permissions, money flow)       | BOTH: e2e AND lower-layer coverage                                 |
| Unsure which layer                                                | `test-layer-review` first, then act on its recommendation          |
| New or reworked `.view.tsx`                                       | Also: Storybook stories → `create-storybook-story`                 |

Skip cases (no test needed — say so explicitly rather than silently skipping): pure copy/translation changes, Storybook-only edits, config-only changes, urgent hotfix (file a follow-up ticket instead).

Why "pure UI state → NOT e2e": e2e typically runs against a live env with little parallelism (cost model in the specifics overlay); every unnecessary e2e test is minutes of suite time and a flake surface. Why the high-stakes row inverts: when the FE is the *only* enforcement point for a permission or money rule, an integration test proving "the gate renders" doesn't prove "the gate holds in the real app" — keep both layers.

## Phase 1 — Author

Sequence, don't parallelize by default. For a typical ticket (1–3 clusters), invoke the authoring skills inline, one cluster at a time — the skills are cheap and context-local.

Fan out only where the harness supports subagents AND the cluster count is large (5+) or clusters are independent and file-disjoint: one subagent per cluster, each prompt embedding:

- the target branch name and "conventional commits, no ticket id in subject" (personal convention)
- the relevant facts from the project's specifics file (locale trap, seeding traps, tag rules) — subagents do not inherit your conversation, rules, or memory
- absolute paths, what NOT to touch, and "return a structured report: files written, test names, seeding strategy used"

Never parallelize e2e authors — in suites where registering a POM touches a shared fixture file (the common POM-fixture pattern), concurrent e2e authors produce lost updates on it; e2e clusters serialize. Parallelize only layer-disjoint or genuinely file-disjoint (unit) clusters.

Concurrent dispatch is the default fan-out mechanism (Claude Code: multiple Agent calls in one message). **The Workflow tool is Claude Code-only, requires explicit user opt-in** ("use a workflow", "ultracode", or a skill that mandates it), **and must be present in the session's tool inventory** — verify at use time; subagent sessions in particular lack it, and when it is absent the templates' prompts work as plain subagent prompts. Reach for it only for audit/migration/review-scale test work — otherwise briefly offer it. Templates: `references/workflow-templates.md`.

## Phase 2 — Adversarial test review (every authored test, including your own)

A test that passes proves nothing by itself. For **each** test, answer three questions; a test failing any of them gets fixed or deleted, not shipped.

### 1. Would it catch the regression it claims to guard?

Run the mutate-the-code thought experiment: identify the exact line(s) whose breakage this test exists to detect, mentally revert/mutate them, and trace whether the assertion actually goes red. When the fix is small and cheap to toggle, do the real thing: `git stash` the fix, run the test, confirm red, unstash, confirm green. A regression spec that stays green with the bug reintroduced is coverage theater — this is the single most common defect in authored tests and the reason this phase exists.

### 2. Does it assert behavior, not implementation?

- Asserts what the user observes (rendered text, roles, navigation, dialog state, persisted data) — not internal state, private methods, mock call counts on internals, or library CSS classes.
- Would survive a refactor that preserves behavior.

### 3. Is it free of the repo's flake smells?

Screen every e2e diff line for:

- `page.waitForTimeout(...)` — replace with `expect().toBeVisible()` polling or `.waitFor({ state })`
- `waitForLoadState('networkidle')` — Playwright auto-waits on the next action
- conditionals inside test bodies (`if (visible) click()`) — use the project's ui-helpers for genuinely optional UI; if the element is a precondition, click directly and let auto-wait fail loudly
- `{ force: true }` — masks a real actionability bug
- library-internal selectors (`.Mui*`, `.rbc-*`) as assertion targets — add a `data-testid` or assert `aria-*` at the source
- `locator.isVisible({ timeout })` used as a wait — it returns immediately; use `waitFor({ state: 'visible' })` in try/catch for feature-detection guards
- asserting "either A or B happened" — the spec admits the UI is non-deterministic; pin down which outcome is correct
- navigating the UI N times to reach a state the test could reach directly (URL, seeded data) — slow and flake-prone

This is the canonical flake-smell catalog for this repo. `test-layer-review` applies the same vocabulary as *placement* signals — keep the two lists in step when either changes.

Some projects scope e2e lint separately from root lint (root lint skips e2e files entirely, and the e2e-scoped lint flags most of these smells) — run the e2e lint on every new spec; command in the specifics overlay.

For review at scale (a PR full of tests, a suite audit), fan out one refuter per test with the mutate-the-code question — see the adversarial-review template in `references/workflow-templates.md`.

## Unit/RTL review checklist

Enforce when reviewing Jest/RTL output (from `unit-test` or a subagent). This deliberately mirrors the repo's auto-loaded testing rules — apply it even when reviewing output produced where those rules didn't auto-load (subagent contexts, other checkouts). If the repo rules and this mirror disagree, the repo rules win — update this skill:

- [ ] MSW for API mocking — never mock `fetch` or the api client directly (MSW tests the real request path; fetch mocks assert your own stub)
- [ ] Queries by role (`screen.getByRole`) over testid — testid only when the role is genuinely unreachable (the `alt=""` trap below)
- [ ] Equivalence Partitioning visible in the case list — one test per partition/boundary, not five tests in one partition
- [ ] No snapshot tests for new code
- [ ] No implementation-detail mocking (internal state, private methods)
- [ ] Test file next to source: `X.view.tsx` → `X.view.test.tsx`
- [ ] Responsive branches covered per the `responsive-design` skill's test patterns (mock the project's viewport-hook wrapper, never resize jsdom)

**The `alt=""` trap** (the sanctioned exception to "roles over testids"): a decorative `<img alt="">` downgrades to `role="presentation"`, so `getByRole('img')` cannot find it AND `testing-library/no-node-access` blocks `querySelector`. Add a `data-testid` on the `<img>` in the component itself and query by testid. Avoid `getByRole('img', { hidden: true })` (fragile across jsdom builds).

## Storybook

New or reworked `.view.tsx` components need stories — invoke `create-storybook-story`. One fact worth enforcing at review: the title must follow the project convention — exact format in the specifics overlay; a wrong title buries the story where reviewers won't find it. (For decorative images in the view, see the `alt=""` trap in the Unit/RTL checklist above.)

## The ticket-automation trap (expensive; do not skip)

In projects with tracker↔VCS automation (e.g. a GitHub↔Jira integration): never put **someone else's** bug-ticket key in a commit subject, branch name, or PR title when committing a spec for it — the integration would march that ticket forward with no fix shipped. Canonical write-up (mechanism, safe reference locations, commit convention): the specifics overlay.

## No fake-green

If a bug is gated on legacy data you cannot seed on dev, do NOT hand-craft the malformed state to force a red-then-green "regression" test — that asserts an invented condition. Instead: run the discriminating fresh-data experiment to classify the bug (general vs legacy-only), ship an honest finding plus a manual-test note, and optionally a positive happy-path regression. Report skipped coverage as skipped, with the reason.

## Suite-placement audit (occasional)

When asked to audit existing tests ("is our suite in the right shape", "the e2e suite is slow"), this is `test-layer-review`'s domain — invoke it per file/area rather than judging inline. For a whole-suite sweep, use the suite-placement-audit template in `references/workflow-templates.md`. Respect the stakes carve-out: FE-only-enforced permission/money gates keep their e2e even when integration could cover the rendering — recommend "add lower-layer coverage", never "move it down".

## Exit checklist

Before reporting the test work done:

- [ ] Every gate cluster has a test, a named skip reason, or a follow-up ticket
- [ ] Every test passed the three adversarial questions (and revert-check ran where cheap)
- [ ] New e2e specs: package-scoped lint run; tags and seeding per that package's conventions (see the specifics reference)
- [ ] Unit tests: fast lint gate on the new files (command in the specifics reference); tests actually executed, output shown
- [ ] New/reworked views have stories
- [ ] No foreign ticket key in commit/branch/PR title (the ticket-automation trap)
- [ ] Failures and skips reported honestly, with output

**Hand-off**: when this skill ran as part of a ticket pipeline (`implement-feature` or `debug-issue`), the next step is `validate-change` — closing the test gate is not ticket-level validation (AC matrix, adversarial code review, verification gates still pending).
