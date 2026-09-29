# Task icons

A Material Symbols icon for what each agenda task is about, chosen by a matcher
that is built elsewhere and only run here.

**Status:** built; the Python-free runtime is research
**Code:** `lisp/ps-task-icons.el` (names, cache, async runs), drawn by
`lisp/ps-agenda-layout.el` and `lisp/ps-schedule-view.el`;
`scripts/org_task_icon_matcher.py` (the runner); `icons/task-matcher/` (the
bundle); settings block `** Agenda task icons (ps-task-icons.el)`. User docs:
`docs/Agenda.org` → "Reading a line", `docs/Installation.org` step 8.

## Problem

A glance at a task's icon should say what the task is about without reading
the title. The icon has to come from the Material Symbols font the rest of the
interface uses, and there are about 3,500 distinct glyphs. Matching a free-text
task to one of them is an ML problem of its own, with its own datasets,
evaluation and training. It is too large to live in a configuration.

## Decisions

**The matcher is built in a separate project and shipped as a bundle.** The
task-concept-retrieval research project creates, evaluates and exports
matchers. This repository takes none of its code, only its output: a directory
of precomputed icon data plus a `manifest.json`. The current bundle is that
project's M3 method:
- BM25 over LLM-written icon descriptions;
- a field-weighted multilingual-e5-small bi-encoder with a quality prior;
- the two fused by reciprocal rank, with an abstention gate.

Everything on the icon side is precomputed:
- the bi-encoder's per-field cosines collapse into one matrix;
- BM25 collapses into a sparse term-by-icon matrix.

At run time only the task text is encoded. The export and its checks are
documented in that project's `docs/deployment.md`.

**The runner is minimal and standalone.** `org_task_icon_matcher.py` needs
`onnxruntime`, `tokenizers` and `numpy`, not torch or sentence-transformers. It
downloads the ONNX encoder named in the manifest once, verified by sha256. It
mirrors the research project's query building and scoring (`tcr/bundle.py`
there). The two are checked to give identical answers on the same bundle.

**The manifest drives the Elisp, not settings.**
- `query.inputs` says which task fields the model reads. Only those are
  collected and sent, so a future model that reads parent headings or the body
  needs no change here.
- `tag` identifies everything that decides an answer: the matrices, the
  encoder, and the query and fusion settings. Answers are cached on disk under
  the tag, and a bundle with a new tag discards them.

**The task is sent as structured fields with its markup kept.** The title comes
without the TODO keyword, priority and tags, which describe the task's state
rather than its idea. Links and emphasis stay in it. The bundle declares how
to turn markup into the model's text (`query.normalize`), so a model trained on
markup can keep it.

**Scoring stays with the encoder, outside Elisp.** One query against the fused
3.5k × 384 matrix measured about 360 ms per task in native-compiled Elisp, and
about 820 ms interpreted. The runner does it in milliseconds.

**One matcher run per batch of uncached tasks; the cache does the rest.** After
an agenda render, uncached tasks go to one runner process, which takes about a
second including model load. The layout is refreshed when its answer arrives.
A warm render never starts Python. "No icon" is cached as an answer too.

**Failure is quiet and says why once.** No Python, missing packages or a failed
model download never signal. The runner's last stderr line is written to be
shown as is (for example, the `pip install` to run), and it is reported once
per distinct reason. The runner is then not restarted for ten minutes, so it
does not respawn on every render.

**The icon column collapses where no icon can show:** on a text terminal,
without the font, and in the Tasks view, which turns task icons off.

## Rejected

- **Emojis matched against emoji names.** They were the first version. They
  were colourful where everything else is monochrome, and the matches were
  often loose.
- **Importing the research project's code at run time.** It would make this
  public repository depend on a research checkout and on torch.
- **The int8 encoder.** It is half the download of fp16, but it agreed with the
  reference method on only 80% of top-1 picks, against 99.7% for fp16. e5 packs
  icon scores so tightly that int8's noise reorders near-ties.
- **Scoring in Elisp** (see above).

## Constraints and traps

- **Never batch the encoder.** With an int8 model, dynamic quantization takes
  its scale over the whole input, so a text's vector (and so its icon) depends
  on the other texts in the batch. Both the runner and the exporter encode one
  text per call. That keeps the rule safe if a quantized encoder returns.
- **Basic graph optimizations only.** onnxruntime 1.27's layer-norm fusion
  fails to load the fp16 encoder. The runner and the exporter both use
  `ORT_ENABLE_BASIC`, which also keeps them on the identical graph.
- **A fusion member ranks only what it matched.** When BM25 knows no word of a
  task (any Russian or Spanish title), all its scores are zero, and ranking them
  would hand its first vote to whichever icon sorts first. Both implementations
  skip zero scores.
- **The runner mirrors `tcr/bundle.py`.** A change to query building or scoring
  must be made in both, and the project's parity check rerun.

## Not built yet

- **A Python-free runtime.** Research only; see below.
- **Better matches.** Quality is the research project's job; a new bundle is
  dropped into `icons/task-matcher/`. One known M3 weakness: an exact
  reciprocal-rank tie goes to BM25, so a stray word match (the Spanish "a"
  against a letter-A glyph) can beat the bi-encoder's pick.

## Research: running the matcher without Python

What it would take for the task icons to need nothing but Emacs and one
shared library, on macOS first and on Linux and Windows too.

**onnx.el as-is is not the route.** It is a C dynamic module around
onnxruntime, documented as Linux-only, and not on MELPA. Its GitHub repository
has been archived since August 2025 and development moved to sourcehut. Its
tokenizer companion, tokenizers.el, is a Rust module that needs a Rust
toolchain.

**Our own equivalent is practical: about 1.5–2 weeks of work.**

- **A small C module (2–3 days, about 300–400 lines).**
  - It targets the ONNX Runtime C API, which has a stable ABI through
    `OrtGetApiBase`.
  - It loads the library at run time with `dlopen` / `LoadLibrary`, so
    compiling needs only the vendored, MIT-licensed header.
  - It compiles on first use with the system C compiler, as jinx (already in
    this config) does. Windows builds with MinGW, as jinx's does.
  - Its interface is two functions: `load` (path to session, as a user
    pointer with a finalizer) and `run` (token ids to floats).
  - The library comes from Homebrew or the onnxruntime release archives
    (macOS universal, Linux x64/arm64, Windows x64).
- **Scoring folded into the graph (1 day, in the research project's
  exporter).** Export encoder + mean pool + normalize + the icon-matrix
  multiply + prior + gate statistics + top-k as one ONNX graph. The module then
  returns the few best icons and the gate signal, and Elisp does almost nothing.
  The BM25 half runs in Elisp over the query's own terms only, which is cheap.
  Or it goes away once a fine-tuned model beats M3.
- **A pure-Elisp tokenizer (1–2 days).** multilingual-e5 uses XLM-R's
  SentencePiece unigram model:
  - NFKC normalization (`ucs-normalize`);
  - the `▁` word-start prefix;
  - a Viterbi search over 250k scored pieces;
  - fairseq id offsets.

  Golden ERT tests compare it with the Hugging Face tokenizer on English,
  Spanish and Russian titles. It should sit behind an interface, since a
  Qwen-style model would need byte-level BPE instead.
- **Distribution (2–3 days).** Either compile on first use, or ship prebuilt
  binaries per platform from CI. The risks:
  - the Windows toolchain;
  - onnxruntime version drift (pin the C API version the module asks for);
  - macOS quarantine on a downloaded library.

**Other routes, rejected:**
- **llama.cpp.** A single Homebrew binary, and native to decoder-based
  embedders, but it returns embeddings only. Scoring would fall to Elisp at
  about 360 ms per task.
- **Ollama.** Needs a daemon, a heavier dependency than Python.
- **Model2Vec static embeddings.** Distilled token vectors need no runtime at
  all. But scoring is still an Elisp matrix multiply, the table has 250k rows,
  and quality drops. It is worth measuring in the research project, not here.
- **A Rust module** (emacs-module-rs with the ort and tokenizers crates). It
  would have exact tokenizer parity, but it needs a Rust toolchain or prebuilt
  binaries, and emacs-module-rs is no longer maintained.
