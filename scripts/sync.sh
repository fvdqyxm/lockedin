#!/usr/bin/env bash
set -Eeuo pipefail

# Build only changed/new LaTeX sources, then stage, commit, and push.
# Compiled PDFs land next to their .tex files so they show up on GitHub.
# Intermediate build files are gitignored.
#
# The README is regenerated as a clickable index: every lecture and homework
# file on disk is listed (unwritten ones are marked, not hidden — a lecture
# counts as written as soon as its body differs from the generator template);
# solutions.tex files appear once they have real content.
#
# After the notes repo is synced, the nvim config repo (~/.config/nvim) is
# committed and pushed too, so editor changes travel with the notes.
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
  # Skip paths that no longer exist on disk (deleted or renamed-away files):
  # latexmk would fail on them and abort the whole sync.
  while IFS= read -r f; do
    [[ -f "$REPO_ROOT/$f" ]] || continue
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
    elif latexmk -lualatex -interaction=nonstopmode -halt-on-error -g -cd "$full" >/tmp/sync_build.log 2>&1; then
      # -g forces a run: recovers from a stale error remembered by a previous
      # (e.g. editor) build of an unchanged file.
      printf '  ok    %s (forced retry)\n' "$tex"
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

# ---------- Regenerate README.md as a clickable index ----------
# Every lecture on disk is listed with clickable PDF/tex links; unwritten
# scaffolds are marked "not yet written" instead of hidden. The index
# regenerates on every sync, and lecture numbering just keeps iterating
# (lecture_05, lecture_10, ...), so rows sort numerically.
# Homework solution files and solutions.tex appear only with real content.
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

  # The untouched scaffold body, extracted from the generator itself (the
  # template's document body contains no shell variables, so it compares raw).
  local template_body
  template_body="$(sed -n '/\\begin{document}/,/\\end{document}/p' \
    "$REPO_ROOT/scripts/new_lecture_note.sh" \
    | sed -E 's/^[ \t]+//;s/[ \t]+$//' | grep -v '^$')"

  # A lecture is an unwritten scaffold ONLY if its document body is still the
  # untouched template (modulo whitespace). Notes that kept leftover
  # placeholder sections — even commented-out ones — count as written.
  lecture_is_scaffold() {
    diff <(printf '%s\n' "$template_body") \
         <(sed -n '/\\begin{document}/,/\\end{document}/p' "$1" \
           | sed -E 's/^[ \t]+//;s/[ \t]+$//' | grep -v '^$') >/dev/null 2>&1
  }

  plural() {
    if (( $1 == 1 )); then printf '%s' "$2"; else printf '%ss' "$2"; fi
  }

  local nav="" body=""
  local total_lec=0 total_scaf=0 total_hw=0 total_sol=0

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

    # Lectures: list EVERY lecture on disk (.tex or .pdf), clickable, with
    # unwritten scaffolds marked rather than hidden. Numbers iterate
    # indefinitely, so collect the union of tex/pdf numbers and sort
    # numerically (02 < 10) rather than lexicographically.
    local lec_rows="" n_lec=0 n_scaf=0
    while IFS= read -r num; do
      [[ -n "$num" ]] || continue
      local tex="lecture_${num}.tex"
      local pdf="lecture_${num}.pdf"
      local notes=""
      [[ -f "$course_dir/lectures/$pdf" ]] && notes="[PDF]($folder/lectures/$pdf)"
      [[ -f "$course_dir/lectures/$tex" ]] && notes="${notes:+$notes · }[tex]($folder/lectures/$tex)"
      if [[ -f "$course_dir/lectures/$tex" ]] && lecture_is_scaffold "$course_dir/lectures/$tex"; then
        notes="${notes:+$notes · }*not yet written*"
        n_scaf=$((n_scaf + 1))
      else
        n_lec=$((n_lec + 1))
      fi
      lec_rows+="| $num | $notes |"$'\n'
    done < <(find "$course_dir/lectures" -maxdepth 1 \( -name 'lecture_*.tex' -o -name 'lecture_*.pdf' \) 2>/dev/null \
             | sed -E 's@.*/lecture_([0-9]+)\.(tex|pdf)$@\1@' | sort -u | sort -n)

    if [[ -n "$lec_rows" ]]; then
      section+="### Lectures"$'\n\n'
      section+='| # | Notes |'$'\n'
      section+='|---|-------|'$'\n'
      section+="$lec_rows"$'\n'
      total_lec=$((total_lec + n_lec))
      total_scaf=$((total_scaf + n_scaf))
    fi

    # Homework: index EVERY homework on disk — solution files (hwNN_sol.tex)
    # and bare assignment PDFs alike. Unwritten solution scaffolds are marked
    # rather than hidden. Numbers iterate (hw03, hw10, ...), so collect the
    # union of numbers and sort numerically.
    local hw_rows="" n_hw_done=0
    while IFS= read -r n; do
      [[ -n "$n" ]] || continue
      local num
      printf -v num '%02d' "$n"
      # solution file (padded or bare numbering)
      local cand sol_tex="" assign_pdf=""
      for cand in "hw${num}_sol.tex" "hw${n}_sol.tex"; do
        [[ -f "$course_dir/homework/$cand" ]] && sol_tex="$cand" && break
      done
      # assignment pdf (mixed naming on disk: hw02.pdf, hw2.pdf, HW2.pdf)
      for cand in "hw${num}.pdf" "hw${n}.pdf" "HW${num}.pdf" "HW${n}.pdf"; do
        [[ -f "$course_dir/homework/$cand" ]] && assign_pdf="$cand" && break
      done
      local assign_link="—"
      [[ -n "$assign_pdf" ]] && assign_link="[assignment]($folder/homework/$assign_pdf)"
      [[ -f "$course_dir/homework/hw_packet.pdf" ]] && assign_link="[packet]($folder/homework/hw_packet.pdf)"
      local sol_links="—" written=0
      if [[ -n "$sol_tex" ]]; then
        sol_links="[tex]($folder/homework/$sol_tex)"
        local sol_pdf="${sol_tex%.tex}.pdf"
        [[ -f "$course_dir/homework/$sol_pdf" ]] && sol_links="$sol_links · [pdf]($folder/homework/$sol_pdf)"
        if hw_is_done "$course_dir/homework/$sol_tex"; then
          written=1
        else
          sol_links="$sol_links · *not yet written*"
        fi
      fi
      (( written )) && n_hw_done=$((n_hw_done + 1))
      hw_rows+="| $n | $assign_link | $sol_links |"$'\n'
    done < <(find "$course_dir/homework" -maxdepth 1 \
               \( -name 'hw*_sol.tex' \
                  -o \( -name 'hw[0-9]*.pdf' ! -name '*_sol.pdf' \) \
                  -o \( -name 'HW[0-9]*.pdf' ! -name '*_sol.pdf' \) \) 2>/dev/null \
             | sed -E -e 's@.*/hw0*([0-9]+)_sol\.tex$@\1@' \
                      -e 's@.*/[hH][wW]0*([0-9]+)\.pdf$@\1@' \
             | sort -u | sort -n)

    if [[ -n "$hw_rows" ]]; then
      section+="### Homework"$'\n\n'
      section+='| HW | Assignment | My solutions |'$'\n'
      section+='|----|------------|--------------|'$'\n'
      section+="$hw_rows"$'\n'
      total_hw=$((total_hw + n_hw_done))
    fi

    # Course appears whenever anything exists on disk for it.
    [[ -n "$section" ]] || continue

    nav+="${nav:+ · }[$label](#$folder)"
    body+="<a id=\"$folder\"></a>"$'\n\n'
    body+="## $label — $longname"$'\n\n'
    # Textbook: cite it, and link every root <course>_textbook*.pdf so the
    # book itself is clickable from the README.
    local tb_links="" tb
    for tb in "$REPO_ROOT"/${folder}_textbook*.pdf; do
      [[ -f "$tb" ]] || continue
      local tb_base="${tb##*/}"
      tb_links="${tb_links:+$tb_links · }[PDF](${tb_base})"
    done
    body+="Textbook: $textbook${tb_links:+ · $tb_links}"$'\n\n'
    body+="$section"
  done

  {
    printf '# fa26_books\n\n'
    printf 'LaTeX lecture notes, homework write-ups, and comprehensive solutions for Fall 2026.\n'
    printf 'Every lecture and homework is indexed — unwritten files are\n'
    printf 'marked — and every PDF opens right in your browser.\n\n'

    if [[ -n "$nav" ]]; then
      printf '**Jump to:** %s\n\n' "$nav"
    fi

    local -a stats=()
    (( total_lec > 0 )) && stats+=("**${total_lec}** $(plural "$total_lec" "lecture note")")
    (( total_scaf > 0 )) && stats+=("**${total_scaf}** $(plural "$total_scaf" "unstarted scaffold")")
    (( total_hw  > 0 )) && stats+=("**${total_hw}** $(plural "$total_hw" "homework write-up")")
    (( total_sol > 0 )) && stats+=("**${total_sol}** $(plural "$total_sol" "solution manual")")
    if (( ${#stats[@]} > 0 )); then
      local stats_line
      printf -v stats_line '%s · ' "${stats[@]}"
      printf '%s\n\n' "${stats_line% · }"
    fi

    # Latest review plan (dated filenames sort chronologically).
    local latest_review_pdf rv_links
    latest_review_pdf="$(find "$REPO_ROOT/review" -maxdepth 1 -name 'to_review_*.pdf' 2>/dev/null | sort | tail -n 1)"
    if [[ -n "$latest_review_pdf" ]]; then
      local rv_base="${latest_review_pdf##*/}"
      local rv_tex="${rv_base%.pdf}.tex"
      rv_links="[PDF](review/$rv_base)"
      [[ -f "$REPO_ROOT/review/$rv_tex" ]] && rv_links="$rv_links · [tex](review/$rv_tex)"
      printf '**Latest review plan:** %s\n\n' "$rv_links"
    fi

    if [[ -z "$body" ]]; then
      printf '_Nothing on disk yet — create files with the scripts and they appear here._\n'
    else
      printf '%s' "$body"
    fi

    # One-off extras: practice problems and reference sheets.
    local extras="" x
    while IFS= read -r x; do
      [[ -n "$x" ]] || continue
      local xb="${x##*/}"
      local xd="$(dirname "$x")"; xd="${xd##*/}"
      extras+="- [${xb%.pdf}]($xd/$xb)"$'\n'
    done < <(find "$REPO_ROOT/practice" "$REPO_ROOT/reference" -maxdepth 1 -name '*.pdf' 2>/dev/null | sort)
    if [[ -n "$extras" ]]; then
      printf '## Practice & reference\n\n%s\n' "$extras"
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
    printf '├── review/                  # dated to-review study plans\n'
    printf '└── scripts/\n'
    printf '    ├── new_lecture_note.sh  # scaffold a new lecture note\n'
    printf '    ├── new_homework.sh      # scaffold a homework solutions file\n'
    printf '    └── sync.sh              # build changed notes + commit & push (also syncs the nvim config repo)\n'
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
    printf 'Every `lecture_NN` and `hwNN_sol.tex` shows up in the index as soon as\n'
    printf 'it exists on disk (unwritten ones are marked); `solutions.tex` appears\n'
    printf 'once it has real content. The index regenerates on every sync.\n\n'
    printf 'Build changed notes and push:\n\n'
    printf '```bash\n'
    printf './scripts/sync.sh                    # builds only changed .tex, then commits & pushes\n'
    printf './scripts/sync.sh "Math 118 lec 3"   # custom commit message\n'
    printf './scripts/sync.sh --all              # force-rebuild everything\n'
    printf '```\n\n'
    printf 'Every `sync.sh` run also commits and pushes the nvim config repo\n'
    printf '(`~/.config/nvim`), so editor changes travel with the notes.\n\n</details>\n'
  } > "$out"
}

printf '\nRegenerating README.md index...\n'
generate_readme

# ---------- Stage, commit, push ----------
git add -A

committed=0
if git diff --cached --quiet; then
  printf '\nNothing new to commit in the notes repo.\n'
else
  printf '\nStaged changes:\n'
  git diff --cached --stat
  git commit -m "$COMMIT_MESSAGE"
  committed=1
fi

# Push everything committed — including commits a previous run left unpushed
# (e.g. a failed push). With nothing to push git just says up-to-date.
BRANCH="$(git branch --show-current)"
if git remote get-url origin >/dev/null 2>&1; then
  if ! git pull --rebase origin "$BRANCH"; then
    printf '\nNotes repo: git pull --rebase hit a conflict.\n' >&2
    printf 'Fix it with: git status  (edit the files)  git add -A  git rebase --continue\n' >&2
    printf 'then re-run sync.sh — it will finish the push.\n' >&2
    exit 1
  fi
  git push origin HEAD
  printf '\nPushed to origin/%s\n' "$BRANCH"
elif (( committed )); then
  printf '\nNo origin remote; committed locally only.\n'
fi

# ---------- Also sync the nvim config repo ----------
NVIM_REPO="$HOME/.config/nvim"

if ! git -C "$NVIM_REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf '\nnvim config: not a git repo; skipping.\n'
else
  nvim_committed=0
  if git -C "$NVIM_REPO" diff --quiet >/dev/null 2>&1 \
    && git -C "$NVIM_REPO" diff --cached --quiet >/dev/null 2>&1 \
    && [[ -z "$(git -C "$NVIM_REPO" ls-files --others --exclude-standard)" ]]; then
    printf '\nnvim config: no new changes.\n'
  else
    printf '\nSyncing nvim config repo (%s)...\n' "$NVIM_REPO"
    git -C "$NVIM_REPO" add -A
    git -C "$NVIM_REPO" commit -m "$COMMIT_MESSAGE"
    nvim_committed=1
  fi
  if git -C "$NVIM_REPO" remote get-url origin >/dev/null 2>&1; then
    NVIM_BRANCH="$(git -C "$NVIM_REPO" branch --show-current)"
    if ! git -C "$NVIM_REPO" pull --rebase origin "$NVIM_BRANCH"; then
      printf '\nnvim config: git pull --rebase hit a conflict.\n' >&2
      printf 'Fix it in %s: git status  (edit)  git add -A  git rebase --continue\n' "$NVIM_REPO" >&2
      printf 'then re-run sync.sh — it will finish the push.\n' >&2
      exit 1
    fi
    git -C "$NVIM_REPO" push origin HEAD
    printf 'Pushed nvim config to origin/%s\n' "$NVIM_BRANCH"
  elif (( nvim_committed )); then
    printf 'nvim config: no origin remote; committed locally only.\n'
  fi
fi
