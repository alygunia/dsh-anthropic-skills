#!/usr/bin/env bash
# Linux / macOS counterpart to scripts/link-user-skills.ps1.
#
# Links every skill in this repo's `anthropic-skills` submodule into the global
# DSH skill root, so every DSH profile and every project discovers them.
#
# DSH's filesystem skill provider scans `<DSH_HOME>/skills` (rank 400) among its
# default roots, and discovery is exactly one level deep: it only recognises
# `<root>/<name>/SKILL.md`. The submodule layout is already `skills/<name>/SKILL.md`,
# so one link per skill is what makes it visible — a single link to the whole
# `skills/` directory would sit one level too deep and be ignored.
#
# Symlinks (not copies) mean `git submodule update --remote` updates the live
# skills. Idempotent: existing entries are never overwritten.
set -euo pipefail

ROOT=""
DO_REMOVE=0
DRY_RUN=0

usage() {
  cat <<'EOF'
usage: link-user-skills.sh [--root <dir>] [--remove] [--dry-run]

  --root <dir>   destination skill root
                 (default: $DSH_HOME/skills, else ~/.dsh/skills)
  --remove       remove only the links this repo owns
  --dry-run, -n  report what would change without touching the filesystem

examples:
  ./scripts/link-user-skills.sh
  ./scripts/link-user-skills.sh --dry-run
  ./scripts/link-user-skills.sh --remove
  ./scripts/link-user-skills.sh --root /srv/shared/skills
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      if [ $# -lt 2 ]; then echo "error: --root needs a value" >&2; exit 2; fi
      ROOT="$2"; shift 2 ;;
    --remove) DO_REMOVE=1; shift ;;
    --dry-run|-n) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$REPO_ROOT/anthropic-skills/skills"

if [ ! -d "$SOURCE" ]; then
  echo "error: skill source not found: $SOURCE" >&2
  echo "run: git submodule update --init --recursive" >&2
  exit 1
fi

SOURCE_FULL="$(cd -- "$SOURCE" && pwd)"

if [ -z "$ROOT" ]; then
  ROOT="${DSH_HOME:-$HOME/.dsh}/skills"
fi

skills=()
for dir in "$SOURCE_FULL"/*/; do
  [ -f "$dir/SKILL.md" ] && skills+=("${dir%/}")
done

if [ "${#skills[@]}" -eq 0 ]; then
  echo "error: no <name>/SKILL.md found under $SOURCE_FULL" >&2
  exit 1
fi

if [ "$DO_REMOVE" -eq 0 ] && [ "$DRY_RUN" -eq 0 ] && [ ! -d "$ROOT" ]; then
  mkdir -p -- "$ROOT"
fi

created=0
removed=0
kept=0

for src in "${skills[@]}"; do
  name="$(basename -- "$src")"
  link="$ROOT/$name"

  if [ "$DO_REMOVE" -eq 1 ]; then
    if [ ! -L "$link" ]; then
      if [ -e "$link" ]; then echo "skip    $link (not a link into this repo)"; fi
      continue
    fi
    # Only ever remove links that resolve inside our submodule; never a real
    # directory of the user's own skills.
    resolved="$(readlink -f -- "$link" 2>/dev/null || true)"
    case "$resolved" in
      "$SOURCE_FULL"/*)
        if [ "$DRY_RUN" -eq 1 ]; then
          echo "remove  $link"
        else
          rm -- "$link"
          echo "removed $link"
        fi
        removed=$((removed + 1)) ;;
      *)
        echo "skip    $link (not a link into this repo)" ;;
    esac
    continue
  fi

  if [ -e "$link" ] || [ -L "$link" ]; then
    echo "keep    $link"
    kept=$((kept + 1))
    continue
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "create  $link -> $src"
    created=$((created + 1))
    continue
  fi

  ln -s -- "$src" "$link"
  echo "created $link -> $src"
  created=$((created + 1))
done

echo
echo "root    : $ROOT"
echo "source  : $SOURCE_FULL"
echo "skills  : ${#skills[@]}"
if [ "$DO_REMOVE" -eq 1 ]; then
  echo "removed : $removed"
else
  echo "created : $created, kept: $kept"
  echo
  echo "DSH picks these up without a restart: the provider watches the root and probes a"
  echo "missing root until it appears, then replaces the session catalog."
fi
