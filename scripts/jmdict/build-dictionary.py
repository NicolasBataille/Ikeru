#!/usr/bin/env python3
"""Build `jmdict.sqlite` — the dictionary the « texte perso » feature reads.

Why this exists at all: the curated N5 bundle covers **18 % of the occurrences**
of realistic modern Japanese (measured 2026-08-19 on ten hand-written sentences
in the registers the feature targets — tweet, menu, manga bubble, work message,
lyrics). A « tu connais X % de ce texte » computed against 693 words would have
displayed 18 % on text a learner half understands, and most of the gap was not
even vocabulary — it was particles and inflection fragments. The mirror is a
lie without a real dictionary.

## ⛔ Do not re-run this on a whim

The dictionary is committed whole, 27,75 MiB, into a **public** repository. That
is a deliberate product decision (Nico, 2026-08-20): pruning to the common
entries would save 85 % of the weight for three points of resolution, but what
disappears is ございます, ネタバレ, 申し付け — the commercial keigo and the
social-media slang, which is precisely the tail this feature exists to read. The
precedent is the bundled audio, committed on the same reasoning.

The cost is not today's 27 MiB, it is the **~13 MiB of permanent public history
every regeneration adds**, forever, whether or not the result differs. So:

- **regenerate rarely and on purpose**, never « to be up to date ». JMdict moves
  by a handful of entries a week; that is far below what justifies a resync.
- a good reason is a **measured gap** — words a learner actually met that the
  bundle could not resolve. Not a date.
- before committing the result, check it actually changed something that
  matters: `sqlite3 jmdict.sqlite "select count(*) from entries"` and a run of
  `DictionaryCoverageTests`. An identical-in-practice rebuild is 13 MiB of
  history for nothing.

## What the app needs from it, and nothing more

1. **Lookup by surface form.** A form is any string that can literally appear in
   text: every kanji spelling and every kana spelling, including the ones
   JMdict marks search-only (`sK`/`sk`) or rare (`rK`/`rk`) — those exist
   precisely so a lookup can find them. They are indexed, never displayed.
2. **A reading**, to show furigana and to speak the word.
3. **Parts of speech**, which carry two jobs at once:
   - the deinflector needs them to know that 降っ can come from 降る (`v5r`) but
     not from a `v1`;
   - the coverage mirror needs them to keep particles and auxiliaries **out of
     the denominator**. Apple's `NLTagger` exposes no part of speech for
     Japanese (measured: `availableTagSchemes(for: .word, language: .japanese)`
     returns only Language, Script, TokenType), so JMdict is the only source.
4. **A gloss**, French when JMdict has one, English otherwise.

## French coverage is 7 %, and that number is not the useful one

Measured on the 2026-08-19 file: 15 336 of 218 498 entries carry a French
gloss. But the French set is curated toward common words — **43.4 % of the
priority-marked entries have one**, and 85 % of all French glosses sit on such
an entry. So a learner reading ordinary text meets French far more often than
7 % suggests, and rare words are exactly where English shows up.

Hence the shipped rule, decided with the product side: **an English gloss is
shown labelled as English, never silently.** `gloss_fr IS NULL` is the signal
the UI reads to draw that label. « Définition non disponible » is reserved for
words JMdict does not have at all.

## Part-of-speech tags arrive as XML entities

JMdict writes `<pos>&v5k;</pos>`, and expat substitutes the entity's **value**
("Godan verb with `ku' ending"), losing the short tag the code wants. The
internal DTD is therefore read first and the mapping inverted. Exactly one of
the 267 declared values is ambiguous ("word containing irregular kana usage"),
and it is a `misc`/`ke_inf` value, never a `pos` — checked, not assumed.

Usage:
    python3 scripts/jmdict/build-dictionary.py --xml JMdict.xml [--out PATH]
"""
from __future__ import annotations

import argparse
import re
import sqlite3
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
DEFAULT_OUT = REPO / "Ikeru" / "Resources" / "ContentBundles" / "jmdict.sqlite"
DEFAULT_CURATED = REPO / "Ikeru" / "Resources" / "ContentBundles" / "n5-content.sqlite"

XML_LANG = "{http://www.w3.org/XML/1998/namespace}lang"

# Cap on what is stored per entry. A learner reading a sentence wants the sense
# that fits it, not a lexicographic survey; three senses of three glosses is
# already more than a tap-to-reveal card can show without scrolling.
MAX_SENSES = 3

# Marqueurs `ke_inf`/`re_inf` qui disent « cette graphie existe mais n'est pas
# le mot » : rarement utilisée, ou présente uniquement pour la recherche.
MARGINAL = {"rK", "sK", "rk", "sk"}
MAX_GLOSSES_PER_SENSE = 3


def entity_map(xml_path: Path) -> dict[str, str]:
    """Long entity value → short tag (`Godan verb …` → `v5k`)."""
    with xml_path.open(encoding="utf-8") as handle:
        head = handle.read(400_000)
    pairs = re.findall(r'<!ENTITY\s+([\w-]+)\s+"([^"]*)">', head)
    if not pairs:
        raise SystemExit("aucune entité trouvée : le DTD interne a-t-il bougé ?")
    return {value: name for name, value in pairs}


def gloss_text(sense: ET.Element, lang: str) -> str:
    """The sense's glosses in `lang`, joined — empty when it has none."""
    texts = [
        (g.text or "").strip()
        for g in sense.findall("gloss")
        if (g.get(XML_LANG) or "eng") == lang and (g.text or "").strip()
    ]
    return "; ".join(texts[:MAX_GLOSSES_PER_SENSE])


def curated_forms(path: Path) -> set[str]:
    """Spellings the app already teaches, used as a learner-level prior."""
    if not path.exists():
        print(f"⚠️  {path.name} absent : le signal « au programme » sera vide")
        return set()
    con = sqlite3.connect(path)
    forms = {row[0] for row in con.execute("SELECT word FROM vocabulary") if row[0]}
    con.close()
    return forms


def build(xml_path: Path, out_path: Path, curated_path: Path) -> int:
    tags = entity_map(xml_path)
    curated = curated_forms(curated_path)

    if out_path.exists():
        out_path.unlink()
    con = sqlite3.connect(out_path)
    con.executescript(
        """
        PRAGMA journal_mode = OFF;
        PRAGMA synchronous  = OFF;
        CREATE TABLE entries (
            id       INTEGER PRIMARY KEY,
            reading  TEXT    NOT NULL,
            pos      TEXT    NOT NULL,
            gloss_fr TEXT,
            gloss_en TEXT    NOT NULL,
            common   INTEGER NOT NULL,
            -- 1 quand la forme figure au programme curaté de l'app (N5).
            -- Signal d'APPRENANT, pas de corpus : 行く et 行う portent tous
            -- deux `ichi1`, mais 行う est nf01 parce que les journaux
            -- l'emploient sans cesse — d'où 行って rendu « effectuer » au lieu
            -- d'« aller ». Celui qui lit ici est un débutant, pas Asahi.
            curated  INTEGER NOT NULL,
            -- Rang de fréquence JMdict (`nf01`…`nf48`), 99 quand l'entrée n'en
            -- porte pas. C'est un vrai classement, pas un drapeau : le réduire
            -- à un booléen jetait l'information qui départage deux entrées.
            freq     INTEGER NOT NULL
        );
        -- WITHOUT ROWID, et ce n'est pas de la coquetterie : en table
        -- ordinaire + index, `form` est stocké DEUX fois (12,9 Mo de table +
        -- 11,4 Mo d'index, mesuré). Ici la clé primaire EST le B-tree de
        -- recherche, donc le texte n'existe qu'une fois.
        CREATE TABLE forms (
            form     TEXT    NOT NULL,
            entry_id INTEGER NOT NULL,
            -- Rang de la graphie dans son entrée :
            --   0 — premier kanji, ou première lecture d'un mot qui n'a PAS de
            --       kanji (les particules, この, だけ) ;
            --   1 — autre kanji, ou première lecture d'un mot qui a un kanji ;
            --   2 — toute autre lecture.
            --
            -- Trois bugs mesurés tiennent dans cette colonne. Sans elle, 降る
            -- s'affichait « descendre » (il est la graphie principale de ふる
            -- et une graphie secondaire de くだる). En ne marquant que le
            -- premier kanji, この devenait « 九 » et だけ « 岳 ». Et en mettant
            -- les lectures au même rang que les kanji, は, が, から, の, と, も
            -- ressortaient tous en NOMS — 葉, 蛾, 空, 野, 戸, 藻 — parce que
            -- は est la première lecture de 葉 autant que la particule. Un
            -- kanji lu par sa kana n'est pas la même chose qu'un mot qui
            -- s'écrit en kana.
            priority INTEGER NOT NULL,
            PRIMARY KEY (form, entry_id)
        ) WITHOUT ROWID;
        """
    )

    entries: list[tuple] = []
    forms: list[tuple[str, int]] = []
    kept = 0

    for _, element in ET.iterparse(str(xml_path), events=("end",)):
        if element.tag != "entry":
            continue

        seq_text = element.findtext("ent_seq")
        if not seq_text:
            element.clear()
            continue
        entry_id = int(seq_text)

        kanji = [k.text for k in element.findall("k_ele/keb") if k.text]
        kana = [r.text for r in element.findall("r_ele/reb") if r.text]
        if not kana:
            element.clear()
            continue

        # Une graphie marquée « rarement utilisée » (rK/rk) ou « recherche
        # seulement » (sK/sk) est indexable mais ne représente pas le mot.
        # の s'écrit 乃 en théorie — marqué search-only — et c'est ce qui le
        # faisait perdre contre 野 « champ ». Idem この (此の, rarely used).
        real_kanji = [
            k.findtext("keb")
            for k in element.findall("k_ele")
            if k.findtext("keb")
            and not {tags.get((i.text or "").strip()) for i in k.findall("ke_inf")} & MARGINAL
        ]
        real_kana = [
            r.findtext("reb")
            for r in element.findall("r_ele")
            if r.findtext("reb")
            and not {tags.get((i.text or "").strip()) for i in r.findall("re_inf")} & MARGINAL
        ]

        # Senses: parts of speech accumulate across senses (JMdict omits <pos>
        # on a sense that repeats the previous one's), glosses stay per sense.
        pos_tags: list[str] = []
        fr_parts: list[str] = []
        en_parts: list[str] = []
        for sense in element.findall("sense"):
            for pos in sense.findall("pos"):
                tag = tags.get((pos.text or "").strip())
                if tag and tag not in pos_tags:
                    pos_tags.append(tag)
            # ⚠️ Toutes les acceptions sont PARCOURUES, seules les premières
            # non vides sont retenues. Couper la boucle à `MAX_SENSES` faisait
            # tomber le français de 15 336 entrées à 8 363 : JMdict place
            # souvent la gloss française sur une acception tardive, là où
            # l'anglaise est sur la première.
            french = gloss_text(sense, "fre")
            english = gloss_text(sense, "eng")
            if french and len(fr_parts) < MAX_SENSES:
                fr_parts.append(french)
            if english and len(en_parts) < MAX_SENSES:
                en_parts.append(english)

        if not en_parts:
            element.clear()
            continue

        priorities = [
            p.text or "" for p in element.findall("k_ele/ke_pri") + element.findall("r_ele/re_pri")
        ]
        common = int(len(priorities) > 0)
        bands = [int(m.group(1)) for p in priorities if (m := re.fullmatch(r"nf(\d+)", p))]
        entries.append(
            (
                entry_id,
                kana[0],
                " ".join(pos_tags),
                " / ".join(fr_parts) or None,
                " / ".join(en_parts),
                common,
                min(bands) if bands else 99,
                int(bool(curated & set(kanji + kana))),
            )
        )
        # Every spelling is a lookup key, kanji and kana alike. Duplicates
        # inside one entry are dropped; across entries they are expected —
        # 生 alone is several words, and the caller ranks the candidates.
        ranks: dict[str, int] = {}
        if real_kanji:
            ranks[real_kanji[0]] = 0
        elif real_kana:
            # Mot qui s'écrit en kana : sa première lecture EST sa graphie.
            ranks[real_kana[0]] = 0
        for form in kanji:
            ranks.setdefault(form, 1)
        for index, form in enumerate(kana):
            ranks.setdefault(form, 1 if index == 0 else 2)
        for form, rank in ranks.items():
            forms.append((form, entry_id, rank))
        kept += 1

        element.clear()

    con.executemany(
        # Colonnes NOMMÉES, et pas un tuple positionnel : la première version
        # insérait `freq` dans `curated` et réciproquement, sans que rien ne
        # proteste — 行く ressortait « au programme = 99 ». Un décalage
        # positionnel entre le CREATE TABLE et le tuple ne se voit pas à la
        # relecture, il se voit sur la première donnée absurde.
        "INSERT INTO entries (id, reading, pos, gloss_fr, gloss_en, common, freq, curated) "
        "VALUES (?,?,?,?,?,?,?,?)", entries)
    con.executemany(
        "INSERT OR IGNORE INTO forms (form, entry_id, priority) VALUES (?,?,?)", forms)
    con.commit()
    con.execute("VACUUM")

    with_fr = con.execute("SELECT count(*) FROM entries WHERE gloss_fr IS NOT NULL").fetchone()[0]
    common_count = con.execute("SELECT count(*) FROM entries WHERE common = 1").fetchone()[0]
    curated_count = con.execute("SELECT count(*) FROM entries WHERE curated = 1").fetchone()[0]
    con.close()

    size_mb = out_path.stat().st_size / 1_048_576
    print(f"entrées          : {kept}")
    print(f"formes indexées  : {len(forms)}")
    print(f"gloss FR         : {with_fr} ({100 * with_fr / kept:.1f}%)")
    print(f"courantes        : {common_count} ({100 * common_count / kept:.1f}%)")
    print(f"au programme N5  : {curated_count}")
    print(f"taille           : {size_mb:.1f} Mo → {out_path}")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--xml", type=Path, required=True, help="JMdict.xml décompressé")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--curated", type=Path, default=DEFAULT_CURATED)
    args = parser.parse_args(argv)
    if not args.xml.exists():
        raise SystemExit(f"introuvable : {args.xml}")
    return build(args.xml, args.out, args.curated)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
