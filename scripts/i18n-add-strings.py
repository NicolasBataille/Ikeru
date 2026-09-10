#!/usr/bin/env python3
"""Insert entries into `Localizable.xcstrings` **without reformatting it**.

⚠️ Never round-trip this catalogue through `json.dumps`. Doing so once rewrote
all 16 000 lines — Xcode writes `"key" : {` with spaces around the colon, and
Python does not — burying a two-line change in an unreviewable diff. This script
splices formatted text blocks at the right alphabetical position and leaves
every other byte alone.

Input is JSON on stdin: `{"key": {"en": "...", "fr": "..."}, ...}`.
A key already present is skipped, never overwritten: the catalogue is the
translator's file, not the generator's.

Usage:
    echo '{"Paste":{"en":"Paste","fr":"Coller"}}' | python3 scripts/i18n-add-strings.py
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

CATALOGUE = Path(__file__).resolve().parent.parent / "Ikeru" / "Localization" / "Localizable.xcstrings"


def block(key: str, translations: dict[str, str]) -> str:
    """One entry, formatted exactly the way Xcode writes it."""
    encoded_key = json.dumps(key, ensure_ascii=False)
    lines = [f"    {encoded_key} : {{", '      "localizations" : {']
    for index, language in enumerate(sorted(translations)):
        value = json.dumps(translations[language], ensure_ascii=False)
        comma = "," if index < len(translations) - 1 else ""
        lines += [
            f'        "{language}" : {{',
            '          "stringUnit" : {',
            '            "state" : "translated",',
            f"            \"value\" : {value}",
            "          }",
            f"        }}{comma}",
        ]
    lines += ["      }", "    }"]
    return "\n".join(lines)


def existing_keys(text: str) -> list[tuple[str, int]]:
    """Top-level keys with the offset of the line they start on."""
    found = []
    for match in re.finditer(r'^    ("(?:[^"\\]|\\.)*") : \{$', text, flags=re.MULTILINE):
        found.append((json.loads(match.group(1)), match.start()))
    return found


def main() -> int:
    payload = json.load(sys.stdin)
    text = CATALOGUE.read_text(encoding="utf-8")
    keys = existing_keys(text)
    if not keys:
        raise SystemExit("aucune clé trouvée : le format du catalogue a-t-il changé ?")

    added, skipped = 0, 0
    for key in sorted(payload, reverse=True):
        if any(existing == key for existing, _ in keys):
            skipped += 1
            continue
        # Position alphabétique : juste avant la première clé qui la suit.
        target = next((offset for existing, offset in keys if existing > key), None)
        entry = block(key, payload[key])
        if target is None:
            # Après la dernière clé : il faut virguler celle qui précède.
            last_key, last_offset = keys[-1]
            end = text.index("\n    }\n", last_offset) + len("\n    }")
            text = text[:end] + ",\n" + entry + text[end:]
        else:
            text = text[:target] + entry + ",\n" + text[target:]
        keys = existing_keys(text)
        added += 1
        print(f"ajouté : {key}")

    CATALOGUE.write_text(text, encoding="utf-8")
    print(f"\n{added} ajoutée(s), {skipped} déjà présente(s)")
    # Garde-fou : le fichier doit rester du JSON valide et n'avoir rien perdu.
    reparsed = json.loads(CATALOGUE.read_text(encoding="utf-8"))
    print(f"catalogue relu : {len(reparsed['strings'])} clés")
    return 0


if __name__ == "__main__":
    sys.exit(main())
