# Shared lenses, scope and reporting contract

Used by `/audit` and `/route`. The conventions of these notes — TODO keywords, task
shape, Org formatting, notes-vault rules, no-commits — live in `AGENTS.md` and the
`.claude/generated-context.md` it imports. Do not restate them here or in a skill.

## Resolving scope

Scope is free text; there is no syntax to memorize. Resolve it, then **restate the
resolved scope in one line** before doing any work.

- A path (`ML/Math.org`), a description ("my maths plan"), a section
  ("the section about linear algebra"), a line range, several files, or the
  editor selection when nothing is named.
- Ambiguous — two sections could match, or the file is unclear — **ask**, don't guess.
- All the notes at once is accepted but expensive: propose a per-file plan instead of doing it
  in one pass.
- A slice of the capture inbox's `triage.md` (its path is under *Capture inbox* in
  `.claude/generated-context.md`) — the generated capture digest. See
  the contract note at the top of that file. "triage", "the triage inbox",
  "info-triage", or `triage.org` being the file on screen all mean this one;
  never read `triage.org` itself, which holds strictly less. `/route` spells the
  substitution out.

## Charters

Before judging anything in a file, read the file's header charter (the prose under
`#+TITLE:` / `#+SUBTITLE:`). It defines what belongs there and what "good" means in
that file — which varies a lot: a hobby file may value clean design and modern
repertoire over information density, while a technical file wants currency and
job-relevance.

- No charter → say so in one line, then use common sense. Never invent a standard
  silently.
- Charter that points at reference data (e.g. marked career-relevant) → ground
  judgements in the reference files `AGENTS.md` lists for it. Read them; don't recall them.
- **The evidence can argue for less, not only for more.** When the data shows an area
  is low-demand or already held, and another plan file covers it more deeply, the right
  output is *fewer and better* tasks — file less, and say why. Restraint grounded in the
  data is a finding; volume is not. This is not deprioritising by field (see `vet`) — it
  is refusing to pad a section the evidence says is already served.
- A charter can be wrong. If it produces a bad result here, say so and propose the
  alternative — that is a useful finding, not a violation.

## The four lenses

They are a pipeline, not a menu: `vet` gates the rest. A `DROP` ends that item; a
`REPLACE` carries its replacement forward into `task`.

**`vet` — does this deserve its place?** Five checks, only the first about age:
- *Currency*: superseded, abandoned, dead. Name the modern replacement. **Always state the
  item's date** — publication year, latest revision, last release, last commit — but never
  conclude from the date alone: a 1970s paper can still be the canonical reference. Read title,
  topic, subfield and date **together** as a suspicion signal, and whenever they suggest the item
  *may* have been overtaken, **run a web search for what replaced it before deciding**. Your
  training data has a cutoff and the field moved after it, so an unverified "still current" is a
  guess wearing a fact's clothes. One search is cheap against the hours a stale task costs the user.
- *Source quality*: prefer primary sources (official docs, arXiv, the actual
  author) over SEO listicles and content marketing. **Judge the artifact itself, never its title
  or the heading it happens to sit under** — open the repo README, the arXiv abstract, the docs,
  the product page. A one-line capture in these notes records what the user thought years ago, not what
  the thing is now. If a source cannot be fetched (paywall, 403, login wall), say so *in the
  finding* and mark that judgement unverified rather than letting recalled knowledge pass as a
  checked fact. When the item comes from the info-triage inbox, none of that fetching applies:
  the artifact is already on disk at `<id>/extracted/NN-*/content.md` and *that* is what to
  open, "cannot be fetched" is already answered by `extraction:`, and a currency check may
  still need a search but starts from the title, author and date in the frontmatter rather
  than rediscovering them.
- *A weak source can carry a strong question*: judge the artifact and the question it
  raises separately. A low-quality item pointing at something the notes do not cover is
  a finding about **the gap**, not about the item — keep the question, shape it into the
  task, and preserve the link in the vault labelled for what it is.
- *Internal redundancy*: six links on one topic where two would do.
- *The guard*: **outdated ≠ old**. SVM, PCA, KL-divergence, Sutton & Barto are
  foundational, not stale. Never flag something merely for being old.
- *The second guard*: **`vet` judges substance, never form.** A four-word heading, a bare
  URL, a pile of sub-bullets, a stated intention with no method — these are what `task`
  exists to fix. They are never grounds for a `DROP`. Ask what the item *wants*, not how
  badly it is written: if there is a real subject behind it, or an intent the notes do
  not otherwise cover, the intent survives and the form, completeness or choice of method
  gets rewritten. `DROP` is for items that are wrong, dead, superseded or genuinely
  worthless once understood — not for items that were captured in a hurry. Most of these
  notes were captured in a hurry.

Flagging what is intrinsically weak — obsolete technique, low-quality source, a
hyper-niche corner even within its own field — is one of the most valued outputs.
Say it plainly. But never downgrade something for sitting outside a "main" area:
breadth here is deliberate.

**Watch for self-authorship bias.** Items previously written or rewritten by an assistant
read as well-shaped because they are written in your own register — full sentences, a
stated rationale, a named candidate. Items the user typed in five seconds read as
weak by the same measure, and they are the ones carrying the original intent. Before
praising an item's shape or faulting it, check which kind it is; the fluent one is not
automatically better, and the terse one is not automatically worse.

Verify before asserting. Fetch a URL rather than guessing whether it is dead;
never fabricate a replacement link.

**`task` — is it a well-shaped, actionable task?** Per the task shape in the
conventions: a glanceable title plus a 1–2 line body that reads as a self-contained
prompt. Link piles become a task plus a notes-vault note holding the references. Preserve
reasonably-good links by moving them to the vault; cutting a decent link outright
is a mistake. Fold dangling sub-bullets into the task.

Prefer directed tasks, in the style of learning `AGENTS.md` describes. The test for a
good one: **the exercise should be the thing that would not be true of a neighbouring
artifact.** Ask what is distinctive about *this* book, tool or paper and make that the
exercise — the simulation harness a book happens to ship, the two capabilities a tool
happens to combine, the gap between a paper and the blog post that reimplemented it, the
divergence a counterexample lets you watch. "Read it" and "work through the tutorial" are
what gets written when that question has not been asked yet.

**`group` — is it in the right place?** Scoped to the file in hand, deliberately, so
`/audit` stays cheap to run per file: wrong section, sections that should merge or split,
duplicate homes for one topic, ordering. Also: has a new area appeared that the structure
no longer covers? Placement *across* files belongs to `dup` and to `/route`'s destination
step, not to this lens.

**`dup` — does this already exist elsewhere?** **Across every plan file** —
that is the point of this lens and the reason it is the expensive one. Cite each match as
`file:line` so the call can be checked. Aim the search with the file index in
`.claude/generated-context.md` rather than grepping blindly: it says which file owns
which subject. Costs a search of every file, so it runs only when the skill's
pipeline calls for it or the user asks.

## Findings contract

```
N. path:line   ACTION   short item name
   detail — why, and what the replacement or destination is
```

Actions: `KEEP` `DROP` `REPLACE` `UPDATE` `TASKIFY` `MOVE` `MERGE` `SPLIT` `DUP` `ASK`

- `UPDATE` fixes in place (dead link, moved URL, stale detail); `REPLACE` swaps the
  item for a better one.
- `MERGE` folds into an existing item; `DUP` means it already exists and this copy goes.
- `ASK` is a first-class outcome. A surfaced uncertainty beats a confident wrong guess.
- A finding may carry a **secondary cross-file note**: the item lands in one file, but an
  adjacent angle already lives in another and should point at the same vault note. Say so
  inside the finding ("filed here; `ML/ML.org:120` covers the application side and should
  cite the same note") and let the user decide. Never edit the other file silently.
- Number findings consecutively and stably — approval happens by number in chat.
- Show actionable findings only. Include `KEEP` lines when the user asks for all,
  or when the point is a completeness check.
- Sort by position in the source.

**Findings ceiling.** If a scope produces more than ~15 findings, stop. Report the
count per lens and propose running one lens at a time. Long lists get
rubber-stamped, and rubber-stamping loses exactly the corrections that make this
worth doing.

## Approval

Report, then wait. Never edit before the user picks findings — these notes are a
personal plan and every change is their decision.

They reply by number ("apply 3, 7, 9–12; discuss 4"). Apply only what was picked,
surgically, preserving surrounding structure. Delete cleanly: no tombstone notes
explaining what was removed — the reason belongs in the reply, not the file.

Afterwards, say plainly what was applied and what was skipped.
