# fa26_books

LaTeX lecture notes and homework for Fall 2026. Click any PDF link below to read it right in your browser.

## Notes index

### Math 104 — Real Analysis

| Lecture | PDF |
|---------|-----|
| Lecture 01 | [PDF](math104/lectures/lecture_01.pdf) |

| Homework | Assignment | My solutions |
|----------|------------|--------------|
| HW 1 | [PDF](math104/homework/hw01.pdf) | [.tex](math104/homework/hw01_sol.tex) / [PDF](math104/homework/hw01_sol.pdf) |

### Math 110 — Abstract Linear Algebra


| Homework | Assignment | My solutions |
|----------|------------|--------------|
| HW 1 | [packet](math110/homework/hw_packet.pdf) | [.tex](math110/homework/hw01_sol.tex) / [PDF](math110/homework/hw01_sol.pdf) |
| HW 2 | [packet](math110/homework/hw_packet.pdf) | [.tex](math110/homework/hw02_sol.tex) / [PDF](math110/homework/hw02_sol.pdf) |
| HW 3 | [packet](math110/homework/hw_packet.pdf) | [.tex](math110/homework/hw03_sol.tex) / [PDF](math110/homework/hw03_sol.pdf) |
| HW 4 | [packet](math110/homework/hw_packet.pdf) | [.tex](math110/homework/hw04_sol.tex) / [PDF](math110/homework/hw04_sol.pdf) |
| HW 5 | [packet](math110/homework/hw_packet.pdf) | [.tex](math110/homework/hw05_sol.tex) / [PDF](math110/homework/hw05_sol.pdf) |
| HW 6 | [packet](math110/homework/hw_packet.pdf) | [.tex](math110/homework/hw06_sol.tex) / [PDF](math110/homework/hw06_sol.pdf) |
| HW 7 | [packet](math110/homework/hw_packet.pdf) | [.tex](math110/homework/hw07_sol.tex) / [PDF](math110/homework/hw07_sol.pdf) |
| HW 8 | [packet](math110/homework/hw_packet.pdf) | [.tex](math110/homework/hw08_sol.tex) / [PDF](math110/homework/hw08_sol.pdf) |
| HW 9 | [packet](math110/homework/hw_packet.pdf) | [.tex](math110/homework/hw09_sol.tex) / [PDF](math110/homework/hw09_sol.pdf) |
| HW 10 | [packet](math110/homework/hw_packet.pdf) | [.tex](math110/homework/hw10_sol.tex) / [PDF](math110/homework/hw10_sol.pdf) |
| HW 11 | [packet](math110/homework/hw_packet.pdf) | [.tex](math110/homework/hw11_sol.tex) / [PDF](math110/homework/hw11_sol.pdf) |
| HW 12 | [packet](math110/homework/hw_packet.pdf) | [.tex](math110/homework/hw12_sol.tex) / [PDF](math110/homework/hw12_sol.pdf) |
| HW 13 | [packet](math110/homework/hw_packet.pdf) | [.tex](math110/homework/hw13_sol.tex) / [PDF](math110/homework/hw13_sol.pdf) |

### Math 113 — Abstract Algebra

| Lecture | PDF |
|---------|-----|
| Lecture 02 | [PDF](math113/lectures/lecture_02.pdf) |

| Homework | Assignment | My solutions |
|----------|------------|--------------|
| HW 1 | [PDF](math113/homework/hw01.pdf) | [.tex](math113/homework/hw01_sol.tex) / [PDF](math113/homework/hw01_sol.pdf) |

### Math 118 — Fourier Analysis

| Lecture | PDF |
|---------|-----|
| Lecture 01 | [PDF](math118/lectures/lecture_01.pdf) |
| Lecture 02 | [PDF](math118/lectures/lecture_02.pdf) |

| Homework | Assignment | My solutions |
|----------|------------|--------------|
| HW 1 | [PDF](math118/homework/hw01.pdf) | [.tex](math118/homework/hw01_sol.tex) / [PDF](math118/homework/hw01_sol.pdf) |

### Stat 150 — Stochastic Processes

| Lecture | PDF |
|---------|-----|
| Lecture 01 | [PDF](stat150/lectures/lecture_01.pdf) |

---

## Layout

```
fa26_books/
├── math*_textbook.pdf        # textbooks at the root
├── math104/
│   ├── lectures/             # lecture_NN.tex + lecture_NN.pdf
│   └── homework/             # hwNN.pdf (assignment) + hwNN_sol.tex / .pdf (my solutions)
├── math110/  math113/  math118/  stat150/   # same shape
├── practice/                 # extra practice problems
├── reference/                # LaTeX/vimtex cheatsheet
└── scripts/
    ├── new_lecture_note.sh   # scaffold a new lecture note
    └── sync.sh               # build changed notes + commit & push
```

## Workflow

Create a new lecture note:
```bash
./scripts/new_lecture_note.sh 118 3          # → math118/lectures/lecture_03.tex
./scripts/new_lecture_note.sh Math110 4      # → math110/lectures/lecture_04.tex
./scripts/new_lecture_note.sh stat150 2      # → stat150/lectures/lecture_02.tex
```

Build changed notes and push:
```bash
./scripts/sync.sh                    # builds only changed .tex, then commits & pushes
./scripts/sync.sh "Math 118 lec 3"   # custom commit message
./scripts/sync.sh --all              # force-rebuild everything
```
