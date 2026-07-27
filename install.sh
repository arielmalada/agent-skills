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
WINSYMLINK_FALLBACK=0
case "${1:-}" in
  --dry-run) MODE="dry-run" ;;
  --uninstall) MODE="uninstall" ;;
  --verify) MODE="verify" ;;
  "") ;;
  *) echo "unknown flag: $1" >&2; exit 2 ;;
esac

resolve_path() { # $1 = path; absolute resolved path. readlink -f is GNU-only (absent on stock macOS).
  if readlink -f / >/dev/null 2>&1; then
    readlink -f "$1" 2>/dev/null || true
  else
    local d b
    d="$(dirname "$1")" b="$(basename "$1")"
    [ -d "$d" ] || { echo ""; return; }
    echo "$(cd "$d" 2>/dev/null && pwd -P)/$b"
  fi
}

points_into_repo() { # $1 = path; true if it's a symlink resolving inside $REPO
  [ -L "$1" ] || return 1
  local tgt
  tgt="$(readlink "$1")"
  case "$tgt" in /*) ;; *) tgt="$(dirname "$1")/$tgt" ;; esac   # relative links resolve against the link's dir
  case "$(resolve_path "$tgt")" in "$REPO"/*) return 0 ;; esac
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
    if [ -L "$dst" ]; then
      echo "  linked  $dst -> $src"
    else
      # Git Bash / MSYS silently COPIES when native symlinks aren't enabled. A copy goes
      # stale the moment the repo changes, and --verify rejects it — fail loudly instead.
      echo "  COPIED (not linked) $dst — see the Windows note below" >&2
      WINSYMLINK_FALLBACK=1
    fi
  fi
}

unlink_one() { # $1 = target
  if points_into_repo "$1"; then
    if [ "$MODE" = "dry-run" ]; then echo "  would remove $1"; else rm "$1"; echo "  removed $1"; fi
  fi
}

do_install() {
  echo "Claude Code skills -> $CC_SKILLS"
  [ "$MODE" = "dry-run" ] || mkdir -p "$CC_SKILLS"
  for d in "$REPO"/skills/*/; do
    link_one "${d%/}" "$CC_SKILLS/$(basename "$d")"
  done

  echo "Claude Code agents -> $CC_AGENTS"
  [ "$MODE" = "dry-run" ] || mkdir -p "$CC_AGENTS"
  for f in "$REPO"/agents/claude-code/*.md; do
    link_one "$f" "$CC_AGENTS/$(basename "$f")"
  done

  echo "opencode skills: nothing to do — opencode discovers ~/.claude/skills natively."

  echo "opencode agents -> $OC_AGENTS"
  [ "$MODE" = "dry-run" ] || mkdir -p "$OC_AGENTS"
  for f in "$REPO"/agents/opencode/*.md; do
    link_one "$f" "$OC_AGENTS/$(basename "$f")"
  done

  if [ "$WINSYMLINK_FALLBACK" = "1" ]; then
    cat >&2 <<'EOF'

!! Windows: entries above were COPIED, not symlinked, so they will go stale and
   --verify will reject them. Git Bash needs native symlinks enabled:
     1. Enable Developer Mode (Settings > System > For developers), or run as admin
     2. export MSYS=winsymlinks:nativestrict
     3. ./install.sh --uninstall is NOT safe for copies — delete them by hand, then re-run
EOF
  fi

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

  echo "== cross-skill references resolve =="
  # Every backticked skill name a skill/agent invokes must be either a skill in this repo
  # or a declared external (supplied per-project via the overlay roster). Catches the
  # classic rot: a skill renamed here, its call sites left pointing at the old name.
  #
  # Externals are expected to be absent from this repo — keep this list in step with
  # README "External dependencies".
  externals="create-storybook-story ticket-fetch ac-verify feature-context"
  local_skills=""
  for d in "$REPO"/skills/*/; do local_skills="$local_skills $(basename "$d")"; done

  # Agents ship in this repo too, and get referenced by name the same way.
  for f in "$REPO"/agents/claude-code/*.md; do local_skills="$local_skills $(basename "$f" .md)"; done
  # Backticked hyphenated tokens that are markup, not skills. Keep on ONE line:
  # the membership test below matches on surrounding spaces, and a newline is not one.
  notskills="aria-disabled aria-hidden aria-label aria-live data-phone data-state data-testid line-clamp overflow-ellipsis"

  local found=0
  while IFS='|' read -r f name; do
    [ -n "$name" ] || continue
    case " $notskills " in *" $name "*) continue ;; esac
    found=$((found + 1))
    case " $local_skills " in *" $name "*) continue ;; esac
    case " $externals " in *" $name "*) continue ;; esac
    echo "  FAIL unknown skill \`$name\` referenced in ${f#"$REPO"/}" >&2; fail=1
  done < <(grep -rHoE '`[a-z][a-z0-9]+-[a-z0-9-]+`' --include='*.md' \
             "$REPO"/skills "$REPO"/agents 2>/dev/null \
           | sed -E 's/^(.*):[^`]*`([a-z][a-z0-9-]+)`.*$/\1|\2/' | sort -u)
  echo "  checked $found hyphenated skill/agent reference(s) against this repo + declared externals"

  echo "== retired names absent =="
  # Names this repo used to use. A rename is only done when every call site moved,
  # and single-word names (`verify`) are invisible to the pattern check above.
  # Format: oldname:replacement
  for pair in code-review:adversarial-review verify:exercise-change simplify:polish-code \
              playwright-qa-validate:validate-in-browser useIsXs:useIsPhone; do
    old="${pair%%:*}" new="${pair##*:}"
    # A line may name a retired name deliberately (explaining why it was retired, or warning
    # about a name-alike shell command). Mark those with retired-name-ok to opt out.
    hits="$(grep -rnF "\`$old\`" --include='*.md' "$REPO"/skills "$REPO"/agents 2>/dev/null \
            | grep -vF 'retired-name-ok' || true)"
    if [ -n "$hits" ]; then
      echo "  FAIL retired name \`$old\` still referenced — use \`$new\`" >&2
      echo "$hits" | sed "s|$REPO/|    |" >&2
      fail=1
    else
      echo "  ok \`$old\` gone (-> \`$new\`)"
    fi
  done

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
