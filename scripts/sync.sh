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

# ---------- Regenerate README.md as a clickable PDF index ----------
generate_readme() {
  local out="$REPO_ROOT/README.md"

  # Course registry: folder|label|long name
  local courses=(
    "math104|Math 104|Real Analysis"
    "math110|Math 110|Abstract Linear Algebra"
    "math113|Math 113|Abstract Algebra"
    "math118|Math 118|Fourier Analysis"
    "stat150|Stat 150|Stochastic Processes"
  )

  {
    printf '# fa26_books\n\n'
    printf 'LaTeX lecture notes and homework for Fall 2026. Click any PDF link below to read it right in your browser.\n\n'
    printf '## Notes index\n\n'

    for entry in "${courses[@]}"; do
      IFS='|' read -r folder label longname <<<"$entry"
      local course_dir="$REPO_ROOT/$folder"
      [[ -d "$course_dir" ]] || continue

      printf '### %s — %s\n\n' "$label" "$longname"

      # Lectures table
      local has_lectures=0
      while IFS= read -r pdf; do
        [[ -n "$pdf" ]] || continue
        if [[ "$has_lectures" -eq 0 ]]; then
          printf '| Lecture | PDF |\n|---------|-----|\n'
          has_lectures=1
        fi
        local base="${pdf##*/}"
        local num="${base#lecture_}"
        num="${num%.pdf}"
        printf '| Lecture %s | [PDF](%s/lectures/%s) |\n' "$num" "$folder" "$base"
      done < <(find "$course_dir/lectures" -maxdepth 1 -name 'lecture_*.pdf' 2>/dev/null | sort)

      # Homework table
      local has_hw=0
      while IFS= read -r sol_tex; do
        [[ -n "$sol_tex" ]] || continue
        if [[ "$has_hw" -eq 0 ]]; then
          printf '\n| Homework | Assignment | My solutions |\n|----------|------------|--------------|\n'
          has_hw=1
        fi
        local base="${sol_tex##*/}"          # hw01_sol.tex
        local num="${base#hw}"
        num="${num%%_sol.tex}"                # 01
        local n=$((10#$num))                  # 1, 2, ... 13
        local sol_pdf="${base%.tex}.pdf"      # hw01_sol.pdf
        local assign_pdf="hw${num}.pdf"
        local assign_link="—"
        [[ -f "$course_dir/homework/$assign_pdf" ]] && assign_link="[PDF]($folder/homework/$assign_pdf)"
        [[ -f "$course_dir/homework/hw_packet.pdf" ]] && assign_link="[packet]($folder/homework/hw_packet.pdf)"
        printf '| HW %s | %s | [.tex](%s/homework/%s) / [PDF](%s/homework/%s) |\n' \
          "$n" "$assign_link" "$folder" "$base" "$folder" "$sol_pdf"
      done < <(find "$course_dir/homework" -maxdepth 1 -name 'hw*_sol.tex' 2>/dev/null | sort)

      printf '\n'
    done

    printf -- '---\n\n'
    printf '## Layout\n\n'
    printf '```\n'
    printf 'fa26_books/\n'
    printf '├── math*_textbook.pdf        # textbooks at the root\n'
    printf '├── math104/\n'
    printf '│   ├── lectures/             # lecture_NN.tex + lecture_NN.pdf\n'
    printf '│   └── homework/             # hwNN.pdf (assignment) + hwNN_sol.tex / .pdf (my solutions)\n'
    printf '├── math110/  math113/  math118/  stat150/   # same shape\n'
    printf '├── practice/                 # extra practice problems\n'
    printf '├── reference/                # LaTeX/vimtex cheatsheet\n'
    printf '└── scripts/\n'
    printf '    ├── new_lecture_note.sh   # scaffold a new lecture note\n'
    printf '    └── sync.sh               # build changed notes + commit & push\n'
    printf '```\n\n'
    printf '## Workflow\n\n'
    printf 'Create a new lecture note:\n'
    printf '```bash\n'
    printf './scripts/new_lecture_note.sh 118 3          # → math118/lectures/lecture_03.tex\n'
    printf './scripts/new_lecture_note.sh Math110 4      # → math110/lectures/lecture_04.tex\n'
    printf './scripts/new_lecture_note.sh stat150 2      # → stat150/lectures/lecture_02.tex\n'
    printf '```\n\n'
    printf 'Build changed notes and push:\n'
    printf '```bash\n'
    printf './scripts/sync.sh                    # builds only changed .tex, then commits & pushes\n'
    printf './scripts/sync.sh "Math 118 lec 3"   # custom commit message\n'
    printf './scripts/sync.sh --all              # force-rebuild everything\n'
    printf '```\n'
  } > "$out"
}

printf '\nRegenerating README.md index...\n'
generate_readme

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
