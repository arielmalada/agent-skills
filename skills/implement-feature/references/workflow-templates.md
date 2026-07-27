# Workflow Templates for implement-feature

> **Claude Code Workflow tool only.** In any other harness this file's scripts do not run — reuse the embedded prompt prose as plain subagent prompts instead.

Complete, runnable scripts for the Workflow tool. **The Workflow tool requires explicit user opt-in** ("use a workflow", "ultracode", or a skill that mandates it) **AND presence in the session's tool inventory** — verify at use time; subagent sessions in particular lack it, and without it these scripts are inert: reuse their embedded prompts as plain subagent prompts.

For routine tickets, run the same prompts as direct Agent-tool calls (multiple Agent calls in one message run concurrently). Scripts are plain JavaScript (no TypeScript annotations); `meta` must be a pure literal; never call `Date.now()`, `Math.random()`, or argless `new Date()` inside a script — pass timestamps via `args`.

---

## Template 1 — understand-sweep

**When to use:** start of a big ticket that spans several subsystems (a feature folder + a shared package + a route + the e2e suite). Parallel Explore readers each map one subsystem; a synthesis step merges them into one structured feature map. **When NOT to use:** a ticket confined to one feature folder — a single thorough Explore agent (direct Agent call) is cheaper and usually better than three vague ones. After the sweep, ALWAYS personally read the 2–3 load-bearing files the map identifies — Explore locates code, it does not guarantee interpretation.

```js
export const meta = {
  name: 'understand-sweep',
  description: 'Parallel Explore readers over subsystems, merged into a structured feature map',
  phases: [{ title: 'Fan-out' }, { title: 'Synthesize' }]
}

// args: {
//   ticket: 'TICKET-1234',
//   repoRoot: '/abs/path/to/repo',
//   acSummary: 'one-paragraph AC digest',
//   cheapModel: 'sonnet',   // omit to inherit the session model; id is harness-specific
//   subsystems: [{ name: 'feature-folder', scope: 'packages/<pkg>/app/features/<feature>/',
//                  questions: ['Which controller fetches X?', 'Where is the column def for Y?'] }]
// }

const mapSchema = {
  type: 'object',
  required: ['subsystem', 'keyFiles', 'findings', 'reusables'],
  properties: {
    subsystem: { type: 'string' },
    keyFiles: {
      type: 'array',
      items: {
        type: 'object',
        required: ['path', 'role', 'excerpt'],
        properties: {
          path: { type: 'string' },
          role: { type: 'string' },
          excerpt: { type: 'string', description: 'signature/props/column def — the load-bearing lines' }
        }
      }
    },
    findings: { type: 'array', items: { type: 'string' } },
    reusables: { type: 'array', items: { type: 'string' }, description: 'existing components/helpers to reuse instead of new code' }
  }
}

phase('Fan-out')
const reports = (
  await parallel(
    args.subsystems.map((s) => () =>
      agent(
        `Read-only exploration for ticket ${args.ticket} in the repo at ${args.repoRoot}.
Ticket digest: ${args.acSummary}
Your scope (do not wander outside it): ${s.scope}
Answer these questions:
${s.questions.map((q, i) => `${i + 1}. ${q}`).join('\n')}
Also list existing shared components/helpers in scope that the feature could reuse (check the shared packages the specifics overlay lists).
Report absolute file paths + key code excerpts (props, signatures, column defs). Locate code — do NOT judge it or propose changes.`,
        { label: `explore-${s.name}`, phase: 'Fan-out', agentType: 'Explore', model: args.cheapModel, schema: mapSchema }
      )
    )
  )
).filter(Boolean)

phase('Synthesize')
const featureMap = await agent(
  `Merge these subsystem reports for ${args.ticket} into one feature map. Deduplicate files, resolve naming overlaps, and rank the 2-3 LOAD-BEARING files the orchestrator must read personally before planning.
Reports: ${JSON.stringify(reports)}`,
  {
    label: 'synthesize-map',
    phase: 'Synthesize',
    schema: {
      type: 'object',
      required: ['loadBearingFiles', 'map', 'reusables', 'openQuestions'],
      properties: {
        loadBearingFiles: { type: 'array', items: { type: 'string' } },
        map: { type: 'array', items: mapSchema },
        reusables: { type: 'array', items: { type: 'string' } },
        openQuestions: { type: 'array', items: { type: 'string' } }
      }
    }
  }
)

if (!featureMap) {
  log('synthesize agent died — returning raw subsystem reports instead of a merged map')
  return { map: reports, loadBearingFiles: [], reusables: [], openQuestions: [] }
}

log(`Feature map ready: ${featureMap.loadBearingFiles.length} load-bearing files — read them yourself before planning`)
return featureMap
```

`parallel` (a barrier) is correct here — synthesis genuinely needs all reports together.

---

## Template 2 — design judge-panel

**When to use:** a genuinely wide solution space — multiple viable architectures with real trade-offs (new shared component vs sx overrides vs component swap; local state vs lifted query). N independent Plan agents design from forced-diverse stances, a judge scores them, a synthesizer merges the winner with strong elements of the losers. **When NOT to use:** tickets with one obvious approach (most tickets) — this triples design cost for zero benefit; a single Plan agent with numbered questions is the default. Always spot-check the winning design's load-bearing claims yourself before the alignment gate. Design and judge agents deliberately run on the session model — no `model:` downgrade: design judgment is where a wrong output propagates.

```js
export const meta = {
  name: 'design-judge-panel',
  description: 'N independent design attempts from diverse stances, judged and synthesized',
  phases: [{ title: 'Design' }, { title: 'Judge' }, { title: 'Synthesize' }]
}

// args: {
//   ticket: 'TICKET-1234',
//   brief: 'problem statement + constraints + decisions already made',
//   contextPaths: ['absolute paths the designers MUST read'],
//   angles: [
//     { name: 'reuse-max', stance: 'Reuse existing shared components at all costs; zero new abstractions.' },
//     { name: 'clean-arch', stance: 'Optimal controller/view split per SOLID; new abstractions allowed where they pay.' },
//     { name: 'minimal-diff', stance: 'Smallest reviewable diff that satisfies the AC literally.' }
//   ]
// }

const designSchema = {
  type: 'object',
  required: ['approach', 'filesToTouch', 'commitSlices', 'risks', 'loadBearingClaims'],
  properties: {
    approach: { type: 'string' },
    filesToTouch: { type: 'array', items: { type: 'string' } },
    commitSlices: {
      type: 'array',
      items: {
        type: 'object',
        required: ['message', 'content'],
        properties: {
          message: { type: 'string', description: 'conventional commit subject, feat:/fix:/chore:, NO ticket id' },
          content: { type: 'string' }
        }
      }
    },
    risks: { type: 'array', items: { type: 'string' } },
    loadBearingClaims: { type: 'array', items: { type: 'string' }, description: 'claims the whole design hinges on — each must be spot-checkable' }
  }
}

phase('Design')
const designs = (
  await parallel(
    args.angles.map((a) => () =>
      agent(
        `Design a solution for ${args.ticket}.
Brief: ${args.brief}
READ these files yourself before designing (do not trust summaries): ${args.contextPaths.join(', ')}
Your assigned stance — commit to it fully: ${a.stance}
Slice the plan into small conventional commits (feat:/fix:/chore:, no ticket id in subject).`,
        { label: `design-${a.name}`, phase: 'Design', agentType: 'Plan', effort: 'high', schema: designSchema }
      ).then((d) => (d ? { angle: a.name, design: d } : null))
    )
  )
).filter(Boolean)

phase('Judge')
const verdict = await agent(
  `Judge these ${designs.length} designs for ${args.ticket}. Score each 1-10 on: (a) fit to ticket AC, (b) reuse of existing code over new code, (c) reviewability of the commit slicing, (d) risk. Read the load-bearing files yourself where scores hinge on a factual claim — do not take a design's word for it.
Designs: ${JSON.stringify(designs)}`,
  {
    label: 'judge',
    phase: 'Judge',
    agentType: 'general-purpose',
    effort: 'high',
    schema: {
      type: 'object',
      required: ['scores', 'winner', 'stealFromLosers'],
      properties: {
        scores: {
          type: 'array',
          items: {
            type: 'object',
            required: ['angle', 'total', 'notes'],
            properties: { angle: { type: 'string' }, total: { type: 'number' }, notes: { type: 'string' } }
          }
        },
        winner: { type: 'string' },
        stealFromLosers: { type: 'array', items: { type: 'string' } }
      }
    }
  }
)

if (!verdict) {
  log('judge agent died — returning the raw designs for a manual pick')
  return { designs }
}

phase('Synthesize')
const finalPlan = await agent(
  `Produce the final implementation plan for ${args.ticket}: take the winning design ("${verdict.winner}") and fold in these elements from the others: ${verdict.stealFromLosers.join('; ')}.
Material: ${JSON.stringify({ designs, verdict })}`,
  { label: 'synthesize-plan', phase: 'Synthesize', agentType: 'Plan', schema: designSchema }
)

if (!finalPlan) {
  log(`synthesizer died — use the winner design ("${verdict.winner}") directly`)
  const winnerDesign = designs.find((d) => d.angle === verdict.winner)
  return { finalPlan: winnerDesign ? winnerDesign.design : null, verdict }
}

log(`Winner: ${verdict.winner}. Spot-check these claims before the alignment gate: ${finalPlan.loadBearingClaims.join(' | ')}`)
return { finalPlan, verdict }
```

---

## Template 3 — implement→review pipeline

**When to use:** the plan is pre-sliced into commit-sized units that touch **disjoint files** (e.g. new component / translations / storybook / wiring as independent slices, or a repetitive migration over many files). Each unit is implemented by one agent and reviewed by the next stage while later units still implement — `pipeline()` gives that overlap for free. **When NOT to use:** units with sequential dependencies (unit 2 imports what unit 1 created) or ANY shared-file overlap — implement those inline in the main thread, in order. **Agents NEVER commit.** Parallel `git add`/`git commit` on the shared branch race: index.lock contention at best, and at worst one agent's commit silently absorbs another agent's staged files, corrupting the slicing with no error. Implementers edit + lint + format only; the orchestrator commits sequentially per unit after the workflow (via the `commit` skill). Do not reach for `isolation: 'worktree'` either: a worktree can't check out a branch the main tree holds, and edits made there wouldn't land in the shared working tree without a patch step this template doesn't do.

```js
export const meta = {
  name: 'implement-review-pipeline',
  description: 'Implement pre-sliced units on disjoint files (no commits); coverage-first review per unit, then a cross-cutting pass',
  phases: [{ title: 'Implement' }, { title: 'Review' }, { title: 'Cross-check' }]
}

// args: {
//   branch: 'TICKET-1234',
//   defaultBranch: 'main',            // the repo's default branch — never hardcode it
//   repoRoot: '/abs/path/to/repo',
//   lintCmd: 'the fast lint gate command from the specifics overlay',
//   formatCmd: 'the formatter command from the specifics overlay',
//   cheapModel: 'sonnet',             // omit to inherit the session model; harness-specific id
//   conventions: 'paste the convention block: commit format, import rules, locale traps, what not to touch',
//   units: [{ name: 'view', commitMessage: 'feat: add invoice list view', files: ['/abs/path/A.view.tsx'],
//             instructions: 'exact spec for this unit' }]
// }

const implSchema = {
  type: 'object',
  required: ['filesTouched', 'lintClean', 'formatted', 'notes'],
  properties: {
    filesTouched: { type: 'array', items: { type: 'string' } },
    lintClean: { type: 'boolean' },
    formatted: { type: 'boolean', description: "the project's formatter run on the touched files" },
    notes: { type: 'string', description: 'deviations from the spec, blockers, translation keys the main thread must add' }
  }
}

const reviewSchema = {
  type: 'object',
  required: ['findings'],
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        required: ['file', 'summary', 'failureScenario', 'confidence', 'severity'],
        properties: {
          file: { type: 'string' },
          summary: { type: 'string' },
          failureScenario: { type: 'string', description: 'concrete inputs/state -> wrong output' },
          confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
          severity: { type: 'string', enum: ['blocker', 'major', 'minor', 'nit'] }
        }
      }
    }
  }
}

const results = await pipeline(
  args.units,
  (unit) =>
    agent(
      `Implement ONE commit-sized unit in ${args.repoRoot}.
First verify: git branch --show-current must print ${args.branch} — if it does not, STOP and report that in notes instead of editing (NEVER edit on ${args.defaultBranch}).
You have NO other context — these conventions are binding:
${args.conventions}
Unit spec: ${unit.instructions}
Files you may touch (absolute): ${unit.files.join(', ')} — do NOT touch anything else, especially not locale JSONs (translations go through the project's translation tooling in the main thread; list needed keys in notes).
After editing: ${args.lintCmd} must pass on the touched files, then format them with ${args.formatCmd}.
Do NOT run git add or git commit — parallel commits on the shared branch race; the orchestrator commits after the workflow.`,
      { label: `impl-${unit.name}`, phase: 'Implement', model: args.cheapModel, schema: implSchema }
    ),
  async (impl, unit) => {
    if (!impl || !impl.filesTouched || impl.filesTouched.length === 0) return { unit: unit.name, impl, review: null }
    const review = await agent(
      `Review the UNCOMMITTED working-tree changes on branch ${args.branch} in ${args.repoRoot}, scoped STRICTLY to: ${unit.files.join(', ')} — run git diff -- <those files> yourself. Other agents may still be editing other files; ignore everything outside your scope.
Unit spec (what the changes should do): ${unit.instructions}
Hunt correctness bugs — no style nits. For every candidate finding, trace the actual data flow (would the field really be undefined? is there a guard?) and state the concrete failure scenario. Report EVERY issue you find, including ones you are uncertain about — do NOT filter for confidence or importance; tag each with confidence and severity instead. A downstream judge filters.`,
      { label: `review-${unit.name}`, phase: 'Review', model: args.cheapModel, schema: reviewSchema }
    )
    return { unit: unit.name, impl, review }
  }
)

phase('Cross-check')
const perUnit = results.filter(Boolean)
const allFiles = args.units.flatMap((u) => u.files)
const cross = await agent(
  `Cross-cutting review of ALL uncommitted changes on branch ${args.branch} in ${args.repoRoot}: run git diff -- ${allFiles.join(' ')} yourself. Per-unit reviews already ran — look ONLY for cross-unit issues they cannot see: translation keys referenced but never registered (locale JSONs are intentionally untouched — flag keys the main thread must add via the project's translation tooling), imports between units that don't resolve, inconsistent naming or patterns across units, a convention applied in one unit but not another. Same reporting rule: report everything, tag confidence + severity, do not self-filter.`,
  { label: 'cross-check', phase: 'Cross-check', model: args.cheapModel, schema: reviewSchema }
)

const findings = perUnit
  .flatMap((r) => (r.review ? r.review.findings : []))
  .concat(cross ? cross.findings : [])
const failed = perUnit.filter((r) => !r.impl || !r.impl.lintClean)
if (failed.length) log(`units needing main-thread attention: ${failed.map((r) => r.unit).join(', ')}`)
log(`${findings.length} unfiltered findings — judge in the main thread, then commit per unit`)
return { findings, unitReports: perUnit.map((r) => ({ unit: r.unit, impl: r.impl })) }
```

After the pipeline, in the main thread (session model): judge the unfiltered findings (reviewers deliberately do NOT self-filter — cheaper models follow "only report confirmed" literally and recall drops), fix what's real, add any flagged translation keys via the project's translation tooling, then commit sequentially per unit with the `commit` skill using each unit's `commitMessage`. Then proceed to the `author-tests` hand-off — the pipeline replaces neither the test gate nor `validate-change`.
