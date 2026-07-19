# Workflow templates for author-tests

> **Claude Code Workflow tool only.** In any other harness this file's scripts do not run — reuse the embedded prompt prose as plain subagent prompts instead.

Runnable scripts for the Workflow tool. **The Workflow tool requires explicit user opt-in** ("use a workflow", "ultracode", or a skill that mandates it). For routine tickets (1–3 test clusters), do NOT use these — invoke the authoring skills inline, or fan out with plain Agent-tool calls (multiple Agent calls in one message run concurrently). Reach for a workflow at audit/migration/review scale, and offer it briefly rather than assuming.

Harness mechanics (reflect the Workflow tool API as of authoring — re-check against the tool's own cheat sheet in the session where you run these, and trust that over this file): scripts are plain JavaScript (no TS annotations). `meta` must be a pure literal. Never call `Date.now()` / `Math.random()` / argless `new Date()` inside a script — pass timestamps via `args`. Subagents' final text IS their return value: prompt for raw JSON and force it with `schema`. `agent()` returns null when the agent dies or is skipped — `.filter(Boolean)` agent-result arrays AND null-guard every singleton result before dereferencing it.

---

## 1. Test-plan fan-out (one author per behavior cluster)

**When to use:** a large change (5+ independent test-worthy behavior clusters) where each cluster needs its own spec/test authored, and the user opted into a workflow. **When NOT to use:** typical tickets (author inline — cheaper and keeps context); clusters that share files. E2E authors frequently touch the shared fixture file (`test-base.ts`) when registering new POMs — the template serializes e2e authoring for that reason and only parallelizes layer-disjoint work. Add `isolation: 'worktree'` only if authors must mutate the same files in parallel.

```javascript
export const meta = {
    name: 'test-plan-fanout',
    description: 'Classify test-worthy behavior clusters, author each at the right layer, verify',
    phases: [{ title: 'Plan' }, { title: 'Author' }, { title: 'Verify' }]
};

// args: { diffRef: 'origin/<base>...HEAD', branch: 'TICKET-1234', ticket: 'TICKET-1234', today: '2026-07-03' }
// diffRef: resolve <base> with `gh pr view --json baseRefName` first — with stacked
// PRs, 'master...HEAD' can inflate the diff with the parent branch's work.

phase('Plan');
const plan = await agent(
    `Read the diff ${args.diffRef} in this repo. List every test-worthy behavior cluster
     (a user-observable behavior that could regress independently). Classify each with the gate:
     bug-fix regression or cross-page/auth/backend-contract -> "e2e";
     pure UI state/validation/rendering -> "unit";
     FE-only-enforced permission/money rule -> "both".
     Pure copy/translation/config clusters -> layer "skip" with a reason.
     Return JSON only.`,
    {
        label: 'gate-classification',
        agentType: 'general-purpose',
        schema: {
            type: 'object',
            properties: {
                clusters: {
                    type: 'array',
                    items: {
                        type: 'object',
                        properties: {
                            name: { type: 'string' },
                            files: { type: 'array', items: { type: 'string' } },
                            layer: { type: 'string', enum: ['e2e', 'unit', 'both', 'skip'] },
                            reason: { type: 'string' }
                        },
                        required: ['name', 'files', 'layer', 'reason']
                    }
                }
            },
            required: ['clusters']
        }
    }
);
if (!plan) {
    log('gate-classification agent died — aborting');
    return { error: 'plan agent returned null' };
}

phase('Author');
const conventions = `
Branch: ${args.branch}. Conventional commits, NO ticket id in the subject.
E2E facts (subagents don't inherit context — these are load-bearing):
- Import test/expect from e2e/src/fixtures/test-base, never @playwright/test.
- The suite's run locale may differ from the product's default locale (check the specifics
  overlay) — pull text-selector strings from the run locale's translation file.
- Seed via the project's API helper, applying the seeding traps from the specifics overlay
  (embed them here verbatim; today=${args.today} for validity-sensitive seeds).
- Tags, lint command, and auth do-not-touch rules: from the specifics overlay (embed them here).
Unit facts: MSW for API mocks, getByRole queries, Equivalence Partitioning, no snapshots,
test file next to source. Run yarn lint:files on new files.
Return raw JSON only.`;

const authorSchema = {
    type: 'object',
    properties: {
        files: { type: 'array', items: { type: 'string' } },
        testNames: { type: 'array', items: { type: 'string' } },
        seeding: { type: 'string' },
        lintClean: { type: 'boolean' }
    },
    required: ['files', 'testNames', 'seeding', 'lintClean']
};

const unitClusters = plan.clusters.filter((c) => c.layer === 'unit' || c.layer === 'both');
const e2eClusters = plan.clusters.filter((c) => c.layer === 'e2e' || c.layer === 'both');

// Unit authors are file-disjoint -> parallel via pipeline.
// Stage callbacks receive (prevResult, originalItem, index) — bind the item to the
// SECOND parameter; the first stage's prevResult is not guaranteed to be the item.
const unitResults = (await pipeline(unitClusters, (_prev, c) =>
    agent(
        `Invoke the unit-test skill (via the Skill tool — do not paraphrase it) to author unit/integration tests for cluster
         "${c.name}" (source files: ${c.files.join(', ')}). ${conventions}`,
        { label: `unit:${c.name}`, phase: 'Author', schema: authorSchema }
    )
)).filter(Boolean);

// E2E authors may all touch test-base.ts -> serialize.
const e2eResults = [];
for (const c of e2eClusters) {
    const r = await agent(
        `Invoke the write-e2e-test skill (via the Skill tool — do not paraphrase it) to author a Playwright spec for cluster
         "${c.name}" (ticket ${args.ticket}, source files: ${c.files.join(', ')}).
         Regression specs go in e2e/tests/issues/. ${conventions}`,
        { label: `e2e:${c.name}`, phase: 'Author', schema: authorSchema }
    );
    if (r) e2eResults.push(r);
}

phase('Verify');
log(`Authored: ${unitResults.length} unit cluster(s), ${e2eResults.length} e2e cluster(s); skipped: ${
    plan.clusters.filter((c) => c.layer === 'skip').map((c) => `${c.name} (${c.reason})`).join('; ') || 'none'
}`);
return { plan: plan.clusters, unitResults, e2eResults };
```

---

## 2. Adversarial test review (would each test catch its bug?)

**When to use:** reviewing a batch of authored tests (a test-heavy PR, the output of template 1) where each test's regression-catching claim deserves independent refutation. **When NOT to use:** 1–3 tests — do the mutate-the-code check yourself inline; a workflow's overhead exceeds the work.

```javascript
export const meta = {
    name: 'adversarial-test-review',
    description: 'Per-test verification that each test would catch the regression it guards',
    phases: [{ title: 'Inventory' }, { title: 'Refute' }, { title: 'Report' }]
};

// args: { diffRef: 'origin/<base>...HEAD' } — resolve <base> via `gh pr view --json baseRefName`
// (stacked PRs: a master diff misstates scope).

phase('Inventory');
const inventory = await agent(
    `List every test added/modified in ${args.diffRef}: file, test title, and the exact production
     code lines (file + brief excerpt) whose breakage the test exists to detect. Return JSON only.`,
    {
        label: 'test-inventory',
        agentType: 'Explore',
        schema: {
            type: 'object',
            properties: {
                tests: {
                    type: 'array',
                    items: {
                        type: 'object',
                        properties: {
                            file: { type: 'string' },
                            title: { type: 'string' },
                            guards: { type: 'string' }
                        },
                        required: ['file', 'title', 'guards']
                    }
                }
            },
            required: ['tests']
        }
    }
);
if (!inventory) {
    log('test-inventory agent died — aborting');
    return { error: 'inventory agent returned null' };
}

phase('Refute');
const verdictSchema = {
    type: 'object',
    properties: {
        verdict: { type: 'string', enum: ['CATCHES', 'MISSES', 'UNSURE'] },
        smells: { type: 'array', items: { type: 'string' } },
        explanation: { type: 'string' }
    },
    required: ['verdict', 'smells', 'explanation']
};

// pipeline: each test flows inventory -> refutation independently, no barrier.
// First-stage callback: item is the guaranteed SECOND parameter (prevResult, item, index).
const reviews = (await pipeline(
    inventory.tests,
    (_prev, t) =>
        agent(
            `Adversarially review one test. File: ${t.file}, test: "${t.title}".
             It claims to guard: ${t.guards}.
             1) Mutate-the-code thought experiment: read the test AND the guarded production code;
                if the guarded lines were reverted/broken, does an assertion in THIS test go red?
                If every assertion would still pass, verdict MISSES.
             2) Does it assert user-observable behavior (not internal state, mock internals, or
                library CSS classes like .Mui*/.rbc-*)?
             3) Flake smells on its lines: waitForTimeout, networkidle, conditional-in-test,
                force:true, isVisible-as-wait, library-internal selectors.
             Return JSON only.`,
            { label: `refute:${t.title}`, schema: verdictSchema, effort: 'high' }
        ),
    // Propagate a dead refuter's null so filter(Boolean) actually drops it —
    // { ...t, ...null } would be a truthy verdict-less object that pollutes needsFixing.
    (verdict, t) => (verdict ? { ...t, ...verdict } : null)
)).filter(Boolean);

phase('Report');
const misses = reviews.filter((r) => r.verdict !== 'CATCHES' || r.smells.length > 0);
const dropped = inventory.tests.length - reviews.length;
log(`${reviews.length} tests reviewed; ${misses.length} need fixing; ${dropped} refuter(s) died (unreviewed).`);
return { reviews, needsFixing: misses };
```

---

## 3. Suite-placement audit

**When to use:** a whole-suite sweep ("audit the e2e suite", "what should move down to jest") — dozens of spec files, each independently classifiable. **When NOT to use:** a single file or feature folder — invoke the `test-layer-review` skill inline instead. Note the stakes carve-out is embedded in the prompt because subagents don't inherit the profile rule.

```javascript
export const meta = {
    name: 'suite-placement-audit',
    description: 'Classify every e2e spec: keep, move to integration/unit, or delete',
    phases: [{ title: 'List' }, { title: 'Classify' }, { title: 'Synthesize' }]
};

// args: { specGlob: 'packages/<pkg>/e2e/tests/**/*.spec.ts' }

phase('List');
const listing = await agent(
    `List every spec file matching ${args.specGlob}. Return JSON only: { files: [...] }.`,
    {
        label: 'list-specs',
        agentType: 'Explore',
        schema: {
            type: 'object',
            properties: { files: { type: 'array', items: { type: 'string' } } },
            required: ['files']
        }
    }
);
if (!listing) {
    log('list-specs agent died — aborting');
    return { error: 'listing agent returned null' };
}

phase('Classify');
// First-stage callback: item is the guaranteed SECOND parameter (prevResult, item, index).
const classifications = (await pipeline(listing.files, (_prev, f) =>
    agent(
        `Invoke the test-layer-review skill (via the Skill tool — do not paraphrase it) and apply it to ${f}. For each test in the file decide:
         KEEP-E2E (cross-page flow, auth, real backend contract), MOVE-DOWN (pure UI state /
         validation / rendering — belongs in jest+RTL), or DELETE (duplicate/obsolete).
         STAKES CARVE-OUT (overrides MOVE-DOWN): FE-only-enforced permission gates and money-flow
         guards stay e2e even when integration could cover the rendering — for those recommend
         "keep e2e AND add lower-layer coverage".
         Also flag flake smells: waitForTimeout, networkidle, conditional-in-test, force:true,
         library-internal selectors (.Mui*, .rbc-*).
         Return JSON only.`,
        {
            label: `classify:${f}`,
            schema: {
                type: 'object',
                properties: {
                    file: { type: 'string' },
                    verdicts: {
                        type: 'array',
                        items: {
                            type: 'object',
                            properties: {
                                test: { type: 'string' },
                                verdict: { type: 'string', enum: ['KEEP-E2E', 'MOVE-DOWN', 'DELETE', 'KEEP-AND-ADD-LOWER'] },
                                reason: { type: 'string' },
                                smells: { type: 'array', items: { type: 'string' } }
                            },
                            required: ['test', 'verdict', 'reason', 'smells']
                        }
                    }
                },
                required: ['file', 'verdicts']
            }
        }
    )
)).filter(Boolean);

phase('Synthesize');
const flat = classifications.flatMap((c) => c.verdicts.map((v) => ({ file: c.file, ...v })));
log(`Audited ${classifications.length} files, ${flat.length} tests. MOVE-DOWN: ${
    flat.filter((v) => v.verdict === 'MOVE-DOWN').length
}, DELETE: ${flat.filter((v) => v.verdict === 'DELETE').length}, stakes-kept: ${
    flat.filter((v) => v.verdict === 'KEEP-AND-ADD-LOWER').length
}.`);
return { classifications };
```
