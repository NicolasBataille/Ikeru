#!/usr/bin/env python3
"""Extract the JLPT N5 word list from Jonathan Waller's Tanos JLPT resources.

Emits ``scripts/tanos/n5-word-list.json``: one entry per word, carrying the
**written form** and its **hiragana reading** — and nothing else.

## What is taken, and what is deliberately NOT

Taken: which words are on the N5 list, and how they are read. Both are facts
about the JLPT and about Japanese.

**Not taken: the English glosses.** The deck has them (field ordinal 1) and
this script never reads that ordinal — see ``_FIELD_ORDINALS`` below, which
asserts the layout and then uses two of the three fields.

Why, since the site's licence is permissive: tanos.co.uk states "Everything on
this site (that I'm not selling), is licenced under Creative Commons 'BY'"
(retrieved 2026-08-16). But **nowhere does it state where the English meanings
came from**, and they are plausibly EDICT/JMdict-derived — in which case CC BY
was not Waller's to grant on that layer. The kanji readings in this bundle are
already KANJIDIC-derived and that was discovered *after* the app claimed
otherwise on screen (see ``AttributionView.swift``); importing a gloss column
of unverifiable provenance into a **public** repo would repeat that, with a
worse licence chain.

So Ikeru writes its own English glosses for every one of these words, exactly
as ``scripts/content-fr/`` already does for French. The list still gets
credited — CC BY asks for it, the site asks for a link, and both are cheap.

## Source

    http://www.tanos.co.uk/jlpt/jlpt5/vocab/n5-vocab-kanji-eng-hiragana.anki

An Anki 1.x deck, which is a SQLite database. Retrieved 2026-08-16: 662 facts,
three fields (0 = Front / written form, 1 = Back / English, 2 = Hiragana).

## Known defects in the source, corrected here

- ``左`` is given the reading ``はだり``; the word reads ``ひだり``. Typo in the
  source, fixed by ``_READING_CORRECTIONS``. Found by diffing the 179 words
  that overlap Ikeru's existing hand-written entries — which is the only
  reason it was caught, so do not assume the other 483 are clean.
- 163 entries have an **empty** hiragana field. All are kana-only words, where
  the reading is derivable: hiragana words read as themselves, katakana words
  transliterate. No kanji-bearing word lacks a reading (asserted below).
- 9 entries carry several readings separated by ``、`` (``木`` → ``き、もく``).
  The first is kept as the primary reading and the rest are preserved in
  ``alternate_readings`` rather than dropped.

Usage:
    python3 scripts/tanos/build-vocab-list.py           # download + write JSON
    python3 scripts/tanos/build-vocab-list.py --deck PATH   # use a local copy
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
import tempfile
import urllib.request
from pathlib import Path

DECK_URL = "http://www.tanos.co.uk/jlpt/jlpt5/vocab/n5-vocab-kanji-eng-hiragana.anki"
OUTPUT = Path(__file__).resolve().parent / "n5-word-list.json"

# Field layout of the retrieved deck. The script asserts this rather than
# trusting it: a re-uploaded deck with reordered fields would otherwise
# silently import English text into the reading column.
_FIELD_ORDINALS = {"Front": 0, "Back": 1, "Hiragana": 2}
_WRITTEN, _READING = _FIELD_ORDINALS["Front"], _FIELD_ORDINALS["Hiragana"]

# Corrections applied to the source. Keep every entry justified in the
# docstring above — a silent correction table is how a "fix" becomes a second
# undocumented source of truth.
_READING_CORRECTIONS = {"左": "ひだり"}

_KATAKANA_START, _KATAKANA_END = "ァ", "ヶ"
_KANJI_START, _KANJI_END = "一", "鿿"


class BuildError(RuntimeError):
    """Raised for any condition that must abort the run."""


def _download(url: str) -> Path:
    tmp = Path(tempfile.gettempdir()) / "tanos-n5-vocab.anki"
    with urllib.request.urlopen(url) as response:  # noqa: S310 — pinned constant
        tmp.write_bytes(response.read())
    return tmp


def _assert_layout(conn: sqlite3.Connection) -> None:
    actual = {name: ordinal for ordinal, name in conn.execute("SELECT ordinal, name FROM fieldModels")}
    if actual != _FIELD_ORDINALS:
        raise BuildError(
            f"Deck field layout changed: expected {_FIELD_ORDINALS}, got {actual}. "
            "Re-check which ordinal holds the English gloss before importing anything."
        )


def has_kanji(text: str) -> bool:
    return any(_KANJI_START <= c <= _KANJI_END for c in text)


def katakana_to_hiragana(text: str) -> str:
    """Transliterate katakana to hiragana, leaving everything else alone.

    Matches the bundle's existing convention: ``パン`` is stored with the
    reading ``ぱん``, not ``パン``. The prolonged-sound mark ``ー`` has no
    hiragana counterpart and is kept as-is.
    """
    return "".join(
        chr(ord(c) - 0x60) if _KATAKANA_START <= c <= _KATAKANA_END else c
        for c in text
    )


def extract(deck: Path) -> list[dict]:
    conn = sqlite3.connect(deck)
    try:
        _assert_layout(conn)
        rows = conn.execute(
            """
            SELECT written.value, reading.value
            FROM facts
            JOIN fields AS written ON written.factId = facts.id AND written.ordinal = ?
            JOIN fields AS reading ON reading.factId = facts.id AND reading.ordinal = ?
            """,
            (_WRITTEN, _READING),
        ).fetchall()
    finally:
        conn.close()

    entries: list[dict] = []
    seen: set[str] = set()
    for raw_word, raw_reading in rows:
        word = (raw_word or "").strip()
        if not word:
            raise BuildError("Deck contains a fact with an empty written form")
        if word in seen:
            raise BuildError(f"Deck contains {word!r} twice — dedupe rule needed")
        seen.add(word)

        reading = _READING_CORRECTIONS.get(word, (raw_reading or "").strip())
        alternates: list[str] = []
        if "、" in reading:
            primary, *alternates = [part.strip() for part in reading.split("、") if part.strip()]
            reading = primary
        if not reading:
            if has_kanji(word):
                raise BuildError(
                    f"{word!r} bears kanji but has no reading — it cannot be derived, "
                    "and guessing one would ship a wrong reading to a learner"
                )
            reading = katakana_to_hiragana(word)

        entries.append(
            {
                "word": word,
                "reading": reading,
                "alternate_readings": alternates,
            }
        )

    entries.sort(key=lambda e: e["word"])
    return entries


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--deck", type=Path, help="Local copy of the .anki deck (skips the download)")
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args()

    deck = args.deck or _download(DECK_URL)
    try:
        entries = extract(deck)
    except BuildError as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1) from error

    args.output.write_text(
        json.dumps(
            {
                "source": {
                    "name": "Tanos JLPT resources (Jonathan Waller)",
                    "url": DECK_URL,
                    "site": "http://www.tanos.co.uk/jlpt/",
                    "licence": "CC BY",
                    "retrieved": "2026-08-16",
                    "taken": "word list and hiragana readings only — English glosses deliberately not imported",
                },
                "words": entries,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    derived = sum(1 for e in entries if e["reading"] and not e["alternate_readings"])
    print(f"wrote {len(entries)} words to {args.output} ({derived} single-reading)")


if __name__ == "__main__":
    main()
