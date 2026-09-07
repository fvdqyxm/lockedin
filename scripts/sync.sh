#!/usr/bin/env bash
set -Eeuo pipefail

# Build only changed/new LaTeX sources, then stage, commit, and push.
# Compiled PDFs land next to their .tex files so they show up on GitHub.
# Intermediate build files are gitignored.
#
# The README is regenerated as a clickable index of COMPLETED work only:
# untouched lecture scaffolds, empty homework solutions, and unstarted
# solutions.tex files are detected by content and left out of the index.
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

# ---------- Regenerate README.md as a clickable index of COMPLETED work ----------
# Only finished documents are listed:
#   • lectures whose .tex no longer contains the scaffold placeholder
#   • homework solution files with real write-up content
#   • solutions.tex files with at least one uncommented \exercise{...}
# Scaffolds and unstarted files stay on disk but never appear in the index.
generate_readme() {
  local out="$REPO_ROOT/README.md"

  # Course registry: folder|label|long name|textbook
  local courses=(
    "math104|Math 104|Real Analysis|Ross, *Elementary Analysis* (2nd ed.)"
    "math110|Math 110|Abstract Linear Algebra|Axler, *Linear Algebra Done Right* (4th ed.)"
    "math113|Math 113|Abstract Algebra|Fraleigh, *A First Course in Abstract Algebra* (7th ed.)"
    "math118|Math 118|Fourier Analysis|Boggess & Narcowich, *A First Course in Wavelets with Fourier Analysis* (2nd ed.)"
    "stat150|Stat 150|Stochastic Processes|Durrett, *Essentials of Stochastic Processes* (3rd ed.)"
  )

  # A homework solutions file is "done" when its Solutions section contains
  # at least one substantive line (prose, math, anything the scaffold lacks).
  # Comments, headings, empty solution blocks, and scaffold structure do not
  # count. Hand-written files without the standard marker are assumed done.
  hw_is_done() {
    awk '
      BEGIN { in_sol = 0; filled = 0; saw_marker = 0 }
      /\\section\*\{Solutions\}/ { saw_marker = 1; in_sol = 1; next }
      /\\end\{document\}/        { in_sol = 0 }
      in_sol {
        line = $0
        gsub(/^[ \t]+|[ \t]+$/, "", line)
        if (line == "") next
        if (line ~ /^%/) next
        if (line ~ /^\\(subsubsection\*|begin\{(solution|originalproblem|Verbatim)\}|end\{(solution|originalproblem|Verbatim)\}|includepdf|clearpage)/) next
        filled++
      }
      END { exit ((saw_marker == 0 || filled > 0) ? 0 : 1) }
    ' "$1"
  }

  # solutions.tex is "started" once an exercise header or problem box is
  # actually present (the scaffold keeps them all commented out).
  solutions_is_started() {
    grep -Eq '^[[:space:]]*\\(exercise\{|begin\{problem\})' "$1"
  }

  # A lecture note is still a scaffold while its placeholder text survives.
  lecture_is_scaffold() {
    grep -q 'Write the one-sentence point of today' "$1"
  }

  plural() {
    if (( $1 == 1 )); then printf '%s' "$2"; else printf '%ss' "$2"; fi
  }

  local nav="" body=""
  local total_lec=0 total_hw=0 total_sol=0

  for entry in "${courses[@]}"; do
    IFS='|' read -r folder label longname textbook <<<"$entry"
    local course_dir="$REPO_ROOT/$folder"
    [[ -d "$course_dir" ]] || continue

    local section=""

    # Comprehensive solutions: listed only once real exercises exist.
    if [[ -f "$course_dir/solutions.tex" ]] && solutions_is_started "$course_dir/solutions.tex"; then
      local sol_links="Comprehensive solutions: [tex]($folder/solutions.tex)"
      [[ -f "$course_dir/solutions.pdf" ]] && sol_links="$sol_links · [pdf]($folder/solutions.pdf)"
      section+="$sol_links"$'\n\n'
      total_sol=$((total_sol + 1))
    fi

    # Lectures: skip untouched scaffolds.
    local lec_rows="" n_lec=0
    while IFS= read -r pdf; do
      [[ -n "$pdf" ]] || continue
      local base="${pdf##*/}"
      local num="${base#lecture_}"
      num="${num%.pdf}"
      local tex="lecture_${num}.tex"
      if [[ -f "$course_dir/lectures/$tex" ]] && lecture_is_scaffold "$course_dir/lectures/$tex"; then
        continue
      fi
      local row="| $num | [PDF]($folder/lectures/$base)"
      [[ -f "$course_dir/lectures/$tex" ]] && row="$row · [tex]($folder/lectures/$tex)"
      lec_rows+="$row |"$'\n'
      n_lec=$((n_lec + 1))
    done < <(find "$course_dir/lectures" -maxdepth 1 -name 'lecture_*.pdf' 2>/dev/null | sort)

    if [[ -n "$lec_rows" ]]; then
      section+="### Lectures"$'\n\n'
      section+='| # | Notes |'$'\n'
      section+='|---|-------|'$'\n'
      section+="$lec_rows"$'\n'
      total_lec=$((total_lec + n_lec))
    fi

    # Homework: only files with actual written solutions.
    local hw_rows="" n_hw=0
    while IFS= read -r sol_tex; do
      [[ -n "$sol_tex" ]] || continue
      hw_is_done "$sol_tex" || continue
      local base="${sol_tex##*/}"          # hw01_sol.tex
      local num="${base#hw}"
      num="${num%%_sol.tex}"               # 01
      local n=$((10#$num))                 # 1, 2, ...
      local sol_pdf="${base%.tex}.pdf"     # hw01_sol.pdf
      local assign_pdf="hw${num}.pdf"
      local assign_link="—"
      [[ -f "$course_dir/homework/$assign_pdf" ]] && assign_link="[assignment]($folder/homework/$assign_pdf)"
      [[ -f "$course_dir/homework/hw_packet.pdf" ]] && assign_link="[packet]($folder/homework/hw_packet.pdf)"
      local row="| $n | $assign_link | [tex]($folder/homework/$base)"
      [[ -f "$course_dir/homework/$sol_pdf" ]] && row="$row · [pdf]($folder/homework/$sol_pdf)"
      hw_rows+="$row |"$'\n'
      n_hw=$((n_hw + 1))
    done < <(find "$course_dir/homework" -maxdepth 1 -name 'hw*_sol.tex' 2>/dev/null | sort)

    if [[ -n "$hw_rows" ]]; then
      section+="### Homework"$'\n\n'
      section+='| HW | Assignment | My solutions |'$'\n'
      section+='|----|------------|--------------|'$'\n'
      section+="$hw_rows"$'\n'
      total_hw=$((total_hw + n_hw))
    fi

    # Course appears at all only when something is finished.
    [[ -n "$section" ]] || continue

    nav+="${nav:+ · }[$label](#$folder)"
    body+="<a id=\"$folder\"></a>"$'\n\n'
    body+="## $label — $longname"$'\n\n'
    body+="Textbook: $textbook"$'\n\n'
    body+="$section"
  done

  {
    printf '# fa26_books\n\n'
    printf 'LaTeX lecture notes, homework write-ups, and comprehensive solutions for Fall 2026.\n'
    printf 'Only completed work is indexed; every PDF opens right in your browser.\n\n'

    if [[ -n "$nav" ]]; then
      printf '**Jump to:** %s\n\n' "$nav"
    fi

    local -a stats=()
    (( total_lec > 0 )) && stats+=("**${total_lec}** $(plural "$total_lec" "lecture note")")
    (( total_hw  > 0 )) && stats+=("**${total_hw}** $(plural "$total_hw" "homework write-up")")
    (( total_sol > 0 )) && stats+=("**${total_sol}** $(plural "$total_sol" "solution manual")")
    if (( ${#stats[@]} > 0 )); then
      local stats_line
      printf -v stats_line '%s · ' "${stats[@]}"
      printf '%s\n\n' "${stats_line% · }"
    fi

    if [[ -z "$body" ]]; then
      printf '_Nothing finished yet — scaffolds and work in progress are not indexed._\n'
    else
      printf '%s' "$body"
    fi

    printf -- '---\n\n'

    printf '<details>\n<summary>Repository layout</summary>\n\n'
    printf '```text\n'
    printf 'fa26_books/\n'
    printf '├── *_textbook*.pdf          # course textbooks at the root\n'
    printf '├── math104/                 # one folder per course, e.g. math104\n'
    printf '│   ├── lectures/            #   lecture_NN.tex + lecture_NN.pdf\n'
    printf '│   ├── homework/            #   hwNN.pdf (assignment) + hwNN_sol.tex / .pdf\n'
    printf '│   └── solutions.tex        #   comprehensive per-chapter exercise solutions\n'
    printf '├── math110/ math113/ math118/ stat150/    # same shape\n'
    printf '├── practice/                # extra practice problems\n'
    printf '├── reference/               # LaTeX/vimtex cheatsheet\n'
    printf '└── scripts/\n'
    printf '    ├── new_lecture_note.sh  # scaffold a new lecture note\n'
    printf '    ├── new_homework.sh      # scaffold a homework solutions file\n'
    printf '    └── sync.sh              # build changed notes + commit & push\n'
    printf '```\n\n</details>\n\n'

    printf '<details>\n<summary>Workflow — scripts and solutions syntax</summary>\n\n'
    printf 'Create a new lecture note:\n\n'
    printf '```bash\n'
    printf './scripts/new_lecture_note.sh 118 3          # → math118/lectures/lecture_03.tex\n'
    printf './scripts/new_lecture_note.sh Math110 4      # → math110/lectures/lecture_04.tex\n'
    printf './scripts/new_lecture_note.sh stat150 2      # → stat150/lectures/lecture_02.tex\n'
    printf '```\n\n'
    printf 'Create a homework solutions file (problem count auto-detected from the\n'
    printf 'assignment PDF; a pasted list becomes the problem headers):\n\n'
    printf '```bash\n'
    printf './scripts/new_homework.sh 104 2              # → math104/homework/hw02_sol.tex\n'
    printf './scripts/new_homework.sh 113 4 -            # paste "1. Fraleigh Exercise 4.6" ... then Ctrl-D\n'
    printf './scripts/new_homework.sh Math110 14 6       # force 6 conventional problem slots\n'
    printf '```\n\n'
    printf 'Add a solved textbook exercise (per-course `solutions.tex`):\n\n'
    printf '```latex\n'
    printf '\\exercise{8.6}          %% header under the right chapter banner\n'
    printf '\\begin{solution}\n'
    printf '  ...your write-up...\n'
    printf '\\end{solution}\n'
    printf '```\n\n'
    printf 'A file appears in the index above only once it has real content —\n'
    printf 'scaffolds never show up.\n\n'
    printf 'Build changed notes and push:\n\n'
    printf '```bash\n'
    printf './scripts/sync.sh                    # builds only changed .tex, then commits & pushes\n'
    printf './scripts/sync.sh "Math 118 lec 3"   # custom commit message\n'
    printf './scripts/sync.sh --all              # force-rebuild everything\n'
    printf '```\n\n</details>\n'
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
