#!/usr/bin/env python3
"""Register source files in Ikeru.xcodeproj so a new folder actually builds.

The project keeps explicit file references — not folder references — for Swift
sources, so a file that exists on disk and is not registered here compiles
nowhere and fails at the import site, which is a confusing place to discover it.

Deterministic identifiers derived from the path: re-running is a no-op instead
of creating a second entry for the same file.

Usage:
    python3 scripts/pbxproj-add-files.py --group "Ikeru/Views/Learning/TextImport" FILE [FILE …]
"""
from __future__ import annotations

import argparse
import hashlib
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PBXPROJ = REPO / "Ikeru.xcodeproj" / "project.pbxproj"


def identifier(seed: str) -> str:
    """A stable 24-hex-character Xcode identifier for `seed`."""
    return hashlib.sha1(seed.encode("utf-8")).hexdigest()[:24].upper()


def group_id(text: str, path: str) -> str | None:
    """The PBXGroup whose `path` is the last component of `path`, if present."""
    name = Path(path).name
    for match in re.finditer(r"\t\t([0-9A-F]{24}) /\* (.+?) \*/ = \{\n\t\t\tisa = PBXGroup;", text):
        block_start = match.end()
        block = text[block_start:text.index("};", block_start)]
        if re.search(rf'\n\t\t\tpath = "?{re.escape(name)}"?;', block):
            return match.group(1)
    return None


def parent_group_id(text: str, path: str) -> str | None:
    return group_id(text, str(Path(path).parent))


def add_group(text: str, path: str) -> tuple[str, str]:
    """Creates the PBXGroup for `path` under its parent, returning the new text."""
    existing = group_id(text, path)
    if existing:
        return text, existing
    gid = identifier(f"group:{path}")
    name = Path(path).name
    parent = parent_group_id(text, path)
    if parent is None:
        raise SystemExit(f"groupe parent introuvable pour {path}")

    block = (f"\t\t{gid} /* {name} */ = {{\n"
             f"\t\t\tisa = PBXGroup;\n"
             f"\t\t\tchildren = (\n"
             f"\t\t\t);\n"
             f"\t\t\tpath = {name};\n"
             f"\t\t\tsourceTree = \"<group>\";\n"
             f"\t\t}};\n")
    marker = "/* End PBXGroup section */"
    text = text.replace(marker, block + marker, 1)

    anchor = re.search(rf"\t\t{parent} /\* .+? \*/ = \{{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n", text)
    if not anchor:
        raise SystemExit(f"impossible d'insérer {name} dans son parent")
    text = text[:anchor.end()] + f"\t\t\t\t{gid} /* {name} */,\n" + text[anchor.end():]
    return text, gid


def add_file(text: str, relative: str, gid: str, sources_phase: str) -> str:
    name = Path(relative).name
    file_ref = identifier(f"file:{relative}")
    build_file = identifier(f"build:{relative}")
    if file_ref in text:
        return text

    text = text.replace(
        "/* End PBXFileReference section */",
        f'\t\t{file_ref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; '
        f'path = {name}; sourceTree = "<group>"; }};\n/* End PBXFileReference section */', 1)
    text = text.replace(
        "/* End PBXBuildFile section */",
        f"\t\t{build_file} /* {name} in Sources */ = {{isa = PBXBuildFile; "
        f"fileRef = {file_ref} /* {name} */; }};\n/* End PBXBuildFile section */", 1)

    anchor = re.search(rf"\t\t{gid} /\* .+? \*/ = \{{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n", text)
    if not anchor:
        raise SystemExit(f"groupe {gid} introuvable pour {name}")
    text = text[:anchor.end()] + f"\t\t\t\t{file_ref} /* {name} */,\n" + text[anchor.end():]

    anchor = re.search(rf"\t\t{sources_phase} /\* Sources \*/ = \{{\n(?:.*?\n)*?\t\t\tfiles = \(\n", text)
    if not anchor:
        raise SystemExit("phase Sources introuvable")
    text = text[:anchor.end()] + f"\t\t\t\t{build_file} /* {name} in Sources */,\n" + text[anchor.end():]
    return text


def sources_phase_for(text: str, target: str) -> str:
    """Identifier of `target`'s Sources build phase."""
    match = re.search(rf'/\* {re.escape(target)} \*/ = \{{\n\t\t\tisa = PBXNativeTarget;'
                      r'(?:.*?\n)*?\t\t\tbuildPhases = \(\n((?:.*?\n)*?)\t\t\t\);', text)
    if not match:
        raise SystemExit(f"cible {target} introuvable")
    for phase in re.findall(r"\t\t\t\t([0-9A-F]{24}) /\* (.+?) \*/,", match.group(1)):
        if phase[1] == "Sources":
            return phase[0]
    raise SystemExit(f"phase Sources de {target} introuvable")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--group", required=True, help="chemin du groupe, ex. Ikeru/Views/Learning/TextImport")
    parser.add_argument("--target", default="Ikeru")
    parser.add_argument("files", nargs="+", help="chemins relatifs au dépôt")
    args = parser.parse_args(argv)

    text = PBXPROJ.read_text(encoding="utf-8")
    phase = sources_phase_for(text, args.target)

    # Crée la chaîne de groupes manquants, du haut vers le bas.
    parts = Path(args.group).parts
    for depth in range(1, len(parts) + 1):
        text, gid = add_group(text, str(Path(*parts[:depth])))

    for relative in args.files:
        if not (REPO / relative).exists():
            raise SystemExit(f"fichier absent : {relative}")
        text = add_file(text, relative, gid, phase)
        print(f"enregistré : {relative}")

    PBXPROJ.write_text(text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
