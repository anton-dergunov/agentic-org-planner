#!/usr/bin/env python3
"""org_task_icon_matcher.py — pick a Material Symbols icon for each agenda task.

Usage:
  echo '[{"key": "1", "title": "Book a *dentist* appointment"}]' \\
    | python org_task_icon_matcher.py [BUNDLE_DIR]
  -> {"1": "dentistry"}

Input is a JSON list of tasks: {"key", "title", "parents", "body"}.  The title
keeps its org markup; the TODO keyword, priority and tags are already removed.
`parents` (outermost first) and `body` are sent only when the bundle's manifest
lists them in `query.inputs`.  Output maps each key to an icon name, or null when
no icon is a confident match (no icon is better than a wrong icon).

The matcher is a *bundle* (default: ../icons/task-matcher/): precomputed icon
matrices plus a manifest.  It is produced by the task-concept-retrieval research
project (tcr/bundle.py there, which mirrors the query building and scoring
below); this script only runs it.  The ONNX text encoder named in the manifest
is downloaded once into ~/.cache/ps-task-icons/ and verified by sha256.

Requirements: pip install onnxruntime tokenizers numpy
"""

import hashlib
import json
import re
import sys
import urllib.request
from pathlib import Path

import numpy as np

DEFAULT_BUNDLE = Path(__file__).resolve().parent.parent / "icons" / "task-matcher"
CACHE_DIR = Path.home() / ".cache" / "ps-task-icons"


# --- Query text ------------------------------------------------------------------
# "org-plain" turns org markup into plain text the way the research project's
# `normalize_text` does: the matcher was built and evaluated on text like this.

_KEYWORDS = {"TODO", "NEXT", "INPR", "WAIT", "MAYB", "DONE"}
_PRIORITY_RE = re.compile(r"^\[#[A-Za-z]\]\s*")
_TAGS_RE = re.compile(r"\s+(:(?:[A-Za-z0-9_@#%]+:)+)\s*$")
_STATS_COOKIE_RE = re.compile(r"\s*\[\d*(?:/\d*|%)\]")
_TIMESTAMP_RE = re.compile(r"[<\[]\d{4}-\d{2}-\d{2}[^>\]]*[>\]]")
_SCHEDULING_RE = re.compile(r"\b(SCHEDULED|DEADLINE|CLOSED|Started):", re.IGNORECASE)
_ORG_LINK_DESC_RE = re.compile(r"\[\[[^\]]*?\]\[([^\]]+)\]\]")
_ORG_LINK_BARE_RE = re.compile(r"\[\[([^\]]+)\]\]")
_URL_RE = re.compile(r"\bhttps?://\S+")
_MAILTO_RE = re.compile(r"\bmailto:(\S+)")
_EMPHASIS_RE = re.compile(r"(?<![\w])([*/_=~+])(\S(?:.*?\S)?)\1(?![\w])")


def _readable_from_target(target):
    """Turn a link target into readable words, or '' if it looks opaque."""
    t = target.strip()
    m = re.match(r"^[A-Za-z][A-Za-z0-9+.-]*:(.*)$", t)
    if m:
        t = m.group(1)
    t = t.lstrip("/")
    if "/" in t:
        t = t.rstrip("/").split("/")[-1]
    t = re.sub(r"[#?].*$", "", t)
    t = re.sub(r"\.[A-Za-z0-9]{1,5}$", "", t)
    t = t.replace("_", " ").replace("-", " ").strip()
    if re.fullmatch(r"[0-9a-fA-F]{8,}", t) or not re.search(r"[A-Za-z]{2,}", t):
        return ""
    return t


def org_plain(raw):
    """Org heading or body text -> plain text: no cookies, links, emphasis, stamps."""
    text = _STATS_COOKIE_RE.sub("", raw).strip()
    parts = text.split(None, 1)
    if parts and parts[0] in _KEYWORDS:
        text = parts[1] if len(parts) > 1 else ""
    text = _PRIORITY_RE.sub("", text)
    tags = _TAGS_RE.search(text)
    if tags:
        text = text[: tags.start()]
    text = _SCHEDULING_RE.sub(" ", text)
    text = _TIMESTAMP_RE.sub(" ", text)
    text = _ORG_LINK_DESC_RE.sub(lambda m: m.group(1), text)
    text = _ORG_LINK_BARE_RE.sub(lambda m: _readable_from_target(m.group(1)), text)
    text = _MAILTO_RE.sub(lambda m: _readable_from_target(m.group(1)), text)
    text = _URL_RE.sub(lambda m: _readable_from_target(m.group(0)), text)
    prev = None
    while prev != text:  # nested/adjacent markers
        prev = text
        text = _EMPHASIS_RE.sub(lambda m: m.group(2), text)
    return re.sub(r"\s+", " ", text).strip()


NORMALIZERS = {"org-plain": org_plain, "none": str.strip}


def compose_query(task, spec):
    """The title, prefixed by the nearest parent and followed by a body prefix
    when the manifest lists those inputs."""
    norm = NORMALIZERS[spec["normalize"]]
    text = norm(task.get("title") or "")
    parents = task.get("parents") or []
    if "parents" in spec["inputs"] and parents:
        parent = norm(parents[-1])
        text = f"{parent}: {text}" if parent else text
    body = task.get("body") or ""
    if "body" in spec["inputs"] and body:
        body = norm(body.replace("\n", " "))[: spec["body_chars"]]
        text = f"{text}. {body}" if text else body
    return text


# --- Encoder ---------------------------------------------------------------------

def fetch(spec):
    """Local copy of SPEC ({url, sha256}), downloaded once into CACHE_DIR."""
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    path = CACHE_DIR / f"{spec['sha256'][:16]}-{spec['url'].rsplit('/', 1)[-1]}"
    if path.exists():
        return path
    size = spec.get("size", 0) / 1e6
    print(f"[task-icons] downloading {spec['url'].rsplit('/', 1)[-1]} ({size:.0f} MB)",
          file=sys.stderr, flush=True)
    tmp = path.with_suffix(path.suffix + ".part")
    urllib.request.urlretrieve(spec["url"], tmp)
    h = hashlib.sha256()
    with open(tmp, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    if h.hexdigest() != spec["sha256"]:
        tmp.unlink()
        raise RuntimeError(f"sha256 mismatch for {spec['url']}")
    tmp.replace(path)
    return path


class Encoder:
    """tokenizer -> ONNX transformer -> mean pool -> L2 normalize."""

    def __init__(self, spec):
        import onnxruntime as ort
        from tokenizers import Tokenizer

        self.tokenizer = Tokenizer.from_file(str(fetch(spec["tokenizer"])))
        self.tokenizer.enable_truncation(spec["max_length"])
        opts = ort.SessionOptions()
        opts.log_severity_level = 3
        # Basic graph optimizations only: onnxruntime 1.27's layer-norm fusion
        # fails to load the fp16 encoder (fixed by 1.30), and the exporter and
        # the runner must run the same graph to give the same answers.
        opts.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_BASIC
        self.session = ort.InferenceSession(str(fetch(spec["model"])), opts,
                                            providers=["CPUExecutionProvider"])
        self.inputs = {i.name for i in self.session.get_inputs()}
        self.prefix = spec["query_prefix"]

    def encode(self, text):
        """One L2-normalized vector.  Texts are never batched: an int8 model
        quantizes activations with a scale taken over the whole input, so in a
        batch a text's vector (and so its icon) would depend on its batch mates."""
        ids = np.array([self.tokenizer.encode(self.prefix + text).ids], dtype=np.int64)
        feeds = {"input_ids": ids, "attention_mask": np.ones_like(ids)}
        if "token_type_ids" in self.inputs:
            feeds["token_type_ids"] = np.zeros_like(ids)
        pooled = self.session.run(None, feeds)[0][0].mean(axis=0)
        return pooled / max(float(np.linalg.norm(pooled)), 1e-12)


# --- Scoring ---------------------------------------------------------------------

def confidence(scores):
    """How many standard deviations the best icon stands above the rest."""
    std = float(scores.std())
    return 0.0 if std <= 1e-9 else (float(scores.max()) - float(scores.mean())) / std


class Matcher:
    """A bundle's members (BM25 and/or dense), fused by reciprocal rank, gated."""

    def __init__(self, bundle_dir, encoder=None):
        bundle_dir = Path(bundle_dir)
        m = json.loads((bundle_dir / "manifest.json").read_text(encoding="utf-8"))
        self.manifest = m
        self.names = (bundle_dir / m["icons"]).read_text(encoding="utf-8").split()
        self.dense = np.load(bundle_dir / m["dense"]["matrix"]).astype(np.float32)
        self.prior = np.load(bundle_dir / m["dense"]["prior"]).astype(np.float32)
        self.bm25 = None
        if m.get("bm25"):
            with np.load(bundle_dir / m["bm25"]["matrix"]) as z:
                self.bm25 = {k: z[k] for k in ("indptr", "indices", "data")}
                self.vocab = {t: i for i, t in enumerate(z["vocab"].tolist())}
            self.token_re = re.compile(m["bm25"]["token_pattern"])
        self.encoder = encoder or Encoder(m["encoder"])

    def bm25_scores(self, text):
        raw = np.zeros(len(self.names), dtype=np.float32)
        for tok in self.token_re.findall(text.casefold()):
            r = self.vocab.get(tok)
            if r is not None:
                lo, hi = self.bm25["indptr"][r], self.bm25["indptr"][r + 1]
                raw[self.bm25["indices"][lo:hi]] += self.bm25["data"][lo:hi]
        sat = self.manifest["bm25"]["saturation"]
        scores = raw / (raw + sat)
        scores[raw <= 0] = 0.0
        return scores

    def decide(self, text, qvec):
        """The icon for one query, or None when the gate abstains."""
        members = []
        if self.bm25 is not None:
            members.append(self.bm25_scores(text))
        members.append(self.dense @ qvec + self.prior)
        fusion = self.manifest["fusion"]
        if max(confidence(s) for s in members) < fusion["threshold"]:
            return None
        if len(members) == 1:
            return self.names[int(np.argmax(members[0]))]
        rrf = {}
        for scores in members:
            for rank, i in enumerate(np.argsort(-scores)[: fusion["pool"]]):
                if scores[i] <= 0:  # a member ranks only what it matched
                    break
                rrf[int(i)] = rrf.get(int(i), 0.0) + 1.0 / (fusion["rrf_k"] + rank + 1)
        return self.names[max(rrf, key=rrf.get)] if rrf else None

    def match(self, tasks):
        spec = self.manifest["query"]
        texts = [compose_query(t, spec) for t in tasks]
        return {t["key"]: (self.decide(x, self.encoder.encode(x)) if x else None)
                for t, x in zip(tasks, texts)}


def main():
    bundle = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_BUNDLE
    tasks = json.loads(sys.stdin.read() or "[]")
    if not isinstance(tasks, list):
        raise SystemExit("input must be a JSON list of tasks")
    print(json.dumps(Matcher(bundle).match(tasks), ensure_ascii=False))


if __name__ == "__main__":
    main()
