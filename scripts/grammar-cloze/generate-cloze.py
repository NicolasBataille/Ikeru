#!/usr/bin/env python3
"""Build the fill-in-the-blank exercise for every grammar point.

Writes two columns on ``grammar_points``:

- ``cloze_sentence`` — the first example's JAPANESE with the grammar element
  replaced by ``____`` (four underscores). The translation is deliberately NOT
  stored here: it is derived at read time from the already-localised
  ``examples`` column, so a French learner sees a French gloss. Freezing it
  here shipped an English translation under a French UI (device, 2026-08-19).
- ``cloze_answer`` — the exact substring that was removed.

The answer is derived from the point's title where that works (37 of 51), and
read from ``answers.json`` otherwise. The 14 exceptions are not sloppiness in
the titles: a title carries the DICTIONARY form (ている, てはいけない, すぎる)
while the example is in the POLITE form (ています, てはいけません, すぎました);
or it contains a wildcard (〜のほうが〜より); or its kana is written in kanji in
the example (まえに → 前に).

**It refuses to guess.** A point whose answer cannot be located verbatim in its
example is reported and left without a cloze — the exercise simply skips it —
rather than shipping a blank in the wrong place. A learner who is taught to
fill the wrong slot learns the wrong pattern.

Usage:
    python3 scripts/grammar-cloze/generate-cloze.py [--db PATH] [--check]
"""
from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
DEFAULT_DB = REPO / "Ikeru" / "Resources" / "ContentBundles" / "n5-content.sqlite"
ANSWERS = HERE / "answers.json"

BLANK = "____"


def derived_answer(title: str, sentence: str) -> str | None:
    """The title's pattern, when it appears verbatim in the sentence."""
    pattern = title.split("(")[0].strip().replace("〜", "").replace("～", "").strip()
    for candidate in [pattern] + [part.strip() for part in pattern.split("/")]:
        if candidate and candidate in sentence:
            return candidate
    return None


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--check", action="store_true", help="verify without writing")
    args = parser.parse_args(argv)

    overrides = json.loads(ANSWERS.read_text(encoding="utf-8"))["answers"]
    con = sqlite3.connect(args.db)
    rows = con.execute("SELECT id, title, examples FROM grammar_points ORDER BY id").fetchall()

    updates: list[tuple[str, str, int]] = []
    problems: list[str] = []

    for point_id, title, examples_json in rows:
        examples = json.loads(examples_json)
        if not examples:
            problems.append(f"{point_id} {title}: aucun exemple")
            continue
        first = examples[0]
        japanese, _, translation = first.partition(" — ")
        japanese = japanese.strip()

        answer = overrides.get(str(point_id)) or derived_answer(title, japanese)
        if not answer:
            problems.append(f"{point_id} {title}: motif introuvable dans « {japanese} »")
            continue
        if answer not in japanese:
            problems.append(
                f"{point_id} {title}: réponse « {answer} » absente de « {japanese} »")
            continue

        # Japonais SEUL. La traduction n'est PAS figée ici : elle est dérivée à
        # la lecture depuis la colonne `examples` déjà localisée, sinon un
        # apprenant en français lisait la traduction anglaise — constaté sur
        # device le 2026-08-19. Le japonais de `examples[0]` est identique dans
        # les deux langues pour les 51 points (vérifié), donc le trou posé ici
        # vaut pour les deux.
        _ = translation
        blanked = japanese.replace(answer, BLANK, 1)
        updates.append((blanked, answer, point_id))

    print(f"points                 : {len(rows)}")
    print(f"exercices construits   : {len(updates)}")
    print(f"sans exercice          : {len(problems)}")
    for problem in problems:
        print("   " + problem)

    if args.check:
        print("\n(--check : rien écrit)")
        return 1 if problems else 0

    columns = {row[1] for row in con.execute("PRAGMA table_info(grammar_points)")}
    if "cloze_sentence" not in columns:
        con.execute("ALTER TABLE grammar_points ADD COLUMN cloze_sentence TEXT")
    if "cloze_answer" not in columns:
        con.execute("ALTER TABLE grammar_points ADD COLUMN cloze_answer TEXT")
    con.executemany(
        "UPDATE grammar_points SET cloze_sentence=?, cloze_answer=? WHERE id=?", updates)
    con.commit()
    con.execute("VACUUM")
    con.close()
    print(f"\nécrit dans {args.db}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
