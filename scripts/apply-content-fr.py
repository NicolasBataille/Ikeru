#!/usr/bin/env python3
"""Inject the French content translations into the N5 SQLite bundle.

Reads the hand-written translations in ``scripts/content-fr/*.json`` and
writes them into French-suffixed columns of
``Ikeru/Resources/ContentBundles/n5-content.sqlite``:

    vocabulary.meaning_fr
    sentences.french
    grammar_points.title_fr, explanation_fr, examples_fr
    kanji.meanings_fr

The script is idempotent: columns are only added when missing, and rows are
rewritten with the same values on a second run. It fails loudly — a JSON entry
that matches no row, or a row left without a translation, aborts with a
non-zero exit status rather than leaving invisible holes in the bundle.

Why these translations are hand-written rather than imported: see
``scripts/content-fr/README.md`` (EDRDG licenses JMdict's *English* glosses
only; the French ones are third-party copyright, unresolved).

Usage:
    python3 scripts/apply-content-fr.py [--db PATH] [--source DIR] [--dry-run]
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DB = REPO_ROOT / "Ikeru" / "Resources" / "ContentBundles" / "n5-content.sqlite"
DEFAULT_SOURCE = REPO_ROOT / "scripts" / "content-fr"


class ApplyError(RuntimeError):
    """Raised for any condition that must abort the run."""


# MARK: - Schema helpers


def existing_columns(conn: sqlite3.Connection, table: str) -> set[str]:
    return {row[1] for row in conn.execute(f"PRAGMA table_info({table})")}


def ensure_column(conn: sqlite3.Connection, table: str, column: str) -> bool:
    """Add ``column`` (TEXT) to ``table`` if absent. Returns True when added."""
    if column in existing_columns(conn, table):
        return False
    conn.execute(f"ALTER TABLE {table} ADD COLUMN {column} TEXT")
    return True


# MARK: - Loading


def load_entries(path: Path) -> list[dict]:
    if not path.exists():
        raise ApplyError(f"missing translation file: {path}")
    with path.open(encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, list) or not data:
        raise ApplyError(f"{path.name}: expected a non-empty JSON array")
    return data


def require(entry: dict, key: str, source: str) -> object:
    if key not in entry:
        raise ApplyError(f"{source}: entry {entry!r} has no '{key}'")
    value = entry[key]
    if value is None:
        raise ApplyError(f"{source}: entry {entry!r} has a null '{key}'")
    if isinstance(value, str) and not value.strip():
        raise ApplyError(f"{source}: entry {entry!r} has an empty '{key}'")
    if isinstance(value, list) and not value:
        raise ApplyError(f"{source}: entry {entry!r} has an empty '{key}' array")
    return value


def as_json_array(value: object, source: str, key: str) -> str:
    if not isinstance(value, list):
        raise ApplyError(f"{source}: '{key}' must be an array, got {type(value).__name__}")
    for item in value:
        if not isinstance(item, str) or not item.strip():
            raise ApplyError(f"{source}: '{key}' contains a non-string or empty item")
    return json.dumps(value, ensure_ascii=False)


# MARK: - Applying


def apply_table(
    conn: sqlite3.Connection,
    *,
    table: str,
    key_column: str,
    entries: list[dict],
    key_field: str,
    columns: dict[str, str],
    json_columns: frozenset[str],
    source: str,
) -> int:
    """Write one table's translations. Returns the number of rows updated."""
    known_keys = {row[0] for row in conn.execute(f"SELECT {key_column} FROM {table}")}

    seen: set = set()
    updated = 0
    for entry in entries:
        key = require(entry, key_field, source)
        if key in seen:
            raise ApplyError(f"{source}: duplicate {key_field} {key!r}")
        seen.add(key)
        if key not in known_keys:
            raise ApplyError(
                f"{source}: {key_field}={key!r} matches no row in {table} "
                f"({len(known_keys)} rows in the bundle)"
            )

        values = []
        for column, field in columns.items():
            raw = require(entry, field, source)
            values.append(
                as_json_array(raw, source, field) if column in json_columns else raw
            )

        assignments = ", ".join(f"{column} = ?" for column in columns)
        cursor = conn.execute(
            f"UPDATE {table} SET {assignments} WHERE {key_column} = ?",
            (*values, key),
        )
        updated += cursor.rowcount

    missing = known_keys - seen
    if missing:
        sample = sorted(str(key) for key in missing)[:10]
        raise ApplyError(
            f"{table}: {len(missing)} row(s) left without a translation "
            f"(e.g. {', '.join(sample)}) — {source} covers {len(seen)} of {len(known_keys)}"
        )

    return updated


def verify_no_holes(conn: sqlite3.Connection, table: str, column: str) -> None:
    """Abort if any row's translated column is NULL, empty, or an empty array."""
    (holes,) = conn.execute(
        f"SELECT COUNT(*) FROM {table} "
        f"WHERE {column} IS NULL OR TRIM({column}) = '' OR TRIM({column}) = '[]'"
    ).fetchone()
    if holes:
        raise ApplyError(f"{table}.{column}: {holes} row(s) NULL/empty after the update")


# MARK: - Entry point


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--db", type=Path, default=DEFAULT_DB, help="SQLite bundle to update")
    parser.add_argument(
        "--source", type=Path, default=DEFAULT_SOURCE, help="directory holding the *.json translations"
    )
    parser.add_argument("--dry-run", action="store_true", help="validate everything, then roll back")
    args = parser.parse_args(argv)

    if not args.db.exists():
        print(f"error: content bundle not found: {args.db}", file=sys.stderr)
        return 1

    plans = [
        {
            "table": "vocabulary",
            "key_column": "id",
            "file": "vocabulary.json",
            "key_field": "id",
            "columns": {"meaning_fr": "meaning_fr"},
            "json_columns": frozenset(),
        },
        {
            "table": "sentences",
            "key_column": "id",
            "file": "sentences.json",
            "key_field": "id",
            "columns": {"french": "french"},
            "json_columns": frozenset(),
        },
        {
            "table": "grammar_points",
            "key_column": "id",
            "file": "grammar.json",
            "key_field": "id",
            "columns": {
                "title_fr": "title_fr",
                "explanation_fr": "explanation_fr",
                "examples_fr": "examples_fr",
            },
            "json_columns": frozenset({"examples_fr"}),
        },
        {
            "table": "kanji",
            "key_column": "character",
            "file": "kanji.json",
            "key_field": "character",
            "columns": {"meanings_fr": "meanings_fr"},
            "json_columns": frozenset({"meanings_fr"}),
        },
    ]

    conn = sqlite3.connect(args.db)
    try:
        conn.execute("BEGIN")
        added: list[str] = []
        results: list[tuple[str, int, int]] = []

        for plan in plans:
            for column in plan["columns"]:
                if ensure_column(conn, plan["table"], column):
                    added.append(f"{plan['table']}.{column}")

            entries = load_entries(args.source / plan["file"])
            updated = apply_table(
                conn,
                table=plan["table"],
                key_column=plan["key_column"],
                entries=entries,
                key_field=plan["key_field"],
                columns=plan["columns"],
                json_columns=plan["json_columns"],
                source=plan["file"],
            )
            for column in plan["columns"]:
                verify_no_holes(conn, plan["table"], column)
            results.append((plan["table"], len(entries), updated))

        if args.dry_run:
            conn.execute("ROLLBACK")
        else:
            conn.execute("COMMIT")
    except (ApplyError, sqlite3.Error) as error:
        conn.execute("ROLLBACK")
        print(f"error: {error}", file=sys.stderr)
        return 1
    finally:
        conn.close()

    if added:
        print("Columns added: " + ", ".join(added))
    else:
        print("Columns already present — no schema change.")
    print(f"{'Table':<16}{'entries':>9}{'rows written':>14}")
    for table, entries, updated in results:
        print(f"{table:<16}{entries:>9}{updated:>14}")
    if args.dry_run:
        print("(dry run — rolled back)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
