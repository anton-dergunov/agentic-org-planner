# Screenshots

The pictures in the README and the docs. They are real screenshots of this configuration, not
mock-ups, taken over the sample notes. This file is how to retake them: each scene is described
well enough to rebuild by hand, or to hand to a coding agent. Scenes with a live Claude Code
conversation can't be replayed by a script, so there isn't one.

## Format

- PNG, 1920×1200 (16:10), the format of the blog's project pictures, with transparent rounded
  corners.
- Solarized Light, the default theme. Other themes appear only in the docs' gallery.
- Frame 1067×667 points; 1280×800 for the lead and 1200×750 for `/route`, which need room for the Claude
  Code panel. The frame is small on purpose: scaled to 1920 pixels wide, its text comes out
  large enough to read on a project card.

## Taking them

```bash
scripts/make_screenshot_vault.py --dest /tmp/ps-screenshot/vault
env $(env | grep -E '^(CLAUDE|CLAUDECODE)' | sed 's/=.*//; s/^/-u /') \
  PS_ORG_BASE=/private/tmp/ps-screenshot/vault/notes \
  ./scripts/run_emacs_dev.sh -l "$PWD/scripts/screenshot.el"
```

- The vault script copies `samples/realistic/` and moves every date so that the sample's busiest
  day (2026-05-21) is today. The agenda, the schedule's now-line, availability and conflicts then
  agree without faking the clock. Take the agenda and schedule shots on a **weekday, late
  morning**: the now-line then sits between events, and the date header is not drawn in the
  weekend face.
- It also copies the capture-inbox sample (`samples/info-triage/`) beside the notes, and
  `screenshot.el` points the Triage feature and the agent's context at it.
- For this session only, `screenshot.el` hides the sync label and Ediff's "Type ? for help",
  shows the scratch folder as `~/` in the mode line, and teaches the typo checker a few real
  words it flags ("agentic", "tokenizer", "quantized").
- Open files through `/private/tmp/...`, the path the vault is registered under, or the mode line
  shows the full path instead of the file's name.
- Strip the `CLAUDE*` variables when launching from inside a Claude Code session, as above:
  otherwise the panel's Claude inherits the outer session's settings.
- `M-x ps/screenshot-frame` saves `screenshots/<name>.png`, by window id so the corners come out
  transparent. An agent drives the session with `emacsclient -s ps-shots --eval ...`, and types
  into the Claude panel with `claude-code-ide-send-prompt`.
- Leave the cursor on a task or a blank line, never on `#+TITLE:` (it reveals the raw keyword).
- After a theme change, redraw before capturing (`font-lock-ensure` in each visible buffer and
  `redraw-frame`), or the old theme's faces linger around the TODO badges.

## The shots

In carousel order. The blog uses 1, 2, 4, 5, 6 and 9.

| # | File | Scene |
|---|---|---|
| 1 | `agent-audit.png` | 1280×800. File tree at 22 columns, `ML/ML.org`, Claude Code at 56 columns, a fresh session in manual mode (Shift+Tab until the footer says so). `/audit ML/ML.org line 5 — vet lens; one finding in at most 4 lines; put links in the task, no sources list`; approve its web reads; then `apply 1` and `M-x ps/screenshot-inline-diff`. A composite, because Claude Code's tool-call lines push the prompt off screen: capture once at the edit prompt (B) and once with the panel paged up so the prompt shows (A), printing `(ps/screenshot-panel-rows)` to a file each time, then run `scripts/compose_lead_screenshot.py A.png rows-a.txt B.png rows-b.txt screenshots/agent-audit.png`. It keeps the prompt, the first Web Search call when there is room, the reply, `apply 1` and the edit dialog, and drops the other tool-call lines; tune the panel width until it reports no more than a few free lines above the prompt. Before capturing, the proposed buffer (not the sample file) gets a little variety in its LLM Evaluation section, so the plan shows more than plain TODOs: `[#A]` on the first task; "Compare judge-model approaches" as INPR with a one-line note using /italic/, *bold* and =code=; "Study pairwise ranking evaluation" as NEXT with a `SCHEDULED:` date three days ahead; "Learn about calibration metrics" as DONE. |
| 2 | `agent-route.png` | 1200×750. `triage.org` of the sample queue, Claude Code beside it. `/clear`, then `/route the triage inbox, items from 2026-08-18: exactly one short line per item (decision → file § section), no explanations; stay in this folder, no web search`. Approve only read-only commands inside the notes folder; decline anything that looks outside it. |
| 3 | `capture-inbox.png` | `C-c p I`, RET on item 4 (the paper). Queue scrolled to its first day, `index.md` scrolled to its Sources. |
| 4 | `agenda.png` | File tree + `C-c p a`, point on the first scheduled task. |
| 5 | `schedule.png` | No file tree. The Calendar's day view (`C-c p c d`) top left, `ps/show-conflicts` (Include past on) top right, `ps/org-show-availability` in its inline layout across the bottom, about 14 lines. Redraw the Calendar and Conflicts once their windows have their final widths. |
| 6 | `plan-file.png` | `Work/Career.org` from the top, point at the end of line 12. |
| 7 | `file-tree.png` | Tree widened to 62 columns, `ML` (the file) expanded, then its "Foundation Models" and "LLM Evaluation" headings; `ML/ML.org` beside it. |
| 8 | `situations.png` | Tree at 17 columns. `C-c p S m`, the task "Map current strengths and weaknesses" open in an 11-line window below, then the "Situations ▾" menu open as a dropdown. The menu is modal: open it from a timer with a click posn about 330 pt left of the button's right edge, just under it, grab the frame region from the shell with `screencapture -R`, press Escape, then round the corners with `ps/screenshot--round-corners`. |
| 9 | `blank-lines.png` | In the playground from `scripts/make_blank_line_playground.sh`, F7, then `d` on `Body/Health.org`; report narrowed to 60 columns, panes balanced, `ps/screenshot-hide-ediff-control`. |

`plan-file-tango.png` and `plan-file-modus-vivendi.png` repeat shot 6 under those themes
(`M-x ps/preview-theme`) for the gallery in `docs/Customization.org`.
