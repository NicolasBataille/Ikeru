#!/usr/bin/env python3
"""Select a beginner Japanese↔French sentence corpus out of the Tatoeba exports.

This script is the *selection* half of the corpus pipeline. It reads the three
Tatoeba per-language exports, runs the funnel described in ``README.md``, and
writes the retained sentences to ``sentences.json`` — the versioned artefact
that ``scripts/apply-tatoeba-sentences.py`` later injects into the content
bundle. Running it is only needed to *regenerate* the selection; the committed
JSON is the source of truth for the app.

Licence: the Tatoeba **text** is CC BY 2.0 FR (https://tatoeba.org/en/downloads).
Nothing here touches Tatoeba **audio**, which is licensed per contributor and
mostly not reusable outside Tatoeba.

Nothing is written by hand: every Japanese sentence and every French
translation is reproduced verbatim from Tatoeba, minus two typographic
normalisations on the French (see ``normalise_french``) that align it with the
96 sentences already in the bundle.

Usage:
    scripts/tatoeba/build-corpus.py --exports DIR [--out FILE] [--verbose]

``DIR`` must hold the three decompressed exports:
    jpn_sentences.tsv  fra_sentences.tsv  jpn-fra_links.tsv
"""

from __future__ import annotations

import argparse
import collections
import json
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
DEFAULT_DB = REPO_ROOT / "Ikeru" / "Resources" / "ContentBundles" / "n5-content.sqlite"
DEFAULT_OUT = Path(__file__).resolve().parent / "sentences.json"
TOKENIZER_SOURCE = Path(__file__).resolve().parent / "tokenize-japanese.swift"
BLOCKLIST_PATH = Path(__file__).resolve().parent / "blocklist.json"

# MARK: - Thresholds (every one of these is justified in README.md)
#
# ## Why MAX_UNKNOWN_TOKENS stayed at 2 when the bundle tripled
#
# The warning that used to sit on that constant was right about the mechanism
# and wrong about what to do. More known words DOES mean fewer unknown tokens
# per sentence, so at 693 words the same cut admits sentences it would once
# have rejected. Measured with `--max-unknown N --dry-run`:
#
#     cut at 0 →  316 sentences,  154/693 words anchored,  29/31 grammar
#     cut at 1 →  506 sentences,  187/693 words anchored,  30/31 grammar
#     cut at 2 →  536 sentences,  188/693 words anchored,  30/31 grammar
#
# Tightening to 1 looked almost free — 30 sentences, one vocabulary word. Then
# the 37 sentences that actually differ were read, and they are not the tail
# anyone would want cut:
#
#     日本語を話します。          Je parle le japonais.
#     わたしはテレビを見ています。  Je regarde la télévision.
#     この本は読みやすい。         Ce livre est facile à lire.
#     いくらお金をもっていますか。  Combien d'argent avez-vous sur vous ?
#
# Dropping « I speak Japanese » out of a Japanese-learning app to satisfy a
# threshold is the wrong trade. What protects the 2-unknown band is a filter
# that was already there: MIN_UNKNOWN_DOC_FREQ makes every unknown a word
# appearing in ≥150 corpus sentences, so "two unknowns" means two common words,
# never two idiom fragments. And the band is a tail, not the bulk — of 1374
# candidates only 230 carry two unknowns (512 carry none, 588 carry one), so
# roughly 7 % of the retained corpus sits at the loose end.
#
# Cut at 0 is not a stricter i+1, it is i+0: no sentence teaches anything new,
# and it costs a grammar point.
#
# The lesson for the next person: `--max-unknown N --dry-run` prints the whole
# distribution. Re-run it rather than inheriting this paragraph.

MIN_CHARS = 6              # below this, Tatoeba yields interjections ("はい。")
MAX_CHARS = 18             # above this, sentences pile up clauses and proper nouns
MAX_UNKNOWN_TOKENS = 2     # i+1 tolerance. RE-MEASURED 2026-08-16 against the
                           # 693-word bundle (the note here said 688; it was
                           # wrong, and the whole point of that note was that
                           # stale numbers mislead). Kept at 2 — see below.
MIN_UNKNOWN_DOC_FREQ = 150 # an unknown word must still be common corpus-wide
GLUE_DOC_FREQ_RATIO = 0.002  # hiragana token seen in ≥0.2% of jpn → grammatical glue
MAX_PER_VOCAB_WORD = 5     # VocabularyExamplesView shows Self.examplesPerWord (2) of these
                           # via .prefix(2); that view is unreached from navigation today
                           # (verified 2026-08-15, see its own doc comment) — the cap keeps
                           # the data sane for whichever reader eventually reaches it

# MARK: - Character classes

KANJI_RE = re.compile(r"[㐀-䶿一-鿿豈-﫿]")
HIRAGANA_ONLY_RE = re.compile(r"^[ぁ-ゖゝ-ゟー]+$")
HIRAGANA_CHAR_RE = re.compile(r"[ぁ-ゖ]")
KATAKANA_RUN_RE = re.compile(r"[ァ-ヺヽヾ]{1,}ー?[ァ-ヺー]*")
ALLOWED_JAPANESE_RE = re.compile(
    r"^[ぁ-ゖ゛-ゞ"      # hiragana + kana marks
    r"ァ-ヺーヽヾ"   # katakana + chōonpu
    r"々"                            # 々 iteration mark
    r"㐀-䶿一-鿿豈-﫿"  # kanji
    r"、。？！]+$"       # 、。？！ only
)
INTERNAL_TERMINATOR_RE = re.compile(r"[。？！](?=.)")

# MARK: - Katakana allowlist
#
# Tatoeba's Japanese half is saturated with placeholder people and places
# (トム appears in 201 of the 2 799 candidate pairs, メアリー in 27, plus every
# country on the map). Rather than blocklist names — an endless game — the
# funnel *allowlists* the katakana a beginner actually needs: concrete everyday
# nouns, hand-reviewed from the katakana runs present in the candidate set.
# Anything else (a name, a country, a unit, キロメートル) drops the sentence.
# Deliberately excluded: alcohol and tobacco (ビール, ワイン, アルコール,
# タバコ) and coarse register (バカ, ケチ, ナンパ).
KATAKANA_ALLOWLIST = frozenset({
    "アイスクリーム", "エレベーター", "オフィス", "カード", "カメラ", "ガラス",
    "ギター", "キッチン", "クラス", "ケーキ", "ゲーム", "コート", "コーヒー",
    "コップ", "コピー", "コンサート", "サッカー", "シャツ", "シャワー", "ジュース",
    "スカート", "スキー", "スープ", "スーパー", "ズボン", "セーター", "タクシー",
    "チケット", "チョコレート", "テーブル", "テスト", "テニス", "テレビ", "ドア",
    "ドレス", "ナイフ", "ニュース", "ネクタイ", "ノート", "パーティー", "パスポート",
    "パソコン", "パン", "バス", "バッグ", "ピアノ", "フォーク", "プレゼント",
    "ページ", "ベッド", "ペン", "ボール", "ボールペン", "ホテル", "ポケット",
    "マスク", "ミルク", "メール", "メガネ", "メニュー", "ランチ", "レストラン",
    "レモン", "ゴルフ", "デザート",
})

# MARK: - Register and topic blocklists
#
# The 90-kanji floor already removes most unsuitable vocabulary (it is written
# with kanji this bundle does not teach). What survives is kana-written: coarse
# male register, prohibitive imperatives, and a handful of adult topics.
REGISTER_PATTERNS = [
    re.compile(r"[るくぐすつぬぶむう]な[。！]?$"),  # 〜な (prohibitive)
    re.compile(r"[ぞぜ][。！]?$"),      # 〜ぞ / 〜ぜ
    re.compile(r"じゃねぇ|てめぇ|やがっ|くそ|"
               r"ちくしょう|ばかやろ"),  # じゃねぇ, てめぇ, 〜やがっ, くそ…
    re.compile(r"ろ[。！]?$"),          # 〜しろ / 見ろ (plain imperative)
    re.compile(r"くれ[。！]?$"),        # 〜てくれ (blunt imperative "give/do for me")
]
TOPIC_BLOCKLIST_JA = re.compile(
    r"死|殺|戦争|酒|酔|ビール|ワイン|"
    r"アルコール|タバコ|セックス|裸|"
    r"銀行強盗|泥棒|血|バカ|ケチ|ナンパ"
)
TOPIC_BLOCKLIST_FR = re.compile(
    r"\b(merde|putain|bordel|conne?s?|cul|sexe|bais|salope|tuer?|tué|mort[se]?|meurt|"
    r"suicid\w*|ivre|bourré\w*|saoul\w*|bière|vin|alcool|cigarette|clope|drogue|nu[e]?s?)\b",
    re.IGNORECASE,
)

# MARK: - Grammar markers
#
# Approximate on purpose: these are surface regexes, not a parse. 「と」 counts
# the particle and the quotative alike, and a marker can fire inside a word.
# They measure whether the corpus *exercises* each taught point, nothing finer.
GRAMMAR_MARKERS = {
    1: r"は",
    2: r"です|ます|でした|ました",
    3: r"を",
    4: r"に",
    5: r"で",
    6: r"が",
    7: r"も",
    8: r"の",
    9: r"と",
    10: r"か[。？]?$",
    11: r"から|まで",
    12: r"[よね][。！？]?$",
    13: r"ない|なかっ|なく",
    14: r"ません|ではありません|じゃありません",
    15: r"ました|でした",
    16: r"[っんいきしちにびみりげ][てで]|"
        r"べて|てください",
    17: r"ている|ています|てる|でいる",
    18: r"たい[で。！？]|たくない|たかっ",
    19: r"てもいい|でもいい",
    20: r"てはいけ|ではいけ",
    21: r"なければ|なくては|なきゃ",
    22: r"ましょう",
    23: r"ことがあり|ことがある",
    24: r"つもり",
    25: r"あげる|もらっ|もらい|くれ",
    26: r"方",
    27: r"すぎ",
    28: r"ながら",
    29: r"この|その|あの|どの",
    30: r"ここ|そこ|あそこ|どこ",
    31: r"けど|が、",
}

VERB_ENDINGS = "うくぐすつぬぶむる"


class BuildError(RuntimeError):
    """Raised for any condition that must abort the run."""


# MARK: - Loading


def load_sentences(path: Path) -> dict[int, str]:
    if not path.exists():
        raise BuildError(f"missing export: {path}")
    out: dict[int, str] = {}
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 3:
                continue
            out[int(parts[0])] = parts[2]
    if not out:
        raise BuildError(f"{path.name}: no rows parsed")
    return out


def load_links(path: Path, jpn: dict[int, str], fra: dict[int, str]) -> list[tuple[int, int]]:
    if not path.exists():
        raise BuildError(f"missing export: {path}")
    links: list[tuple[int, int]] = []
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            parts = line.split()
            if len(parts) != 2:
                continue
            left, right = int(parts[0]), int(parts[1])
            if left in jpn and right in fra:
                links.append((left, right))
    if not links:
        raise BuildError(f"{path.name}: no jpn↔fra pair resolved against the exports")
    return links


def load_bundle(db_path: Path) -> tuple[set[str], list[tuple[int, str, str]], set[str]]:
    if not db_path.exists():
        raise BuildError(f"content bundle not found: {db_path}")
    conn = sqlite3.connect(db_path)
    try:
        kanji = {row[0] for row in conn.execute("SELECT character FROM kanji")}
        vocab = [
            (row[0], row[1], row[2] or "")
            for row in conn.execute("SELECT id, word, reading FROM vocabulary ORDER BY id")
        ]
        # "Already bundled" must mean Ikeru's own 96, not a previous run of this
        # very script: the bundle normally already holds the last generation's
        # imported rows (`source = 'tatoeba'`) by the time this runs again.
        # Counting those as "existing" would make stage 6 reject the whole
        # corpus it is regenerating, rather than only the hand-written ones.
        # `source` may not exist yet on a bundle fresh out of
        # generate_content_bundles.py — in that case every row is Ikeru's.
        columns = {row[1] for row in conn.execute("PRAGMA table_info(sentences)")}
        if "source" in columns:
            existing = {
                row[0] for row in conn.execute(
                    "SELECT japanese FROM sentences WHERE source IS NULL OR source <> 'tatoeba'"
                )
            }
        else:
            existing = {row[0] for row in conn.execute("SELECT japanese FROM sentences")}
    finally:
        conn.close()
    if not kanji or not vocab:
        raise BuildError("content bundle has no kanji or no vocabulary — wrong file?")
    return kanji, vocab, existing


def load_blocklist(path: Path) -> dict[int, str]:
    """Per-ja_id rejections that no structural filter can express.

    See ``blocklist.json`` for the reasons. ``sentences.json`` stays fully
    generated — this is the one hand-maintained input to the funnel, and it
    exists precisely so a rejection like "this French mistranslates that
    Japanese" never has to be hand-patched into the generated output instead.
    """
    if not path.exists():
        raise BuildError(f"missing blocklist: {path}")
    with path.open(encoding="utf-8") as handle:
        data = json.load(handle)
    return {int(key): reason for key, reason in data.items() if key != "_comment"}


# MARK: - Tokenisation


def tokenise(texts: dict[int, str]) -> dict[int, list[str]]:
    """Segment every text with Apple's NLTokenizer via the Swift helper."""
    if shutil.which("swiftc") is None:
        raise BuildError("swiftc not found — the Japanese segmenter needs the Swift toolchain")
    with tempfile.TemporaryDirectory() as tmp:
        binary = Path(tmp) / "tokenize-japanese"
        build = subprocess.run(
            ["swiftc", "-O", "-o", str(binary), str(TOKENIZER_SOURCE)],
            capture_output=True, text=True,
        )
        if build.returncode != 0:
            raise BuildError(f"could not build the segmenter:\n{build.stderr}")
        payload = "".join(f"{ident}\t{text}\n" for ident, text in texts.items())
        run = subprocess.run([str(binary)], input=payload, capture_output=True, text=True)
        if run.returncode != 0:
            raise BuildError(f"segmenter failed:\n{run.stderr}")

    tokens: dict[int, list[str]] = {}
    for line in run.stdout.splitlines():
        ident, _, joined = line.partition("\t")
        tokens[int(ident)] = joined.split(" ") if joined else []
    missing = set(texts) - set(tokens)
    if missing:
        raise BuildError(f"segmenter returned nothing for {len(missing)} sentence(s)")
    return tokens


# MARK: - Known-lexicon model


def build_known_lexicon(
    vocab: list[tuple[int, str, str]]
) -> tuple[set[str], set[str], dict[str, set[str]]]:
    """Return ``(exact_forms, all_stems, stems_by_word)`` for the bundle's words.

    Stems exist because NLTokenizer segments inflections off the stem
    (行きます → 行き + ます), so an exact-form match alone would call every
    conjugated bundle verb "unknown".

    Two rules keep this from turning into a substring free-for-all, both
    learned from false matches in an earlier revision:

    - A word's *reading* is only a matchable form when the word is written in
      kana already (ある, いい). For a kanji word the reading practically never
      surfaces as its own token, while the kana string collides constantly —
      歩く's reading あるく made every ある in the corpus look like "to walk".
    - A stem must contain a kanji. Kana stems are too short to be a word: 重い →
      おも matched おもしろい, 長い → なが matched ながら.
    - A stem must be at least two characters. Any two-character word ending in
      a VERB_ENDINGS/い character reduces to a *one-kanji* stem, and a single
      kanji is not a word boundary — it is a radical shared by every compound
      built on it. 五つ (いつつ, "five [things]") stemmed to bare 五, which then
      matched every unrelated 五-compound: the sentence for 五時 ("5 o'clock")
      got filed under 五つ, and 五つ/四つ/二つ ended up **entirely** wrong
      (verified 2026-08-15 against the pre-fix bundle: 100% of their examples
      were composed of the wrong word). The same one-kanji-stem bug hit verbs:
      見る → 見 matched 見せて ("to show"), 出る → 出 matched 出来ます ("to be
      able to"), 入る → 入 matched 入れましょう ("to make [coffee]"), 聞く → 聞
      matched 聞こえる ("to be audible"). Requiring `len(stem) >= 2` drops stem
      matching for every two-character bundle word (聞く, 見る, 出る, 入る, 行く,
      来る, 買う, …) — their conjugated forms (聞きます, 見ています…) stop
      matching via the stem rule and can still match via `vocabulary_in`'s
      token-boundary rule (rule 1), just not via a bare stem prefix. That is a
      real cost in coverage, accepted because the stem rule was producing wrong
      answers, not merely missing ones.
    """
    exact: set[str] = set()
    all_stems: set[str] = set()
    by_word: dict[str, set[str]] = {}
    for _, word, reading in vocab:
        exact.add(word)
        if reading and reading == word:
            exact.add(reading)
        stems: set[str] = set()
        if len(word) >= 2 and (word[-1] == "い" or word[-1] in VERB_ENDINGS):
            stem = word[:-1]
            if len(stem) >= 2 and KANJI_RE.search(stem):
                stems.add(stem)
        by_word[word] = stems
        all_stems |= stems
    return exact, all_stems, by_word


def token_spans(tokens: list[str], text: str) -> set[tuple[int, int]]:
    """Character offsets where the tokenizer put a boundary, as (start, end).

    NLTokenizer drops punctuation, so the token stream is not a partition of
    the text; walking `text` with `find` keeps the offsets honest.
    """
    starts: list[int] = []
    ends: list[int] = []
    cursor = 0
    for token in tokens:
        index = text.find(token, cursor)
        if index < 0:
            continue
        starts.append(index)
        ends.append(index + len(token))
        cursor = index + len(token)
    return {(s, e) for s in starts for e in ends if e > s}


def build_glue(doc_freq: collections.Counter, corpus_size: int) -> set[str]:
    """Hiragana-only tokens frequent enough to be grammatical glue, not lexicon.

    Particles, copula forms and inflection fragments (なけれ, ませ, ん, っ…) are
    a closed class, and a closed class is exactly what shows up at the top of a
    250 000-sentence frequency table. Taking the threshold from the data avoids
    hand-maintaining a list of Japanese function morphemes in a Python file.
    """
    floor = corpus_size * GLUE_DOC_FREQ_RATIO
    return {
        token for token, count in doc_freq.items()
        if count >= floor and HIRAGANA_ONLY_RE.match(token)
    }


# Function words that the data-driven glue set cannot see, because it only
# considers hiragana-only tokens and these are written with a kanji.
KANJI_GLUE = frozenset({"下さい", "御", "様"})


def unknown_tokens(
    tokens: list[str], exact: set[str], stems: set[str], glue: set[str]
) -> list[str]:
    """Tokens a learner of this bundle would not recognise.

    Known = grammatical glue, a bundle word (or its stem), or a loanword from
    the hand-reviewed katakana allowlist. The allowlist counts as known because
    it was reviewed for exactly this question; leaving it out made the
    frequency gate below reject 「外のテーブルがいいのですが。」 for テーブル.
    """
    unknown: list[str] = []
    for token in tokens:
        if token in glue or token in exact or token in KANJI_GLUE:
            continue
        if token in KATAKANA_ALLOWLIST:
            continue
        if any(token.startswith(stem) for stem in stems):
            continue
        unknown.append(token)
    return unknown


def vocabulary_in(
    japanese: str,
    tokens: list[str],
    vocab: list[tuple[int, str, str]],
    word_stems: dict[str, set[str]],
) -> list[str]:
    """Every bundle word this sentence genuinely uses, in vocabulary order.

    A word matches when either

    1. it occurs in the sentence *between two tokenizer boundaries* — a plain
       substring test files 分かりません under 分 ("minute"), while the
       boundaries (分かり | ませ | ん) reject it and still accept 一つ, which
       the tokenizer splits into 一 + つ; or
    2. a token starts with the word's kanji stem, which is how conjugations
       (行きます, 読めない, 食べています) reach their dictionary form.

    Known imprecision: rule 2 accepts a different verb sharing the stem kanji —
    見せて counts for 見る. Rule 1's boundaries make that rare enough to accept
    rather than paper over.
    """
    spans = token_spans(tokens, japanese)
    found: list[str] = []
    for _, word, _ in vocab:
        if not word:
            continue
        start = japanese.find(word)
        aligned = False
        while start >= 0:
            if (start, start + len(word)) in spans:
                aligned = True
                break
            start = japanese.find(word, start + 1)
        if aligned:
            found.append(word)
            continue
        stems = word_stems.get(word, set())
        if stems and any(token.startswith(stem) for token in tokens for stem in stems):
            found.append(word)
    return found


# MARK: - French handling


def normalise_french(text: str) -> str:
    """The only edits made to a contributor's French, both purely typographic.

    1. Curly apostrophe → straight, matching the 96 sentences already bundled.
    2. A plain space before ? ! ; : (French spacing), collapsing the
       non-breaking and narrow-no-break variants Tatoeba mixes.
    No word is added, removed or reordered.
    """
    text = text.replace("’", "'")
    text = re.sub(r"[    ]*([?!;:])", r" \1", text)
    return re.sub(r"\s+", " ", text).strip()


def french_is_usable(text: str) -> bool:
    if len(text) < 4 or len(text) > 90:
        return False
    if not text[0].isupper():
        return False
    if text[-1] not in ".!?…":
        return False
    if re.search(r"[0-9<>\[\]{}|/\\*_#@~^]", text):
        return False
    if "«" in text or "»" in text or '"' in text:
        return False
    if "(" in text or ")" in text:
        return False
    return True


# MARK: - Japanese handling


def japanese_is_usable(japanese: str, kanji: set[str]) -> str | None:
    """Return a rejection reason, or ``None`` when the sentence passes."""
    if not ALLOWED_JAPANESE_RE.match(japanese):
        return "script"          # latin letters, digits, 「」, 〜, …
    if INTERNAL_TERMINATOR_RE.search(japanese):
        return "multi_sentence"
    if len(HIRAGANA_CHAR_RE.findall(japanese)) < 2:
        # A Japanese *sentence* needs grammatical kana. Without them Tatoeba
        # hands back enumerations like 「一、二、三、四、五。」 — true, but not
        # something a learner can be asked to read, shadow or rebuild.
        return "not_a_sentence"
    if any(char not in kanji for char in KANJI_RE.findall(japanese)):
        return "kanji"
    length = len(japanese)
    if length < MIN_CHARS or length > MAX_CHARS:
        return "length"
    for run in KATAKANA_RUN_RE.findall(japanese):
        if run.strip("ー") and run not in KATAKANA_ALLOWLIST:
            return "katakana"
    if TOPIC_BLOCKLIST_JA.search(japanese):
        return "topic"
    if any(pattern.search(japanese) for pattern in REGISTER_PATTERNS):
        return "register"
    return None


POLITE_RE = re.compile(
    r"です|ます|ました|ません|でした|"
    r"ください|ましょう"
)


# MARK: - Funnel


def run(exports: Path, db_path: Path, verbose: bool,
        max_unknown: int = MAX_UNKNOWN_TOKENS) -> dict:
    jpn = load_sentences(exports / "jpn_sentences.tsv")
    fra = load_sentences(exports / "fra_sentences.tsv")
    links = load_links(exports / "jpn-fra_links.tsv", jpn, fra)
    kanji, vocab, existing_japanese = load_bundle(db_path)
    blocklist = load_blocklist(BLOCKLIST_PATH)

    funnel: list[tuple[str, int, int]] = []   # (stage, kept pairs, dropped pairs)

    def record(stage: str, kept: int, dropped: int) -> None:
        funnel.append((stage, kept, dropped))
        if verbose:
            print(f"  {stage:<28}{kept:>7} kept  {dropped:>7} dropped", file=sys.stderr)

    record("0. jpn↔fra pairs", len(links), 0)

    # -- Stage 0b: hand-reviewed rejections that no structural filter below can
    # express (an ungrammatical sentence, a mistranslated pairing). See
    # blocklist.json for the reason behind each ja_id.
    blocked = sum(1 for ja_id, _ in links if ja_id in blocklist)
    links = [(ja_id, fr_id) for ja_id, fr_id in links if ja_id not in blocklist]
    record("0b. blocklist", len(links), blocked)

    # -- Stage 1..5: per-sentence Japanese filters, counted separately.
    reasons = collections.Counter()
    survivors: list[tuple[int, int]] = []
    for ja_id, fr_id in links:
        reason = japanese_is_usable(jpn[ja_id], kanji)
        if reason:
            reasons[reason] += 1
        else:
            survivors.append((ja_id, fr_id))
    before = len(links)
    for stage in ("script", "multi_sentence", "not_a_sentence", "kanji", "length",
                  "katakana", "topic", "register"):
        dropped = reasons[stage]
        before -= dropped
        record(f"1.{stage}", before, dropped)

    # -- Stage 6: French usable + normalised.
    with_french: list[tuple[int, int, str]] = []
    dropped = 0
    for ja_id, fr_id in survivors:
        french = normalise_french(fra[fr_id])
        if french_is_usable(french) and not TOPIC_BLOCKLIST_FR.search(french):
            with_french.append((ja_id, fr_id, french))
        else:
            dropped += 1
    record("2. french quality", len(with_french), dropped)

    # -- Stage 7: lexical difficulty (needs the segmenter).
    texts = {ja_id: jpn[ja_id] for ja_id, _, _ in with_french}
    if verbose:
        print(f"  segmenting {len(texts)} candidates + reference corpus…", file=sys.stderr)
    reference_tokens = tokenise(jpn)
    doc_freq: collections.Counter = collections.Counter()
    for token_list in reference_tokens.values():
        doc_freq.update(set(token_list))
    glue = build_glue(doc_freq, len(reference_tokens))
    exact, stems, stems_by_word = build_known_lexicon(vocab)
    if verbose:
        print(f"  glue types: {len(glue)}   exact forms: {len(exact)}   stems: {len(stems)}",
              file=sys.stderr)

    # How many unknowns each candidate carries, BEFORE the cut. Reported so the
    # threshold can be re-justified against the bundle of the day instead of
    # inherited — the 206-word rationale below `MAX_UNKNOWN_TOKENS` outlived the
    # bundle it was measured on by 487 words.
    unknown_histogram: collections.Counter = collections.Counter()

    lexical: list[dict] = []
    dropped = 0
    for ja_id, fr_id, french in with_french:
        unknown = unknown_tokens(reference_tokens[ja_id], exact, stems, glue)
        unknown_histogram[len(unknown)] += 1
        if len(unknown) > max_unknown:
            dropped += 1
            continue
        if any(doc_freq[token] < MIN_UNKNOWN_DOC_FREQ for token in unknown):
            dropped += 1
            continue
        content = (
            tuple(sorted(t for t in reference_tokens[ja_id] if t not in glue)),
            jpn[ja_id][-4:],
        )
        lexical.append({
            "ja_id": ja_id, "fr_id": fr_id, "japanese": jpn[ja_id],
            "french": french, "unknown": unknown,
            "tokens": reference_tokens[ja_id], "content_key": content,
        })
    record("3. lexical i+1", len(lexical), dropped)

    # -- Stage 8: must use at least one bundle vocabulary word.
    anchored: list[dict] = []
    dropped = 0
    for row in lexical:
        words = vocabulary_in(row["japanese"], row["tokens"], vocab, stems_by_word)
        if not words:
            dropped += 1
            continue
        anchored.append({**row, "words": words})
    record("4. vocabulary anchor", len(anchored), dropped)

    # -- Stage 9a: one French per Japanese, and no clash with the bundled 96.
    by_japanese: dict[str, list[dict]] = collections.defaultdict(list)
    for row in anchored:
        by_japanese[row["japanese"]].append(row)
    deduped: list[dict] = []
    dropped_dup = 0
    dropped_existing = 0
    for japanese, rows in by_japanese.items():
        if japanese in existing_japanese:
            dropped_existing += len(rows)
            continue
        rows.sort(key=lambda row: row["fr_id"])   # oldest translation wins
        deduped.append(rows[0])
        dropped_dup += len(rows) - 1
    record("5. one french per japanese", len(deduped) + dropped_existing, dropped_dup)
    record("6. not already bundled", len(deduped), dropped_existing)

    def quality(row: dict) -> tuple:
        return (
            0 if POLITE_RE.search(row["japanese"]) else 1,  # polite register first
            len(row["unknown"]),                            # then fewest unknowns
            len(row["japanese"]),                           # then shortest
            row["ja_id"],                                   # then deterministic
        )

    # -- Stage 9b: collapse near-duplicates. あの本は小さい。 and その本は小さい。
    # reduce to the same bag of non-grammatical tokens — they drill the same
    # item, and a learner meeting both twice in a session learns nothing extra.
    # The key carries the last four characters as well, so 読みます / 読みました
    # / 読みません survive as the distinct conjugation lessons they are.
    by_content: dict[tuple, list[dict]] = collections.defaultdict(list)
    for row in deduped:
        by_content[row["content_key"]].append(row)
    distinct: list[dict] = []
    dropped = 0
    for rows in by_content.values():
        rows.sort(key=quality)
        distinct.append(rows[0])
        dropped += len(rows) - 1
    record("7. near-duplicate collapse", len(distinct), dropped)

    # -- Stage 10: file each sentence under one word, rarest word first.
    #
    # The schema allows a single `vocabulary_word` per row and the query shape
    # is "examples for word W" (`ContentRepository.fetchSentences`), so the
    # assignment decides which words actually gain examples. Serving the
    # scarcest words first turns the same pool into far wider coverage than
    # "longest match wins" — and the cap keeps any one word from flooding
    # whichever reader eventually renders this list (see MAX_PER_VOCAB_WORD).
    candidates: dict[str, list[dict]] = collections.defaultdict(list)
    for row in distinct:
        for word in row["words"]:
            candidates[word].append(row)
    assigned: dict[int, str] = {}
    counts: collections.Counter = collections.Counter()
    for _ in range(MAX_PER_VOCAB_WORD):
        order = sorted(candidates, key=lambda w: (counts[w], len(candidates[w]), w))
        for word in order:
            if counts[word] >= MAX_PER_VOCAB_WORD:
                continue
            free = sorted(
                (row for row in candidates[word] if row["ja_id"] not in assigned),
                key=quality,
            )
            if not free:
                continue
            assigned[free[0]["ja_id"]] = word
            counts[word] += 1
    # Mop-up: the rounds above spread examples as widely as possible, which can
    # leave a good sentence unfiled because every word it *led* with was served
    # first. File each leftover under its least-loaded word that is still under
    # the cap, so nothing usable is thrown away for a scheduling artefact.
    for row in sorted(distinct, key=quality):
        if row["ja_id"] in assigned:
            continue
        options = [w for w in row["words"] if counts[w] < MAX_PER_VOCAB_WORD]
        if not options:
            continue
        word = min(options, key=lambda w: (counts[w], w))
        assigned[row["ja_id"]] = word
        counts[word] += 1
    selected = [
        {**row, "vocabulary_word": assigned[row["ja_id"]]}
        for row in distinct if row["ja_id"] in assigned
    ]
    record("8. cap per vocabulary word", len(selected), len(distinct) - len(selected))

    # -- Stage 9: drop rows that repeat another sentence's French under the
    # same vocabulary word. Stage 7 dedupes the Japanese and its token bag,
    # but never the French gloss — Tatoeba links several distinct Japanese
    # sentences to the same translation often enough that, once filed under
    # one word, they read as the same example card copy-pasted three times
    # (新聞 had 「日本語の新聞はありますか。」 glossed identically thrice). This
    # runs after the cap, so a dropped duplicate's slot is not backfilled —
    # a smaller, distinct-per-card corpus, not a bigger one.
    by_word_french: dict[tuple[str, str], list[dict]] = collections.defaultdict(list)
    for row in selected:
        by_word_french[(row["vocabulary_word"], row["french"])].append(row)
    deduped_selected: list[dict] = []
    dropped = 0
    for rows in by_word_french.values():
        rows.sort(key=quality)
        deduped_selected.append(rows[0])
        dropped += len(rows) - 1
    record("9. french dedup per word", len(deduped_selected), dropped)
    selected = deduped_selected

    selected.sort(key=lambda row: row["ja_id"])

    # -- Coverage.
    covered_words = {row["vocabulary_word"] for row in selected}
    contained_words = {word for row in selected for word in row["words"]}
    grammar_hits = {
        point: sum(1 for row in selected if re.search(pattern, row["japanese"]))
        for point, pattern in GRAMMAR_MARKERS.items()
    }

    return {
        "funnel": funnel,
        "selected": selected,
        "vocab_total": len(vocab),
        "vocab_anchored": len(covered_words),
        "vocab_contained": len(contained_words),
        "vocab_missing": sorted({w for _, w, _ in vocab} - contained_words),
        "grammar_hits": grammar_hits,
        "polite_share": sum(1 for row in selected if POLITE_RE.search(row["japanese"])),
        "unknown_histogram": unknown_histogram,
        "max_unknown": max_unknown,
        "known_words": len(vocab),
    }


# MARK: - Entry point


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--exports", type=Path, required=True,
                        help="directory holding the three decompressed Tatoeba TSV exports")
    parser.add_argument("--db", type=Path, default=DEFAULT_DB, help="content bundle to read")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help="JSON artefact to write")
    parser.add_argument("--verbose", action="store_true", help="print the funnel to stderr")
    parser.add_argument("--max-unknown", type=int, default=MAX_UNKNOWN_TOKENS,
                        help="lexical i+1 tolerance; see MAX_UNKNOWN_TOKENS. Exposed so the "
                             "threshold can be re-measured against the bundle of the day "
                             "rather than inherited from the one it was chosen on")
    parser.add_argument("--dry-run", action="store_true",
                        help="report the funnel without writing --out (for threshold sweeps)")
    args = parser.parse_args(argv)

    try:
        result = run(args.exports, args.db, args.verbose, args.max_unknown)
    except BuildError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    selected = result["selected"]
    if not selected:
        print("error: the funnel retained nothing — refusing to write an empty corpus",
              file=sys.stderr)
        return 1

    payload = {
        "source": "Tatoeba (https://tatoeba.org) — sentence text under CC BY 2.0 FR",
        "generated_by": "scripts/tatoeba/build-corpus.py",
        "count": len(selected),
        "sentences": [
            {
                "japanese": row["japanese"],
                "french": row["french"],
                "vocabulary_word": row["vocabulary_word"],
                "tatoeba_ja_id": row["ja_id"],
                "tatoeba_fr_id": row["fr_id"],
            }
            for row in selected
        ],
    }
    if not args.dry_run:
        args.out.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )

    print(f"{'stage':<32}{'kept':>8}{'dropped':>10}")
    for stage, kept, dropped in result["funnel"]:
        print(f"{stage:<32}{kept:>8}{dropped:>10}")
    print()
    print(f"retained: {len(selected)} sentences  "
          f"({result['polite_share']} in です/ます register)")
    print(f"vocabulary: {result['vocab_anchored']}/{result['vocab_total']} words filed under, "
          f"{result['vocab_contained']}/{result['vocab_total']} appear anywhere")
    missing_grammar = [point for point, hits in result["grammar_hits"].items() if hits == 0]
    print(f"grammar: {31 - len(missing_grammar)}/31 points exercised "
          f"(missing: {missing_grammar or 'none'})")

    # The distribution the cut hides. Printed every run so the next person to
    # touch `MAX_UNKNOWN_TOKENS` sees what each value costs instead of guessing.
    histogram = result["unknown_histogram"]
    total = sum(histogram.values())
    print(f"\nunknown tokens per candidate (bundle: {result['known_words']} words, "
          f"cut at {result['max_unknown']}):")
    running = 0
    for count in sorted(histogram):
        running += histogram[count]
        marker = "  <- cut here" if count == result["max_unknown"] else ""
        print(f"  {count:>2} unknown  {histogram[count]:>6}  "
              f"(cumulative {running:>6} / {total}){marker}")

    if args.dry_run:
        print("\n(dry run — nothing written)")
    else:
        print(f"wrote {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
