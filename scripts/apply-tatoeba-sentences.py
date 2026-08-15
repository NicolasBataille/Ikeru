#!/usr/bin/env python3
"""Inject the selected Tatoeba sentences into the N5 SQLite bundle.

Reads ``scripts/tatoeba/sentences.json`` (produced by
``scripts/tatoeba/build-corpus.py``) and writes it into
``Ikeru/Resources/ContentBundles/n5-content.sqlite``:

    sentences.japanese, sentences.french, sentences.vocabulary_word
    sentences.source          -- 'ikeru' | 'tatoeba'   (licence provenance)
    sentences.tatoeba_ja_id   -- Tatoeba sentence id, NULL for Ikeru rows
    sentences.tatoeba_fr_id   -- Tatoeba translation id, NULL for Ikeru rows

Why the provenance columns: the 96 original sentences are Ikeru's own, the
imported ones are Tatoeba's under CC BY 2.0 FR. Without a per-row marker the
two become impossible to tell apart, and the attribution in
``AttributionView.swift`` becomes unverifiable.

``sentences.english`` is left NULL on imported rows. The English half of a
Tatoeba pair is a *different* link that would have to be joined, deduplicated
and quality-filtered on its own, and nothing in the app reads
``sentences.english`` today. The query shape that reads this table at all is
``ContentRepository.fetchSentences`` (private, selects ``japanese`` alone),
called from ``vocabularyForKanji``, ``sentencesForVocabulary`` and
``vocabularyByLevel`` — but as of 2026-08-15 no reachable navigation path
renders what those return: ``VocabularyExamplesView``/``KanjiStudyView`` are
unreached from any navigation path (see that view's own doc comment), and the
``vocabularyByLevel`` callers (``SessionComposer``, ``LeechInterventionService``)
never look at ``exampleSentences`` — ``VocabularyItemMapper`` drops it when
mapping. A column with no reader does not justify a second import.

The script is idempotent in content: every run deletes the rows it previously
wrote (``source = 'tatoeba'``) and re-inserts them with deterministic ids, so
a second run's ``.dump`` is identical to the first's — measured, not assumed
(see ``JOURNAL.md``). The on-disk *bytes* are a different question: without a
VACUUM, SQLite reallocates pages differently after every DELETE+INSERT, which
matters because this file is a binary committed to git — a no-op re-run would
otherwise produce a several-hundred-KB diff indistinguishable from a real
content change. The script VACUUMs after every non-dry-run commit to close
that gap. It closes it to 3 bytes, not to zero: even after VACUUM, two runs
over identical content still differ in SQLite's own bookkeeping — the file
change counter, schema cookie and "version-valid-for" fields in the file
header, which the engine bumps on every write it performs, VACUUM included.
Getting from there to a literal zero-byte diff would mean patching those
fields by hand after the fact, which trades a real guarantee (content is
identical, verified by ``.dump``) for a cosmetic one. It fails loudly — a
duplicate (including one that only clashes with the bundle's non-Tatoeba
rows), a vocabulary word that matches no row, or an id collision aborts the
transaction rather than leaving the bundle half-written.

Run order when regenerating the bundle from scratch:

    python3 scripts/generate_content_bundles.py     # 96 original sentences
    python3 scripts/apply-content-fr.py             # French for those 96
    python3 scripts/apply-tatoeba-sentences.py      # this script

Usage:
    python3 scripts/apply-tatoeba-sentences.py [--db PATH] [--source FILE] [--dry-run]
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DB = REPO_ROOT / "Ikeru" / "Resources" / "ContentBundles" / "n5-content.sqlite"
DEFAULT_SOURCE = REPO_ROOT / "scripts" / "tatoeba" / "sentences.json"

#: Imported rows live above this id so they never collide with the hand-written
#: ones (currently 1…96) and stay recognisable in a raw `SELECT *`.
ID_BASE = 10_000

SOURCE_IKERU = "ikeru"
SOURCE_TATOEBA = "tatoeba"

REQUIRED_FIELDS = ("japanese", "french", "vocabulary_word", "tatoeba_ja_id", "tatoeba_fr_id")


class ApplyError(RuntimeError):
    """Raised for any condition that must abort the run."""


# MARK: - Schema helpers


def existing_columns(conn: sqlite3.Connection, table: str) -> set[str]:
    return {row[1] for row in conn.execute(f"PRAGMA table_info({table})")}


def ensure_column(conn: sqlite3.Connection, table: str, column: str, kind: str) -> bool:
    """Add ``column`` to ``table`` if absent. Returns True when added."""
    if column in existing_columns(conn, table):
        return False
    conn.execute(f"ALTER TABLE {table} ADD COLUMN {column} {kind}")
    return True


# MARK: - Loading


def load_payload(path: Path) -> list[dict]:
    if not path.exists():
        raise ApplyError(f"missing corpus file: {path}")
    with path.open(encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict) or "sentences" not in data:
        raise ApplyError(f"{path.name}: expected an object with a 'sentences' array")
    rows = data["sentences"]
    if not isinstance(rows, list) or not rows:
        raise ApplyError(f"{path.name}: 'sentences' must be a non-empty array")
    declared = data.get("count")
    if declared is not None and declared != len(rows):
        raise ApplyError(
            f"{path.name}: header says {declared} sentences, array holds {len(rows)}"
        )
    return rows


def validate(
    conn: sqlite3.Connection, rows: list[dict], known_words: set[str], source_name: str
) -> None:
    # The in-JSON check below only catches a duplicate *within this file* —
    # build-corpus.py already guarantees that. It says nothing about a
    # sentence injected straight into sentences.json that happens to repeat
    # one of the bundle's own hand-written rows. That must be checked against
    # the bundle itself: rows this script is about to DELETE (source =
    # 'tatoeba') don't count as a clash — they are what this run replaces —
    # but everything else does, including rows not yet stamped with a source
    # at all (a bundle fresh out of generate_content_bundles.py).
    existing_japanese = {
        row[0] for row in conn.execute(
            "SELECT japanese FROM sentences WHERE source IS NULL OR source <> ?",
            (SOURCE_TATOEBA,),
        )
    }
    seen_japanese: set[str] = set()
    seen_ja_ids: set[int] = set()
    for row in rows:
        for field in REQUIRED_FIELDS:
            if field not in row or row[field] in (None, ""):
                raise ApplyError(f"{source_name}: entry {row!r} has no '{field}'")
        japanese = row["japanese"]
        if japanese in seen_japanese:
            raise ApplyError(f"{source_name}: duplicate japanese sentence {japanese!r}")
        if japanese in existing_japanese:
            raise ApplyError(
                f"{source_name}: japanese sentence {japanese!r} already exists in the "
                f"bundle outside the imported Tatoeba rows — it would be inserted twice"
            )
        seen_japanese.add(japanese)
        ja_id = row["tatoeba_ja_id"]
        if not isinstance(ja_id, int) or not isinstance(row["tatoeba_fr_id"], int):
            raise ApplyError(f"{source_name}: non-integer Tatoeba id in {row!r}")
        if ja_id in seen_ja_ids:
            raise ApplyError(f"{source_name}: duplicate tatoeba_ja_id {ja_id}")
        seen_ja_ids.add(ja_id)
        if row["vocabulary_word"] not in known_words:
            raise ApplyError(
                f"{source_name}: vocabulary_word {row['vocabulary_word']!r} matches no "
                f"row in the vocabulary table — the sentence would be unreachable"
            )


# MARK: - Applying


def apply(conn: sqlite3.Connection, rows: list[dict]) -> tuple[int, int]:
    """Replace the imported rows. Returns ``(deleted, inserted)``."""
    deleted = conn.execute(
        "DELETE FROM sentences WHERE source = ?", (SOURCE_TATOEBA,)
    ).rowcount

    # Everything that is not ours is Ikeru's own writing — stamp it once so no
    # row is ever left with an unknown provenance.
    conn.execute(
        "UPDATE sentences SET source = ? WHERE source IS NULL OR TRIM(source) = ''",
        (SOURCE_IKERU,),
    )

    kept = {row[0] for row in conn.execute("SELECT id FROM sentences")}
    ordered = sorted(rows, key=lambda row: row["tatoeba_ja_id"])
    inserted = 0
    for offset, row in enumerate(ordered, start=1):
        identifier = ID_BASE + offset
        if identifier in kept:
            raise ApplyError(
                f"id {identifier} is already taken by a non-Tatoeba row — "
                f"raise ID_BASE rather than overwriting hand-written content"
            )
        conn.execute(
            "INSERT INTO sentences "
            "(id, japanese, english, vocabulary_word, french, source, "
            " tatoeba_ja_id, tatoeba_fr_id) "
            "VALUES (?, ?, NULL, ?, ?, ?, ?, ?)",
            (
                identifier,
                row["japanese"],
                row["vocabulary_word"],
                row["french"],
                SOURCE_TATOEBA,
                row["tatoeba_ja_id"],
                row["tatoeba_fr_id"],
            ),
        )
        inserted += 1
    return deleted, inserted


def verify(conn: sqlite3.Connection, expected: int) -> None:
    (unstamped,) = conn.execute(
        "SELECT COUNT(*) FROM sentences WHERE source IS NULL OR TRIM(source) = ''"
    ).fetchone()
    if unstamped:
        raise ApplyError(f"{unstamped} sentence(s) left without a source marker")

    (imported,) = conn.execute(
        "SELECT COUNT(*) FROM sentences WHERE source = ?", (SOURCE_TATOEBA,)
    ).fetchone()
    if imported != expected:
        raise ApplyError(f"expected {expected} imported rows, found {imported}")

    (holes,) = conn.execute(
        "SELECT COUNT(*) FROM sentences WHERE japanese IS NULL OR TRIM(japanese) = '' "
        "OR french IS NULL OR TRIM(french) = '' "
        "OR vocabulary_word IS NULL OR TRIM(vocabulary_word) = ''"
    ).fetchone()
    if holes:
        raise ApplyError(f"{holes} sentence(s) with an empty japanese/french/vocabulary_word")

    (orphans,) = conn.execute(
        "SELECT COUNT(*) FROM sentences s "
        "LEFT JOIN vocabulary v ON v.word = s.vocabulary_word WHERE v.word IS NULL"
    ).fetchone()
    if orphans:
        raise ApplyError(
            f"{orphans} sentence(s) filed under a word absent from the vocabulary table — "
            f"the only production reader looks them up by that word, so they would never show"
        )

    (mismatched,) = conn.execute(
        "SELECT COUNT(*) FROM sentences WHERE "
        "(source = ? AND (tatoeba_ja_id IS NULL OR tatoeba_fr_id IS NULL)) OR "
        "(source = ? AND (tatoeba_ja_id IS NOT NULL OR tatoeba_fr_id IS NOT NULL))",
        (SOURCE_TATOEBA, SOURCE_IKERU),
    ).fetchone()
    if mismatched:
        raise ApplyError(f"{mismatched} row(s) whose source and Tatoeba ids disagree")


# MARK: - Entry point


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--db", type=Path, default=DEFAULT_DB, help="SQLite bundle to update")
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE, help="corpus JSON to read")
    parser.add_argument("--dry-run", action="store_true", help="validate everything, then roll back")
    args = parser.parse_args(argv)

    if not args.db.exists():
        print(f"error: content bundle not found: {args.db}", file=sys.stderr)
        return 1

    conn = sqlite3.connect(args.db)
    try:
        rows = load_payload(args.source)

        conn.execute("BEGIN")
        added = [
            f"sentences.{name}"
            for name, kind in (
                ("source", "TEXT"),
                ("tatoeba_ja_id", "INTEGER"),
                ("tatoeba_fr_id", "INTEGER"),
            )
            if ensure_column(conn, "sentences", name, kind)
        ]

        known_words = {row[0] for row in conn.execute("SELECT word FROM vocabulary")}
        validate(conn, rows, known_words, args.source.name)

        deleted, inserted = apply(conn, rows)
        verify(conn, expected=len(rows))

        (originals,) = conn.execute(
            "SELECT COUNT(*) FROM sentences WHERE source = ?", (SOURCE_IKERU,)
        ).fetchone()

        if args.dry_run:
            conn.execute("ROLLBACK")
        else:
            conn.execute("COMMIT")
            # VACUUM cannot run inside a transaction (SQLite rejects it), so it
            # has to happen here, after COMMIT — and it has to happen at all,
            # because this file is a binary committed to git. Without it, a
            # no-op re-run (same corpus, same bundle) still reallocates pages
            # on DELETE+INSERT and produces a several-hundred-KB diff that is
            # indistinguishable from a real content change.
            conn.execute("VACUUM")
    except (ApplyError, sqlite3.Error, json.JSONDecodeError) as error:
        # COMMIT may already have succeeded before VACUUM raised, in which
        # case there is no open transaction left to roll back and this itself
        # would raise "cannot rollback - no transaction is active" — masking
        # the real error. Swallow only that.
        try:
            conn.execute("ROLLBACK")
        except sqlite3.OperationalError:
            pass
        print(f"error: {error}", file=sys.stderr)
        return 1
    finally:
        conn.close()

    if added:
        print("Columns added: " + ", ".join(added))
    else:
        print("Columns already present — no schema change.")
    print(f"Replaced {deleted} previously imported row(s) with {inserted}.")
    print(f"sentences: {originals} original (ikeru) + {inserted} imported (tatoeba) "
          f"= {originals + inserted}")
    if args.dry_run:
        print("(dry run — rolled back)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
