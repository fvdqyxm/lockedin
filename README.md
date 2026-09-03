# fa26_books

LaTeX lecture notes and homework for Fall 2026.

## Courses

| Folder        | Course          | Textbook (repo root)                  |
|---------------|-----------------|---------------------------------------|
| `math104/`    | Math 104 — Real Analysis            | `math104_textbook.pdf`                |
| `math110/`    | Math 110 — Abstract Linear Algebra  | `math110_textbook.pdf`                |
| `math113/`    | Math 113 — Abstract Algebra         | `math113_textbook.pdf`                |
| `math118/`    | Math 118 — Fourier Analysis         | `math118_textbook.pdf`                |
| `stat150/`    | Stat 150 — Stochastic Processes     | `stat150_textbook_essentials.pdf`, `stat150_textbook_other.pdf` |

## Layout

```
fa26_books/
├── math*_textbook.pdf        # reference textbooks live at the root
├── math104/
│   ├── lectures/             # lecture_NN.tex  + compiled lecture_NN.pdf
│   └── homework/             # hwNN.pdf (assignment) + hwNN_sol.tex / hwNN_sol.pdf (my solutions)
├── math110/  ... math113/  math118/  stat150/   # same shape
├── reference/                # LaTeX/vimtex cheatsheet
├── practice/                 # extra practice problems
├── new_lecture_note.sh       # scaffold a new lecture note
└── sync.sh                   # build all notes + commit & push
```

Each course folder is split into `lectures/` and `homework/`. My written work is
the `.tex` source plus the compiled `.pdf` next to it; professor-given assignment
PDFs sit alongside the solutions in `homework/`.

## Workflow

Create a new lecture note (course may be a number, slug, or spelled out):

```bash
./new_lecture_note.sh 118 3          # -> math118/lectures/lecture_03.tex
./new_lecture_note.sh Math110 4      # -> math110/lectures/lecture_04.tex
./new_lecture_note.sh stat150 2      # -> stat150/lectures/lecture_02.tex
```

Build every `.tex` into a PDF (in place) and push to GitHub:

```bash
./sync.sh                           # default commit message
./sync.sh "Math 118 lecture 3"      # custom commit message
```

`sync.sh` runs `latexmk -lualatex` on each source so the PDF lands next to the
`.tex`, stages everything, commits, and pushes. Intermediate build files
(`.aux`, `.log`, ...) are gitignored.
