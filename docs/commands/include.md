# include

**Syntax**
```vn
include "chapter2.vn" as chapter2;
```

**Description**
Inlines another script file at parse time and namespaces its labels with the alias (for example `chapter2.start`).
Use this to split large projects into multiple files without label collisions.
`include` must appear at the top of the file before any other commands. Alias is required.

Label resolution rules:
- Unqualified labels inside the included file are rewritten to `alias.label`.
- Use `::label` to jump to a root label in the main script.
- Use `other.label` to jump to another namespace explicitly.
- Character ids and `show` targets inside the included file are also namespaced to `alias.<id>`.

Simple meaning:
- `label` stays inside the included file.
- `::label` jumps to the main script.

**Example**
```vn
include "chapter2.vn" as chapter2;
include "maps/town.vn" as town;
```
