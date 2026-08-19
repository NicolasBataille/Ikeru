#!/usr/bin/env python3
"""Annotate the bundle's sentences with furigana, and refuse to guess.

Writes ``sentences.furigana``: the Japanese sentence with each consecutive-kanji
run followed by its reading in parentheses — ``水(みず)を飲(の)みたいです。`` —
which is the exact shape ``KanaRubyText`` parses.

Three stages, and the third is the point:

1. **Tokenise** with Apple's ``CFStringTokenizer`` (see
   ``tokenize-readings.swift``). Context-aware, and right most of the time.
2. **Correct** with ``overrides.json`` — hand-reviewed, every entry justified by
   the sentence that motivated it.
3. **Verify, then refuse.** Every kanji must end up inside an annotated run, and
   every reading must be pure kana. Anything the splitter cannot resolve is
   reported and the run is left UNANNOTATED rather than annotated wrongly —
   a wrong reading is worse than a missing one, because the learner copies it.

Why not trust the tokeniser alone: measured 2026-08-19, it reads 日本 as にっぽん
where the bundle teaches にほん, and 何を as なん where it is なに. Why not trust
the bundle alone: the bundle stores the DICTIONARY reading, so it would force
なに into 何ですか and ひと into 日本人. Neither source is authoritative; the
overrides are the reviewed difference between them.

Usage:
    python3 scripts/furigana/generate-furigana.py [--db PATH] [--check]

``--check`` verifies without writing.
"""
from __future__ import annotations

import argparse
import json
import re
import sqlite3
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
DEFAULT_DB = REPO / "Ikeru" / "Resources" / "ContentBundles" / "n5-content.sqlite"
TOKENIZER_SRC = HERE / "tokenize-readings.swift"
OVERRIDES = HERE / "overrides.json"

RS, GS, US = "\x1e", "\x1d", "\x1f"

KANJI = re.compile(r"[一-鿿々]")
KANJI_RUN = re.compile(r"[一-鿿々]+")
KANA_ONLY = re.compile(r"^[぀-ゟ゠-ヿー]+$")


def is_kanji(ch: str) -> bool:
    return bool(KANJI.match(ch))


def tokenise(sentences: list[str]) -> list[list[tuple[str, str]]]:
    """Run the Swift helper; returns per-sentence [(token, reading), ...]."""
    with tempfile.TemporaryDirectory() as tmp:
        binary = Path(tmp) / "tokread"
        build = subprocess.run(["swiftc", "-O", "-o", str(binary), str(TOKENIZER_SRC)],
                               capture_output=True, text=True)
        if build.returncode != 0:
            raise SystemExit("swiftc failed:\n" + build.stderr)
        infile = Path(tmp) / "in.txt"
        infile.write_text((RS + "\n").join(sentences), encoding="utf-8")
        run = subprocess.run([str(binary), str(infile)], capture_output=True, text=True)
        if run.returncode != 0:
            raise SystemExit("tokenizer failed:\n" + run.stderr)

    # `.split("\n")`, jamais `.splitlines()` : celui-ci coupe AUSSI sur \x1c,
    # \x1d et \x1e — precisement les separateurs utilises ici, ce qui rendait
    # 5181 « lignes » pour 632 phrases.
    out = []
    for line in run.stdout.split("\n"):
        if not line:
            continue
        _, _, rest = line.partition(RS)
        toks = []
        for pair in rest.split(GS):
            w, _, rd = pair.partition(US)
            if w:
                toks.append((w, rd))
        out.append(toks)
    return out


def apply_overrides(token: str, reading: str, prev: str, nxt: str, rules: dict) -> str:
    entry = rules["global"].get(token)
    if entry:
        return entry["reading"]
    for rule in rules["contextual"]:
        if rule["token"] != token:
            continue
        if "next_in" in rule and (not nxt or nxt[0] not in rule["next_in"]):
            continue
        if "next_starts" in rule and not any(nxt.startswith(p) for p in rule["next_starts"]):
            continue
        if "prev_ends" in rule and not any(prev.endswith(p) for p in rule["prev_ends"]):
            continue
        return rule["reading"]
    return reading


def split_okurigana(token: str, reading: str):
    """Peel kana off both ends so the annotation covers only the kanji run.

    ``食べ`` + ``たべ`` -> ``("", "食", "た", "べ")`` -> rendered ``食(た)べ``.
    `KanaRubyText` groups CONSECUTIVE kanji and expects the reading to follow
    that group, so annotating the whole token would misparse.

    Returns None when the token holds kana BETWEEN kanji (``食べ物``), which
    needs the reading split across two runs — reported, never guessed.
    """
    lead = ""
    while token and not is_kanji(token[0]):
        if not reading.startswith(token[0]):
            return None
        lead += token[0]
        token, reading = token[1:], reading[1:]
    tail = ""
    while token and not is_kanji(token[-1]):
        if not reading.endswith(token[-1]):
            return None
        tail = token[-1] + tail
        token, reading = token[:-1], reading[:-1]
    if not token or not reading:
        return None
    if any(not is_kanji(c) for c in token):
        return None
    return lead, token, reading, tail


def annotate(sentence: str, tokens: list[tuple[str, str]], rules: dict,
             problems: list[str]) -> str:
    out: list[str] = []
    cursor = 0
    for token, reading in tokens:
        idx = sentence.find(token, cursor)
        if idx < 0:
            continue
        out.append(sentence[cursor:idx])
        cursor = idx + len(token)

        if not KANJI.search(token):
            out.append(token)
            continue

        compound = rules.get("compounds", {}).get(token)
        if compound:
            out.append(compound)
            continue

        prev = sentence[:idx]
        nxt = sentence[cursor:]
        reading = apply_overrides(token, reading, prev, nxt, rules)

        split = split_okurigana(token, reading) if reading else None
        if split is None:
            problems.append(f"{sentence}  |  {token} -> {reading or '(aucune)'}")
            out.append(token)
            continue
        lead, base, rd, tail = split
        if not KANA_ONLY.match(rd):
            problems.append(f"{sentence}  |  {token} -> {rd} (lecture non kana)")
            out.append(token)
            continue
        out.append(f"{lead}{base}({rd}){tail}")
    out.append(sentence[cursor:])
    return "".join(out)



SEGMENT = re.compile(r"([一-鿿々]+)\(([^)]*)\)")

# Divergences ATTENDUES entre la lecture assemblee et la lecture de dictionnaire
# du bundle. Chacune doit etre justifiee : le bundle stocke une lecture de
# dictionnaire, qui n'est pas toujours celle du contexte.
ALLOWED_DIVERGENCES = {
    ("一日", "ついたち"): "『四月一日です。』 est une date -> ついたち ; "
                          "le bundle enseigne いちにち (la duree).",
}


def _segments(annotated: str):
    """-> [(texte_source, lecture_ou_None)] dans l'ordre."""
    out, i = [], 0
    for m in SEGMENT.finditer(annotated):
        if m.start() > i:
            out.append((annotated[i:m.start()], None))
        out.append((m.group(1), m.group(2)))
        i = m.end()
    if i < len(annotated):
        out.append((annotated[i:], None))
    return out


def reading_span(annotated: str, start: int, length: int):
    """Lecture couvrant [start, start+length) du texte source, ou None."""
    pos, out = 0, []
    for base, reading in _segments(annotated):
        for k, ch in enumerate(base):
            if start <= pos < start + length:
                if reading is None:
                    out.append(ch)
                elif k == 0:
                    out.append(reading)
                elif pos - k < start:
                    return None          # la fenetre coupe un groupe annote
            pos += 1
    return "".join(out)


def verify_against_vocabulary(sentences, annotated, vocab):
    """Compare la lecture ASSEMBLEE de chaque mot du bundle a celle qu'il enseigne.

    C'est le controle qui attrape ce qu'une relecture token par token ne peut pas
    voir : 日本 -> にほん et 人 -> にん sont chacun defendables, mais juxtaposes
    ils donnent にほんにん la ou 日本人 se lit にほんじん. Quatre corrections du
    fichier d'overrides viennent de ce controle, pas de la relecture.
    """
    problems = []
    for src, ann in zip(sentences, annotated):
        for word, expected in vocab.items():
            if len(word) < 2 or word not in src:
                continue
            if not KANJI.search(word):
                continue                 # katakana : jamais annote
            got = reading_span(ann, src.find(word), len(word))
            if not got or got == expected:
                continue
            if (word, got) in ALLOWED_DIVERGENCES:
                continue
            problems.append(f"{src}  |  {word}: bundle {expected!r} vs annote {got!r}")
    return problems


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--db", type=Path, default=DEFAULT_DB)
    ap.add_argument("--check", action="store_true", help="verify without writing")
    args = ap.parse_args(argv)

    rules = json.loads(OVERRIDES.read_text(encoding="utf-8"))
    con = sqlite3.connect(args.db)
    rows = con.execute(
        "SELECT id, japanese FROM sentences WHERE TRIM(COALESCE(japanese,''))!=''"
    ).fetchall()
    ids = [r[0] for r in rows]
    sentences = [r[1] for r in rows]

    tokenised = tokenise(sentences)
    if len(tokenised) != len(sentences):
        raise SystemExit(
            f"tokenizer returned {len(tokenised)} lines for {len(sentences)} sentences")

    problems: list[str] = []
    annotated = [annotate(s, t, rules, problems) for s, t in zip(sentences, tokenised)]

    uncovered: list[str] = []
    for src, ann in zip(sentences, annotated):
        bare = re.sub(r"\(([^)]*)\)", "", ann)
        if bare != src:
            raise SystemExit(f"annotation altered the sentence:\n  {src}\n  {bare}")
        for run in KANJI_RUN.finditer(ann):
            end = run.end()
            if end >= len(ann) or ann[end] != "(":
                uncovered.append(f"{src}  |  {run.group()}")

    vocab = {w: r for w, r in con.execute(
        "SELECT word, reading FROM vocabulary "
        "WHERE TRIM(COALESCE(reading,''))!=''")}
    divergences = verify_against_vocabulary(sentences, annotated, vocab)

    total = len(sentences)
    clean = total - len({p.split("  |  ")[0] for p in problems})
    print(f"phrases                 : {total}")
    print(f"annotees sans reserve   : {clean}")
    print(f"runs kanji non couverts : {len(uncovered)}")
    if problems:
        print(f"\ntokens non resolus ({len(problems)}) — laisses SANS annotation :")
        for p in problems[:40]:
            print("   " + p)
        if len(problems) > 40:
            print(f"   ... et {len(problems) - 40} de plus")

    print(f"lectures divergentes    : {len(divergences)}")
    if divergences:
        print("\nlecture assemblee != lecture du bundle :")
        for d in divergences[:20]:
            print("   " + d)

    failed = bool(uncovered or divergences)
    if args.check:
        print("\n(--check : rien ecrit)")
        return 1 if failed else 0
    if failed:
        raise SystemExit("verification en echec — rien ecrit")

    cols = {r[1] for r in con.execute("PRAGMA table_info(sentences)")}
    if "furigana" not in cols:
        con.execute("ALTER TABLE sentences ADD COLUMN furigana TEXT")
    con.executemany("UPDATE sentences SET furigana=? WHERE id=?",
                    list(zip(annotated, ids)))
    con.commit()
    con.execute("VACUUM")
    con.close()
    print(f"\necrit dans {args.db}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
