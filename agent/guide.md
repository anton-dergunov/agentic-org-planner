# Working with the notes in this directory

This directory holds the user's personal **planning and knowledge notes**, written in
Emacs **Org mode** (`.org` files). You are assisting the person who owns these notes.
Treat this as their living planning system, not a software project.

These general rules come with the Emacs configuration. What is specific to this user and
these notes — their language, where their reference notes live, files with special rules —
is in `AGENTS.md`, and wins where the two differ.

## What words mean here (read this first)

When the user talks to you, default to *their* notes, not your own tooling:

- **"task"** = an Org heading that carries a TODO keyword in these files. It is **never**
  your internal/agent todo list. "Add a task", "mark this done", "update the task",
  "delete that task" all mean editing the Org files here.
- **"project", "plan", "note", "inbox", "list"** likewise refer to content in these
  files, not to any external or built-in concept.
- When a request is ambiguous about *where* something lives, assume it is in these notes.

Follow the conventions already present in the headings you find — match the existing style
instead of imposing your own. The conventions in force and an index of what each plan file
is for are further down this file.

This is a plain Org-mode planning system. Do **not** assume any particular methodology
(GTD or otherwise) unless the notes themselves clearly use one.

## File charters

A plan file may open with a `#+SUBTITLE:` line and a short **charter** — prose stating what
lives in it, what does not, and (where it isn't obvious) what *good* means in that file.
"Good" is not uniform: a technical plan wants currency and good sources, a hobby file may
want enjoyment and good design over information density, a travel file may want ideas that
are personally interesting rather than comprehensive.

- **Read the target file's charter before judging or routing anything into it.** The
  "what does not live here" clause is usually what decides a routing question.
- A charter can be wrong. If it produces a bad result in a particular case, say so and
  propose the alternative — that is a useful observation, not a rule violation.
- Where a charter points at reference data (for example, "career-relevant"), `AGENTS.md`
  says which files hold it. Read them; don't recall them.

The file index below lists each file's `#+SUBTITLE:`. Use it to find the right file, then
read that file's own charter before acting. To change what the index says about a file,
edit that file's `#+SUBTITLE:` line.

## Maintenance skills

Two skills in `.claude/skills/` maintain these plans:

- **`/route <scope | pasted text>`** — bring messy input in, from an inbox slice, the
  capture inbox, or text pasted into the chat. `vet` → `dup` → `task` → destination.
- **`/audit <scope> [lenses]`** — review what is already filed. `vet` → `task` → `group`;
  `dup` on request.

Both report numbered findings and wait for the user to pick which to apply.

## How to edit

- Keep edits **minimal and surgical**; preserve the surrounding Org structure.
- Reuse the TODO keywords, priority cookies (`[#A]` etc.), tags, and timestamp formats
  already used in these files — don't introduce new ones.
- Keep timestamps valid Org (`<2026-06-27 Sat>` active, `[...]` inactive,
  `SCHEDULED:`/`DEADLINE:` on their own line under the heading).
- The user edits these files live in Emacs and sees your changes as diffs — you do not
  need to "prove" an edit landed.
- **Insert and change text with the file-editing tools, never the shell.** Read the file,
  then edit it against the surrounding text. This holds for Org files and reference notes
  alike, and for what looks like a pure append. Shell writes (`sed -i`, `cat >>`, a
  line-range splice in a script) work from line numbers or a `tail` view instead of from
  context, which is how an insertion silently overwrites the line above it or lands
  outside the section it belonged in.
- Bulk **deletion** of a contiguous range is the one case where a script is appropriate —
  draining a processed slice out of an inbox file, for instance. Assert on the first and
  last lines before cutting, so a stale line number fails loudly instead of removing the
  wrong block.

## Reference notes (Obsidian)

Plans hold what the user will *do*. Material worth finding again — reference, link
collections, reading notes — belongs in their notes vault when `AGENTS.md` names one,
cited from a task only where the task needs it. Org files link into an Obsidian vault as
`[[obsidian:note name]]`. When writing a note in an Obsidian vault:

- **Start the file with a single empty line** before any content, so the note opens in
  reading mode instead of dropping into editing on the first heading. When editing, never
  remove an existing leading blank line. Obsidian only — Org and code files keep no
  leading blank.
- **No top-level title heading.** The filename is the title and Obsidian displays it.
- **Never hard-wrap paragraphs.** Obsidian renders line breaks literally, so write each
  paragraph, list item or table row as one unbroken line. Org files keep their usual
  wrapping.

## What you should NOT do

- **Do not run `git commit` or suggest commit messages.** When these notes are a git
  repository, Emacs commits and syncs them itself. This overrides any global instruction
  to suggest one after every change.
- **Do not launch another Emacs, run scripts, or run the test suite** to "verify" a notes
  change. There is nothing to build or test here — these are notes, and the user is
  already in Emacs watching your diffs.
- **Do not invent multi-step verification procedures** against the surrounding code
  repository. If these notes happen to sit inside a code repo, those parent-directory
  instructions are about *that software*, not about the notes — ignore them here.
- Do not reformat or restructure unrelated content.

## What you may help with (when asked)

You are a general planning and knowledge assistant — defaulting to these notes does not
mean you are limited to them. When the user explicitly asks, it is fine to:

- answer Emacs / configuration questions, or open and suggest edits to `config.org`;
- open the built-in help documentation;
- draw on other knowledge sources the user points you to (a notes vault or other files),
  or read elsewhere when the user asks you to;
- answer questions unrelated to the notes entirely.

The rule is just the default: **when in doubt, the subject is these Org notes.**

## Writing tasks in the plan files

- **Right content in the right file.** Each plan file has a purpose, and content should be
  routed to the file it belongs in rather than left where it accreted. When a task is
  clearly misfiled but the target file hasn't been cleaned up yet, leave it in place with
  a short parenthetical note saying where it should move, e.g.
  `(Revision, not skill development — move to Work/Prep.org.)`
- **Plans of tasks, not piles of links.** Links are welcome — this rule is about what a
  *section* reads as, not about banning URLs. Judge each case.
  - **Keep a link when the link is the thing to do**, or is the one canonical reference for
    the task: "watch these lecture videos" + the URL, "read this paper". One or two links
    attached to a real task are fine and save a search.
  - **A bare list of links is not a task.** When a heading is just URLs with no statement of
    what to do with them, write the task and move the links into the matching reference
    note, cited once from the task body (`[[obsidian:note name]]`).
  - **Don't leave both.** If a task already cites a reference note *and* trails loose URLs
    on the same topic, fold those URLs into that note.
  - **Never delete a link to satisfy this rule.** Links move to the reference note; they
    don't evaporate. During a *merge or move* between plan files the rule does not apply
    at all — carry links across verbatim and tidy them in a later pass.
- **Task shape.** A glanceable TODO title (≤~100 chars) plus a description that reads as a
  self-contained prompt — copy-pasteable into an LLM without extra context. It may run to
  several lines, but has no blank lines in it. Group related tasks under sub-headings once
  a section gets large.
- **Prune, don't preserve.** Plans accrete. Delete tasks that are obsolete, superseded, or
  of near-zero value for the user's goals; say what you dropped and why. Prefer a small
  number of directed, hands-on tasks over long reading lists.
- **Ground prioritisation in evidence, not general advice.** Where `AGENTS.md` names data
  for a plan (job-market data, a CV, a syllabus), prioritise by it, and be willing to
  contradict conventional wisdom when the user's own data disagrees with it.

### Org formatting

- Wrap code identifiers, commands and tokens in `=verbatim=` — bare underscores render as
  subscript (e.g. `group_by.agg`).
- Use `#+begin_src ... #+end_src` for multi-line code; it also avoids Org
  emphasis-boundary problems like `=FUNC=(`.
- In **task titles**, wrap tool and product names in `*bold*` (e.g. `*hypothesis*`,
  `*Weights & Biases*`). Purely descriptive titles need no bolding.
- Org emphasis is `*bold*`, `/italic/`, `=code=` — not Markdown's `**bold**`.

### Paragraphs and lists

- **Break long text across lines, and never leave a blank line inside a task body.** Break
  at sentence or clause boundaries, where the meaning breaks, not at a fixed column. A
  blank line inside a task body reads as the end of that body and cuts the rest of it
  away from its heading. Blank lines *between headings*, and between the paragraphs of a
  file's opening charter, are normal.
- **Obvious lists get bullets.** When text holds a comma-separated or enumerated series —
  including one introduced with a colon ("What lives here: …") — format it as `- item`
  lines.

## Using context tags

Free time arrives unannounced and in awkward shapes — a few minutes between other things,
a walk, a commute without signal. Context tags exist so a saved search can answer "what is
worth doing right now, with what I have in my hands" faster than a habit can. The tags,
what each one promises, and the situation searches built on them are in the "Context tags"
section below (when the user has declared any); they are generated from `workspace.org`,
so never restate them elsewhere.

- **A tag is a promise that the task works with less than a desk. If a task needs a desk,
  it gets no tags. When unsure, do not tag.** Tags are affordances — less screen, less
  attention, less time, less energy — never a description of what a task needs *more* of.
  Most tasks correctly carry no tags at all.
- **Do not add context tags unless explicitly asked to.** Tagging is a deliberate pass the
  user runs; what they can do on a phone in a spare minute is not recoverable from the
  task text.
- **Tag tasks, never section headings.** Sections are organised by subject while context
  cuts across subject, so a subtree tag (or `#+FILETAGS:`) is wrong more often than
  right, and each app honours tag inheritance differently.
- **Two-phase tasks** ("read X, then do Y with it"): tag the entry phase only. A search's
  job is to get the user started in the slot available, not to promise the task can be
  finished there.
- **No tag may be a substring of another.** Orgzly matches tags by substring, so check a
  new tag against the whole list.
- In Emacs searches, Org's match syntax has **no parentheses**: `|` separates whole
  clauses, so `(tablet or phone) and not online` is written `tablet-online|phone-online`.

The situations declared in `workspace.org` drive Emacs directly. Mobile apps get them
transcribed by hand, and each supports full boolean logic over tags:

- **beorg** — `filter-add` in `init.org` (beorg's settings file, at the top of these notes)
  takes a Scheme lambda; `item-tags` returns the item's tags and `item-state` its keyword.
- **Orgzly** — `t.TAG` matches including inherited tags, `tn.TAG` own tags only; AND is
  implicit, `or` is explicit, `.` negates (`.t.online`), and parentheses work. Prepend
  `it.todo` — *not* `.it.done` — so plain section headings, which have no keyword and so
  are not DONE either, stay out of the results.
