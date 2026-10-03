---
name: audit
description: Review Org plan items already in these notes and report what should change — outdated or weak material, badly shaped tasks, wrong grouping. Verification only; reports numbered findings and waits for approval. Use for "review this plan / file / section", "is this task any good", "what here is outdated", "does this structure still fit". Scope can be a file, a section, a selection, or several files.
---

# /audit — review what is already in the notes

Read `../_shared/lenses.md` (beside this skill's folder) first: it defines scope resolution,
charters, the four lenses and the findings contract. This file covers only what is
specific to `/audit`.

**Verification only.** Report numbered findings and wait. Never edit before the
user picks findings by number.

## Pipeline

`vet` → `task` → `group`. All three by default.

`dup` is **off** by default — a search across every file rarely pays off on material
already in place. Run it when the user asks, or when auditing two or more files
together and cross-file overlap is the point.

Lenses can be named in the invocation (`/audit Play/Travel.org vet`); then run only
those.

## Steps

1. Resolve the scope and restate it in one line, with the lenses being run.
2. Read the file's charter. Say so in one line if there isn't one.
3. Read the whole scope before judging any part of it — an item that looks
   redundant alone often is not, and grouping problems are invisible item by item.
4. Verify anything uncertain. Fetch URLs rather than assuming; check whether a
   library is still maintained before calling it dead.
5. Report per the findings contract, sorted by line number.
6. Wait. Apply only what the user picks.

## Notes specific to auditing

**Most files have never been reviewed.** Expect a first pass over an
untouched file to blow past the findings ceiling. That is the normal case, not a
failure — stop at the ceiling, report counts per lens, and propose one lens at a
time, starting with `vet` (it removes items the other lenses would waste effort on).

**These entries were filed by hand, not scraped.** Every one looked interesting at
the time, sometimes without full understanding. Default to preserving; move
reasonably-good material into the notes vault named in `AGENTS.md` (e.g. Obsidian)
rather than deleting it. But
still make the call on things that are genuinely obsolete or genuinely weak, and
say so plainly — an explicit "this is obsolete" is one of the most useful outputs.

**A whole-scope comment is welcome** alongside the findings: is this file still
coherent, is a section missing, has the area moved on. Keep it to a few lines,
separate from the numbered list.

**Ask before restructuring heavily.** Local structural fixes — renaming a heading,
splitting a catch-all, moving an item to the right section — are findings like any
other. A wholesale reorganization is a different job; propose it, don't do it.
