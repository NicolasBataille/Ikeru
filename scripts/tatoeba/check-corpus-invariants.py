#!/usr/bin/env python3
"""Assert the invariants the sentence corpus must hold, straight off the bundle.

Written during the adversarial review of `feat/sentence-corpus`. Every check
below FAILS on that branch's bundle — they are the proof of the defects, not a
green rubber stamp. Run:

    python3 scripts/tatoeba/check-corpus-invariants.py

Exit code 0 when every invariant holds, 1 otherwise.

The three invariants, and why each is a learner-visible defect when broken:

1. **A word's example must contain that word.** The reader is "examples for
   word W" — a card for 五つ (いつつ, "five things") illustrated by 五時 (ごじ,
   "five o'clock") teaches the wrong reading of the right kanji. Only forms a
   word genuinely takes are accepted: a counter or plain noun never inflects,
   an い-adjective takes a closed set of endings.

2. **No two examples of the same word may share one French gloss.** Two rows
   with the identical translation spend two of a word's few example slots on
   the same lesson.

3. **No Japanese sentence may appear twice in the table.** `build-corpus.py`
   drops candidates already bundled, but `apply-tatoeba-sentences.py` only
   dedupes *within* its JSON — so the invariant has two owners and neither
   holds it end to end. Feeding the apply script a JSON row whose Japanese
   already exists as an `ikeru` row inserts the duplicate silently.
"""

from __future__ import annotations

import re
import sqlite3
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
DEFAULT_DB = REPO_ROOT / "Ikeru" / "Resources" / "ContentBundles" / "n5-content.sqlite"

KANJI_RE = re.compile(r"[㐀-䶿一-鿿豈-﫿]")
VERB_ENDINGS = "うくぐすつぬぶむる"

#: い-adjective: the stem takes exactly these continuations. 高校 is not one.
I_ADJECTIVE_TAILS = ("い", "く", "かっ", "けれ", "さ", "すぎ", "め", "そう")


#: A word opening on a numeral kanji is a number or a counter — 一つ, 五つ, 千.
#: It never inflects, whatever its last kana looks like: 五つ ends in つ, which
#: is also a godan verb ending, and that coincidence is precisely how the
#: funnel's stem rule filed 五時 under 五つ.
NUMERAL_RE = re.compile(r"^[一二三四五六七八九十百千万]")


def word_class(word: str, reading: str) -> str:
    """Rough part of speech, enough to know which surface forms are legitimate."""
    if NUMERAL_RE.match(word):
        return "invariable"
    if len(word) >= 2 and word.endswith("い") and reading.endswith("い"):
        return "i-adjective"
    if len(word) >= 2 and word[-1] in VERB_ENDINGS and reading[-1:] == word[-1:]:
        return "verb"
    return "invariable"


def accepted_forms(word: str, kind: str) -> list[str]:
    if kind == "i-adjective":
        return [word[:-1] + tail for tail in I_ADJECTIVE_TAILS]
    return [word]


def check_word_present(rows: list[tuple], vocab: dict[str, str]) -> list[str]:
    """Invariant 1 — only invariable words and い-adjectives are judged here.

    Verbs are left out on purpose: their conjugation table is wide enough that
    a surface test would produce noise rather than proof.
    """
    failures = []
    for japanese, french, word, ja_id in rows:
        reading = vocab.get(word, "")
        kind = word_class(word, reading)
        if kind == "verb":
            continue
        if any(form in japanese for form in accepted_forms(word, kind)):
            continue
        failures.append(
            f"  {word} ({reading}) is filed on «{japanese}» "
            f"[tatoeba {ja_id}] — «{french}» — the word never occurs in it"
        )
    return failures


def check_no_repeated_gloss(rows: list[tuple]) -> list[str]:
    """Invariant 2."""
    by_word: dict[str, dict[str, list[str]]] = {}
    for japanese, french, word, _ in rows:
        by_word.setdefault(word, {}).setdefault(french, []).append(japanese)
    failures = []
    for word in sorted(by_word):
        for french, japaneses in by_word[word].items():
            if len(japaneses) > 1:
                failures.append(
                    f"  {word}: {len(japaneses)} examples share the gloss "
                    f"«{french}» — {' / '.join(japaneses)}"
                )
    return failures


def check_no_duplicate_japanese(conn: sqlite3.Connection) -> list[str]:
    """Invariant 3."""
    duplicates = conn.execute(
        "SELECT japanese, COUNT(*) FROM sentences GROUP BY japanese HAVING COUNT(*) > 1"
    ).fetchall()
    return [f"  «{japanese}» appears {count} times" for japanese, count in duplicates]


def main(argv: list[str]) -> int:
    db_path = Path(argv[0]) if argv else DEFAULT_DB
    conn = sqlite3.connect(db_path)
    vocab = {row[0]: row[1] or "" for row in conn.execute("SELECT word, reading FROM vocabulary")}
    rows = conn.execute(
        "SELECT japanese, french, vocabulary_word, tatoeba_ja_id FROM sentences "
        "WHERE source = 'tatoeba'"
    ).fetchall()

    checks = [
        ("1. every example contains the word it is filed under", check_word_present(rows, vocab)),
        ("2. no two examples of a word share a French gloss", check_no_repeated_gloss(rows)),
        ("3. no Japanese sentence appears twice", check_no_duplicate_japanese(conn)),
    ]
    conn.close()

    failed = 0
    for label, failures in checks:
        if failures:
            failed += 1
            print(f"FAIL {label} — {len(failures)} violation(s)")
            for line in sorted(failures):
                print(line)
        else:
            print(f"ok   {label}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
