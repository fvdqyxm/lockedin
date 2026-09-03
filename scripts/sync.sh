#!/usr/bin/env bash
set -Eeuo pipefail

# Build only changed/new LaTeX sources, then stage, commit, and push.
# Compiled PDFs land next to their .tex files so they show up on GitHub.
# Intermediate build files are gitignored.
#
# Usage:
#   ./sync.sh                    # build changed files + commit & push
#   ./sync.sh "Math 118 lec 3"   # custom commit message
#   ./sync.sh --all              # force-rebuild everything, then commit & push

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
COMMIT_MESSAGE="Build and sync notes"
FORCE_ALL=0

if [[ "${1:-}" == "--all" ]]; then
  FORCE_ALL=1
  shift
fi
[[ $# -ge 1 ]] && COMMIT_MESSAGE="$1"

if ! command -v latexmk >/dev/null 2>&1; then
  printf 'latexmk not found. Install TeX Live (macOS: brew install --cask mactex-no-gui).\n' >&2
  exit 1
fi

cd "$REPO_ROOT"

# ---------- Figure out which .tex files to build ----------
TEX_FILES=()

if [[ "$FORCE_ALL" -eq 1 ]]; then
  while IFS= read -r f; do
    TEX_FILES+=("$f")
  done < <(find "$REPO_ROOT" \
    -type d -name build -prune -o \
    -type f -name '*.tex' -print | sort)
else
  # Modified tracked files (unstaged or staged) that are .tex.
  while IFS= read -r f; do
    TEX_FILES+=("$f")
  done < <(git diff --name-only HEAD -- '*.tex' | sort)
  # Untracked (new) .tex files not yet in git.
  while IFS= read -r f; do
    TEX_FILES+=("$f")
  done < <(git ls-files --others --exclude-standard -- '*.tex' | sort)
fi

if [[ ${#TEX_FILES[@]} -gt 0 ]]; then
  printf 'Building %d changed LaTeX file(s)...\n' "${#TEX_FILES[@]}"
  fail=0
  for tex in "${TEX_FILES[@]}"; do
    full="$REPO_ROOT/$tex"
    if latexmk -lualatex -interaction=nonstopmode -halt-on-error -cd "$full" >/tmp/sync_build.log 2>&1; then
      printf '  ok    %s\n' "$tex"
    else
      printf '  FAIL  %s\n' "$tex" >&2
      tail -n 20 /tmp/sync_build.log >&2
      fail=1
    fi
    latexmk -c -cd "$full" >/dev/null 2>&1 || true
  done

  if [[ "$fail" -ne 0 ]]; then
    printf '\nOne or more builds failed (see /tmp/sync_build.log). Aborting sync.\n' >&2
    exit 1
  fi
else
  printf 'No .tex files changed since last commit.\n'
fi

# ---------- Stage, commit, push ----------
git add -A

if git diff --cached --quiet; then
  printf '\nNothing new to commit.\n'
  exit 0
fi

printf '\nStaged changes:\n'
git diff --cached --stat

BRANCH="$(git branch --show-current)"
git commit -m "$COMMIT_MESSAGE"
if git remote get-url origin >/dev/null 2>&1; then
  git pull --rebase origin "$BRANCH"
  git push origin HEAD
  printf '\nPushed to origin/%s\n' "$BRANCH"
else
  printf '\nNo origin remote; committed locally only.\n'
fi
