# agent-skills

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

**Ticket conductors** (invoke each other, **under review**): `implement-feature` → `author-tests` → `validate-change` (+ `create-pr`); `debug-issue` cross-links all of them.

**Quality primitives** (replacements for Claude Code's built-in `code-review` / `verify` / `simplify`, usable in any harness): `adversarial-review`, `exercise-change`, `polish-code`. Conductors reference these names only.

**Test authoring**: `write-e2e-test` (Playwright specs, POMs, fixtures) and `unit-test` (Jest/RTL, Equivalence Partitioning) hold the per-layer methodology; `test-layer-review` decides placement for tests that already exist. `author-tests` sequences all three.

**Supporting**: `commit`, `create-pr`, `responsive-design`, `validate-in-browser`.

**Agents**: `figma-reader` (cost-isolated design reading), `playwright-qa` (cost-isolated browser QA; auth arrives via an injection block from the dispatching skill's overlay), `ui-design-reviewer` (7-category view review; conventions via injection block).

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
