# Workflow templates for debug-issue

> **Claude Code Workflow tool only.** In any other harness this file's scripts do not run — reuse the embedded prompt prose as plain subagent prompts instead.

The Workflow tool requires **explicit user opt-in** ("use a workflow", "ultracode", or a skill that mandates it). It is also **not present in every environment** — before planning around these scripts, verify at use time that a `Workflow` tool actually appears in the current session's tool inventory (subagent sessions in particular may lack it). If it is absent, these templates are inert reference material: fall back to direct Agent fan-out per SKILL.md Phase 3. For routine bugs, prefer direct Agent-tool fan-out anyway — multiple Agent calls in one message run concurrently and cost less ceremony. Reach for these scripts when the investigation is large (4+ hypotheses, multi-stage refutation, resumability matters) AND the user has opted in; otherwise briefly offer it and move on.

Both scripts are plain JavaScript (no TS annotations). `meta` must stay a pure literal. Never call `Date.now()`, `Math.random()`, or argless `new Date()` inside a script — pass any timestamps via `args`. Subagents return their final text; the `schema` option forces validated structured output so you never parse prose.

---

## Template 1 — Hypothesis fan-out with falsification

**When to use:** Phase 3 with 4+ enumerated hypotheses, each with a written falsification test, where survivors should be cross-examined without waiting for the slowest investigator (pipeline: H2's cross-exam runs while H5 is still investigating). **When NOT to use:** fewer than ~4 hypotheses (direct Agent fan-out in one message is faster), or when hypotheses are interdependent and must be judged together (then you need a barrier and a judge, not a pipeline).

Invoke with args like:

```json
{
  "repoRoot": "/abs/path/to/repo",
  "bug": "one paragraph: symptom + exact error text + env + affected user",
  "evidence": "repro result, network traffic summary, commit range, permissions/locale",
  "hypotheses": [
    { "id": "H1", "cause": "adapter drops the field for legacy records", "falsification": "read the adapter; if it null-guards the legacy shape, H1 is dead" },
    { "id": "H2", "cause": "regression in commit range abc..def", "falsification": "git log the range; if no commit touches this data path, H2 is dead" }
  ],
  "doNotTouch": [
    "the project's shared auth-state file (and never run the auth-setup project)"
  ]
}
```

```js
export const meta = {
  name: 'debug-hypothesis-fanout',
  description: 'Falsification-first investigation of competing root-cause hypotheses',
  phases: [{ title: 'Investigate' }, { title: 'Cross-examine survivors' }, { title: 'Synthesize' }]
};

const verdictSchema = {
  type: 'object',
  required: ['id', 'verdict', 'evidence'],
  properties: {
    id: { type: 'string' },
    verdict: { type: 'string', enum: ['FALSIFIED', 'SURVIVED', 'INCONCLUSIVE'] },
    evidence: { type: 'string', description: 'The killing evidence, or the complete causal chain, with absolute file paths' },
    files: { type: 'array', items: { type: 'string' } }
  }
};

const guardrails = [
  'Read-only investigation: do NOT modify, create, or delete any file.',
  ...(args.doNotTouch || []).map((p) => `Do NOT touch ${p}.`),
  'Use absolute paths under the repo root. Return ONLY the structured verdict.'
].join('\n');

phase('Investigate');
const results = await pipeline(
  args.hypotheses,
  // Stage callbacks receive (prevResult, originalItem, index) — in stage 1 the hypothesis
  // is the SECOND param; the default guards runtimes that seed prevResult with the item.
  (prev, h = prev) =>
    agent(
      `You are investigating ONE root-cause hypothesis for a bug in the repo at ${args.repoRoot}.
BUG: ${args.bug}
EVIDENCE SO FAR: ${args.evidence}
HYPOTHESIS ${h.id}: ${h.cause}
YOUR JOB — try to FALSIFY it: ${h.falsification}
Verdict contract: FALSIFIED only if you found the killing evidence (cite it). SURVIVED only if you actively hunted the killing evidence, it is absent, AND you traced a complete causal chain from this cause to the observed symptom. Otherwise INCONCLUSIVE.
${guardrails}
Set id to "${h.id}".`,
      { label: `investigate-${h.id}`, phase: 'Investigate', agentType: 'general-purpose', schema: verdictSchema }
    ),
  async (res, h) => {
    if (!res || res.verdict !== 'SURVIVED') return res;
    const xres = await agent(
      `A prior investigator claims this hypothesis SURVIVED falsification. Cross-examine it in the repo at ${args.repoRoot}.
BUG: ${args.bug}
HYPOTHESIS ${h.id}: ${h.cause}
INVESTIGATOR'S CAUSAL CHAIN: ${res.evidence}
Attack the chain: verify each cited file/claim yourself; look for a step that does not hold and for an alternative mechanism producing the same symptom. FALSIFIED if you break the chain (cite where), SURVIVED if it holds under attack, INCONCLUSIVE otherwise.
${guardrails}
Set id to "${h.id}".`,
      { label: `cross-examine-${h.id}`, phase: 'Cross-examine survivors', agentType: 'general-purpose', schema: verdictSchema }
    );
    // A dead cross-examiner must NOT erase a stage-1 SURVIVED: propagating null here would drop
    // the hypothesis from every bucket via filter(Boolean) and misreport "Survivors: none".
    return (
      xres || {
        id: h.id,
        verdict: 'INCONCLUSIVE',
        evidence: 'stage-1 SURVIVED but the cross-examiner did not complete — re-run cross-examination for this hypothesis',
        files: []
      }
    );
  }
);

phase('Synthesize');
const verdicts = results.filter(Boolean);
if (verdicts.length < args.hypotheses.length) {
  log(`WARNING: ${args.hypotheses.length - verdicts.length} stage-1 investigator(s) returned nothing — those hypotheses are unjudged, not falsified; re-run them before trusting the synthesis`);
}
const survivors = verdicts.filter((v) => v.verdict === 'SURVIVED');
const inconclusive = verdicts.filter((v) => v.verdict === 'INCONCLUSIVE');
log(`Survivors: ${survivors.map((s) => s.id).join(', ') || 'none'}; inconclusive: ${inconclusive.map((s) => s.id).join(', ') || 'none'}`);
return { survivors, inconclusive, all: verdicts };
```

Interpretation: exactly one survivor → root-cause candidate, proceed to Template 2. Multiple survivors → the falsification tests were too weak; design a discriminating experiment and re-run only those hypotheses. Zero survivors with inconclusives → sharpen those falsification tests or gather more Phase-2 evidence.

---

## Template 2 — Root-cause adversarial verification (perspective-diverse refuters)

**When to use:** Phase 4, when a single candidate survived and the fix is expensive enough (multi-file, risky area, money/permissions flow) that shipping a wrong cause would be costly. Uses `parallel` deliberately — the verdict is a majority vote, so it genuinely needs all refuters before deciding. **When NOT to use:** the candidate is trivially verifiable by reading one function yourself, or the fix is a one-liner you can validate by re-running the repro — the workflow ceremony would cost more than being wrong. Note: this template always runs all 4 lenses; the SKILL's pick-3-for-routine-bugs variant applies to direct Agent fan-out only — anything expensive enough to justify this template warrants all 4.

Invoke with args like:

```json
{
  "repoRoot": "/abs/path/to/repo",
  "rootCause": "the candidate cause, with the causal chain and file paths from Template 1",
  "symptoms": ["symptom A with exact error", "symptom B", "only one brand's users affected"],
  "proposedFixLocation": "file + function where the fix would go, and the intended change",
  "doNotTouch": [
    "the project's shared auth-state file (and never run the auth-setup project)"
  ]
}
```

```js
export const meta = {
  name: 'debug-root-cause-verify',
  description: 'Adversarial multi-lens verification of a root-cause candidate before fixing',
  phases: [{ title: 'Refute' }, { title: 'Verdict' }]
};

const refuteSchema = {
  type: 'object',
  required: ['lens', 'refuted', 'reasoning'],
  properties: {
    lens: { type: 'string' },
    refuted: { type: 'boolean', description: 'true = this lens breaks the candidate' },
    reasoning: { type: 'string', description: 'Evidence with absolute file paths; if refuted, the specific gap' },
    unexplainedSymptoms: { type: 'array', items: { type: 'string' } }
  }
};

const lenses = [
  { id: 'symptom-coverage', brief: 'Check EVERY listed symptom against the causal chain. Refute if any symptom cannot be produced by this cause — list it in unexplainedSymptoms.' },
  { id: 'timeline', brief: 'Use git log/blame to find when the causing code landed. Refute if the code predates the first report and nothing else (data, env, dependency, flag) changed to activate it.' },
  { id: 'alternative-mechanism', brief: 'Construct a DIFFERENT mechanism that produces the same symptoms, then check the code for it. Refute if a rival mechanism is at least as consistent with the evidence.' },
  { id: 'fix-location', brief: 'Assume the proposed fix is applied. Trace the data flow forward from the fix site to each symptom. Refute if any symptom would remain after the fix.' }
];

phase('Refute');
const common = `Repo: ${args.repoRoot}
ROOT-CAUSE CANDIDATE: ${args.rootCause}
OBSERVED SYMPTOMS: ${JSON.stringify(args.symptoms)}
PROPOSED FIX: ${args.proposedFixLocation}
You are a refuter. Your goal is to KILL this candidate, not to confirm it. Read the actual code; do not trust the candidate's summary.
Read-only: do NOT modify files. ${(args.doNotTouch || []).map((p) => `Do NOT touch ${p}.`).join(' ')} Return ONLY the structured verdict.`;

const refutations = (
  await parallel(
    lenses.map((lens) => () =>
      agent(`${common}\nYOUR LENS (${lens.id}): ${lens.brief}\nSet lens to "${lens.id}".`, {
        label: `refute-${lens.id}`,
        phase: 'Refute',
        agentType: 'general-purpose',
        schema: refuteSchema
      })
    )
  )
).filter(Boolean);

phase('Verdict');
if (refutations.length === 0) {
  log('No refuter returned a verdict — INCONCLUSIVE, re-run the refutation');
  return { verdict: 'INCONCLUSIVE', refutedBy: [], unexplainedSymptoms: [], note: 'no refuter completed — re-run before trusting the candidate' };
}
const kills = refutations.filter((r) => r.refuted);
// Half or more refuting kills the candidate (ties kill) — matches SKILL.md Phase 4.
const confirmed = kills.length * 2 < refutations.length;
log(`${kills.length}/${refutations.length} lenses refuted → ${confirmed ? 'CONFIRMED root cause' : 'KILLED — back to hypothesis fan-out'}`);
return {
  verdict: confirmed ? 'CONFIRMED' : 'KILLED',
  refutedBy: kills.map((k) => ({ lens: k.lens, reasoning: k.reasoning })),
  unexplainedSymptoms: refutations.flatMap((r) => r.unexplainedSymptoms || [])
};
```

Interpretation: `CONFIRMED` still means "survived attack", not "proven" — a single refuting lens with strong evidence deserves a manual look even when outvoted (read `refutedBy` before fixing). `KILLED` means half or more of the completed lenses refuted (a tie kills — doubt at that level means the cause isn't verified) → feed the refuters' reasoning back into Phase 3 as new evidence and re-run the fan-out with sharpened hypotheses. `INCONCLUSIVE` means no refuter completed — re-run the workflow; do not treat it as either verdict.
