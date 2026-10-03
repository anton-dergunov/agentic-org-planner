# Screenshots

The pictures in the README and the docs. They are real screenshots of this configuration, not
mock-ups, taken over the sample notes. This file is how to retake them: each scene is described
well enough to rebuild by hand, or to hand to a coding agent. Scenes with a live Claude Code
conversation can't be replayed by a script, so there isn't one.

## Format

- PNG, 1920×1200 (16:10), the format of the blog's project pictures.
- Solarized Light, the default theme. Other themes appear only in the docs' gallery.
- Frame 1280×800 points, or 1440×900 for the two agent scenes, which need room for the
  Claude Code panel. `ps/screenshot-frame` captures the frame and scales it to 1920 pixels
  wide, so both sizes come out the same.

## Taking them

```bash
scripts/make_screenshot_vault.py --dest /tmp/ps-screenshot
env $(env | grep -E '^(CLAUDE|CLAUDECODE)' | sed 's/=.*//; s/^/-u /') \
  PS_ORG_BASE=/private/tmp/ps-screenshot/notes \
  ./scripts/run_emacs_dev.sh -l "$PWD/scripts/screenshot.el"
```

- The vault script copies `samples/realistic/` and moves every date so that the sample's busiest
  day (2026-05-21) is today. The agenda, the schedule's now-line, availability and conflicts then
  agree without faking the clock. Take the agenda and schedule shots on a **weekday, late
  morning**: the now-line then sits between events, and the date header is not drawn in the
  weekend face.
- It also copies the capture-inbox fixture (`samples/info-triage/`) beside the notes, and
  `screenshot.el` points the Triage feature at it.
- Open the vault through `/private/tmp/...`, the path it is registered under, or the mode line
  shows the full path instead of the file's name.
- Strip the `CLAUDE*` variables when launching from inside a Claude Code session, as above:
  otherwise the panel's Claude inherits the outer session's settings.
- `M-x ps/screenshot-frame` saves `screenshots/<name>.png`. It clears the echo area first.
  An agent can drive the session with `emacsclient -s ps-shots --eval ...`; type into the
  Claude panel with `claude-code-ide-send-prompt`.
- Leave the cursor on a blank line or a task, never on `#+TITLE:` (it reveals the raw keyword).

## The shots

In carousel order. The blog uses 1, 2, 4, 5, 6 and 9.

| # | File | Scene |
|---|---|---|
| 1 | `agent-audit.png` | 1440×900. File tree, `ML/ML.org`, Claude Code at 70 columns in manual mode (Shift+Tab until the footer says so, or edits won't wait for review). Prompt `/audit ML/ML.org`; approve its fetches. Reply with the number of one finding that edits the file, and capture with its diff open. |
| 2 | `agent-route.png` | 1440×900. `triage.org` of the fixture queue, Claude Code beside it. Prompt `/route the triage inbox`; capture the routing table, with the duplicate caught. |
| 3 | `capture-inbox.png` | `C-c p I`: the queue with one item selected and its `index.md` rendered beside it. |
| 4 | `agenda.png` | File tree + `C-c p a`, point on the first scheduled task. |
| 5 | `schedule.png` | The agenda's Schedule section on top (15 lines), `ps/show-conflicts` below it (11 lines), `ps/org-show-availability` at the bottom, all full width. |
| 6 | `plan-file.png` | `Work/Career.org` from the top, with "Map current strengths" folded so the retrieval task's code and link show. Point on line 13. |
| 7 | `file-tree.png` | The tree with `ML` (the file) expanded to its headings (TAB on it), `ML/ML.org` beside it. |
| 8 | `situations.png` | `C-c p S m`: "A spare minute". |
| 9 | `blank-lines.png` | In the playground from `scripts/make_blank_line_playground.sh`, F7 on a damaged file: the review with the restored blank lines. |

`plan-file-<theme>.png` repeat shot 6 under another theme (`M-x ps/preview-theme`) for the
gallery in `docs/Customization.org`.
