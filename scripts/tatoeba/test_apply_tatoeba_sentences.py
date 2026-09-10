#!/usr/bin/env python3
"""Tests for ``scripts/apply-tatoeba-sentences.py``, in particular D5: the
script must fail loudly when a corpus JSON contains a Japanese sentence that
already exists in the bundle outside the rows it manages (``source <>
'tatoeba'``), not only when it duplicates another row *within the same JSON*.

Run as ``scripts/apply-tatoeba-sentences.py`` has a hyphen in its filename and
so cannot be ``import``ed as a module — these tests invoke it exactly as a
user or CI would, as a subprocess against a throwaway copy of the real
bundle. That also replays the reviewer's scenario end-to-end rather than unit
-testing an internal function in isolation.

Usage: ``python3 scripts/tatoeba/test_apply_tatoeba_sentences.py``
"""

from __future__ import annotations

import json
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
SCRIPT = REPO_ROOT / "scripts" / "apply-tatoeba-sentences.py"
BUNDLE = REPO_ROOT / "Ikeru" / "Resources" / "ContentBundles" / "n5-content.sqlite"

#: A sentence already present in the bundle as a hand-written ("ikeru") row —
#: see Ikeru/Resources/ContentBundles/n5-content.sqlite, id 1. This is the
#: exact sentence the adversarial review reported as a false-negative case
#: for the old (JSON-internal-only) duplicate check.
DUPLICATE_JAPANESE = "りんごを一つください。"


def run_script(db: Path, source: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), "--db", str(db), "--source", str(source)],
        capture_output=True, text=True, timeout=30,
    )


def tatoeba_row_count(db: Path) -> int:
    conn = sqlite3.connect(db)
    try:
        (count,) = conn.execute(
            "SELECT COUNT(*) FROM sentences WHERE source = 'tatoeba'"
        ).fetchone()
        return count
    finally:
        conn.close()


def japanese_present(db: Path, japanese: str) -> int:
    conn = sqlite3.connect(db)
    try:
        (count,) = conn.execute(
            "SELECT COUNT(*) FROM sentences WHERE japanese = ?", (japanese,)
        ).fetchone()
        return count
    finally:
        conn.close()


def write_source(path: Path, sentences: list[dict]) -> None:
    payload = {
        "source": "test fixture",
        "generated_by": "test_apply_tatoeba_sentences.py",
        "count": len(sentences),
        "sentences": sentences,
    }
    path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")


class ApplyTatoebaSentencesTestCase(unittest.TestCase):

    def setUp(self) -> None:
        if not BUNDLE.exists():
            self.skipTest(f"content bundle not found: {BUNDLE}")
        self.tmpdir = Path(tempfile.mkdtemp(prefix="apply-tatoeba-test-"))
        self.db = self.tmpdir / "n5-content.sqlite"
        shutil.copyfile(BUNDLE, self.db)
        self.assertEqual(
            japanese_present(self.db, DUPLICATE_JAPANESE), 1,
            f"fixture assumption broken: {DUPLICATE_JAPANESE!r} is expected to "
            f"already exist exactly once in the bundle as a non-tatoeba row",
        )

    def tearDown(self) -> None:
        shutil.rmtree(self.tmpdir, ignore_errors=True)


class DuplicateAgainstExistingBundleRowTests(ApplyTatoebaSentencesTestCase):
    """D5: injecting a duplicate of a *non-tatoeba* row must fail loudly."""

    def test_rejects_duplicate_of_an_existing_ikeru_sentence(self) -> None:
        before = tatoeba_row_count(self.db)
        source = self.tmpdir / "sentences.json"
        write_source(source, [{
            "japanese": DUPLICATE_JAPANESE,
            "french": "Une pomme, s'il vous plaît.",
            "vocabulary_word": "一つ",
            # An id far outside the real Tatoeba id space, so this can only
            # collide on the Japanese text itself, not on tatoeba_ja_id.
            "tatoeba_ja_id": 99_999_999,
            "tatoeba_fr_id": 99_999_999,
        }])

        result = run_script(self.db, source)

        self.assertNotEqual(
            result.returncode, 0,
            f"expected a non-zero exit for a duplicate against an existing "
            f"bundle row; got 0. stdout={result.stdout!r} stderr={result.stderr!r}",
        )
        self.assertIn("already exists", result.stderr)
        self.assertIn(DUPLICATE_JAPANESE, result.stderr)

        # The failed run must not have left the bundle half-written: the
        # transaction was never committed, so both the tatoeba row count and
        # the duplicate-check target must be exactly what they were before.
        self.assertEqual(tatoeba_row_count(self.db), before)
        self.assertEqual(japanese_present(self.db, DUPLICATE_JAPANESE), 1)

    def test_still_rejects_duplicate_within_the_json_itself(self) -> None:
        """Regression guard: the pre-existing in-JSON check must keep working."""
        source = self.tmpdir / "sentences.json"
        write_source(source, [
            {
                "japanese": "これはテストです。",
                "french": "C'est un test.",
                "vocabulary_word": "一つ",
                "tatoeba_ja_id": 99_999_001,
                "tatoeba_fr_id": 99_999_001,
            },
            {
                "japanese": "これはテストです。",
                "french": "C'est un autre test.",
                "vocabulary_word": "一つ",
                "tatoeba_ja_id": 99_999_002,
                "tatoeba_fr_id": 99_999_002,
            },
        ])

        result = run_script(self.db, source)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("duplicate japanese sentence", result.stderr)


class ValidRunStillSucceedsTests(ApplyTatoebaSentencesTestCase):
    """Control: the fix must not reject a legitimate, non-duplicate sentence."""

    def test_accepts_a_genuinely_new_sentence(self) -> None:
        source = self.tmpdir / "sentences.json"
        write_source(source, [{
            "japanese": "これはテストの文です。",
            "french": "Ceci est une phrase de test.",
            "vocabulary_word": "一つ",
            "tatoeba_ja_id": 99_999_100,
            "tatoeba_fr_id": 99_999_100,
        }])

        result = run_script(self.db, source)

        self.assertEqual(
            result.returncode, 0,
            f"expected success for a genuinely new sentence. "
            f"stdout={result.stdout!r} stderr={result.stderr!r}",
        )
        self.assertEqual(tatoeba_row_count(self.db), 1)
        self.assertEqual(japanese_present(self.db, "これはテストの文です。"), 1)

    def test_rerunning_over_its_own_previous_output_stays_idempotent(self) -> None:
        """A tatoeba row from a *previous* run of this script is not a
        duplicate against itself — re-running with the same corpus must
        succeed, which is what makes the script safely re-runnable."""
        source = self.tmpdir / "sentences.json"
        write_source(source, [{
            "japanese": "これはテストの文です。",
            "french": "Ceci est une phrase de test.",
            "vocabulary_word": "一つ",
            "tatoeba_ja_id": 99_999_100,
            "tatoeba_fr_id": 99_999_100,
        }])

        first = run_script(self.db, source)
        self.assertEqual(first.returncode, 0, first.stderr)

        second = run_script(self.db, source)
        self.assertEqual(
            second.returncode, 0,
            f"re-running over the script's own prior output must stay "
            f"idempotent. stderr={second.stderr!r}",
        )
        self.assertEqual(tatoeba_row_count(self.db), 1)


if __name__ == "__main__":
    unittest.main()
