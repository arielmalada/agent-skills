# essentials web development agent-skills

Personal agent skills and subagent definitions, usable from both **Claude Code** and **opencode**. All content in this repo is project-agnostic; anything project-specific lives in local-only overlay files that are never committed (see below).

## Layout

```
skills/<name>/SKILL.md              14 skills (frontmatter: name + description only — portable)
skills/<name>/references/           generic reference material + Claude-Code-only Workflow templates
agents/claude-code/*.md             3 subagent definitions (~/.claude/agents format)
agents/opencode/*.md                the same agents in opencode format (mode: subagent)
```

## The overlay pattern (keeps this repo generic)

Skill bodies carry methodology only and refer to project facts by **role** ("the project's ticket-fetch skill", "the formatter gate", "the browser-QA injection block"). The concrete names, commands, URLs, and traps for a given project live in a **local overlay**: `skills/<skill>/references/<project>-specifics.md` (and optionally `skills/<skill>/examples/`), created on the machine where that project lives.

- Overlays are **gitignored** (`skills/*/references/*-specifics.md`, `skills/*/examples/`) — they must never be committed.
- Each overlay should carry: a skill/agent **roster** (role → concrete name), verified commands + traps, env tables, and any injection blocks the skills say to embed in subagent dispatches.
- Skills degrade gracefully without an overlay: they say so and derive equivalents from the project's own rules files.
- Keep one **canonical copy** per fact cluster across overlays (e.g. browser-QA login block in the `validate-in-browser` overlay; verification-command traps in the `validate-change` overlay) and point at it from the others — duplicate facts rot.

## The skills

Every skill stands alone — the conductors are just pre-wired sequences over the smaller ones. **Start with the single-purpose skills**: they are cheaper, they compose in any order you like, and they are the ones worth cherry-picking into an existing setup. Reach for a conductor only when you want the whole pipeline run for you.

### Test authoring — start here

- `write-e2e-test` — authoring a new Playwright spec, POM, or fixture: the e2e-vs-lower-layer gate, suite reconnaissance, selector hierarchy, API-first seeding, wait discipline, flake smells.
- `unit-test` — Jest / RTL tests via Equivalence Partitioning; focused cases instead of coverage-chasing.
- `test-layer-review` — tests that **already exist**: are they at the right layer (unit / integration / e2e)?
- `author-tests` — conductor: runs the test gate, sequences the three above, then adversarially checks each test would actually catch its regression.

### Supporting — small, high-frequency, safe to adopt on their own

- `commit` — conventional commits; one commit per completed plan-mode task.
- `create-pr` — create or update a PR via `gh`, with issue-tracker linking and reviewers.
- `responsive-design` — React + MUI/Emotion across phone / tablet / desktop: which layer (sx vs hook vs prop), which hook, which test surface.
- `validate-in-browser` — live-browser QA that delegates the driving to the cost-isolated `playwright-qa` subagent, keeping page snapshots out of the main context.

### Quality primitives

Drop-in replacements for Claude Code's built-in `code-review` / `verify` / `simplify`, usable in any harness. Conductors reference these by name only.

- `adversarial-review` — hunt correctness bugs in a diff; every finding is verified before it is reported.
- `exercise-change` — prove the change works at runtime with the cheapest faithful driver.
- `polish-code` — behaviour-preserving cleanup pass over changed code; applies the safe wins.

### Conductors (invoke each other)

- `implement-feature` → `author-tests` → `validate-change` (+ `create-pr`) — feature ticket to PR.
- `validate-change` — AC matrix, adversarial review, verification gates, honest report.
- `debug-issue` — reproduce-first root-causing; cross-links all of the above.

### Agents

- `figma-reader` — cost-isolated design reading.
- `playwright-qa` — cost-isolated browser QA; auth arrives via an injection block from the dispatching skill's overlay.
- `ui-design-reviewer` — 7-category view review; conventions via injection block.

## External dependencies

The conductors reference some skills by role that are expected to exist per project (ticket-fetch, AC-verify, e2e-run, story-authoring, translation tooling). Their concrete names go in each project's overlay roster; without them the skills fall back to doing the work inline. 

## Install

Just copy and paste, or ask your agent to install it for you

## Harness matrix

| Capability | Claude Code | opencode |
| --- | --- | --- |
| Skills (SKILL.md, name+description frontmatter) | native | native (reads `~/.claude/skills`) |
| Skill-to-skill invocation | Skill tool | native `skill` tool |
| Subagents / per-dispatch model routing | Agent tool (`model:`) | task tool + agent definitions (model fixed per agent) |
| Workflow tool (`references/workflow-templates.md`) | yes (opt-in) | no — reuse embedded prompts manually |
| Plan mode gate | EnterPlanMode | user-toggled plan mode; present plan as text |
| MCP tool naming | `mcp__<server>__<tool>` | `<server>_<tool>` (configured name) — skills refer to tools by intent/base name |
