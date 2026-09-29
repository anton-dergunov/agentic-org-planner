"""Tests for scripts/org_task_icon_matcher.py.

A tiny bundle is written per test (three icons, 4-d vectors) and the ONNX
encoder is replaced by a stub, so nothing is downloaded.
"""

import io
import json

import numpy as np
import pytest

import scripts.org_task_icon_matcher as m

NAMES = ["savings", "dentistry", "grocery"]
VOCAB = ["dentist", "money", "save", "shop"]
# BM25 weights, vocab x icons, as CSR rows: dentist->dentistry, money/save->savings,
# shop->grocery.
BM25_ROWS = {"dentist": [(1, 2.0)], "money": [(0, 1.5)], "save": [(0, 1.0)], "shop": [(2, 1.0)]}


def _write_bundle(path, *, inputs=("title",), normalize="org-plain", bm25=True,
                  threshold=1.0):
    dense = np.eye(3, 4, dtype=np.float16)          # icon i <-> basis vector i
    np.save(path / "dense.npy", dense)
    np.save(path / "prior.npy", np.zeros(3, dtype=np.float32))
    (path / "names.txt").write_text("\n".join(NAMES) + "\n")
    indptr, indices, data = [0], [], []
    for t in VOCAB:
        for i, w in BM25_ROWS[t]:
            indices.append(i)
            data.append(w)
        indptr.append(len(indices))
    np.savez_compressed(path / "bm25.npz", vocab=np.array(VOCAB),
                        indptr=np.array(indptr, dtype=np.int32),
                        indices=np.array(indices, dtype=np.int32),
                        data=np.array(data, dtype=np.float32))
    manifest = {
        "format": 1, "tag": "test", "icons": "names.txt",
        "encoder": {"query_prefix": "query: "},
        "query": {"inputs": list(inputs), "normalize": normalize, "body_chars": 20},
        "dense": {"matrix": "dense.npy", "prior": "prior.npy"},
        "bm25": ({"matrix": "bm25.npz", "token_pattern": r"[^\W_]+", "saturation": 8.0}
                 if bm25 else None),
        "fusion": {"rrf_k": 60, "pool": 3, "threshold": threshold},
    }
    (path / "manifest.json").write_text(json.dumps(manifest))
    return path


class StubEncoder:
    """Maps a text to a basis vector by keyword; unknown text to a flat vector."""

    def __init__(self):
        self.seen = []

    def encode(self, text):
        self.seen.append(text)
        for i, word in enumerate(["money", "dentist", "shop"]):
            if word in text.lower():
                v = np.full(4, 0.05, dtype=np.float32)
                v[i] = 1.0
                return v / np.linalg.norm(v)
        return np.full(4, 0.5, dtype=np.float32)


@pytest.fixture
def bundle(tmp_path):
    return _write_bundle(tmp_path)


# --- query text --------------------------------------------------------------------

@pytest.mark.parametrize("raw, want", [
    ("Read the *attention* paper [1/3]", "Read the attention paper"),
    ("See [[https://example.com/docs/setup-guide.html][the guide]]", "See the guide"),
    ("Open [[obsidian:Money-Plan]]", "Open Money Plan"),
    ("Check https://example.com/tax_return.pdf", "Check tax return"),
    ("Прочитать /главу/ книги", "Прочитать главу книги"),
    ("Reservar cita con el =dentista=", "Reservar cita con el dentista"),
    ("TODO [#A] Pay rent   :home:", "Pay rent"),
])
def test_org_plain(raw, want):
    assert m.org_plain(raw) == want


def test_compose_title_only_ignores_other_fields():
    spec = {"inputs": ["title"], "normalize": "org-plain", "body_chars": 20}
    task = {"title": "Pay *rent*", "parents": ["Home"], "body": "Landlord account"}
    assert m.compose_query(task, spec) == "Pay rent"


def test_compose_parent_and_body():
    spec = {"inputs": ["title", "parents", "body"], "normalize": "org-plain", "body_chars": 10}
    task = {"title": "Pay rent", "parents": ["Life", "*Home*"], "body": "Landlord\naccount details"}
    assert m.compose_query(task, spec) == "Home: Pay rent. Landlord a"


def test_compose_keeps_markup_when_asked():
    spec = {"inputs": ["title"], "normalize": "none", "body_chars": 0}
    assert m.compose_query({"title": " Read *this* "}, spec) == "Read *this*"


# --- scoring -----------------------------------------------------------------------

def test_bm25_scores_sum_rows_per_token_occurrence(bundle):
    matcher = m.Matcher(bundle, encoder=StubEncoder())
    raw = 1.5 + 1.5 + 1.0                                # money twice, save once
    scores = matcher.bm25_scores("Save money, MONEY!")
    assert scores[0] == pytest.approx(raw / (raw + 8.0))
    assert scores[1] == scores[2] == 0.0


def test_confidence_is_zero_for_flat_scores():
    assert m.confidence(np.ones(5)) == 0.0
    assert m.confidence(np.array([0.0, 0.0, 0.0, 1.0])) > 1.0


def test_match_picks_fused_top_icon(bundle):
    matcher = m.Matcher(bundle, encoder=StubEncoder())
    got = matcher.match([{"key": "a", "title": "Book the *dentist*"},
                         {"key": "b", "title": "Save money"}])
    assert got == {"a": "dentistry", "b": "savings"}


def test_gate_abstains_when_nothing_stands_out(tmp_path):
    matcher = m.Matcher(_write_bundle(tmp_path, threshold=5.0), encoder=StubEncoder())
    assert matcher.match([{"key": "a", "title": "Book the dentist"}]) == {"a": None}


def test_dense_only_bundle(tmp_path):
    matcher = m.Matcher(_write_bundle(tmp_path, bm25=False), encoder=StubEncoder())
    assert matcher.match([{"key": "a", "title": "go shopping"}]) == {"a": "grocery"}


def test_empty_title_is_not_encoded(bundle):
    enc = StubEncoder()
    got = m.Matcher(bundle, encoder=enc).match([{"key": "a", "title": "  [2/5] "}])
    assert got == {"a": None}
    assert enc.seen == []


# --- protocol ----------------------------------------------------------------------

def test_main_reads_tasks_and_prints_json(bundle, monkeypatch, capsys):
    monkeypatch.setattr(m, "Encoder", lambda spec: StubEncoder())
    monkeypatch.setattr("sys.argv", ["org_task_icon_matcher.py", str(bundle)])
    monkeypatch.setattr("sys.stdin", io.StringIO(json.dumps(
        [{"key": "{\"title\":\"Buy at the shop\"}", "title": "Buy at the shop"}])))
    m.main()
    assert json.loads(capsys.readouterr().out) == {"{\"title\":\"Buy at the shop\"}": "grocery"}


def test_member_with_no_match_does_not_vote(bundle):
    """BM25 knows no word of a Russian title: its all-zero scores must not rank
    icon 0 first, or it would tie the dense pick and win."""
    matcher = m.Matcher(bundle, encoder=StubEncoder())
    assert matcher.bm25_scores("Купить продукты").max() == 0.0
    # The stub maps this to icon 2 (grocery); icon 0 (savings) must not win.
    assert matcher.match([{"key": "a", "title": "Купить shop"}]) == {"a": "grocery"}
    assert matcher.decide("Купить продукты", StubEncoder().encode("shop")) == "grocery"
