"""Tests for scripts/make_screenshot_vault.py."""

import datetime as dt

import scripts.make_screenshot_vault as m


def test_active_timestamp_moves_with_its_weekday():
    assert m.shift_timestamps("SCHEDULED: <2026-05-21 Thu>", 1) == \
        "SCHEDULED: <2026-05-22 Fri>"


def test_time_range_and_repeater_are_kept():
    assert m.shift_timestamps("<2026-05-21 Thu 10:00-12:00>", 135) == \
        "<2026-10-03 Sat 10:00-12:00>"
    assert m.shift_timestamps("<2026-05-20 Wed +1w>", 7) == "<2026-05-27 Wed +1w>"


def test_inactive_timestamp_moves_too():
    assert m.shift_timestamps("CLOSED: [2026-04-10 Fri]", -3) == \
        "CLOSED: [2026-04-07 Tue]"


def test_links_and_bare_dates_are_left_alone():
    text = "[[file:2026-05-21.org][2026-05-21]] on 2026-05-21"
    assert m.shift_timestamps(text, 10) == text


def test_journal_name_moves():
    assert m.shift_name("2026-07-13.org", 1) == "2026-07-14.org"


def test_build_lands_the_anchor_on_today(tmp_path):
    today = dt.date(2026, 10, 3)
    notes, days = m.build(tmp_path / "shots", today)
    assert days == (today - m.ANCHOR).days
    career = (notes / "Work/Career.org").read_text()
    assert "<2026-10-03 Sat 10:00-12:00>" in career
    assert "2026-05-21" not in career
    assert not (notes / ".claude").exists()
    assert (notes / ".git").is_dir()
