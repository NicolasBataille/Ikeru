#!/usr/bin/env python3
"""
Fetch KanjiVG stroke-order data and embed it into the Ikeru content bundle.

KanjiVG (https://kanjivg.tagaini.net/) by Ulrich Apel, licensed under
Creative Commons Attribution-ShareAlike 3.0 (CC BY-SA 3.0). KanjiVG covers
kana as well as kanji — files are keyed by Unicode codepoint, not by CJK
block — so this script populates both the `kanji` and `kana` tables from the
same source and the same on-disk cache.
Raw SVGs are cached in scripts/kanjivg-cache/ so regeneration works offline.

The app's Swift parser (IkeruCore StrokeDataService) has a strict contract:
- It extracts `d` attributes from `<path ... d="..."/>` elements with the regex
  `<path[^>]*\\sd="([^"]+)"[^>]*/?\\s*>`.
- It only understands ABSOLUTE M / L / C / Q / Z commands (it uppercases the
  command letter but never converts relative coordinates, and it has no
  S/T/H/V/A support).

Raw KanjiVG paths use relative `c` and smooth `s` commands, so this script
normalizes every path to absolute M/L/C/Q/Z before embedding.

Kana coverage is partial by construction: KanjiVG has one file per Unicode
codepoint, so the 92 base + 50 dakuten kana (single codepoint each) get real
stroke data, but the 66 yōon combinations (きゃ, etc. — two codepoints: a
base kana + a small ゃ/ゅ/ょ) do not, because there is no KanjiVG file for a
two-codepoint digraph. The character list itself is read out of
IkeruCore/Sources/Models/Kana/KanaGroup.swift (the app's source of truth for
which kana exist), not hand-typed here — see `kana_characters_from_swift`.

Usage:
    python3 scripts/fetch-kanjivg.py                 # update default n5 bundle (kanji + kana)
    python3 scripts/fetch-kanjivg.py --db path.sqlite
    python3 scripts/fetch-kanjivg.py --no-network    # cache-only (offline)
    python3 scripts/fetch-kanjivg.py --validate-only # just re-run validation
    python3 scripts/fetch-kanjivg.py --skip-kana     # kanji only
"""

import argparse
import os
import re
import sqlite3
import ssl
import sys
import urllib.request

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
DEFAULT_CACHE_DIR = os.path.join(SCRIPT_DIR, "kanjivg-cache")
DEFAULT_DB_PATH = os.path.join(
    PROJECT_ROOT, "Ikeru", "Resources", "ContentBundles", "n5-content.sqlite"
)
KANA_SWIFT_SOURCE = os.path.join(
    PROJECT_ROOT, "IkeruCore", "Sources", "Models", "Kana", "KanaGroup.swift"
)
KANJIVG_RAW_URL = "https://raw.githubusercontent.com/KanjiVG/kanjivg/master/kanji/{code}.svg"

ATTRIBUTION_COMMENT = (
    "<!-- Stroke data from KanjiVG (https://kanjivg.tagaini.net/), "
    "(c) Ulrich Apel, CC BY-SA 3.0 -->"
)

# ---------------------------------------------------------------------------
# Fetching / caching
# ---------------------------------------------------------------------------


def kanjivg_code(character: str) -> str:
    """Lowercase hex codepoint zero-padded to 5 chars (KanjiVG file naming)."""
    return f"{ord(character):05x}"


def cache_path(character: str, cache_dir: str = DEFAULT_CACHE_DIR) -> str:
    return os.path.join(cache_dir, f"{kanjivg_code(character)}.svg")


def _ssl_context() -> ssl.SSLContext:
    cafile = os.environ.get("SSL_CERT_FILE") or os.environ.get("REQUESTS_CA_BUNDLE")
    return ssl.create_default_context(cafile=cafile)


def fetch_raw_svg(
    character: str,
    cache_dir: str = DEFAULT_CACHE_DIR,
    allow_network: bool = True,
) -> str | None:
    """Return the raw KanjiVG SVG for a character, using the local cache first.

    Fetched files are written to the cache so later runs work offline.
    Returns None if unavailable (not cached and network disabled/failed).
    """
    path = cache_path(character, cache_dir)
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            return f.read()

    if not allow_network:
        return None

    url = KANJIVG_RAW_URL.format(code=kanjivg_code(character))
    try:
        with urllib.request.urlopen(url, timeout=30, context=_ssl_context()) as resp:
            data = resp.read().decode("utf-8")
    except Exception as exc:  # noqa: BLE001 - report and continue per-kanji
        print(f"  WARNING: fetch failed for {character} ({url}): {exc}", file=sys.stderr)
        return None

    os.makedirs(cache_dir, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(data)
    return data


# ---------------------------------------------------------------------------
# SVG path normalization (relative/shorthand -> absolute M/L/C/Q/Z)
# ---------------------------------------------------------------------------

_COMMAND_RE = re.compile(r"([MmLlHhVvCcSsQqTtAaZz])([^MmLlHhVvCcSsQqTtAaZz]*)")
_NUMBER_RE = re.compile(r"-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?")
# KanjiVG stroke paths carry the `d` attribute after `id`/`kvg:type` attrs.
_RAW_PATH_D_RE = re.compile(r"<path[^>]*?\sd=\"([^\"]+)\"")


def extract_raw_path_data(svg_text: str) -> list[str]:
    """Extract stroke path `d` attributes from a raw KanjiVG SVG, in stroke order.

    In KanjiVG files, all <path> elements are strokes (stroke numbers are
    <text> elements) and appear in document order = writing order.
    """
    return _RAW_PATH_D_RE.findall(svg_text)


def _fmt(value: float) -> str:
    """Format a coordinate: <= 2 decimals, no trailing zeros, no exponent."""
    s = f"{value:.2f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def path_to_absolute(d: str) -> str:
    """Convert an SVG path `d` string to absolute coordinates using only
    M / L / C / Q / Z commands (the subset the Swift parser understands).

    Handles M/L/H/V/C/S/Q/T/Z in both absolute and relative forms.
    Arc (A) segments are approximated by a line to the endpoint (KanjiVG
    does not use arcs; this is a defensive fallback).
    """
    segments: list[tuple[str, list[float]]] = []
    cx = cy = sx = sy = 0.0
    prev_cubic_ctrl: tuple[float, float] | None = None
    prev_quad_ctrl: tuple[float, float] | None = None

    for cmd, args in _COMMAND_RE.findall(d):
        nums = [float(n) for n in _NUMBER_RE.findall(args)]
        rel = cmd.islower()
        op = cmd.upper()
        i = 0

        if op == "M":
            first = True
            while i + 2 <= len(nums):
                x, y = nums[i], nums[i + 1]
                i += 2
                if rel:
                    x += cx
                    y += cy
                cx, cy = x, y
                if first:
                    segments.append(("M", [x, y]))
                    sx, sy = x, y
                    first = False
                else:
                    segments.append(("L", [x, y]))
            prev_cubic_ctrl = prev_quad_ctrl = None

        elif op == "L":
            while i + 2 <= len(nums):
                x, y = nums[i], nums[i + 1]
                i += 2
                if rel:
                    x += cx
                    y += cy
                segments.append(("L", [x, y]))
                cx, cy = x, y
            prev_cubic_ctrl = prev_quad_ctrl = None

        elif op == "H":
            for n in nums:
                x = cx + n if rel else n
                segments.append(("L", [x, cy]))
                cx = x
            prev_cubic_ctrl = prev_quad_ctrl = None

        elif op == "V":
            for n in nums:
                y = cy + n if rel else n
                segments.append(("L", [cx, y]))
                cy = y
            prev_cubic_ctrl = prev_quad_ctrl = None

        elif op == "C":
            while i + 6 <= len(nums):
                x1, y1, x2, y2, x, y = nums[i:i + 6]
                i += 6
                if rel:
                    x1 += cx; y1 += cy; x2 += cx; y2 += cy; x += cx; y += cy
                segments.append(("C", [x1, y1, x2, y2, x, y]))
                prev_cubic_ctrl = (x2, y2)
                cx, cy = x, y
            prev_quad_ctrl = None

        elif op == "S":
            while i + 4 <= len(nums):
                x2, y2, x, y = nums[i:i + 4]
                i += 4
                if rel:
                    x2 += cx; y2 += cy; x += cx; y += cy
                if prev_cubic_ctrl is not None:
                    x1 = 2 * cx - prev_cubic_ctrl[0]
                    y1 = 2 * cy - prev_cubic_ctrl[1]
                else:
                    x1, y1 = cx, cy
                segments.append(("C", [x1, y1, x2, y2, x, y]))
                prev_cubic_ctrl = (x2, y2)
                cx, cy = x, y
            prev_quad_ctrl = None

        elif op == "Q":
            while i + 4 <= len(nums):
                x1, y1, x, y = nums[i:i + 4]
                i += 4
                if rel:
                    x1 += cx; y1 += cy; x += cx; y += cy
                segments.append(("Q", [x1, y1, x, y]))
                prev_quad_ctrl = (x1, y1)
                cx, cy = x, y
            prev_cubic_ctrl = None

        elif op == "T":
            while i + 2 <= len(nums):
                x, y = nums[i], nums[i + 1]
                i += 2
                if rel:
                    x += cx
                    y += cy
                if prev_quad_ctrl is not None:
                    x1 = 2 * cx - prev_quad_ctrl[0]
                    y1 = 2 * cy - prev_quad_ctrl[1]
                else:
                    x1, y1 = cx, cy
                segments.append(("Q", [x1, y1, x, y]))
                prev_quad_ctrl = (x1, y1)
                cx, cy = x, y
            prev_cubic_ctrl = None

        elif op == "A":
            # Defensive: approximate arcs with a line to the endpoint.
            while i + 7 <= len(nums):
                x, y = nums[i + 5], nums[i + 6]
                i += 7
                if rel:
                    x += cx
                    y += cy
                segments.append(("L", [x, y]))
                cx, cy = x, y
            prev_cubic_ctrl = prev_quad_ctrl = None

        elif op == "Z":
            segments.append(("Z", []))
            cx, cy = sx, sy
            prev_cubic_ctrl = prev_quad_ctrl = None

    parts: list[str] = []
    for op, nums in segments:
        if op == "Z":
            parts.append("Z")
            continue
        pairs = [f"{_fmt(nums[j])},{_fmt(nums[j + 1])}" for j in range(0, len(nums), 2)]
        parts.append(f"{op} " + " ".join(pairs))
    return " ".join(parts)


def build_app_stroke_svg(raw_svg: str) -> str | None:
    """Transform a raw KanjiVG SVG into the fragment stored in the bundle:
    one `<path d="..."/>` per stroke (writing order), absolute M/L/C/Q/Z only.

    Returns None if no strokes could be extracted.
    """
    raw_paths = extract_raw_path_data(raw_svg)
    if not raw_paths:
        return None
    lines = [ATTRIBUTION_COMMENT]
    for raw_d in raw_paths:
        absolute_d = path_to_absolute(raw_d)
        if not absolute_d:
            return None
        lines.append(f'<path d="{absolute_d}"/>')
    return "\n".join(lines)


def stroke_svg_for(
    character: str,
    cache_dir: str = DEFAULT_CACHE_DIR,
    allow_network: bool = True,
) -> str | None:
    """Cache-first lookup returning the app-format stroke SVG fragment."""
    raw = fetch_raw_svg(character, cache_dir=cache_dir, allow_network=allow_network)
    if raw is None:
        return None
    return build_app_stroke_svg(raw)


# ---------------------------------------------------------------------------
# Kana character list — read from KanaGroup.swift, never hand-typed
# ---------------------------------------------------------------------------

# Matches `KanaCharacter(character: "X", romaji: ...` literals as they are
# written in KanaGroup.swift. Deliberately narrow (not a general Swift
# parser) so it fails loudly via `findall() == []` if the source format ever
# changes, rather than silently returning a partial list.
_KANA_CHARACTER_RE = re.compile(r'KanaCharacter\(character: "([^"]+)"')


def kana_characters_from_swift(swift_path: str = KANA_SWIFT_SOURCE) -> list[str]:
    """Extract the kana this pipeline can trace: the 92 base + 50 dakuten
    single-codepoint characters, read out of KanaGroup.swift (the app's own
    source of truth), not hand-transcribed here.

    The 66 yōon combinations (e.g. きゃ = き + small ゃ) are excluded by
    construction: KanjiVG has no file for a two-codepoint digraph, so any
    `character` value longer than one codepoint is dropped. This is not a
    curated exclusion list — it falls out of `len(character) == 1`.

    Raises if the Swift source is missing or yields no matches: a factual
    character list must come from a real read, never a stale fallback.
    """
    if not os.path.exists(swift_path):
        raise FileNotFoundError(
            f"Cannot read kana source of truth: {swift_path} does not exist. "
            "Has KanaGroup.swift moved?"
        )

    with open(swift_path, encoding="utf-8") as f:
        source = f.read()

    all_matches = _KANA_CHARACTER_RE.findall(source)
    if not all_matches:
        raise ValueError(
            f"No `KanaCharacter(character: \"...\")` entries found in {swift_path} "
            "— the Swift source format may have changed. Refusing to proceed "
            "against an empty/stale character list."
        )

    # Preserve first-seen order, dedupe, and keep only single-codepoint
    # entries (base + dakuten). Multi-codepoint entries are yōon digraphs —
    # see docstring above.
    seen: dict[str, None] = {}
    for character in all_matches:
        if len(character) == 1:
            seen.setdefault(character, None)
    return list(seen.keys())


# ---------------------------------------------------------------------------
# Validation — mimics the Swift StrokeDataService parsing logic
# ---------------------------------------------------------------------------

# Exact translation of the Swift extraction regex in StrokeDataService.
_SWIFT_PATH_RE = re.compile(r"<path[^>]*\sd=\"([^\"]+)\"[^>]*/?\s*>")


def _swift_tokenize(path_data: str) -> list[str]:
    """Mirror of StrokeDataService.tokenize."""
    tokens: list[str] = []
    current = ""
    for char in path_data:
        if char.isalpha():
            if current:
                tokens.append(current)
                current = ""
            tokens.append(char)
        elif char in ", \t\n\r":
            if current:
                tokens.append(current)
                current = ""
        elif char == "-" and current:
            tokens.append(current)
            current = char
        else:
            current += char
    if current:
        tokens.append(current)
    return tokens


def _is_number(token: str) -> bool:
    try:
        float(token)
        return True
    except ValueError:
        return False


def swift_parse_points(path_data: str) -> list[tuple[float, float]]:
    """Mirror of StrokeDataService.parseSVGPathToPoints (M/L/C/Q/Z absolute).

    Bezier curves contribute their control/end coordinates here (the Swift
    code samples the curve, but the coordinate values consumed are the same),
    which is enough to validate command coverage and coordinate ranges.
    """
    tokens = _swift_tokenize(path_data)
    points: list[tuple[float, float]] = []
    index = 0

    def consume_point() -> tuple[float, float] | None:
        nonlocal index
        if index >= len(tokens) or not _is_number(tokens[index]):
            return None
        x = float(tokens[index]); index += 1
        if index >= len(tokens) or not _is_number(tokens[index]):
            return None
        y = float(tokens[index]); index += 1
        return (x, y)

    def peek_numbers(count: int) -> bool:
        return (index + count <= len(tokens)
                and all(_is_number(tokens[index + k]) for k in range(count)))

    while index < len(tokens):
        token = tokens[index]
        if not token[:1].isalpha():
            index += 1
            continue
        command = token.upper()
        index += 1

        if command == "M":
            pt = consume_point()
            if pt:
                points.append(pt)
            while peek_numbers(1):
                pt = consume_point()
                if pt is None:
                    break
                points.append(pt)
        elif command == "L":
            while True:
                pt = consume_point()
                if pt is None:
                    break
                points.append(pt)
                if not peek_numbers(1):
                    break
        elif command == "C":
            while peek_numbers(6):
                cp1 = consume_point(); cp2 = consume_point(); end = consume_point()
                points.extend([cp1, cp2, end])
        elif command == "Q":
            while peek_numbers(4):
                cp = consume_point(); end = consume_point()
                points.extend([cp, end])
        # Z and unknown commands: no points (matches Swift behavior).

    return points


def _validate_stroke_svg(character: str, svg: str | None, label: str) -> tuple[bool, int]:
    """Swift-mirror validation for a single stroke_order_svg value, shared by
    the kanji and kana validators. Returns (ok, parsed_stroke_count) —
    parsed_stroke_count is 0 when validation failed before paths could be
    counted.
    """
    if not svg:
        print(f"  FAIL {label} {character}: stroke_order_svg is empty")
        return False, 0
    path_datas = _SWIFT_PATH_RE.findall(svg)
    if not path_datas:
        print(f"  FAIL {label} {character}: Swift regex extracts no <path> elements")
        return False, 0
    # Only absolute M/L/C/Q/Z may appear — anything else would be silently
    # mis-parsed by the Swift parser.
    bad_cmds = set(re.findall(r"[A-Za-z]", " ".join(path_datas))) - set("MLCQZ")
    if bad_cmds:
        print(f"  FAIL {label} {character}: unsupported path commands {sorted(bad_cmds)}")
        return False, len(path_datas)
    for stroke_index, path_data in enumerate(path_datas, 1):
        pts = swift_parse_points(path_data)
        if len(pts) < 2:
            print(f"  FAIL {label} {character}: stroke {stroke_index} parses to "
                  f"{len(pts)} point(s)")
            return False, len(path_datas)
        if not all(-30 <= x <= 140 and -30 <= y <= 140 for x, y in pts):
            print(f"  FAIL {label} {character}: stroke {stroke_index} has coordinates "
                  f"outside the KanjiVG 109x109 viewBox range")
            return False, len(path_datas)
    return True, len(path_datas)


def validate_database(db_path: str) -> bool:
    """Re-parse every kanji stroke_order_svg with the Swift-equivalent logic."""
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    rows = cur.execute(
        "SELECT character, stroke_count, stroke_order_svg FROM kanji ORDER BY character"
    ).fetchall()
    conn.close()

    failures = 0
    stroke_count_mismatches = []
    for character, expected_strokes, svg in rows:
        ok, parsed_count = _validate_stroke_svg(character, svg, "kanji")
        if not ok:
            failures += 1
            continue
        if parsed_count != expected_strokes:
            stroke_count_mismatches.append((character, expected_strokes, parsed_count))

    print(f"Validated {len(rows)} kanji rows: {len(rows) - failures} OK, "
          f"{failures} failed")
    if stroke_count_mismatches:
        print("Note: KanjiVG stroke count differs from bundled stroke_count for:")
        for character, expected, actual in stroke_count_mismatches:
            print(f"  {character}: bundle says {expected}, KanjiVG has {actual}")
    return failures == 0


def validate_kana_database(db_path: str) -> bool:
    """Re-parse every kana stroke_order_svg with the Swift-equivalent logic.

    Unlike kanji (whose stroke_count is a hand-curated fact from the N5
    list, so a KanjiVG mismatch is only a note), kana's stroke_count is
    *derived* from the same parsed paths in `update_kana_database` — so any
    mismatch here would mean a bug in this script, not a content question,
    and is treated as a hard failure.
    """
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    table_exists = cur.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name='kana'"
    ).fetchone()
    if not table_exists:
        conn.close()
        print("No `kana` table present — nothing to validate.")
        return True

    rows = cur.execute(
        "SELECT character, stroke_count, stroke_order_svg FROM kana ORDER BY character"
    ).fetchall()
    conn.close()

    failures = 0
    for character, stored_count, svg in rows:
        ok, parsed_count = _validate_stroke_svg(character, svg, "kana")
        if not ok:
            failures += 1
            continue
        if parsed_count != stored_count:
            print(f"  FAIL kana {character}: stored stroke_count={stored_count} "
                  f"but re-parsing the stored SVG yields {parsed_count} paths")
            failures += 1

    print(f"Validated {len(rows)} kana rows: {len(rows) - failures} OK, "
          f"{failures} failed")
    return failures == 0


# ---------------------------------------------------------------------------
# Database update
# ---------------------------------------------------------------------------


def update_database(
    db_path: str,
    cache_dir: str = DEFAULT_CACHE_DIR,
    allow_network: bool = True,
) -> tuple[int, int]:
    """Populate kanji.stroke_order_svg for every row. Returns (updated, missing)."""
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    characters = [
        row[0] for row in cur.execute("SELECT character FROM kanji ORDER BY character")
    ]

    updated = 0
    missing = []
    for character in characters:
        svg = stroke_svg_for(character, cache_dir=cache_dir, allow_network=allow_network)
        if svg is None:
            missing.append(character)
            continue
        cur.execute(
            "UPDATE kanji SET stroke_order_svg = ? WHERE character = ?",
            (svg, character),
        )
        updated += 1

    conn.commit()
    conn.close()

    if missing:
        print(f"Missing stroke data for {len(missing)} kanji: {''.join(missing)}",
              file=sys.stderr)
    return updated, len(missing)


KANA_SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS kana (
    character TEXT PRIMARY KEY,
    stroke_count INTEGER,
    stroke_order_svg TEXT
);
"""


def update_kana_database(
    db_path: str,
    cache_dir: str = DEFAULT_CACHE_DIR,
    allow_network: bool = True,
    swift_path: str = KANA_SWIFT_SOURCE,
) -> tuple[int, int]:
    """Populate the `kana` table (character, stroke_count, stroke_order_svg)
    for every base/dakuten kana in KanaGroup.swift. Returns (updated, missing).

    Creates the table if it does not exist yet (`CREATE TABLE IF NOT
    EXISTS`), so this also works against a bundle built before the kana
    table was added to generate_content_bundles.py's schema — no full
    regenerate-then-fetch dance required.
    """
    characters = kana_characters_from_swift(swift_path)

    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.executescript(KANA_SCHEMA_SQL)
    cur.executemany(
        "INSERT OR IGNORE INTO kana (character) VALUES (?)",
        [(character,) for character in characters],
    )

    updated = 0
    missing = []
    for character in characters:
        raw = fetch_raw_svg(character, cache_dir=cache_dir, allow_network=allow_network)
        if raw is None:
            missing.append(character)
            continue
        svg = build_app_stroke_svg(raw)
        if svg is None:
            missing.append(character)
            continue
        # Derived from the same parsed strokes, never hand-curated —
        # guarantees stroke_count always matches the animated path count.
        stroke_count = len(extract_raw_path_data(raw))
        cur.execute(
            "UPDATE kana SET stroke_count = ?, stroke_order_svg = ? WHERE character = ?",
            (stroke_count, svg, character),
        )
        updated += 1

    conn.commit()
    conn.close()

    if missing:
        print(f"Missing stroke data for {len(missing)} kana: {''.join(missing)}",
              file=sys.stderr)
    return updated, len(missing)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Fetch KanjiVG stroke data and embed it into a content bundle.",
    )
    parser.add_argument("--db", default=DEFAULT_DB_PATH,
                        help=f"SQLite bundle to update (default: {DEFAULT_DB_PATH})")
    parser.add_argument("--cache-dir", default=DEFAULT_CACHE_DIR,
                        help=f"KanjiVG SVG cache directory (default: {DEFAULT_CACHE_DIR})")
    parser.add_argument("--no-network", action="store_true",
                        help="Cache-only mode; never hit the network")
    parser.add_argument("--validate-only", action="store_true",
                        help="Skip updating; just validate existing rows")
    parser.add_argument("--skip-kana", action="store_true",
                        help="Only update/validate kanji stroke data, skip the kana table")
    args = parser.parse_args()

    if not os.path.exists(args.db):
        print(f"Database not found: {args.db}", file=sys.stderr)
        sys.exit(1)

    if not args.validate_only:
        updated, missing = update_database(
            args.db, cache_dir=args.cache_dir, allow_network=not args.no_network
        )
        print(f"Updated stroke_order_svg for {updated} kanji ({missing} missing)")

        if not args.skip_kana:
            kana_updated, kana_missing = update_kana_database(
                args.db, cache_dir=args.cache_dir, allow_network=not args.no_network
            )
            print(f"Updated stroke_order_svg for {kana_updated} kana ({kana_missing} missing)")

    ok = validate_database(args.db)
    if not args.skip_kana:
        ok = validate_kana_database(args.db) and ok
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
