# Planning skills

The two Claude Code skills that maintain the plans — `/route` files captured
material, `/audit` reviews what is already filed — and how they reach a vault.

**Status:** built
**Code:** `skills/` (`_shared/lenses.md`, `audit/SKILL.md`, `route/SKILL.md`);
`lisp/ps-skills.el`; settings block `** Skills (ps-skills.el)`

## Problem

Plans accreted bottom-up: when finding good material was the hard part, the
natural move was to save a link under a topic heading, so files read as link
collections with a latent purpose. Now that references can be generated on
demand, a plan should say *what to learn or do*. Turning link piles into tasks,
trimming what is outdated and filing new captures were each done with long
hand-typed instructions, repeated per item. The requirement: define the process
once, and when the output is wrong, fix the process rather than the output. That
is a skill.

## Decisions

**Three layers, no duplication.** The rule everything else follows from.

| Layer | Holds | Loaded |
|---|---|---|
| `AGENTS.md` + the generated context it imports | Invariants of the notes: TODO keywords, task shape, Org formatting, where reference material goes, never commit | every session |
| A file's charter (its header) | What *this* file is for, and what "good" means here | on demand, when a skill targets the file |
| Skill | The procedure: what to check, in what order, how to report | on invocation |

A skill never restates `AGENTS.md`; two sources drift and then neither is
followed. Facts about the notes go in `AGENTS.md`, procedure shared by more than
one skill goes in `_shared/lenses.md`, and a `SKILL.md` holds only what is unique
to it. A third skill would reuse `lenses.md` unchanged.

**The standard of "good" lives in the file it governs.** It is not uniform: a
technical plan wants currency and good sources; a hobby file may value design and
enjoyment over information density; a travel file wants ready-to-go ideas, not
coverage. Forty standards in one skill would be unmaintainable, and in `AGENTS.md`
would load forty to use one. A charter states both what lives in the file *and*
what does not — the exclusion clause is what makes routing decidable. Its one-line
`#+SUBTITLE:` feeds the file index in the generated context
([agent-context.md](agent-context.md)), so routing can pick a file without
opening all of them; the full charter is read only when a skill targets the file.
No charter: the skill says so and uses common sense, never an invented standard.

**Pointers, never copies, for shared reference data.** Several files may need
the same grounding (for example career data: a CV, demand data). `AGENTS.md`
names the paths once; a charter only declares that it needs them.

**Exactly two skills.** They share the lenses but differ in pipeline order and
cost. `/audit` runs `vet → task → group`; `/route` runs `vet → dup → task →
destination`. Duplicate search comes early when routing — "you already have this"
kills an item before effort is spent shaping it — and is off by default when
auditing, where a search across every file rarely pays off. One skill would need
a mode flag that changes both order and cost: two skills wearing one name.

**Lenses inside one skill, not chained skills.** Skills invoking skills is
fragile. Granularity comes from naming lenses in the call (`/audit
Play/Travel.org vet`).

| Lens | Question | Search space | Cost |
|---|---|---|---|
| `vet` | Does it deserve its place? Currency, source quality, *local* redundancy; old-but-foundational is not outdated | the item | free |
| `task` | Is it a well-shaped, self-contained, actionable task? | the item | free |
| `group` | Right section? Should sections merge or split? Does the structure still fit? | the scope | cheap |
| `dup` | Does it already exist in another file? | every file | expensive |

The lenses are a pipeline: a `DROP` ends the item; a `REPLACE` carries the
replacement into `task`.

**Scope is free text.** A path, a description, a section, a line range, several
files, or the editor selection. The skill resolves it and restates it in one
line, and asks when it is genuinely ambiguous. All the notes at once is accepted
but answered with a per-file plan.

**Verification first, approval by number.** Both skills report numbered findings
(`N. path:line ACTION name`, actions `KEEP DROP REPLACE UPDATE TASKIFY MOVE MERGE
SPLIT DUP ASK`) and wait. The user answers in chat ("apply 3, 7, 9–12; discuss
4"), so the conversation is the apply mechanism. `ASK` is a first-class outcome.
This is behavioural, not a tool restriction: the skills must be able to apply
the picked findings in the same conversation.

**A findings ceiling of about fifteen.** Long lists get rubber-stamped, and the
corrections that matter most — facts the model cannot know, such as that a book
was already read — are exactly what rubber-stamping loses. Past the ceiling the
skill reports counts per lens and proposes one lens at a time. This is the
normal case on a file never reviewed before.

**Duplicates in `/route` default to judgement.** An incoming item that adds
something is `MERGE`d into the existing task; one that adds nothing is a `DUP`.
`ask` in the invocation surfaces every duplicate instead.

**Guarding against over-restriction.** Rules written long ago cause refusals of
reasonable requests. So: defaults with named escape hatches, not absolutes; each
rule names the bad output it prevents; disagreement with a charter is licensed
explicitly ("the charter says X, but here it gives a bad result because Y"); and
a misfire is fixed by changing the rule that caused it, not by adding one on top.
Target size is about 60 lines per skill.

**Shipped with the config, linked into each vault.** The skills are part of this
repository and `ps/skills-sync` symlinks every top-level folder of `skills/` into
`<vault>/.claude/skills/` on every vault open. A link makes updating the config
the whole update, and Claude Code finds the skills however it is started — the
Emacs panel, VS Code, a terminal — because it runs with the vault as its working
directory and follows the links. The links are listed in a `.gitignore` the
module owns inside that folder, so the vault's git history and auto-sync never
record machine-specific paths. The same model as the paper library's engine.

## Rejected

- **Names.** `/plan` collides with Claude Code's plan mode; `/inbox` names the
  source, and `/route` also takes pasted text; `/review` is a built-in command;
  `/cleanup` and `/stale` are the `vet` lens.
- **More skills.** A `/shape` skill is the `task` lens; a separate apply skill is
  the chat; a gap-filling skill for a one-off migration is a prompt; a weekly
  review skill has nothing to read while completion is recorded by deleting the
  task rather than marking it `DONE`.
- **Copies written into the vault.** They go stale as the config moves on and
  become a second source the moment anyone edits one in the vault.
- **A Claude Code plugin, or a `--plugin-dir` flag when Emacs starts the CLI.**
  The skills depend on what Emacs generates (the conventions, the file index, the
  capture inbox path), so they are of little use without it. A launch flag would
  also leave sessions started outside Emacs without them and namespace the names
  (`/agentic-org-planner:route`).
- **Linking the whole `.claude/skills/` folder.** A vault may hold skills of its
  own; per-skill links leave room for them.

## Constraints and traps

- **Paths inside skills are relative to the skill's folder** (`../_shared/`), not
  to the vault. `_shared` is linked too, so the path resolves whether it is taken
  lexically or through the link — and would also work from a plugin cache.
- **A real folder in the vault is never replaced.** It is the user's own skill
  and shadows the shipped one. That is also why moving a vault from hand-copied
  skills to the links needs the old folders removed by hand once. If the vault is
  a git repository that tracked those files, staging their deletion file by file
  (as editors do) fails with "pathspec … is beyond a symbolic link", because the
  path now runs through a link. `git rm -r --cached <folder>` or `git add -A`
  (what git sync runs) stages it.
- **Skills read machine facts from the generated context**, never from a path
  written into the skill: the file index and the capture inbox location both come
  from `.claude/generated-context.md`.

## Not built yet

- Running the skills in a cloud session, where neither Emacs nor the links exist.
- Tuning the findings ceiling and the duplicate default after more real use.
- Tag assignment: neither skill assigns tags.
