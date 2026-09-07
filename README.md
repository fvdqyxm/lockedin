# fa26_books

LaTeX lecture notes, homework write-ups, and comprehensive solutions for Fall 2026.
Only completed work is indexed; every PDF opens right in your browser.

**Jump to:** [Math 104](#math104) · [Math 113](#math113) · [Stat 150](#stat150)

**4** lecture notes · **3** homework write-ups

<a id="math104"></a>

## Math 104 — Real Analysis

Textbook: Ross, *Elementary Analysis* (2nd ed.)

### Homework

| HW | Assignment | My solutions |
|----|------------|--------------|
| 1 | [assignment](math104/homework/hw01.pdf) | [tex](math104/homework/hw01_sol.tex) · [pdf](math104/homework/hw01_sol.pdf) |

<a id="math113"></a>

## Math 113 — Abstract Algebra

Textbook: Fraleigh, *A First Course in Abstract Algebra* (7th ed.)

### Lectures

| # | Notes |
|---|-------|
| 02 | [PDF](math113/lectures/lecture_02.pdf) · [tex](math113/lectures/lecture_02.tex) |
| 03 | [PDF](math113/lectures/lecture_03.pdf) · [tex](math113/lectures/lecture_03.tex) |

### Homework

| HW | Assignment | My solutions |
|----|------------|--------------|
| 1 | [assignment](math113/homework/hw01.pdf) | [tex](math113/homework/hw01_sol.tex) · [pdf](math113/homework/hw01_sol.pdf) |
| 2 | — | [tex](math113/homework/hw02_sol.tex) · [pdf](math113/homework/hw02_sol.pdf) |

<a id="stat150"></a>

## Stat 150 — Stochastic Processes

Textbook: Durrett, *Essentials of Stochastic Processes* (3rd ed.)

### Lectures

| # | Notes |
|---|-------|
| 01 | [PDF](stat150/lectures/lecture_01.pdf) · [tex](stat150/lectures/lecture_01.tex) |
| 02 | [PDF](stat150/lectures/lecture_02.pdf) · [tex](stat150/lectures/lecture_02.tex) |

---

<details>
<summary>Repository layout</summary>

```text
fa26_books/
├── *_textbook*.pdf          # course textbooks at the root
├── math104/                 # one folder per course, e.g. math104
│   ├── lectures/            #   lecture_NN.tex + lecture_NN.pdf
│   ├── homework/            #   hwNN.pdf (assignment) + hwNN_sol.tex / .pdf
│   └── solutions.tex        #   comprehensive per-chapter exercise solutions
├── math110/ math113/ math118/ stat150/    # same shape
├── practice/                # extra practice problems
├── reference/               # LaTeX/vimtex cheatsheet
└── scripts/
    ├── new_lecture_note.sh  # scaffold a new lecture note
    ├── new_homework.sh      # scaffold a homework solutions file
    └── sync.sh              # build changed notes + commit & push
```

</details>

<details>
<summary>Workflow — scripts and solutions syntax</summary>

Create a new lecture note:

```bash
./scripts/new_lecture_note.sh 118 3          # → math118/lectures/lecture_03.tex
./scripts/new_lecture_note.sh Math110 4      # → math110/lectures/lecture_04.tex
./scripts/new_lecture_note.sh stat150 2      # → stat150/lectures/lecture_02.tex
```

Create a homework solutions file (problem count auto-detected from the
assignment PDF; a pasted list becomes the problem headers):

```bash
./scripts/new_homework.sh 104 2              # → math104/homework/hw02_sol.tex
./scripts/new_homework.sh 113 4 -            # paste "1. Fraleigh Exercise 4.6" ... then Ctrl-D
./scripts/new_homework.sh Math110 14 6       # force 6 conventional problem slots
```

Add a solved textbook exercise (per-course `solutions.tex`):

```latex
\exercise{8.6}          % header under the right chapter banner
\begin{solution}
  ...your write-up...
\end{solution}
```

A file appears in the index above only once it has real content —
scaffolds never show up.

Build changed notes and push:

```bash
./scripts/sync.sh                    # builds only changed .tex, then commits & pushes
./scripts/sync.sh "Math 118 lec 3"   # custom commit message
./scripts/sync.sh --all              # force-rebuild everything
```

</details>
