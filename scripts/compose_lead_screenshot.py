#!/usr/bin/env python3
"""Rebuild the Claude panel of the lead screenshot from two captures.

The lead picture has to show a whole exchange -- the prompt, Claude's reply, the
"apply N" answer and the edit dialog -- but between them Claude Code prints its
tool calls (searches, fetches, "Update"), which push the prompt off the screen
and say little about this project.  This keeps the four parts, plus the first
web search when there is room for it, and drops the rest.  Nothing Claude wrote is changed: every part is cut whole from a capture.

    scripts/compose_lead_screenshot.py A.png rows-a.txt B.png rows-b.txt OUT.png

A is a capture with the panel paged up (prompt visible), B one with the panel at
the bottom (edit dialog visible).  Each rows file is what `ps/screenshot-panel-rows'
(scripts/screenshot.el) printed at that moment: the panel's edges and the picture
row of every terminal line.  Everything outside the panel is B, untouched.
Needs ImageMagick and pngquant.  See screenshots/README.md, shot 1.
"""
import re, subprocess, sys
a_png, a_rows, b_png, b_rows, out = sys.argv[1:]

def load(path):
    text = open(path).read()
    geo = {k: int(v) for k, v in re.findall(r":(x0|x1|top|bottom|line) (\d+)", text)}
    rows = [(int(y), s.replace('\\"', '"')) for y, s in re.findall(r'\((\d+)\s+"((?:[^"\\]|\\.)*)"\)', text)]
    return geo, rows

def block(rows, start, end, bottom):
    """(y0, y1) from the first row matching START to the row after the last matching END."""
    ys = [y for y, _ in rows]
    i = next((k for k, (_, s) in enumerate(rows) if re.search(start, s)), None)
    if i is None: return None
    j = max((k for k, (_, s) in enumerate(rows) if k >= i and re.search(end, s)), default=None)
    if j is None: return None
    # The end line may wrap: run on to the end of its paragraph.
    while (j + 1 < len(rows) and rows[j + 1][1].strip()
           and not rows[j + 1][1].startswith(("❯", "⏺", "✻", "─"))):
        j += 1
    y1 = ys[j + 1] if j + 1 < len(ys) else bottom
    return ys[i], y1

ga, ra = load(a_rows); gb, rb = load(b_rows)
x0, w, line = gb["x0"], gb["x1"] - gb["x0"], gb["line"]

def find(start, end, prefer):
    for name, g, rows, png in prefer:
        b = block(rows, start, end, g["bottom"])
        if b: return png, b
    sys.exit(f"block not found whole: {start}")

A = ("A", ga, ra, a_png); B = ("B", gb, rb, b_png)
# The prompt ends at the first blank row after it.
def prompt_block():
    ys = [y for y, _ in ra]
    i = next(k for k, (_, s) in enumerate(ra) if s.startswith("❯ /"))
    j = next(k for k in range(i + 1, len(ra)) if not ra[k][1].strip())
    return a_png, (ys[i], ys[j])
prompt = prompt_block()
reply = find(r"^⏺ Scope|^⏺ \d\.|^  1\. ", r'Reply "apply|Pick |apply it', [B, A])
apply = find(r"^❯ apply", r"^❯ apply", [B, A])
# The dialog's rule is the last rule line above "Opened changes".
rules = [y for y, s in rb if s.startswith("──────────")]
opened = next(y for y, s in rb if "Opened changes" in s)
dialog_top = max(y for y in rules if y < opened)

def search_blocks():
    """The first Web Search call, with and without its result line: one tool
    call is kept when there is room, to show the agent looked things up."""
    ys = [y for y, _ in ra]
    i = next((k for k, (_, s) in enumerate(ra) if s.startswith("⏺ Web Search")), None)
    if i is None: return []
    j = i + 1
    while j < len(ra) and ra[j][1].strip() and not ra[j][1].lstrip().startswith("⎿"):
        j += 1
    call = (a_png, (ys[i], ys[j]))
    if j < len(ra) and ra[j][1].lstrip().startswith("⎿"):
        return [(a_png, (ys[i], ys[j + 1])), call]
    return [call]

def fits(parts):
    return dialog_top - sum(y1 - y0 + line for _, (y0, y1) in parts) >= gb["top"]

parts = next((p for p in ([prompt, w_, reply, apply] for w_ in search_blocks()) if fits(p)),
             [prompt, reply, apply])
heights = [y1 - y0 for _, (y0, y1) in parts]
if not fits(parts):
    sys.exit(f"does not fit above the dialog ({dialog_top - gb['top']}px)")
gaps = [line] * len(parts)
# With the search kept and the prompt flush against the top, close the blank
# line between the search and the reply instead: a line of air above the prompt
# reads better than a prompt jammed under the title bar.
if len(parts) == 4 and dialog_top - sum(heights) - sum(gaps) - gb["top"] < line:
    gaps[1] = 0
start = dialog_top - sum(heights) - sum(gaps)
print(f"free space above the prompt: {start - gb['top']}px ({(start - gb['top']) // line} lines)")
cmd = ["magick", b_png, "-fill", "#FDF6E3", "-draw",
       f"rectangle {x0},{gb['top']} {x0 + w - 1},{dialog_top - 1}"]
y = start
for (png, (y0, y1)), h, gap in zip(parts, heights, gaps):
    cmd += ["(", png, "-crop", f"{w}x{h}+{x0}+{y0}", "+repage", ")",
            "-geometry", f"+{x0}+{y}", "-composite"]
    y += h + gap
subprocess.run(cmd + [out], check=True)
subprocess.run(["pngquant", "--force", "--skip-if-larger", "--output", out, "256", out])
