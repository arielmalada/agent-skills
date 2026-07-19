#!/usr/bin/env bash
# Install/uninstall/verify symlinks for the agent-skills repo.
#
#   ./install.sh             install (idempotent, never overwrites real files)
#   ./install.sh --dry-run   show what would happen
#   ./install.sh --uninstall remove only symlinks that resolve into this repo
#   ./install.sh --verify    check symlinks + cross-skill reference targets + collisions
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CC_SKILLS="$HOME/.claude/skills"
CC_AGENTS="$HOME/.claude/agents"
OC_AGENTS="$HOME/.config/opencode/agent"

MODE="install"
case "${1:-}" in
  --dry-run) MODE="dry-run" ;;
  --uninstall) MODE="uninstall" ;;
  --verify) MODE="verify" ;;
  "") ;;
  *) echo "unknown flag: $1" >&2; exit 2 ;;
esac

points_into_repo() { # $1 = path; true if it's a symlink resolving inside $REPO
  [ -L "$1" ] && case "$(readlink -f "$1" 2>/dev/null || true)" in "$REPO"/*) return 0 ;; esac
  return 1
}

link_one() { # $1 = source (in repo), $2 = target
  local src="$1" dst="$2"
  if points_into_repo "$dst"; then
    echo "  ok      $dst (already ours)"
  elif [ -e "$dst" ] || [ -L "$dst" ]; then
    echo "  SKIP    $dst exists and is not ours — resolve manually" >&2
  elif [ "$MODE" = "dry-run" ]; then
    echo "  would   $dst -> $src"
  else
    ln -s "$src" "$dst"
    echo "  linked  $dst -> $src"
  fi
}

unlink_one() { # $1 = target
  if points_into_repo "$1"; then
    if [ "$MODE" = "dry-run" ]; then echo "  would remove $1"; else rm "$1"; echo "  removed $1"; fi
  fi
}

do_install() {
  echo "Claude Code skills -> $CC_SKILLS"
  mkdir -p "$CC_SKILLS"
  for d in "$REPO"/skills/*/; do
    link_one "${d%/}" "$CC_SKILLS/$(basename "$d")"
  done

  echo "Claude Code agents -> $CC_AGENTS"
  mkdir -p "$CC_AGENTS"
  for f in "$REPO"/agents/claude-code/*.md; do
    link_one "$f" "$CC_AGENTS/$(basename "$f")"
  done

  echo "opencode skills: nothing to do — opencode discovers ~/.claude/skills natively."

  echo "opencode agents -> $OC_AGENTS"
  mkdir -p "$OC_AGENTS"
  for f in "$REPO"/agents/opencode/*.md; do
    link_one "$f" "$OC_AGENTS/$(basename "$f")"
  done

  cat <<'EOF'

Manual checklist (not automated):
  - opencode MCP servers are configured separately in opencode.json
    (Figma, Playwright, translation tooling) — skills/agents STOP gracefully without them.
  - Per-project overlays (references/<project>-specifics.md) are local-only and
    not installed by this script — create them next to the skills that need them.
  - Prerequisite: gh CLI for the PR/review flows.
EOF
}

do_uninstall() {
  for d in "$REPO"/skills/*/; do unlink_one "$CC_SKILLS/$(basename "$d")"; done
  for f in "$REPO"/agents/claude-code/*.md; do unlink_one "$CC_AGENTS/$(basename "$f")"; done
  for f in "$REPO"/agents/opencode/*.md; do unlink_one "$OC_AGENTS/$(basename "$f")"; done
}

do_verify() {
  local fail=0

  echo "== symlinks resolve =="
  for d in "$REPO"/skills/*/; do
    t="$CC_SKILLS/$(basename "$d")"
    if points_into_repo "$t" && [ -r "$t/SKILL.md" ]; then echo "  ok $t"; else echo "  FAIL $t" >&2; fail=1; fi
  done
  for f in "$REPO"/agents/claude-code/*.md; do
    t="$CC_AGENTS/$(basename "$f")"
    if points_into_repo "$t" && [ -r "$t" ]; then echo "  ok $t"; else echo "  FAIL $t" >&2; fail=1; fi
  done
  for f in "$REPO"/agents/opencode/*.md; do
    t="$OC_AGENTS/$(basename "$f")"
    if points_into_repo "$t" && [ -r "$t" ]; then echo "  ok $t"; else echo "  FAIL $t" >&2; fail=1; fi
  done

  echo "== cross-skill reference targets =="
  # every "~/.claude/skills/<skill>/references/<file>" mentioned in repo docs must exist post-install
  while IFS= read -r ref; do
    p="${ref/#\~/$HOME}"
    if [ -r "$p" ]; then echo "  ok $ref"; else echo "  FAIL missing target: $ref" >&2; fail=1; fi
  done < <(grep -rhoE '~/\.claude/skills/[A-Za-z0-9._-]+/references/[A-Za-z0-9._-]+\.md' "$REPO"/skills "$REPO"/agents | sort -u)

  echo "== name collisions with a project (pass a repo path as \$PROJECT to check) =="
  if [ -n "${PROJECT:-}" ] && [ -d "$PROJECT/.claude/skills" ]; then
    for d in "$REPO"/skills/*/; do
      n="$(basename "$d")"
      [ -d "$PROJECT/.claude/skills/$n" ] && echo "  COLLISION: $n exists in both user skills and $PROJECT/.claude/skills"
    done
  else
    echo "  (skipped — set PROJECT=/path/to/repo)"
  fi

  [ "$fail" -eq 0 ] && echo "VERIFY: all good" || { echo "VERIFY: failures above" >&2; exit 1; }
}

case "$MODE" in
  install|dry-run) do_install ;;
  uninstall) do_uninstall ;;
  verify) do_verify ;;
esac
