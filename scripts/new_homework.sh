#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  printf 'Usage: %s COURSE HOMEWORK_NUMBER [PROBLEM_COUNT | LIST]\n' "$(basename "$0")" >&2
  printf 'Create <course>/homework/hwNN_sol.tex scaffolded with problem slots.\n' >&2
  printf 'COURSE may be a number (118), a slug (math118, stat150), or spelled out (Math 118, Stat 150).\n' >&2
  printf '\n' >&2
  printf 'PROBLEM_COUNT: optional; auto-detected from the assignment PDF otherwise.\n' >&2
  printf '\n' >&2
  printf 'LIST: paste a numbered problem list (Fraleigh-style) and it becomes the\n' >&2
  printf 'headers verbatim. Use - to paste on the terminal, or pass a file:\n' >&2
  printf '  %s 113 4 -        # paste "1. Fraleigh Exercise 4.6" ... then Ctrl-D\n' "$(basename "$0")" >&2
  printf '  %s 113 4 list.txt\n' "$(basename "$0")" >&2
  printf '\n' >&2
  printf 'Examples:\n' >&2
  printf '  %s 104 2          # → math104/homework/hw02_sol.tex (conventional Problem N)\n' "$(basename "$0")" >&2
  printf '  %s Math110 14 6   # → math110/homework/hw14_sol.tex (force 6 problems)\n' "$(basename "$0")" >&2
}

if [[ $# -lt 2 || $# -gt 3 ]]; then
  usage
  exit 2
fi

course_input="$1"
hw_number="$2"
list_source=""

if [[ ! "$hw_number" =~ ^[0-9]+$ ]]; then
  printf 'Homework number must be an integer: %s\n' "$hw_number" >&2
  exit 2
fi
if [[ $# -ge 3 ]]; then
  if [[ "$3" =~ ^[0-9]+$ ]]; then
    if [[ "$3" -eq 0 ]]; then
      printf 'Problem count must be a positive integer: %s\n' "$3" >&2
      exit 2
    fi
  else
    list_source="$3"
  fi
fi

# ---------- Course registry ----------
# Maps a course number to: folder, human-readable label, and long name.
# Keep in sync with new_lecture_note.sh and sync.sh.
course_folder=""
course_label=""
course_name=""
register() {
  local num="$1" folder="$2" label="$3" name="$4"
  printf '%s\t%s\t%s\t%s\n' "$num" "$folder" "$label" "$name"
}

COURSES="$(register 104 math104 "Math 104"  "Real Analysis")"
COURSES+="$(printf '\n%s' "$(register 110 math110 "Math 110" "Abstract Linear Algebra")")"
COURSES+="$(printf '\n%s' "$(register 113 math113 "Math 113" "Abstract Algebra")")"
COURSES+="$(printf '\n%s' "$(register 118 math118 "Math 118" "Fourier Analysis")")"
COURSES+="$(printf '\n%s' "$(register 150 stat150 "Stat 150" "Stochastic Processes")")"

# Normalise the input to a bare course number (digits only).
course_num="$(printf '%s' "$course_input" | tr -cd '[:digit:]')"

if [[ -z "$course_num" ]]; then
  printf 'Could not read a course number from: %s\n' "$course_input" >&2
  exit 2
fi

while IFS=$'\t' read -r num folder label name; do
  if [[ "$num" == "$course_num" ]]; then
    course_folder="$folder"
    course_label="$label"
    course_name="$name"
    break
  fi
done <<<"$COURSES"

# Fallback for an unregistered course: infer the subject from the input.
if [[ -z "$course_folder" ]]; then
  if printf '%s' "$course_input" | grep -qi 'stat'; then
    course_folder="stat${course_num}"
    course_label="Stat ${course_num}"
  else
    course_folder="math${course_num}"
    course_label="Math ${course_num}"
  fi
  course_name="$course_label"
fi

hw_padded="$(printf '%02d' "$((10#$hw_number))")"
hw_dir="$REPO_ROOT/$course_folder/homework"
target="$hw_dir/hw${hw_padded}_sol.tex"

if [[ -e "$target" ]]; then
  printf 'Already exists: %s\n' "$target" >&2
  exit 1
fi

mkdir -p "$hw_dir"

# ---------- Assignment PDF ----------
# Prefer a standalone assignment (hw02.pdf / HW2.pdf / ...). The lookup is
# case-SENSITIVE (via find) so the includepdf name matches the repo exactly,
# even on macOS's case-insensitive filesystem. Packet-based courses get a
# TODO comment to fill in the page range by hand.
assign_pdf=""
if [[ -d "$hw_dir" ]]; then
  found="$(find "$hw_dir" -maxdepth 1 -type f \
    \( -name "hw${hw_padded}.pdf" -o -name "hw${hw_number}.pdf" \
    -o -name "HW${hw_padded}.pdf" -o -name "HW${hw_number}.pdf" \) \
    -print -quit 2>/dev/null || true)"
  [[ -n "$found" ]] && assign_pdf="${found##*/}"
fi

assign_include=""
if [[ -n "$assign_pdf" ]]; then
  assign_include='\includepdf[pages=-,pagecommand={\thispagestyle{empty}}]{'"$assign_pdf"'}'
  assign_include+=$'\n\\clearpage'
elif [[ -f "$hw_dir/hw_packet.pdf" ]]; then
  assign_include='% TODO: this course uses hw_packet.pdf for all assignments.'
  assign_include+=$'\n% Fill in the page range for this homework, then uncomment:'
  assign_include+=$'\n% \\includepdf[pages=1-2,pagecommand={\\thispagestyle{empty}}]{hw_packet.pdf}'
  assign_include+=$'\n% \\clearpage'
fi

# ---------- Problem count ----------
# ---------- Problem records ----------
# A record is "num<TAB>title" per problem; the title may be empty
# (→ conventional "Problem N" slot). Sources, in priority order:
#   1. an explicit count argument  → conventional slots only
#   2. a pasted list (stdin '-' or a file) → titles kept verbatim
#      (perfect for Fraleigh-style "1. Fraleigh Exercise 4.6" lists)
#   3. the standalone assignment PDF → only reference-like titles are kept
#      ("Fraleigh Exercise 4.6", "LADR §2A, Exercise 11."); long problem
#      statements are dropped, so 104/118-style assignments stay conventional
#   4. this homework's section of hw_packet.pdf (same reference rule)
# Sub-lists inside a problem are ignored (first occurrence of each number wins).
collect_problem_records() {
  # $1 = text, $2 = max title length, $3 = refonly (0/1)
  printf '%s\n' "$1" | awk -v maxtitle="$2" -v refonly="$3" '
    {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      num = ""
      title = ""
      if (match(line, /^[0-9]+[.)][[:space:]]+/)) {
        num = substr(line, 1, RLENGTH)
        gsub(/[^0-9]/, "", num)
        title = substr(line, RLENGTH + 1)
      } else if (match(line, /^(Problem|Exercise)[[:space:]]*\(?[0-9]+\)?/)) {
        head = substr(line, 1, RLENGTH)
        num = head
        gsub(/[^0-9]/, "", num)
        title = substr(line, RLENGTH + 1)
        sub(/^[.)]?[[:space:]]*/, "", title)
      }
      if (num == "" || seen[num]++) next
      if (refonly == 1 && title !~ /(Exercise|§|p\. ?[0-9]|page ?[0-9])/) title = ""
      if (length(title) > maxtitle) title = ""
      printf "%s\t%s\n", num, title
    }
  '
}

# Just this homework's section of hw_packet.pdf.
packet_section_text() {
  command -v pdftotext >/dev/null 2>&1 || return 1
  pdftotext "$1" - 2>/dev/null | awk -v want="$2" '
    BEGIN { in_hw = 0 }
    /^[[:space:]]*Homework[[:space:]]+[0-9]+/ {
      n = $0
      sub(/^[[:space:]]*Homework[[:space:]]+/, "", n)
      sub(/[^0-9].*$/, "", n)
      in_hw = (n == want) ? 1 : 0
      next
    }
    in_hw { print }
  '
}

pdf_text() {
  command -v pdftotext >/dev/null 2>&1 || return 1
  pdftotext "$1" - 2>/dev/null || return 1
}

# Escape LaTeX specials in a pasted title.
latex_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\textbackslash{}/g' -e 's/[&%$#_]/\\&/g'
}

problem_records=""
problem_count=""
problem_source=""

if [[ $# -ge 3 && "$3" =~ ^[0-9]+$ ]]; then
  problem_count="$3"
  problem_source="given on the command line (conventional numbering)"
elif [[ -n "$list_source" ]]; then
  if [[ "$list_source" == "-" ]]; then
    if [[ -t 0 ]]; then
      printf 'Paste the problem list (one per line), then press Ctrl-D:\n' >&2
    fi
    list_text="$(cat)"
  else
    if [[ ! -r "$list_source" ]]; then
      printf 'Cannot read list file: %s\n' "$list_source" >&2
      exit 2
    fi
    list_text="$(cat "$list_source")"
  fi
  problem_records="$(collect_problem_records "$list_text" 60 0)"
  if [[ -z "$problem_records" ]]; then
    printf 'Warning: no numbered problems found in the list; falling back to auto-detection.\n' >&2
  else
    problem_source="headers taken from the supplied list"
  fi
fi

if [[ -z "$problem_records" && -z "$problem_count" ]]; then
  if [[ -n "$assign_pdf" ]]; then
    if text="$(pdf_text "$hw_dir/$assign_pdf")" && [[ -n "$text" ]]; then
      problem_records="$(collect_problem_records "$text" 48 1)"
      [[ -n "$problem_records" ]] && problem_source="auto-detected from $assign_pdf"
    fi
  elif [[ -f "$hw_dir/hw_packet.pdf" ]]; then
    if text="$(packet_section_text "$hw_dir/hw_packet.pdf" "$hw_number")" && [[ -n "$text" ]]; then
      problem_records="$(collect_problem_records "$text" 48 1)"
      [[ -n "$problem_records" ]] && problem_source="auto-detected from the Homework $hw_number section of hw_packet.pdf"
    fi
  fi
fi

# Sanity cap, then the final count.
n_records=0
if [[ -n "$problem_records" ]]; then
  n_records="$(printf '%s\n' "$problem_records" | wc -l | tr -d ' ')"
  if (( n_records > 30 )); then
    problem_records=""
    n_records=0
  fi
fi
if [[ -z "$problem_count" ]]; then
  if (( n_records > 0 )); then
    problem_count="$n_records"
  else
    problem_count=8
    problem_source="default — pass a count as the third argument to override"
  fi
fi

# ---------- Problem slots ----------
problems=""
if [[ -n "$problem_records" ]]; then
  while IFS=$'\t' read -r num title; do
    [[ -n "$num" ]] || continue
    title="$(latex_escape "$title")"
    if [[ -n "$title" ]]; then
      problems+='\subsubsection*{Problem '"$num"' ('"$title"')}'$'\n'
    else
      problems+='\subsubsection*{Problem '"$num"'}'$'\n'
    fi
    problems+='\begin{solution}'$'\n'
    problems+='% Write your proof, calculation, or argument here.'$'\n'
    problems+='\end{solution}'$'\n'
  done <<<"$problem_records"
else
  for ((i = 1; i <= problem_count; i++)); do
    problems+='\subsubsection*{Problem '"$i"'}'$'\n'
    problems+='\begin{solution}'$'\n'
    problems+='% Write your proof, calculation, or argument here.'$'\n'
    problems+='\end{solution}'$'\n'
  done
fi

cat > "$target" <<EOF
% !TEX program = lualatex
% Generated by new_homework.sh — $course_label Homework $hw_number
\documentclass[11pt]{article}

\usepackage{fontspec}
\usepackage{microtype}
\usepackage{mathtools,amssymb,amsfonts,amsthm,bm}
\usepackage{enumitem}
\usepackage{booktabs,array,xcolor}
\usepackage{geometry,fancyhdr,setspace}
\usepackage{pdfpages}
\usepackage[hidelinks]{hyperref}
\usepackage[nameinlink,noabbrev]{cleveref}

% ---------- Page and paragraph rhythm (matches lecture/solutions templates) ----------
\geometry{margin=1in,headheight=15pt}
\setstretch{1.12}
\setlength{\parindent}{0pt}
\setlength{\parskip}{0.55em plus 0.12em minus 0.08em}
\setlength{\abovedisplayskip}{0.8em plus 0.2em minus 0.1em}
\setlength{\belowdisplayskip}{0.8em plus 0.2em minus 0.1em}
\allowdisplaybreaks[3]
\setlist{leftmargin=*,topsep=0.35em,itemsep=0.15em,parsep=0pt}

% ---------- Metadata ----------
\newcommand{\studentname}{Keshav Ramamurthy}
\newcommand{\coursename}{$course_label}
\newcommand{\courselongname}{$course_name}
\newcommand{\assignment}{Homework $hw_number}
\newcommand{\term}{Fall 2026}

% ---------- Core notation (same as ~/.config/nvim/textemplate.tex) ----------
\newcommand{\N}{\mathbb{N}}
\newcommand{\Z}{\mathbb{Z}}
\newcommand{\Q}{\mathbb{Q}}
\newcommand{\R}{\mathbb{R}}
\newcommand{\C}{\mathbb{C}}
\newcommand{\F}{\mathbb{F}}
\newcommand{\K}{\mathbb{K}}
\newcommand{\E}{\mathbb{E}}
\newcommand{\Prob}{\mathbb{P}}
\newcommand{\1}{\mathbf{1}}
\newcommand{\eps}{\varepsilon}
\newcommand{\dd}{\,\mathrm{d}}
\newcommand{\abs}[1]{\left\lvert#1\right\rvert}
\newcommand{\norm}[1]{\left\lVert#1\right\rVert}
\newcommand{\ip}[2]{\left\langle#1,#2\right\rangle}
\newcommand{\set}[1]{\left\{#1\right\}}
\newcommand{\ceil}[1]{\left\lceil#1\right\rceil}
\newcommand{\floor}[1]{\left\lfloor#1\right\rfloor}
\newcommand{\given}{\,\middle\vert\,}
\newcommand{\indep}{\perp\!\!\!\perp}
\newcommand{\wh}[1]{\widehat{#1}}
\newcommand{\deriv}[2]{\frac{\mathrm{d}#1}{\mathrm{d}#2}}
\newcommand{\pderiv}[2]{\frac{\partial#1}{\partial#2}}
\newcommand{\lto}{\longrightarrow}
\newcommand{\st}{\text{ such that }}
\DeclareMathOperator{\Aut}{Aut}
\DeclareMathOperator{\End}{End}
\DeclareMathOperator{\Gal}{Gal}
\DeclareMathOperator{\Hom}{Hom}
\DeclareMathOperator{\Ker}{ker}
\DeclareMathOperator{\im}{im}
\DeclareMathOperator{\rank}{rank}
\DeclareMathOperator{\nullity}{nullity}
\DeclareMathOperator{\Span}{span}
\DeclareMathOperator{\tr}{tr}
\DeclareMathOperator{\diag}{diag}
\DeclareMathOperator{\spec}{spec}
\DeclareMathOperator{\ord}{ord}
\DeclareMathOperator{\supp}{supp}
\DeclareMathOperator{\diam}{diam}
\DeclareMathOperator{\Var}{Var}
\DeclareMathOperator{\Cov}{Cov}
\DeclareMathOperator*{\argmin}{arg\,min}
\DeclareMathOperator*{\argmax}{arg\,max}

% ---------- Statement environments ----------
\newtheorem{problem}{Problem}
\newtheorem{theorem}{Theorem}
\newtheorem{lemma}{Lemma}
\newtheorem{proposition}{Proposition}
\newtheorem{corollary}{Corollary}
\theoremstyle{definition}
\newtheorem{definition}{Definition}
\newtheorem{example}{Example}
\newtheorem{remark}{Remark}

% ---------- Solution machinery (matches solutions.tex / textemplate.tex) ----------
\newenvironment{solution}{\begin{proof}[Solution]}{\end{proof}}
\newenvironment{answer}{\begin{proof}[Answer]}{\end{proof}}
\renewcommand{\qedsymbol}{$\square$}
\newcommand{\exercise}[1]{%
  \par\goodbreak\medskip\noindent\textbf{Exercise #1}\par\nopagebreak\smallskip\nopagebreak}
\newcommand{\exref}[1]{\textsf{\textbf{Exercise~#1}}}
\newenvironment{claim}{\par\smallskip\noindent\textit{Claim.}\ }{\par\smallskip}
\newenvironment{idea}{\par\smallskip\noindent\textit{Idea.}\ }{\par\smallskip}
\newenvironment{proofsketch}{\par\smallskip\noindent\textit{Proof sketch.}\ }{\par\smallskip}

% ---------- Header ----------
\pagestyle{fancy}
\fancyhf{}
\fancyhead[L]{\coursename}
\fancyhead[C]{\assignment\ — my solutions}
\fancyhead[R]{\studentname}
\fancyfoot[C]{\thepage}

\begin{document}

% ---------- Title ----------
\begin{center}
  {\Large\sffamily\bfseries \coursename\ -- \courselongname}\par\vspace{3pt}
  {\sffamily \assignment\ — my solutions}\par\vspace{3pt}
  {\small\sffamily \term\quad\textbullet\quad \studentname}
\end{center}
\medskip
\hrule
\bigskip

$assign_include

\section*{Solutions}
$problems
\end{document}
EOF

printf 'Created %s\n' "$target"
printf 'Scaffolded %d problem slot(s) (%s).\n' "$problem_count" "$problem_source"
printf 'Open it with: nvim %q\n' "$target"
printf 'Build + push with: ./sync.sh\n'
printf 'Note: it stays out of the README index until it has real solution content.\n'
