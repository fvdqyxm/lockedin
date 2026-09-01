# Lecture notes

From the repository root, create a new note with:

```bash
./new_lecture_note.sh Math118 1
```

That creates:

```text
lecture_notes/Math118_lecture_01.tex
```

The course name can be any letters-plus-number format, such as `Math118`, `Stat153`, or `Math 118` when quoted. The lecture number is zero-padded in the filename. New notes use the same LuaLaTeX-friendly notation and theorem structure as the homework template.
