---
name: write-e2e-test
description: This skill should be used when AUTHORING a new Playwright end-to-end spec, page object, or e2e fixture. Triggers on "write an e2e test", "add a Playwright test", "create a new spec", "scaffold a page object", "add a POM", "add an e2e regression test for TICKET-123", "new e2e spec", "add a fixture", "cover this flow end to end", "my e2e test is flaky, rewrite it". Use it whenever a task will produce or substantially rewrite a spec under an e2e directory, even when the user never says "Playwright" and even when the request sounds like a small addition — the layer gate and suite reconnaissance are where most bad e2e tests are born. Covers the e2e-vs-lower-layer gate, learning the suite's existing conventions, page-object scaffolding, fixture registration, selector hierarchy, API-first seeding, isolation under parallelism, wait discipline, and the flake smells reviewers reject. Do NOT use to judge whether tests that ALREADY exist should move layers — that is test-layer-review's domain.
---

# Write E2E Test

Author a Playwright spec that earns its slot in the suite: real backend, no mocking, interactions behind page objects, and selectors that survive a library upgrade.

E2E tests are the most expensive tests you can write and the ones most likely to be deleted in a year because nobody could keep them green. Everything below exists to prevent that: the gate keeps cheap tests out, reconnaissance keeps the spec idiomatic to its suite, and the wait/selector discipline is what separates a test that fails when the product breaks from one that fails on Tuesdays.

This skill is methodology-only. Before writing, **look for the project's own e2e conventions** — a rules file, an e2e README, a CONTRIBUTING section, or a local `references/<project>-specifics.md` overlay next to this skill. Project rules always win over this skill's defaults; when they conflict, follow the project and consider updating the overlay. When no written conventions exist, Step 1 derives them from the suite itself.

## Step 0: Does this belong in e2e at all? (gate)

Run this before writing a line. Most bad e2e tests are not badly written — they are tests that should never have been e2e.

If the behavior is pure component state — filter toggles, validation messages, loading and error states with mockable APIs, rendering variants, formatting — **stop and recommend unit or integration instead**, then hand off to `unit-test`. Those tests run in under a second on every save; the same coverage as e2e costs minutes and arrives after push.

E2E earns its slot when the test needs something only the integrated system provides:

- a journey that crosses pages or features
- authentication, session, or permission behavior
- a real backend contract (the response shape you'd otherwise be asserting against your own mock)
- viewport-dependent CSS, portal/stacking behavior, or real browser APIs jsdom can't model
- a smoke test proving the deployed bundle actually boots

If you are weighing trade-offs, or the user is asking whether existing tests sit at the right layer, **invoke `test-layer-review`** — it owns the full smell catalog and the stakes-amplifier carve-out (high-stakes rules the frontend alone enforces keep their e2e *and* gain lower-layer coverage). Don't reproduce that depth here.

State the gate's outcome out loud. "This is e2e-worthy because it crosses login → checkout against the real payment contract" is a sentence the reviewer needs; silently writing the spec hides the decision.

## Step 1: Learn the suite before writing a line

A spec that is technically correct but foreign to its suite is a maintenance burden — it will be the only file using its own patterns. **Read before writing.** Budget a few minutes here; it is the single highest-leverage step in this skill.

Read, in this order:

| Read | What to extract |
| --- | --- |
| 2–3 recent specs in the target directory | File naming, describe/test title format, tag conventions, how setup is done, assertion style |
| The fixtures file (often a barrel that re-exports `test`) | Which fixtures exist, what to import `test` and `expect` from, how page objects are injected |
| An existing page object | Class vs. factory, locator naming, whether assertions live in the POM or the spec |
| `playwright.config.ts` | baseURL, projects, retries, timeouts, storageState/auth setup, reporters |
| Seeding helpers, API clients, request templates | How other tests create data without clicking |
| Git log on the e2e directory | Which patterns are *current* — the newest spec beats the oldest one when they disagree |

**Where the suite and this skill disagree, the suite wins** — unless the suite's pattern is one of the flake smells at the bottom of this document, in which case follow the better pattern and say why in the PR description. Consistency is worth more than local optimality, but not worth propagating a known flake source.

If the target directory doesn't exist yet — you're writing the suite's first spec — this skill's defaults *are* the convention. Say so, and keep the structure boring and predictable; you're setting precedent.

## Step 2: Placement and naming

Both are **suite-local conventions, not universal truths** — Step 1 is where you learn them. Adopt what the suite already does, even if you'd have chosen differently. A spec filed where nobody looks, or named unlike its neighbours, costs more than a slightly imperfect assertion.

What placement and naming have to achieve, however a given suite spells it:

- **Discoverability** — someone changing this feature in six months should stumble onto the spec without knowing it exists. In practice that means the file lives with its feature, or wherever the suite collects the same kind of test.
- **Traceability** — a red test in CI should say what broke, and when it guards a specific reported bug, lead back to it. Suites do this through the filename, the describe title, a Playwright annotation, or a link in the commit — several work, so use the one already in play.
- **Selectability** — there must be some way to run a subset without running everything. Playwright offers tags, `--grep` on titles, and project/directory splits. Find which one this suite uses; a second mechanism nobody greps for is dead weight.

Suites commonly separate full journeys, bug regressions, feature-grouped specs, and smoke checks — but the depth and the names vary, and `e2e/tests/`, `tests/e2e/`, `cypress/e2e/`, and colocated folders are all normal. Put the spec where its neighbours already live.

Only when the suite genuinely has no convention do you need a default. A workable one: name the file for the feature (or for the bug reference, if it's a regression), name the behavior in the test title as a sentence — `'Submitting an empty form shows a required-field error'` — and put any bug reference in the describe title so a CI failure carries it. Add structured case IDs **only if something downstream actually consumes them** (a test-management tool, a traceability matrix, a compliance report). When nothing reads them, they are overhead that drifts out of sync, and an ID scheme invented for one spec is worse than plain prose.

## Step 3: Page Object Model

Every interaction goes through a page object. Raw locators in a spec are fine exactly once — the second spec that touches the same screen turns them into a copy-paste liability, and a UI change then means editing N files instead of one.

```ts
import { expect, type Locator, type Page } from '@playwright/test';

export class FeatureNamePage {
    readonly page: Page;

    // Group locators by screen area; the grouping is documentation.
    readonly pageHeading: Locator;
    readonly submitButton: Locator;
    readonly successMessage: Locator;

    constructor(page: Page) {
        this.page = page;

        this.pageHeading = page.getByRole('heading', { name: 'Feature' });
        this.submitButton = page.getByRole('button', { name: 'Submit', exact: true });
        this.successMessage = page.getByRole('status');
    }

    async goto(): Promise<void> {
        await this.page.goto('/feature');
        await this.waitForPageToLoad();
    }

    async waitForPageToLoad(): Promise<void> {
        await this.pageHeading.waitFor({ state: 'visible', timeout: 10_000 });
    }

    async submit(): Promise<void> {
        await this.submitButton.click();
    }

    // Parameterized locators are methods, not fields — they need an argument.
    rowFor(id: string): Locator {
        return this.page.getByTestId(`row-${id}`);
    }
}
```

Expose **locators** as readonly fields and **actions** as methods. The spec then asserts on the locators directly (`await expect(page.successMessage).toBeVisible()`), which keeps assertions — the part a reader must see to understand the test — in the spec rather than buried in a helper.

### Selector hierarchy (work top-down; drop a level only when the one above is genuinely unavailable)

1. **`getByRole('button', { name: 'Save', exact: true })`** — matches how a user and a screen reader find the element. Survives restructuring and library upgrades, and a failure usually means a real accessibility regression. Worth preferring even when it takes a minute to find the right role.
2. **`getByLabel` / `getByPlaceholder`** for form controls — same reasoning, more specific.
3. **`getByTestId`** — an explicit, stable contract with the source. Costs a source edit; that's a fair price and often the right answer. Reach for it when the accessible name is dynamic, translated, or duplicated.
4. **`getByText('...', { exact: true })`** — couples the test to copy and to locale. Check which language the app renders under test: a suite running a non-English locale will not match English labels, and a copy tweak breaks the test for no good reason.
5. **CSS class** — last resort, and only in one of these two shapes:
   - **Acceptable:** a library *container* class used as a scope, narrowed by role or content — `page.locator('.MuiPopover-root').getByRole('option', { name })`. The container is part of the library's public surface and is stable across minor versions; you are still asserting on something meaningful inside it.
   - **Not acceptable:** a library *state* class as the truth of an assertion — asserting on a "disabled" or "invisible" modifier class to prove state. Those are internal, they change across major versions, and the test then fails on an upgrade that broke nothing. Assert `aria-disabled`, a `data-state` attribute, or a `data-testid` you added at the source instead.

Chain and filter rather than reaching for CSS: `getByRole('row').filter({ hasText: 'Ada' }).getByRole('button', { name: 'Delete' })` is both readable and robust.

### Keep these out of the page object

- **`click({ force: true })`** — it disables Playwright's actionability checks, which exist to catch exactly the overlay/re-render races that break users. If a click needs `force`, something in the app is genuinely unclickable at that moment; fix the source or wait for the real precondition.
- **Conditional rescues** — `if (await menu.isVisible()) await page.keyboard.press('Escape')`. A branch in a test means the test doesn't know what the app does. Two runs take two paths and only one of them is ever really tested.
- **`waitForTimeout(...)`** — a sleep standing in for a condition. Too short and it flakes, too long and the suite crawls; it is always the wrong tool.
- **`waitForLoadState('networkidle')`** — never settles on apps with polling, WebSockets, or analytics beacons. Playwright auto-waits on the next action anyway.

## Step 4: Register the page object as a fixture

A page object nobody can inject gets re-instantiated by hand in every spec. Register it where Step 1 found the suite's fixtures:

```ts
// 1. Import alongside the others, keeping the existing ordering
import { FeatureNamePage } from '../pages/feature-name.page';

// 2. Extend the fixtures type
type Fixtures = {
    // ...existing
    featureNamePage: FeatureNamePage;
};

// 3. Add to the extend block
export const test = base.extend<Fixtures, WorkerFixtures>({
    // ...existing
    featureNamePage: async ({ page }, use) => {
        await use(new FeatureNamePage(page));
    }
});
```

Specs then destructure what they need — `async ({ featureNamePage }) => { ... }` — with no manual construction and no import churn.

This file is shared by the whole suite, which has a practical consequence: **two agents or two branches editing it concurrently will clobber each other.** If e2e work is being parallelized, serialize the fixture edits.

## Step 5: The spec

The skeleton below is deliberately plain — titles, tags, and describe wording all come from what Step 1 found, not from this template.

```ts
import { expect, test } from '<the suite's fixtures module>';

// Only if the suite selects by tags — reuse its namespaces rather than coining one.
const FEATURE_TAGS = ['@featureName'];

test.describe('Feature name', () => {
    test.beforeEach(async ({ featureNamePage }) => {
        await featureNamePage.goto();
    });

    test(
        'Submitting a valid form shows the success message',
        { tag: FEATURE_TAGS },
        async ({ featureNamePage }) => {
            await featureNamePage.submit();

            await expect(featureNamePage.successMessage).toBeVisible();
        }
    );
});
```

Notes on the shape:

- **Let the config own parallelism.** Most suites set `fullyParallel` once in `playwright.config.ts`; a per-file `describe.configure` is worth adding only where the suite already does it. What matters is the direction: never downgrade a file to `mode: 'serial'` to make a flaky test pass — serial hides the interference instead of removing it, and Step 6's isolation is the actual fix.
- **Retries belong in the config**, not in the spec. A local retry override is how a flaky test hides in a green suite; if one file genuinely needs different behavior, say why in a comment.
- **Tags, if the suite uses them,** drive selective runs (`--grep @featureName`). Match its existing namespaces and granularity — a tag nobody greps for is dead weight, and a missing one silently drops your test out of the runs people actually trigger.
- **One journey per test.** A test that checks five unrelated things reports one failure and hides four. Related assertions along a single flow are fine and good; unrelated ones want their own test.

## Step 6: Set state up through the API, assert through the UI

**Create test data by calling the backend, not by clicking through the app.** UI setup is slow, and every click is another chance to fail for a reason unrelated to what you're testing — a login form breaking would fail every test in the suite instead of the auth spec.

```ts
test('A newly created order appears as Pending', async ({ apiClient, page, ordersPage }) => {
    // Arrange — through the API
    const order = await apiClient.createOrder({ status: 'pending' });

    // Act + Assert — through the UI, which is what this test is actually about
    await page.goto('/orders');
    await expect(ordersPage.rowFor(order.id)).toContainText('Pending');
});
```

Use the suite's existing API client or request templates if it has them; if it doesn't, Playwright's `request` fixture is enough to build one, and it will pay for itself by the third spec.

**Authentication is the special case worth doing once.** Logging in through the UI in `beforeEach` can dominate a suite's runtime. Playwright's standard answer is a setup project that logs in once and saves storageState, which every other project then loads. Check `playwright.config.ts` — if the suite already does this, use it; if you find yourself writing a login helper called from every spec, that's the signal to set it up.

### Isolation, because everything runs in parallel

Tests share a backend. Ordering assumptions and shared records are how a suite becomes "just re-run it" — and a suite nobody trusts is one nobody fixes.

- **Give each test its own data.** Unique names per run (a random suffix, the worker index, the test title) rather than a fixed `"Test User"` that two workers fight over.
- **Never depend on another test having run first.** Each test creates what it needs. If two tests truly must share expensive setup, that's a worker-scoped fixture, not an ordering assumption.
- **Clean up what you created**, in a fixture teardown or `afterEach`, so failures don't leave debris that breaks the next run.
- **Don't assert on global counts** ("the list has 12 rows") — a parallel test creating a row makes that false. Assert on *your* row.

When UI setup genuinely can't be avoided — the flow under test has no API surface — extract it into a shared helper so the next spec doesn't rewrite it.

## Step 7: Wait for conditions, never for time

Playwright's assertions retry until they pass or time out. That auto-retry is the wait mechanism; anything you add on top is usually a bug.

```ts
// Retries until visible, then asserts. No sleep needed.
await expect(ordersPage.successMessage).toBeVisible();

// Wrong: returns immediately, the timeout does nothing, the test races.
if (await ordersPage.successMessage.isVisible({ timeout: 5_000 })) { /* ... */ }
```

For state that settles asynchronously and can't be expressed as a single locator assertion — a polled refetch, a value that converges — use `expect.poll`, which retries the whole function:

```ts
await expect
    .poll(async () => (await ordersPage.rows.count()), { timeout: 10_000 })
    .toBeGreaterThan(0);
```

Assert on what the user can observe. `toHaveText`, `toBeVisible`, `toHaveURL`, and `toHaveScreenshot` describe the product; asserting on internal attributes or class names describes the implementation and breaks on refactors that changed nothing real.

## Step 8: Missing backend data — skip honestly

Shared environments don't always hold the data a test needs. Skipping beats a red build that means nothing:

```ts
const eventCount = await eventsPage.events.count();
test.skip(eventCount === 0, 'No events seeded in this environment — cannot assert popover behavior');
```

This is legitimate for tests that genuinely require pre-existing state, and it must stay rare — a skip reason is a message to a future reader, so make it say what was missing and why the test can't seed it. **It is not a way to quiet a flaky test.** If the data is seedable, seed it (Step 6) instead of skipping.

## Step 9: Prove the test works before shipping it

An e2e test you haven't watched run is a guess.

1. **Run it.** Green on the first try with no prior failure is suspicious more often than not — check it's asserting what you think.
2. **Run it a few times** (`--repeat-each=3`), and against the suite's real parallelism. Flake shows up under contention, not in isolation.
3. **Prove it fails for the right reason.** For a regression spec this is the whole point: revert the fix (`git stash`), watch the test go red, restore it, watch it go green. A regression test that passes with the bug reintroduced is coverage theater. When reverting isn't cheap, break the assertion's precondition deliberately and confirm the failure message names the real problem.
4. **Read the failure output** you produced in step 3. If it wouldn't tell a colleague what broke, improve the assertion or add a step description.
5. **Run the suite's linter** over the new files — many repos scope e2e lint separately from root lint, and it's usually the thing that catches the smells below.

When the spec is part of a larger change, `author-tests` owns the wider gate and adversarial review, and `validate-in-browser` handles exploratory checking of the feature itself.

## Flake smells reviewers reject

`author-tests` holds the canonical catalog for this repo and `test-layer-review` reads the same signals as *placement* evidence; keep all three in step when one changes.

| Smell | Why it's wrong | Instead |
| --- | --- | --- |
| `click({ force: true })` | Disables the actionability checks that catch real overlay and re-render races | Fix the source, or wait for the actual precondition |
| Library *state* classes as assertion truth | Internal to the library; breaks on upgrades that broke nothing | `data-testid`, `aria-disabled`, or a `data-state` attribute at the source |
| Conditional rescue after an action (`if (visible) press('Escape')`) | The test doesn't know what the app does; two runs take two paths | Pin down the real behavior; fix non-determinism at the source |
| `waitForTimeout(...)` | A sleep instead of a condition — flaky when short, slow when long | `expect(...)` auto-retry, `waitFor({ state })`, or `expect.poll` |
| `waitForLoadState('networkidle')` | Never settles with polling, sockets, or analytics | `domcontentloaded` plus an assertion on a specific element |
| `isVisible({ timeout })` used as a wait | Returns immediately; the timeout is ignored and the test races | `waitFor({ state: 'visible' })`, in try/catch when it's a real feature-detection guard |
| Asserting "either A or B happened" | The spec admits the UI is non-deterministic | Find out which outcome is correct; assert that one |
| Clicking through the UI N times to reach a state | Slow, and fails for reasons unrelated to the test | Navigate by URL, or seed via the API |
| Mocking the backend | E2E exists *because* mocks lie; a mocked e2e is a slow integration test | Seed real data, or move the test down a layer |
| Fixed shared data (`"Test User"`) across parallel tests | Cross-test interference that looks like flake | Unique per-test data |
| Text selectors in the wrong locale | Breaks under the app's actual language, and on copy tweaks | `getByRole` with the rendered label, or a test id |

## Exit checklist

- [ ] The gate was applied and the e2e justification stated (or the work handed to `unit-test`)
- [ ] Existing specs, fixtures, and config were read; the new spec matches the suite's conventions
- [ ] All interactions go through a page object; the page object is registered as a fixture
- [ ] Selectors follow the hierarchy — no library state classes, no wrong-locale text
- [ ] Setup goes through the API; each test creates its own uniquely-named data and cleans up
- [ ] No sleeps, no `networkidle`, no `force: true`, no conditionals in test bodies
- [ ] The test ran, ran repeatedly, and was proven to fail when the behavior it guards is broken
- [ ] The suite's e2e lint passed on the new files
- [ ] Placement, naming, and the selection mechanism match what the suite already does — the test turns up in the runs people actually trigger
