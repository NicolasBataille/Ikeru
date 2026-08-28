#!/usr/bin/env python3
"""i18n-lint.py — SwiftUI Text(...) vs Localizable.xcstrings consistency checker.

Standard library only (json, re, sys, pathlib, argparse).

Scans every *.swift file under the app target (Ikeru/, excluding IkeruTests/
and *Tests.swift) for `Text("...")` call sites and reconstructs the
LocalizedStringKey SwiftUI would generate for each one:

  - A plain string literal `Text("Hello")` -> the key IS the literal.
  - An interpolated literal `Text("\(x) cards ready")` -> SwiftUI builds a
    format key, replacing each `\(expr)` with a specifier:
        Int-like expr (`.count`, `x + 1`, `Int(...)`, obvious int identifier)
            -> "%lld"
        anything else (String, .rawValue, String(format:...), ternary, ...)
            -> "%@"
    e.g. `Text("\(cards.count) cards ready")` -> key "%lld cards ready".

Each generated key is checked against Ikeru/Localization/Localizable.xcstrings:
  - "missing-key"        the key does not exist in the catalogue at all.
  - "missing-fr"         the key exists but has no (non-empty) FR translation.
  - "specifier-mismatch" the key's "skeleton" (specifiers erased) exists in the
                         catalogue under a *different* specifier form only
                         (e.g. code wants "%lld XP" but the catalogue only has
                         "%@ XP") -- a strong signal of a dead translation.

Interpolated-key detection is best-effort/advisory: type inference is a
syntactic heuristic, not a real Swift type checker.

Supports a baseline file (--baseline) so CI only fails on *new* violations,
not the backlog. Use --update-baseline to (re)generate it from the current
state of the tree.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CATALOGUE = REPO_ROOT / "Ikeru" / "Localization" / "Localizable.xcstrings"
DEFAULT_ROOT = REPO_ROOT / "Ikeru"
# Le linter ne regardait QUE la cible app. Les cibles embarquees rendent
# pourtant du texte a l'utilisateur, et leurs chaines n'etaient donc jamais
# verifiees — c'est ainsi que les libelles de la Watch ont pu ne jamais entrer
# au catalogue (OBS2-047). IkeruShare avait meme une phase Resources vide, donc
# ses chaines francaises existaient sans jamais atteindre le binaire (OBS2-061).
DEFAULT_ROOTS = [
    REPO_ROOT / "Ikeru",
    REPO_ROOT / "IkeruWatch",
    REPO_ROOT / "IkeruWidget",
    REPO_ROOT / "IkeruShare",
]

# Noms de parametres qui portent, par convention, du texte destine a l'ecran.
# Volontairement etroit : `icon:` est un symbole SF, `value:` un nombre
# formate, ni l'un ni l'autre ne se traduit.
LABEL_PARAM_NAMES = (
    "title", "label", "eyebrow", "subtitle", "caption", "heading",
    "hint", "kicker", "placeholder", "prompt", "message",
)

LABEL_TYPED_STRING_RE = re.compile(
    r"\b(" + "|".join(LABEL_PARAM_NAMES) + r")\s*:\s*String\b(?!\s*\.)"
)
DEFAULT_BASELINE = REPO_ROOT / "scripts" / "i18n-lint-baseline.json"

# ---------------------------------------------------------------------------
# Swift string-literal parsing
# ---------------------------------------------------------------------------


def parse_string_literal(text: str, i: int) -> tuple[list[tuple[str, str]], int]:
    """Parse a Swift double-quoted string literal starting at text[i] == '"'.

    Returns (parts, end_index) where parts is a list of
    ("lit", raw_escaped_text) | ("expr", interpolation_source) tuples, in
    order, and end_index is the index just past the closing quote.
    """
    assert text[i] == '"'
    n = len(text)
    j = i + 1
    parts: list[tuple[str, str]] = []
    buf: list[str] = []
    while j < n:
        c = text[j]
        if c == "\\" and j + 1 < n and text[j + 1] == "(":
            if buf:
                parts.append(("lit", "".join(buf)))
                buf = []
            expr, j = parse_interpolation(text, j + 1)
            parts.append(("expr", expr))
            continue
        if c == "\\" and j + 1 < n:
            buf.append(c)
            buf.append(text[j + 1])
            j += 2
            continue
        if c == '"':
            j += 1
            break
        buf.append(c)
        j += 1
    else:
        # Unterminated literal (shouldn't happen in valid Swift) — bail out
        # gracefully rather than raising.
        if buf:
            parts.append(("lit", "".join(buf)))
        return parts, n
    if buf:
        parts.append(("lit", "".join(buf)))
    return parts, j


def parse_interpolation(text: str, i: int) -> tuple[str, int]:
    """text[i] == '(' (the paren right after a \\ that starts an interpolation).

    Returns (expr_source, end_index) where end_index is just past the
    matching closing paren. Correctly skips over nested parens and nested
    string literals (which may themselves contain interpolations).
    """
    assert text[i] == "("
    n = len(text)
    depth = 1
    j = i + 1
    start = j
    while j < n and depth > 0:
        c = text[j]
        if c == '"':
            _, j = parse_string_literal(text, j)
            continue
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                break
        j += 1
    expr = text[start:j]
    return expr, j + 1


_ESCAPE_UNICODE_RE = re.compile(r"\\u\{([0-9a-fA-F]+)\}")


def decode_swift_literal_text(raw: str) -> str:
    """Decode escape sequences in a raw (still-escaped) Swift string chunk."""
    out = _ESCAPE_UNICODE_RE.sub(lambda m: chr(int(m.group(1), 16)), raw)
    out = (
        out.replace("\\\\", "\x00ESC_BACKSLASH\x00")
        .replace('\\"', '"')
        .replace("\\n", "\n")
        .replace("\\t", "\t")
        .replace("\\0", "\0")
        .replace("\x00ESC_BACKSLASH\x00", "\\")
    )
    return out


# ---------------------------------------------------------------------------
# Interpolated-expression type classification (Int-like -> %lld, else -> %@)
# ---------------------------------------------------------------------------

# Identifiers (last dotted component, call parens stripped) that are almost
# always plain Ints in this codebase (counts, indices, levels, scores, ...).
# Checked with exact match OR as a suffix (e.g. "dueCount", "unlockLevel",
# "xpToNextLevel" all end in a recognized int-ish word).
_INT_LIKE_IDENTIFIERS = {
    "value",
    "amount",
    "total",
    "current",
    "required",
    "wrong",
    "correct",
    "missed",
    "position",
}
_INT_LIKE_SUFFIXES = (
    "count",
    "index",
    "level",
    "score",
    "xp",
    "percentage",
    "percent",
    "remaining",
    "seconds",
    "minutes",
    # Ajoutes le 2026-08-28 : l'heuristique classait `entry.dueCards` en `%@`,
    # donc reclamait au catalogue une cle « %@ cards ready » qui n'existe pas —
    # et surtout, en la lisant de bonne foi, on ajoute une cle MORTE. Un
    # avertissement faux coute plus cher qu'un avertissement absent : il fait
    # ecrire du code faux pour le faire taire.
    "cards",
    "days",
    "streak",
    "total",
    "reviews",
    "items",
)

# Suffixes / substrings that strongly indicate a String-typed expression.
_STRING_LIKE_SUFFIX_RE = re.compile(
    r"(String|Label|Title|Name|Reading|Pattern|Kanji|Description)$"
)
_STRING_LIKE_METHOD_RE = re.compile(
    r"\.(rawValue|capitalized|uppercased|lowercased|description)\b"
)


def classify_expr(expr: str) -> str:
    """Return '%lld' or '%@' for the given interpolation source expression."""
    e = expr.strip()

    # Ternaries and string-literal branches are always %@.
    if '"' in e or "?" in e and ":" in e:
        pass  # fall through to generic checks below; ternary handled by default

    if re.match(r"^Int\s*\(", e):
        return "%lld"
    if re.match(r"^(String|Text)\s*\(", e):
        return "%@"
    if _STRING_LIKE_METHOD_RE.search(e):
        return "%@"
    if re.search(r"\.count$", e):
        return "%lld"
    if re.search(r"\+\s*1$", e):
        return "%lld"

    last = e.split(".")[-1].strip()
    ident = re.sub(r"\(.*\)$", "", last).strip()
    ident_lower = ident.lower()

    if _STRING_LIKE_SUFFIX_RE.search(ident):
        return "%@"
    if ident_lower in _INT_LIKE_IDENTIFIERS:
        return "%lld"
    if any(ident_lower.endswith(suffix) for suffix in _INT_LIKE_SUFFIXES):
        return "%lld"

    return "%@"


def generated_key_for(parts: list[tuple[str, str]]) -> tuple[str, bool]:
    """Build the LocalizedStringKey SwiftUI generates for these parts.

    Returns (key, is_interpolated).
    """
    if all(kind == "lit" for kind, _ in parts):
        raw = "".join(v for _, v in parts)
        return decode_swift_literal_text(raw), False

    # SwiftUI builds a printf-style format string once there's ANY
    # interpolation, so literal "%" characters in the surrounding text must
    # be doubled to "%%" to survive as literal percent signs — otherwise
    # they'd be read as (the start of) a format specifier.
    out: list[str] = []
    for kind, value in parts:
        if kind == "lit":
            out.append(decode_swift_literal_text(value).replace("%", "%%"))
        else:
            out.append(classify_expr(value))
    return "".join(out), True


def skeleton_of(key: str) -> str:
    """Erase specifier *kind* so keys differing only by %lld vs %@ collapse."""
    return key.replace("%lld", "\x01").replace("%@", "\x01")


# ---------------------------------------------------------------------------
# Swift source scanning
# ---------------------------------------------------------------------------

_TEXT_CALL_RE = re.compile(r"(?<![\w.])Text\s*\(")
_VERBATIM_RE = re.compile(r"\s*verbatim\s*:")


def strip_preview_blocks(text: str) -> str:
    """Best-effort removal of `#Preview { ... }` block bodies via brace counting.

    Falls back to leaving the text untouched if no #Preview marker is found
    (cheap early-out) — any noise from previews we fail to strip just lands
    in the baseline like everything else.
    """
    marker = "#Preview"
    if marker not in text:
        return text
    out = []
    i = 0
    n = len(text)
    while i < n:
        idx = text.find(marker, i)
        if idx == -1:
            out.append(text[i:])
            break
        out.append(text[i:idx])
        # find the opening brace of the preview body
        brace_start = text.find("{", idx)
        if brace_start == -1:
            out.append(text[idx:])
            break
        depth = 1
        j = brace_start + 1
        while j < n and depth > 0:
            c = text[j]
            if c == '"':
                _, j = parse_string_literal(text, j)
                continue
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
            j += 1
        # Replace the whole #Preview { ... } block with blank lines so
        # subsequent line numbers stay aligned.
        removed = text[idx:j]
        out.append("\n" * removed.count("\n"))
        i = j
    return "".join(out)


def find_text_call_sites(text: str) -> list[tuple[int, list[tuple[str, str]]]]:
    """Return [(char_index_of_string_literal_start, parts), ...] for every
    `Text("...")` call site. `Text(verbatim:` and `Text(identifier)` (no
    quote) are ignored.
    """
    results = []
    for m in _TEXT_CALL_RE.finditer(text):
        i = m.end()
        n = len(text)
        while i < n and text[i] in " \t\r\n":
            i += 1
        if i >= n:
            continue
        if _VERBATIM_RE.match(text[i : i + 20]):
            continue
        if text[i] != '"':
            continue
        parts, _end = parse_string_literal(text, i)
        results.append((i, parts))
    return results


def iter_swift_files(root: Path):
    for path in sorted(root.rglob("*.swift")):
        rel = path.relative_to(root.parent) if root.parent in path.parents else path
        parts = path.parts
        if "IkeruTests" in parts:
            continue
        if path.name.endswith("Tests.swift"):
            continue
        yield path


def line_number_of(text: str, index: int) -> int:
    return text.count("\n", 0, index) + 1


# ---------------------------------------------------------------------------
# Catalogue loading
# ---------------------------------------------------------------------------


def load_catalogue(path: Path):
    data = json.loads(path.read_text(encoding="utf-8"))
    strings = data.get("strings", {})
    keys = set(strings.keys())
    keys_with_fr = set()
    for key, entry in strings.items():
        loc = entry.get("localizations", {}) if isinstance(entry, dict) else {}
        fr = loc.get("fr")
        if not fr:
            continue
        unit = fr.get("stringUnit") or {}
        value = unit.get("value")
        if value:
            keys_with_fr.add(key)

    skeleton_to_keys: dict[str, set[str]] = {}
    for key in keys:
        skel = skeleton_of(key)
        skeleton_to_keys.setdefault(skel, set()).add(key)

    return keys, keys_with_fr, skeleton_to_keys


# ---------------------------------------------------------------------------
# Violation collection
# ---------------------------------------------------------------------------


def has_english_words(key: str) -> bool:
    """True if the key contains a translatable English word (vs a pure
    number/symbol/specifier skeleton like "%lld XP" or "%@%%")."""
    words = re.findall(r"[A-Za-z]{2,}", key)
    return any(w.lower() not in {"lld", "xp"} for w in words) if words else False


def find_label_typed_strings(text: str) -> list[tuple[int, str]]:
    """Parametres de libelle types `String` plutot que `LocalizedStringKey`.

    C'est la cause racine du BLOQUANT n° 4 (OBS2-050), et elle est invisible
    pour le reste de ce linter : un `String` selectionne l'init
    `Text(verbatim:)`, donc SwiftUI ne cherche RIEN dans le catalogue — et
    surtout `genstrings`/Xcode n'EXTRAIT rien non plus. La chaine n'est donc
    meme pas collectee, ce qui explique qu'un ecran a moitie anglais ait pu
    traverser un lint vert.

    Heuristique syntaxique, pas un verificateur de types : elle signale, elle
    ne prouve pas. D'ou la baseline.
    """
    hits: list[tuple[int, str]] = []
    for line_no, line in enumerate(text.split("\n"), start=1):
        code = line.split("//", 1)[0]
        if not code.strip():
            continue
        for m in LABEL_TYPED_STRING_RE.finditer(code):
            hits.append((line_no, m.group(1)))
    return hits


def lint_repo(roots, catalogue_path: Path) -> list[dict]:
    keys, keys_with_fr, skeleton_to_keys = load_catalogue(catalogue_path)
    violations: list[dict] = []

    if isinstance(roots, Path):
        roots = [roots]
    paths = [p for root in roots if root.exists() for p in iter_swift_files(root)]

    for path in paths:
        text = path.read_text(encoding="utf-8", errors="replace")
        stripped = strip_preview_blocks(text)
        rel = str(path.relative_to(REPO_ROOT)) if REPO_ROOT in path.parents else str(path)

        for line_no, param in find_label_typed_strings(stripped):
            violations.append(
                {
                    "file": rel,
                    "line": line_no,
                    "key": f"{param}: String",
                    "kind": "label-typed-String",
                    "interpolated": False,
                }
            )

        for str_start, parts in find_text_call_sites(stripped):
            key, is_interpolated = generated_key_for(parts)
            line = line_number_of(stripped, str_start)

            if key in keys and key in keys_with_fr:
                continue  # healthy

            if key in keys and key not in keys_with_fr:
                violations.append(
                    {
                        "file": rel,
                        "line": line,
                        "key": key,
                        "kind": "missing-fr",
                        "interpolated": is_interpolated,
                    }
                )
                continue

            # Not present verbatim. If interpolated, check for a
            # specifier-mismatch: same skeleton exists under a different
            # specifier form.
            if is_interpolated:
                skel = skeleton_of(key)
                siblings = skeleton_to_keys.get(skel, set())
                if siblings:
                    violations.append(
                        {
                            "file": rel,
                            "line": line,
                            "key": key,
                            "kind": "specifier-mismatch",
                            "interpolated": is_interpolated,
                            "catalogueVariants": sorted(siblings),
                        }
                    )
                    continue

            violations.append(
                {
                    "file": rel,
                    "line": line,
                    "key": key,
                    "kind": "missing-key",
                    "interpolated": is_interpolated,
                }
            )

    return violations


# ---------------------------------------------------------------------------
# Baseline handling + CLI
# ---------------------------------------------------------------------------


def violation_fingerprint(v: dict) -> str:
    # Line numbers shift with unrelated edits; key the baseline on the
    # (file, key, kind) triple, which is what actually identifies the issue.
    return f"{v['file']}::{v['key']}::{v['kind']}"


def load_baseline(path: Path) -> set[str]:
    if not path.exists():
        return set()
    data = json.loads(path.read_text(encoding="utf-8"))
    return set(data.get("violations", []))


def save_baseline(path: Path, violations: list[dict]) -> None:
    fingerprints = sorted({violation_fingerprint(v) for v in violations})
    payload = {
        "_comment": (
            "Auto-generated by `python3 scripts/i18n-lint.py --update-baseline`. "
            "Each entry is a `<file>::<generated key>::<kind>` fingerprint of a "
            "known-existing i18n-lint violation. New violations not listed here "
            "fail CI; regenerate after intentionally fixing or accepting new ones."
        ),
        "violations": fingerprints,
    }
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def print_report(violations: list[dict], baseline: set[str]) -> list[dict]:
    by_file: dict[str, list[dict]] = {}
    for v in violations:
        by_file.setdefault(v["file"], []).append(v)

    new_violations = []
    print(f"i18n-lint: {len(violations)} total violation(s) across {len(by_file)} file(s).")
    for file in sorted(by_file):
        vs = by_file[file]
        print(f"\n{file}")
        for v in sorted(vs, key=lambda x: x["line"]):
            fp = violation_fingerprint(v)
            is_new = fp not in baseline
            if is_new:
                new_violations.append(v)
            tag = "NEW" if is_new else "baseline"
            interp = " [interpolated/advisory]" if v.get("interpolated") else ""
            print(f"  L{v['line']:<5} {v['kind']:<20} {v['key']!r}{interp}  ({tag})")

    print(
        f"\nSummary: {len(violations)} total, {len(baseline)} in baseline, "
        f"{len(new_violations)} NEW."
    )
    return new_violations


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--catalogue",
        type=Path,
        default=DEFAULT_CATALOGUE,
        help="Path to Localizable.xcstrings",
    )
    parser.add_argument(
        "--root",
        type=Path,
        nargs="+",
        default=DEFAULT_ROOTS,
        help="Source roots to scan for *.swift files (app + embedded targets)",
    )
    parser.add_argument(
        "--baseline",
        type=Path,
        default=DEFAULT_BASELINE,
        help="Path to baseline JSON file",
    )
    parser.add_argument(
        "--update-baseline",
        action="store_true",
        help="Write the current violation set to --baseline instead of failing on new ones",
    )
    args = parser.parse_args()

    if not args.catalogue.exists():
        print(f"error: catalogue not found: {args.catalogue}", file=sys.stderr)
        return 2
    roots = args.root if isinstance(args.root, list) else [args.root]
    existing = [r for r in roots if r.exists()]
    if not existing:
        print(f"error: no source root found among: {roots}", file=sys.stderr)
        return 2

    violations = lint_repo(existing, args.catalogue)

    if args.update_baseline:
        save_baseline(args.baseline, violations)
        print(f"i18n-lint: wrote {len(violations)} violation(s) to {args.baseline}")
        return 0

    baseline = load_baseline(args.baseline)
    new_violations = print_report(violations, baseline)

    if new_violations:
        print(
            f"\ni18n-lint: FAIL — {len(new_violations)} new violation(s) not in baseline.",
            file=sys.stderr,
        )
        return 1

    print("\ni18n-lint: OK — no new violations.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
