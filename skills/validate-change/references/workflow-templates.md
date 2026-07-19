# Workflow templates for validate-change

> **Claude Code Workflow tool only.** In any other harness this file's scripts do not run — reuse the embedded prompt prose as plain subagent prompts instead.

Runnable scripts for the Workflow tool. **The Workflow tool requires explicit user opt-in**
("use a workflow", "ultracode", or a skill that mandates it) — for routine tickets use
direct Agent-tool fan-out instead (multiple Agent calls in one message run concurrently).

Rules these scripts obey (and any edit must keep obeying): `meta` is a pure literal; no
`Date.now()` / `Math.random()` / argless `new Date()` (pass timestamps via `args`); agents
can die → results are `null` → `.filter(Boolean)` before consuming, but a dead agent whose
work carried a check must surface as an explicit SKIPPED sentinel in the report — never
collapse it into "clean"/"empty" (that is the false green this skill forbids); `pipeline()` by default,
`parallel()` only where a genuine barrier exists; schema-force agent outputs so nothing
parses prose. Subagents don't inherit conversation context — every prompt embeds the branch,
base ref, and the repo traps it needs (see the specifics overlay).

---

## Template 1 — Adversarial review pipeline

**When to use:** large or high-stakes diffs (money flow, permission gates, shared-component
changes) where per-dimension finders plus per-finding refuters earn their cost.
**When NOT to use:** routine single-feature diffs — invoke the `code-review` skill inline
instead; the fan-out overhead exceeds the diff. `pipeline()` means dimension A's findings
get verified while dimension B is still reviewing.

```js
export const meta = {
    name: 'adversarial-review',
    description: 'Dimension-fanned diff review; every finding adversarially verified before report',
    phases: [{ title: 'Find' }, { title: 'Verify' }, { title: 'Report' }]
};

// Required args: { branch, baseRef, ticketId }. Optional: { dimensions: string[] }
const branch = args.branch;
const baseRef = args.baseRef;
const diffCmd = `git fetch origin ${args.baseRef} --quiet && git diff origin/${args.baseRef}...HEAD`;

const dimensions = args.dimensions || [
    'correctness: data flow, undefined guards, error handling, async races',
    'coverage symmetry: locale parity + the project gap axes from the specifics overlay',
    'permission gates and brand/tenant variants (verify names against the project permission catalog — path in the specifics overlay)',
    'regression blast radius: other consumers of touched shared components/adapters',
    'test coverage and layer placement (unit vs integration vs e2e)'
];

const findingsSchema = {
    type: 'object',
    required: ['findings'],
    properties: {
        findings: {
            type: 'array',
            items: {
                type: 'object',
                required: ['file', 'summary', 'severity', 'failureScenario'],
                properties: {
                    file: { type: 'string' },
                    line: { type: 'number' },
                    summary: { type: 'string' },
                    severity: { type: 'string', enum: ['critical', 'major', 'minor'] },
                    failureScenario: { type: 'string' }
                }
            }
        }
    }
};

const verdictSchema = {
    type: 'object',
    required: ['verdict', 'reason'],
    properties: {
        verdict: { type: 'string', enum: ['CONFIRMED', 'REFUTED'] },
        reason: { type: 'string' }
    }
};

// Two refuter lenses per finding — perspective-diverse beats identical refuters.
const lenses = [
    'Try to REFUTE this finding: trace the full data flow from source to usage and prove the ' +
        'failure scenario cannot happen (undefined guards like `{field && ...}`, defaults, upstream ' +
        'validation). Also refute if it is a style/premature-optimization complaint (e.g. missing ' +
        'useMemo/useCallback on cheap computations) rather than a defect.',
    'Verify empirically: construct the exact input/state from the failure scenario and walk the ' +
        'code path step by step. If ANY step breaks the scenario, return REFUTED.'
];

const verified = await pipeline(
    dimensions,
    // Stage callbacks receive (prevResult, originalItem, index) — in stage 1 the dimension
    // is the SECOND param; the default guards runtimes that seed prevResult with the item.
    async (prev, dim = prev) => {
        const out = await agent(
            `Repo: ${args.repoRoot}, branch ${branch}, ticket ${args.ticketId}.\n` +
                `Get the exact diff with: ${diffCmd}\nThen read every touched file IN FULL.\n` +
                `Review ONLY this dimension: ${dim}\n` +
                `Ignore the known diff-noise items from the specifics overlay (intentional local dev hacks — embed the list here).\n` +
                `Report only defects with a concrete failure scenario (inputs/state -> wrong output), not style preferences.\n` +
                `Return findings via the schema; an empty array is a valid, good answer.`,
            { label: `find: ${dim.slice(0, 40)}`, phase: 'Find', agentType: 'general-purpose', effort: 'high', schema: findingsSchema }
        );
        // A dead finder is a SKIPPED dimension, never "clean" — sentinel it, don't [] it.
        return out ? { dim, findings: out.findings } : { dim, dead: true };
    },
    async (found) => {
        if (found.dead) return { dim: found.dim, dead: true, confirmed: [], unverified: [] };
        if (found.findings.length === 0) return { dim: found.dim, confirmed: [], unverified: [] };
        // Barrier per finding is genuine: the kill decision needs BOTH verdicts.
        const checked = await parallel(
            found.findings.map((f) => async () => {
                const verdicts = (await parallel(
                    lenses.map((lens) => () =>
                        agent(
                            `Branch ${branch}, base origin/${baseRef}. A reviewer claims a defect:\n` +
                                `File: ${f.file}${f.line ? ':' + f.line : ''}\nClaim: ${f.summary}\n` +
                                `Failure scenario: ${f.failureScenario}\n${lens}\n` +
                                `Read the actual files — do not trust the claim text. Return a verdict via the schema.`,
                            { label: `verify: ${f.file}`, phase: 'Verify', agentType: 'general-purpose', schema: verdictSchema }
                        )
                    )
                )).filter(Boolean);
                const refutes = verdicts.filter((v) => v.verdict === 'REFUTED').length;
                if (verdicts.length > 0 && refutes * 2 >= verdicts.length) return null; // killed
                const status = verdicts.length === 0 ? 'UNVERIFIED' : 'CONFIRMED';
                return { ...f, dimension: found.dim, status };
            })
        );
        const kept = checked.filter(Boolean);
        return {
            dim: found.dim,
            confirmed: kept.filter((f) => f.status === 'CONFIRMED'),
            unverified: kept.filter((f) => f.status === 'UNVERIFIED')
        };
    }
);

phase('Report');
const perDim = verified.filter(Boolean);
const rank = { critical: 0, major: 1, minor: 2 };
const confirmed = perDim.flatMap((d) => d.confirmed || []);
confirmed.sort((a, b) => rank[a.severity] - rank[b.severity]);
log(`Confirmed findings (${confirmed.length}), most severe first:\n${JSON.stringify(confirmed, null, 2)}`);
const unverified = perDim.flatMap((d) => d.unverified || []);
if (unverified.length > 0) {
    log(`UNVERIFIED findings (${unverified.length}) — both refuters died; re-run or verify manually, do NOT report as confirmed:\n${JSON.stringify(unverified, null, 2)}`);
}
const dead = perDim.filter((d) => d.dead);
if (dead.length > 0) {
    log(`SKIPPED dimensions (finder died — NOT reviewed, NOT clean): ${dead.map((d) => d.dim).join(' | ')}`);
}
```

---

## Template 2 — AC-matrix fan-out

**When to use:** tickets with 8+ acceptance criteria, where one verifier per AC cluster keeps
each agent's file-reading focused. The orchestrator fetches the ticket (via
the project's ticket-fetch skill, in the main thread, BEFORE launching) and pre-clusters the AC into
3–6-criteria groups passed as `args.clusters`.
**When NOT to use:** ≤7 criteria — the project's inline AC-verify skill in the main thread is
faster and loses nothing.

```js
export const meta = {
    name: 'ac-matrix',
    description: 'Fan out AC clusters to verifier agents, re-verify negative rows, merge one matrix',
    phases: [{ title: 'Verify clusters' }, { title: 'Recheck negatives' }, { title: 'Merge' }]
};

// Required args: { ticketId, branch, baseRef, clusters: [{ name, criteria: string[] }] }
const diffCmd = `git fetch origin ${args.baseRef} --quiet && git diff origin/${args.baseRef}...HEAD`;

const matrixSchema = {
    type: 'object',
    required: ['rows'],
    properties: {
        rows: {
            type: 'array',
            items: {
                type: 'object',
                required: ['requirement', 'status', 'evidence'],
                properties: {
                    requirement: { type: 'string' },
                    status: { type: 'string', enum: ['MET', 'PARTIAL', 'NOT_MET'] },
                    evidence: { type: 'string' },
                    concerns: { type: 'string' }
                }
            }
        }
    }
};

// The subtle-gap hunt rides along as one extra synthetic cluster.
const clusters = args.clusters.concat([{
    name: 'cross-cutting gap hunt',
    criteria: [
        'Locale parity: every new translation key exists in every locale file (paths + locale set from the specifics overlay)',
        'Entity symmetry: if share got the change, property did too (unless the AC is explicit about one)',
        'Party type: behavior correct for both person and organization parties',
        'Permission gates: gate names exist in the project permission catalog (path from the specifics overlay) and gated/ungated paths both behave',
        'Test coverage: a spec or unit test guards each AC behavior'
    ]
}]);

// Single-row verdict schema for the negative-row recheck (matrixSchema is array-shaped;
// reusing it there would let an empty rows[] silently keep a possibly-wrong verdict).
const recheckSchema = {
    type: 'object',
    required: ['status', 'evidence'],
    properties: {
        status: { type: 'string', enum: ['MET', 'PARTIAL', 'NOT_MET'] },
        evidence: { type: 'string' },
        concerns: { type: 'string' }
    }
};

const results = await pipeline(
    clusters,
    // Stage callbacks receive (prevResult, originalItem, index) — in stage 1 the cluster
    // is the SECOND param; the default guards runtimes that seed prevResult with the item.
    async (prev, cluster = prev) => {
        const out = await agent(
            `Repo: ${args.repoRoot}, branch ${args.branch}, ticket ${args.ticketId}.\n` +
                `Get the diff: ${diffCmd}\nRead the touched files in full; follow evidence into unchanged files when needed.\n` +
                `Score EACH criterion below as MET / PARTIAL / NOT_MET with evidence (file + function) and concerns:\n` +
                cluster.criteria.map((c, i) => `${i + 1}. ${c}`).join('\n') +
                `\nMET means observable behavior matches, not "code looks right". PARTIAL means e.g. done for one entity/locale but not another — say which.`,
            { label: `AC: ${cluster.name}`, phase: 'Verify clusters', agentType: 'general-purpose', effort: 'high', schema: matrixSchema }
        );
        // Tag with the cluster so a dead verifier surfaces as SKIPPED at Merge, not as a
        // silently smaller matrix.
        return { cluster: cluster.name, criteriaCount: cluster.criteria.length, rows: out ? out.rows : null };
    },
    async (res) => {
        if (!res.rows) return res; // dead verifier — pass the sentinel through
        // Adversarially re-check only the negative rows — a false NOT_MET wastes the author's
        // time, a false MET ships a gap; negatives drive PO flags so they must be solid.
        const rechecked = await parallel(
            res.rows.map((row) => async () => {
                if (row.status === 'MET') return row;
                const recheck = await agent(
                    `Branch ${args.branch}, base origin/${args.baseRef}.\n` +
                        `A verifier scored this AC as ${row.status}:\nRequirement: ${row.requirement}\n` +
                        `Evidence given: ${row.evidence}\nConcerns: ${row.concerns || 'none'}\n` +
                        `Try to prove it is actually MET (search the whole diff and adjacent unchanged code for the implementation). Return your final verdict.`,
                    { label: `recheck: ${row.requirement.slice(0, 40)}`, phase: 'Recheck negatives', agentType: 'general-purpose', schema: recheckSchema }
                );
                // Dead recheck keeps the original (conservative) verdict; a returned verdict
                // overlays status/evidence/concerns on the row.
                return recheck ? { ...row, ...recheck } : row;
            })
        );
        return { ...res, rows: rechecked.filter(Boolean) };
    }
);

phase('Merge');
const perCluster = results.filter(Boolean);
const skipped = perCluster.filter((r) => !r.rows);
const rows = perCluster.flatMap((r) => r.rows || []);
const met = rows.filter((r) => r.status === 'MET').length;
const unverifiedCriteria = skipped.reduce((n, r) => n + r.criteriaCount, 0);
log(`AC matrix for ${args.ticketId}: ${met}/${rows.length} verified criteria MET` +
    (unverifiedCriteria > 0 ? ` — PLUS ${unverifiedCriteria} criteria UNVERIFIED (verifier died), NOT counted as met` : '') +
    `\n${JSON.stringify(rows, null, 2)}`);
if (skipped.length > 0) {
    log(`SKIPPED clusters (verifier died — criteria unverified, matrix is INCOMPLETE): ` +
        skipped.map((r) => `${r.cluster} (${r.criteriaCount} criteria)`).join('; '));
}
```

