#!/usr/bin/env python3
"""
Generate SQLite content bundles for the Ikeru Japanese learning app.

Data Sources:
- Kanji readings and meanings: DERIVED FROM KANJIDIC (EDRDG, CC BY-SA 4.0).
  This header used to say "original compositions", and that was false. Measured
  2026-08-15: all 63 dotted kun readings below are byte-identical to KANJIDIC's
  okurigana convention, and the on-readings reproduce its ordering in 89 of 90
  kanji. The entries here are a hand-trimmed SUBSET of KANJIDIC (its affix-
  marked forms such as `ひと-` were dropped), which is a curation of KANJIDIC,
  not an independent authoring of it. Credited in AttributionView. CC BY-SA is
  share-alike — do not restore the "original compositions" wording.
- Radical decompositions: Ikeru's own, NOT RADKFILE. Same measurement: only 36
  of 90 match RADKFILE, with systematic divergence (八/九 here vs RADKFILE's
  ハ-shaped radicals). Do not credit RADKFILE without re-running that diff.
- JLPT N5 kanji list (factual list, not copyrightable)
- Vocabulary: the English glosses are Ikeru's own, all 693 of them. The WORDS
  come from two lists — Ikeru's original hand-picked 205, and 488 more selected
  from the Tanos JLPT N5 list (Jonathan Waller, CC BY, credited in
  AttributionView). Only the word and its reading were taken from Tanos; its
  English gloss column was deliberately not imported, because the site states
  no provenance for it. See scripts/tanos/build-vocab-list.py. The per-row
  marker is `vocabulary.list_source`, so the claim above is checkable by query
  rather than by trust. Entries live in scripts/content/vocabulary.json.
- The 96 original example sentences (original compositions). A further 317
  sentences come from Tatoeba and are applied separately by
  scripts/apply-tatoeba-sentences.py — they are not generated here.

Usage:
    python3 scripts/generate_content_bundles.py
    python3 scripts/generate_content_bundles.py --level n5
    python3 scripts/generate_content_bundles.py --output-dir ./out
"""

import argparse
import json
import os
import sqlite3
from pathlib import Path
from typing import NamedTuple

REPO_ROOT = Path(__file__).resolve().parent.parent
VOCABULARY_JSON = REPO_ROOT / "scripts" / "content" / "vocabulary.json"


# ---------------------------------------------------------------------------
# Data structures
# ---------------------------------------------------------------------------

class KanjiEntry(NamedTuple):
    character: str
    radical_chars: list[str]
    on_readings: list[str]
    kun_readings: list[str]
    meanings: list[str]
    stroke_count: int


class RadicalEntry(NamedTuple):
    character: str
    meaning: str
    stroke_count: int


class VocabEntry(NamedTuple):
    word: str
    reading: str
    meaning: str
    kanji_character: str | None
    jlpt_level: str
    list_source: str


class SentenceEntry(NamedTuple):
    japanese: str
    english: str
    vocabulary_word: str


class GrammarEntry(NamedTuple):
    jlpt_level: str
    title: str
    explanation: str
    examples: list[str]


# ---------------------------------------------------------------------------
# Schema
# ---------------------------------------------------------------------------

SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS kanji (
    character TEXT PRIMARY KEY,
    on_readings TEXT,
    kun_readings TEXT,
    meanings TEXT,
    jlpt_level TEXT,
    stroke_count INTEGER,
    stroke_order_svg TEXT
);
CREATE TABLE IF NOT EXISTS radicals (
    character TEXT PRIMARY KEY,
    meaning TEXT,
    stroke_count INTEGER
);
CREATE TABLE IF NOT EXISTS kana (
    character TEXT PRIMARY KEY,
    stroke_count INTEGER,
    stroke_order_svg TEXT
);
CREATE TABLE IF NOT EXISTS kanji_radical_edges (
    radical_character TEXT,
    kanji_character TEXT,
    PRIMARY KEY (radical_character, kanji_character)
);
CREATE TABLE IF NOT EXISTS vocabulary (
    id INTEGER PRIMARY KEY,
    word TEXT,
    reading TEXT,
    meaning TEXT,
    kanji_character TEXT,
    jlpt_level TEXT,
    -- Which list the word was selected FROM — not who wrote the gloss.
    -- Every `meaning` in this table is Ikeru's own text; `list_source` says
    -- whether the word itself was on Ikeru's original hand-picked list
    -- ('ikeru') or came from the Tanos JLPT N5 list ('tanos', CC BY, credited
    -- in AttributionView). Without this column the attribution is a claim in
    -- a README that nothing can check; with it, one query answers it.
    list_source TEXT
);
CREATE TABLE IF NOT EXISTS sentences (
    id INTEGER PRIMARY KEY,
    japanese TEXT,
    english TEXT,
    vocabulary_word TEXT
);
CREATE TABLE IF NOT EXISTS grammar_points (
    id INTEGER PRIMARY KEY,
    jlpt_level TEXT,
    title TEXT,
    explanation TEXT,
    examples TEXT
);
"""


# ---------------------------------------------------------------------------
# N5 Radicals (used by N5 kanji)
# ---------------------------------------------------------------------------

def n5_radicals() -> list[RadicalEntry]:
    return [
        RadicalEntry("一", "one", 1),
        RadicalEntry("丨", "line", 1),
        RadicalEntry("丶", "dot", 1),
        RadicalEntry("ノ", "slash", 1),
        RadicalEntry("乙", "second", 1),
        RadicalEntry("亅", "hook", 1),
        RadicalEntry("二", "two", 2),
        RadicalEntry("亠", "lid", 2),
        RadicalEntry("人", "person", 2),
        RadicalEntry("儿", "legs", 2),
        RadicalEntry("入", "enter", 2),
        RadicalEntry("八", "eight", 2),
        RadicalEntry("冂", "inverted box", 2),
        RadicalEntry("冖", "cover", 2),
        RadicalEntry("刀", "sword", 2),
        RadicalEntry("力", "power", 2),
        RadicalEntry("十", "ten", 2),
        RadicalEntry("又", "again", 2),
        RadicalEntry("口", "mouth", 3),
        RadicalEntry("囗", "enclosure", 3),
        RadicalEntry("土", "earth", 3),
        RadicalEntry("夂", "go slowly", 3),
        RadicalEntry("大", "big", 3),
        RadicalEntry("女", "woman", 3),
        RadicalEntry("子", "child", 3),
        RadicalEntry("宀", "roof", 3),
        RadicalEntry("寸", "inch", 3),
        RadicalEntry("小", "small", 3),
        RadicalEntry("山", "mountain", 3),
        RadicalEntry("川", "river", 3),
        RadicalEntry("工", "craft", 3),
        RadicalEntry("巾", "cloth", 3),
        RadicalEntry("弓", "bow", 3),
        RadicalEntry("彳", "step", 3),
        RadicalEntry("心", "heart", 4),
        RadicalEntry("手", "hand", 4),
        RadicalEntry("文", "script", 4),
        RadicalEntry("日", "sun", 4),
        RadicalEntry("月", "moon", 4),
        RadicalEntry("木", "tree", 4),
        RadicalEntry("止", "stop", 4),
        RadicalEntry("水", "water", 4),
        RadicalEntry("火", "fire", 4),
        RadicalEntry("父", "father", 4),
        RadicalEntry("牛", "cow", 4),
        RadicalEntry("王", "king", 4),
        RadicalEntry("田", "rice field", 5),
        RadicalEntry("目", "eye", 5),
        RadicalEntry("白", "white", 5),
        RadicalEntry("石", "stone", 5),
        RadicalEntry("立", "stand", 5),
        RadicalEntry("糸", "thread", 6),
        RadicalEntry("耳", "ear", 6),
        RadicalEntry("肉", "meat", 6),
        RadicalEntry("自", "self", 6),
        RadicalEntry("虫", "insect", 6),
        RadicalEntry("行", "go", 6),
        RadicalEntry("衣", "clothing", 6),
        RadicalEntry("見", "see", 7),
        RadicalEntry("言", "say", 7),
        RadicalEntry("貝", "shell", 7),
        RadicalEntry("足", "foot", 7),
        RadicalEntry("車", "cart", 7),
        RadicalEntry("金", "gold", 8),
        RadicalEntry("門", "gate", 8),
        RadicalEntry("雨", "rain", 8),
        RadicalEntry("食", "eat", 9),
        # Components used in N5 kanji decompositions
        RadicalEntry("匕", "spoon", 2),
        RadicalEntry("卜", "divination", 2),
        RadicalEntry("母", "mother", 5),
        RadicalEntry("斤", "axe", 4),
        RadicalEntry("欠", "yawn", 4),
        RadicalEntry("艹", "grass", 3),
        RadicalEntry("舌", "tongue", 6),
        RadicalEntry("化", "change", 4),
        RadicalEntry("五", "five", 4),
        RadicalEntry("幺", "tiny", 3),
        RadicalEntry("売", "sell", 7),
        RadicalEntry("者", "person (者)", 8),
    ]


# ---------------------------------------------------------------------------
# N5 Kanji (~80 characters)
# ---------------------------------------------------------------------------

def n5_kanji() -> list[KanjiEntry]:
    return [
        # Numbers
        KanjiEntry("一", ["一"], ["イチ", "イツ"], ["ひと", "ひと.つ"], ["one"], 1),
        KanjiEntry("二", ["二"], ["ニ"], ["ふた", "ふた.つ"], ["two"], 2),
        KanjiEntry("三", ["一"], ["サン"], ["み", "み.つ", "みっ.つ"], ["three"], 3),
        KanjiEntry("四", ["囗", "八", "儿"], ["シ"], ["よ", "よ.つ", "よっ.つ", "よん"], ["four"], 5),
        KanjiEntry("五", ["二", "一"], ["ゴ"], ["いつ", "いつ.つ"], ["five"], 4),
        KanjiEntry("六", ["亠", "八"], ["ロク"], ["む", "む.つ", "むっ.つ"], ["six"], 4),
        KanjiEntry("七", ["一", "乙"], ["シチ"], ["なな", "なな.つ", "なの"], ["seven"], 2),
        KanjiEntry("八", ["八"], ["ハチ"], ["や", "や.つ", "やっ.つ"], ["eight"], 2),
        KanjiEntry("九", ["乙"], ["キュウ", "ク"], ["ここの", "ここの.つ"], ["nine"], 2),
        KanjiEntry("十", ["十"], ["ジュウ", "ジッ"], ["とお", "と"], ["ten"], 2),
        KanjiEntry("百", ["一", "白"], ["ヒャク"], ["もも"], ["hundred"], 6),
        KanjiEntry("千", ["一", "ノ", "十"], ["セン"], ["ち"], ["thousand"], 3),
        KanjiEntry("万", ["一", "ノ"], ["マン", "バン"], ["よろず"], ["ten thousand"], 3),
        KanjiEntry("円", ["冂", "一", "丨"], ["エン"], ["まる"], ["circle", "yen"], 4),

        # Nature
        KanjiEntry("日", ["一", "口"], ["ニチ", "ジツ"], ["ひ", "か"], ["day", "sun"], 4),
        KanjiEntry("月", ["月"], ["ゲツ", "ガツ"], ["つき"], ["month", "moon"], 4),
        KanjiEntry("火", ["火"], ["カ"], ["ひ", "ほ"], ["fire"], 4),
        KanjiEntry("水", ["水"], ["スイ"], ["みず"], ["water"], 4),
        KanjiEntry("木", ["木"], ["モク", "ボク"], ["き", "こ"], ["tree", "wood"], 4),
        KanjiEntry("金", ["人", "一", "王", "土"], ["キン", "コン"], ["かね", "かな"], ["gold", "money"], 8),
        KanjiEntry("土", ["土"], ["ド", "ト"], ["つち"], ["earth", "soil"], 3),
        KanjiEntry("山", ["山"], ["サン"], ["やま"], ["mountain"], 3),
        KanjiEntry("川", ["川"], ["セン"], ["かわ"], ["river"], 3),
        KanjiEntry("天", ["一", "大"], ["テン"], ["あめ", "あま"], ["heaven", "sky"], 4),
        KanjiEntry("気", ["ノ"], ["キ", "ケ"], ["き"], ["spirit", "mind", "air"], 6),
        KanjiEntry("雨", ["雨"], ["ウ"], ["あめ", "あま"], ["rain"], 8),
        KanjiEntry("花", ["人", "化", "艹"], ["カ"], ["はな"], ["flower"], 7),
        KanjiEntry("空", ["宀", "八", "工"], ["クウ"], ["そら", "あ.く", "から"], ["sky", "empty"], 8),

        # People
        KanjiEntry("人", ["人"], ["ジン", "ニン"], ["ひと"], ["person"], 2),
        KanjiEntry("大", ["一", "人"], ["ダイ", "タイ"], ["おお", "おお.きい"], ["big", "large"], 3),
        KanjiEntry("小", ["小"], ["ショウ"], ["ちい.さい", "こ", "お"], ["small", "little"], 3),
        KanjiEntry("子", ["子"], ["シ", "ス"], ["こ"], ["child"], 3),
        KanjiEntry("女", ["女"], ["ジョ", "ニョ"], ["おんな", "め"], ["woman", "female"], 3),
        KanjiEntry("男", ["田", "力"], ["ダン", "ナン"], ["おとこ"], ["man", "male"], 7),
        KanjiEntry("父", ["父"], ["フ"], ["ちち"], ["father"], 4),
        KanjiEntry("母", ["母"], ["ボ"], ["はは"], ["mother"], 5),
        KanjiEntry("友", ["ノ", "又"], ["ユウ"], ["とも"], ["friend"], 4),
        KanjiEntry("手", ["手"], ["シュ"], ["て"], ["hand"], 4),
        KanjiEntry("先", ["儿", "土"], ["セン"], ["さき"], ["previous", "ahead"], 6),
        KanjiEntry("生", ["一", "丨", "土"], ["セイ", "ショウ"], ["い.きる", "う.まれる", "なま", "は.える"], ["life", "birth", "raw"], 5),
        KanjiEntry("名", ["口", "ノ", "夂"], ["メイ", "ミョウ"], ["な"], ["name"], 6),

        # Location / Direction
        KanjiEntry("上", ["一", "丨"], ["ジョウ", "ショウ"], ["うえ", "あ.がる", "のぼ.る"], ["up", "above"], 3),
        KanjiEntry("下", ["一", "丨"], ["カ", "ゲ"], ["した", "さ.がる", "くだ.る"], ["down", "below"], 3),
        KanjiEntry("中", ["口", "丨"], ["チュウ"], ["なか"], ["middle", "inside"], 4),
        KanjiEntry("右", ["口", "ノ"], ["ウ", "ユウ"], ["みぎ"], ["right"], 5),
        KanjiEntry("左", ["工", "ノ"], ["サ"], ["ひだり"], ["left"], 5),
        KanjiEntry("北", ["匕", "一"], ["ホク"], ["きた"], ["north"], 5),
        KanjiEntry("南", ["十", "冂"], ["ナン"], ["みなみ"], ["south"], 9),
        KanjiEntry("東", ["木", "日"], ["トウ"], ["ひがし"], ["east"], 8),
        KanjiEntry("西", ["一", "囗", "儿"], ["セイ", "サイ"], ["にし"], ["west"], 6),
        KanjiEntry("外", ["夂", "卜"], ["ガイ", "ゲ"], ["そと", "ほか", "はず.す"], ["outside"], 5),
        KanjiEntry("国", ["囗", "王"], ["コク"], ["くに"], ["country"], 8),
        KanjiEntry("前", ["一", "月", "刀"], ["ゼン"], ["まえ"], ["before", "front"], 9),
        KanjiEntry("後", ["彳", "幺", "夂"], ["ゴ", "コウ"], ["あと", "うし.ろ", "のち"], ["after", "behind"], 9),

        # School / Learning
        KanjiEntry("学", ["子", "ノ", "冖"], ["ガク"], ["まな.ぶ"], ["study", "learn"], 8),
        KanjiEntry("校", ["木", "父", "亠"], ["コウ"], [], ["school"], 10),
        KanjiEntry("本", ["木", "一"], ["ホン"], ["もと"], ["book", "origin"], 5),
        KanjiEntry("書", ["日", "一", "者"], ["ショ"], ["か.く"], ["write", "book"], 10),
        KanjiEntry("読", ["言", "売"], ["ドク", "トク"], ["よ.む"], ["read"], 14),
        KanjiEntry("話", ["言", "口", "舌"], ["ワ"], ["はな.す", "はなし"], ["talk", "speak"], 13),
        KanjiEntry("語", ["言", "五", "口"], ["ゴ"], ["かた.る"], ["language", "word"], 14),

        # Actions / Verbs
        KanjiEntry("食", ["人", "口", "食"], ["ショク"], ["た.べる", "く.う"], ["eat", "food"], 9),
        KanjiEntry("飲", ["食", "欠"], ["イン"], ["の.む"], ["drink"], 12),
        KanjiEntry("見", ["見"], ["ケン"], ["み.る", "み.える"], ["see", "look"], 7),
        KanjiEntry("聞", ["門", "耳"], ["ブン", "モン"], ["き.く", "き.こえる"], ["hear", "ask", "listen"], 14),
        KanjiEntry("行", ["行"], ["コウ", "ギョウ"], ["い.く", "ゆ.く", "おこな.う"], ["go", "conduct"], 6),
        KanjiEntry("来", ["一", "木"], ["ライ"], ["く.る", "きた.る"], ["come"], 7),
        KanjiEntry("出", ["山", "丨"], ["シュツ"], ["で.る", "だ.す"], ["go out", "exit"], 5),
        KanjiEntry("入", ["入"], ["ニュウ"], ["い.る", "はい.る"], ["enter"], 2),
        KanjiEntry("休", ["人", "木"], ["キュウ"], ["やす.む"], ["rest"], 6),
        KanjiEntry("立", ["立"], ["リツ"], ["た.つ", "た.てる"], ["stand"], 5),
        KanjiEntry("買", ["目", "貝"], ["バイ"], ["か.う"], ["buy"], 12),

        # Time
        KanjiEntry("年", ["一", "丨", "ノ"], ["ネン"], ["とし"], ["year"], 6),
        KanjiEntry("時", ["日", "寸", "土"], ["ジ"], ["とき"], ["time", "hour"], 10),
        KanjiEntry("間", ["門", "日"], ["カン", "ケン"], ["あいだ", "ま"], ["interval", "between"], 12),
        KanjiEntry("分", ["八", "刀"], ["ブン", "フン"], ["わ.かる", "わ.ける"], ["minute", "part", "understand"], 4),
        KanjiEntry("半", ["丨", "二", "十"], ["ハン"], ["なか.ば"], ["half"], 5),
        # 午 : le SEUL kanji de la liste Tanos N5 qui manquait, mesure le
        # 2026-08-19 en diffant les 90 enseignes contre les 79 de
        # KanjiList.N5.doc. Lectures et sens repris de cette liste, elle-meme
        # KANJIDIC-derivee comme le reste de ce fichier. Porte 午前 / 午後,
        # deja tous deux dans le vocabulaire.
        KanjiEntry("\u5348", ["\u30ce", "\u5341"], ["\u30b4"], ["\u3046\u307e"], ["noon", "sign of the horse"], 4),
        KanjiEntry("毎", ["母", "ノ"], ["マイ"], ["ごと"], ["every"], 6),
        KanjiEntry("今", ["人", "一"], ["コン", "キン"], ["いま"], ["now"], 4),
        KanjiEntry("何", ["人", "口", "一"], ["カ"], ["なに", "なん"], ["what"], 7),

        # Adjectives / Other
        KanjiEntry("白", ["白"], ["ハク", "ビャク"], ["しろ", "しろ.い"], ["white"], 5),
        KanjiEntry("長", ["一", "ノ"], ["チョウ"], ["なが.い"], ["long", "leader"], 8),
        KanjiEntry("高", ["亠", "口", "冂"], ["コウ"], ["たか.い", "たか"], ["high", "tall", "expensive"], 10),
        KanjiEntry("安", ["宀", "女"], ["アン"], ["やす.い"], ["cheap", "peaceful"], 6),
        KanjiEntry("新", ["立", "木", "斤"], ["シン"], ["あたら.しい", "あら.た", "にい"], ["new"], 13),
        KanjiEntry("古", ["十", "口"], ["コ"], ["ふる.い", "ふる"], ["old"], 5),
        KanjiEntry("多", ["夂", "夂"], ["タ"], ["おお.い"], ["many", "much"], 6),
        KanjiEntry("少", ["小", "ノ"], ["ショウ"], ["すく.ない", "すこ.し"], ["few", "little"], 4),
        KanjiEntry("電", ["雨", "田", "乙"], ["デン"], [], ["electricity"], 13),
        KanjiEntry("車", ["車"], ["シャ"], ["くるま"], ["car", "vehicle"], 7),
    ]


# ---------------------------------------------------------------------------
# N5 Vocabulary
# ---------------------------------------------------------------------------

def n5_vocabulary() -> list[VocabEntry]:
    """Load the N5 vocabulary from ``scripts/content/vocabulary.json``.

    The entries used to be ~200 literals in this file. They moved out when the
    list grew to 693 words: a data set that large is data, not code, and it is
    edited by people (and reviewed in diffs) far more often than this
    generator is.

    Provenance, per row, in ``list_source``:

    - ``ikeru`` — the original hand-picked list this file used to carry.
    - ``tanos`` — words selected from Jonathan Waller's JLPT N5 list
      (CC BY, credited in ``AttributionView``). Only the **word and its
      reading** came from there; see ``scripts/tanos/build-vocab-list.py``
      for why the English glosses deliberately did not.

    Every ``meaning`` in the file is Ikeru's own English, exactly as before.
    """
    path = VOCABULARY_JSON
    with open(path, encoding="utf-8") as handle:
        payload = json.load(handle)

    entries: list[VocabEntry] = []
    seen: set[str] = set()
    for row in payload["words"]:
        word = row["word"]
        if word in seen:
            # The shipped bundle carried 今年 twice (ids 34 and 200) until
            # 2026-08-16 — 206 rows for 205 words. Failing loudly here is what
            # would have caught it.
            raise ValueError(f"{path}: {word!r} appears twice")
        seen.add(word)
        if not row.get("meaning"):
            raise ValueError(f"{path}: {word!r} has no English gloss")
        entries.append(
            VocabEntry(
                word,
                row["reading"],
                row["meaning"],
                row.get("kanji_character"),
                row["jlpt_level"],
                row["list_source"],
            )
        )
    return entries


# ---------------------------------------------------------------------------
# N5 Sentences (~100)
# ---------------------------------------------------------------------------

def n5_sentences() -> list[SentenceEntry]:
    return [
        # Numbers
        SentenceEntry("りんごを一つください。", "One apple, please.", "一つ"),
        SentenceEntry("コーヒーを二つ注文しました。", "I ordered two coffees.", "二つ"),
        SentenceEntry("百円のパンを買いました。", "I bought a 100-yen bread.", "百"),
        SentenceEntry("千円札がありますか。", "Do you have a 1000-yen bill?", "千"),

        # Days
        SentenceEntry("月曜日にテストがあります。", "There is a test on Monday.", "月曜日"),
        SentenceEntry("金曜日は友達に会います。", "I will meet a friend on Friday.", "金曜日"),
        SentenceEntry("日曜日は休みです。", "Sunday is a day off.", "日曜日"),

        # Time
        SentenceEntry("今日はいい天気ですね。", "It is nice weather today, isn't it?", "今日"),
        SentenceEntry("明日テストがあります。", "There is a test tomorrow.", "明日"),
        SentenceEntry("昨日は雨でした。", "It was rainy yesterday.", "昨日"),
        SentenceEntry("今は三時です。", "It is three o'clock now.", "今"),
        SentenceEntry("毎日日本語を勉強します。", "I study Japanese every day.", "毎日"),
        SentenceEntry("毎朝六時に起きます。", "I wake up at six every morning.", "毎朝"),
        SentenceEntry("今年は忙しいです。", "This year is busy.", "今年"),
        SentenceEntry("来年日本に行きたいです。", "I want to go to Japan next year.", "来年"),
        SentenceEntry("先月東京に行きました。", "I went to Tokyo last month.", "先月"),
        SentenceEntry("午前九時に学校に行きます。", "I go to school at 9 A.M.", "午前"),
        SentenceEntry("午後から雨が降ります。", "It will rain from the afternoon.", "午後"),

        # Nature
        SentenceEntry("あの山は高いです。", "That mountain is tall.", "山"),
        SentenceEntry("この川はきれいです。", "This river is clean.", "川"),
        SentenceEntry("今日の天気はいいです。", "Today's weather is good.", "天気"),
        SentenceEntry("雨が降っています。", "It is raining.", "雨"),
        SentenceEntry("花が咲いています。", "Flowers are blooming.", "花"),
        SentenceEntry("空がきれいです。", "The sky is beautiful.", "空"),
        SentenceEntry("水を飲みたいです。", "I want to drink water.", "水"),

        # People
        SentenceEntry("あの人は日本人です。", "That person is Japanese.", "日本人"),
        SentenceEntry("男の子が走っています。", "A boy is running.", "男の子"),
        SentenceEntry("女の子が歌を歌っています。", "A girl is singing a song.", "女の子"),
        SentenceEntry("子供が公園で遊んでいます。", "Children are playing in the park.", "子供"),
        SentenceEntry("友達と映画を見ました。", "I watched a movie with a friend.", "友達"),
        SentenceEntry("お父さんは会社で働いています。", "Father works at a company.", "お父さん"),
        SentenceEntry("お母さんは料理が上手です。", "Mother is good at cooking.", "お母さん"),

        # School
        SentenceEntry("私は学生です。", "I am a student.", "学生"),
        SentenceEntry("大学で日本語を勉強しています。", "I am studying Japanese at university.", "大学"),
        SentenceEntry("学校は八時に始まります。", "School begins at eight o'clock.", "学校"),
        SentenceEntry("先生は優しいです。", "The teacher is kind.", "先生"),
        SentenceEntry("この本は面白いです。", "This book is interesting.", "本"),
        SentenceEntry("日本語は難しいですが、楽しいです。", "Japanese is difficult, but fun.", "日本語"),
        SentenceEntry("英語を話しますか。", "Do you speak English?", "英語"),
        SentenceEntry("毎日勉強しなければなりません。", "I must study every day.", "勉強"),

        # Food / Drink
        SentenceEntry("朝ご飯を食べました。", "I ate breakfast.", "食べる"),
        SentenceEntry("お茶を飲みませんか。", "Won't you have some tea?", "飲む"),
        SentenceEntry("この食べ物はおいしいです。", "This food is delicious.", "食べ物"),
        SentenceEntry("何を飲みますか。", "What will you drink?", "飲み物"),
        SentenceEntry("パンと卵を食べました。", "I ate bread and eggs.", "パン"),
        SentenceEntry("肉と魚とどちらが好きですか。", "Which do you like, meat or fish?", "肉"),
        SentenceEntry("昼ご飯はもう食べましたか。", "Have you already eaten lunch?", "昼ご飯"),

        # Actions
        SentenceEntry("テレビを見ます。", "I watch television.", "見る"),
        SentenceEntry("音楽を聞きます。", "I listen to music.", "聞く"),
        SentenceEntry("本を読むのが好きです。", "I like reading books.", "読む"),
        SentenceEntry("手紙を書きました。", "I wrote a letter.", "書く"),
        SentenceEntry("日本語で話してください。", "Please speak in Japanese.", "話す"),
        SentenceEntry("明日東京に行きます。", "I will go to Tokyo tomorrow.", "行く"),
        SentenceEntry("友達が来ます。", "A friend is coming.", "来る"),
        SentenceEntry("部屋を出ました。", "I left the room.", "出る"),
        SentenceEntry("教室に入ってください。", "Please enter the classroom.", "入る"),
        SentenceEntry("新しい辞書を買いました。", "I bought a new dictionary.", "買う"),
        SentenceEntry("今日は休みましょう。", "Let's take a rest today.", "休む"),
        SentenceEntry("ここに立ってください。", "Please stand here.", "立つ"),
        SentenceEntry("この言葉の意味が分かりますか。", "Do you understand the meaning of this word?", "分かる"),
        SentenceEntry("毎日公園を歩きます。", "I walk in the park every day.", "歩く"),
        SentenceEntry("駅で友達を待ちました。", "I waited for a friend at the station.", "待つ"),
        SentenceEntry("東京に住んでいます。", "I live in Tokyo.", "住む"),
        SentenceEntry("彼の名前を知っていますか。", "Do you know his name?", "知る"),
        SentenceEntry("いい映画だと思います。", "I think it is a good movie.", "思う"),
        SentenceEntry("七時に家に帰ります。", "I return home at seven o'clock.", "帰る"),
        SentenceEntry("窓を開けてください。", "Please open the window.", "開ける"),
        SentenceEntry("ドアを閉めてください。", "Please close the door.", "閉める"),
        SentenceEntry("授業は九時に始まります。", "Class starts at nine o'clock.", "始まる"),

        # Adjectives
        SentenceEntry("この家は大きいです。", "This house is big.", "大きい"),
        SentenceEntry("猫は小さいです。", "The cat is small.", "小さい"),
        SentenceEntry("この建物は高いです。", "This building is tall.", "高い"),
        SentenceEntry("この店は安いです。", "This shop is cheap.", "安い"),
        SentenceEntry("新しい靴を買いました。", "I bought new shoes.", "新しい"),
        SentenceEntry("古い神社に行きました。", "I went to an old shrine.", "古い"),
        SentenceEntry("この道は長いです。", "This road is long.", "長い"),
        SentenceEntry("今日は暑いですね。", "It is hot today, isn't it?", "暑い"),
        SentenceEntry("冬は寒いです。", "Winter is cold.", "寒い"),

        # Places / Directions
        SentenceEntry("日本は美しい国です。", "Japan is a beautiful country.", "日本"),
        SentenceEntry("外国に行ったことがありますか。", "Have you been to a foreign country?", "外国"),
        SentenceEntry("家で本を読みます。", "I read books at home.", "家"),
        SentenceEntry("部屋はきれいですか。", "Is the room clean?", "部屋"),
        SentenceEntry("病院に行きました。", "I went to the hospital.", "病院"),
        SentenceEntry("駅はどこですか。", "Where is the station?", "駅"),
        SentenceEntry("右に曲がってください。", "Please turn right.", "右"),
        SentenceEntry("左に公園があります。", "There is a park on the left.", "左"),
        SentenceEntry("銀行は駅の前にあります。", "The bank is in front of the station.", "銀行"),

        # Transport
        SentenceEntry("電車で会社に行きます。", "I go to work by train.", "電車"),
        SentenceEntry("車で東京に行きました。", "I went to Tokyo by car.", "車"),
        SentenceEntry("自転車で学校に行きます。", "I go to school by bicycle.", "自転車"),

        # Misc
        SentenceEntry("名前は何ですか。", "What is your name?", "名前"),
        SentenceEntry("お金がありません。", "I do not have money.", "お金"),
        SentenceEntry("電話をかけてください。", "Please make a phone call.", "電話"),
        SentenceEntry("写真を撮ってもいいですか。", "May I take a photograph?", "写真"),
        SentenceEntry("新聞を読みますか。", "Do you read the newspaper?", "新聞"),
        SentenceEntry("大丈夫ですか。", "Are you all right?", "大丈夫"),
    ]


# ---------------------------------------------------------------------------
# N5 Grammar Points (~30)
# ---------------------------------------------------------------------------

def n5_grammar() -> list[GrammarEntry]:
    return [
        GrammarEntry("n5", "は (Topic Marker)",
                     "Marks the topic of the sentence. Pronounced 'wa' when used as a particle.",
                     ["私は学生です。 — I am a student.",
                      "今日は月曜日です。 — Today is Monday.",
                      "東京は大きいです。 — Tokyo is big."]),

        GrammarEntry("n5", "です / ます (Polite Form)",
                     "Polite sentence endings. です follows nouns/adjectives, ます follows verbs.",
                     ["学生です。 — (I) am a student.",
                      "食べます。 — (I) eat.",
                      "きれいです。 — (It) is pretty."]),

        GrammarEntry("n5", "を (Object Marker)",
                     "Marks the direct object of a transitive verb. Pronounced 'o'.",
                     ["水を飲みます。 — I drink water.",
                      "本を読みます。 — I read a book.",
                      "映画を見ます。 — I watch a movie."]),

        GrammarEntry("n5", "に (Direction / Time / Location)",
                     "Indicates direction of movement, a specific point in time, or location of existence.",
                     ["学校に行きます。 — I go to school.",
                      "六時に起きます。 — I wake up at six.",
                      "椅子の上に猫がいます。 — There is a cat on the chair."]),

        GrammarEntry("n5", "で (Location of Action / Means)",
                     "Marks the place where an action occurs, or the means/tool used.",
                     ["学校で勉強します。 — I study at school.",
                      "バスで行きます。 — I go by bus.",
                      "日本語で話してください。 — Please speak in Japanese."]),

        GrammarEntry("n5", "が (Subject Marker)",
                     "Marks the grammatical subject, especially with existence verbs (ある/いる) and in new-information contexts.",
                     ["猫がいます。 — There is a cat.",
                      "水があります。 — There is water.",
                      "誰が来ましたか。 — Who came?"]),

        GrammarEntry("n5", "も (Also / Too)",
                     "Replaces は, が, or を to mean 'also' or 'too'.",
                     ["私も学生です。 — I am also a student.",
                      "これも美味しいです。 — This is also delicious.",
                      "田中さんも行きます。 — Tanaka will also go."]),

        GrammarEntry("n5", "の (Possessive / Noun Modifier)",
                     "Connects nouns to show possession, affiliation, or to modify a noun.",
                     ["私の本。 — My book.",
                      "日本の食べ物。 — Japanese food.",
                      "大学の先生。 — A university professor."]),

        GrammarEntry("n5", "と (And / With / Quotation)",
                     "Connects nouns ('and'), marks a companion ('with'), or marks a quotation.",
                     ["パンと卵を食べました。 — I ate bread and eggs.",
                      "友達と行きます。 — I go with a friend.",
                      "先生は「静かに」と言いました。 — The teacher said 'Be quiet.'"]),

        GrammarEntry("n5", "か (Question Marker)",
                     "Placed at the end of a sentence to form a question.",
                     ["学生ですか。 — Are you a student?",
                      "何を食べますか。 — What will you eat?",
                      "明日は休みですか。 — Is tomorrow a day off?"]),

        GrammarEntry("n5", "から / まで (From / Until)",
                     "から marks a starting point (from); まで marks an ending point (until/to).",
                     ["九時から五時まで働きます。 — I work from 9 to 5.",
                      "東京から大阪まで電車で行きます。 — I go from Tokyo to Osaka by train.",
                      "朝から雨が降っています。 — It has been raining since morning."]),

        GrammarEntry("n5", "よ / ね (Sentence-ending Particles)",
                     "よ asserts information the listener may not know. ね seeks confirmation or agreement.",
                     ["これは美味しいですよ。 — This is delicious, you know.",
                      "今日は暑いですね。 — It's hot today, isn't it?",
                      "明日テストがありますよ。 — There's a test tomorrow, you know."]),

        GrammarEntry("n5", "ない (Negative Form)",
                     "Negative form of verbs. For i-adjectives, replace い with くない. For na-adjectives/nouns, add じゃない.",
                     ["食べない。 — (I) don't eat.",
                      "高くない。 — Not expensive.",
                      "学生じゃない。 — (I) am not a student."]),

        GrammarEntry("n5", "ません / ではありません (Polite Negative)",
                     "Polite negative endings. ません for verbs; ではありません (or じゃありません) for nouns/adjectives.",
                     ["食べません。 — (I) don't eat.",
                      "学生ではありません。 — (I) am not a student.",
                      "分かりません。 — (I) don't understand."]),

        GrammarEntry("n5", "ました / でした (Past Tense)",
                     "Past tense in polite form. ました for verbs; でした for nouns/na-adjectives.",
                     ["食べました。 — (I) ate.",
                      "学生でした。 — (I) was a student.",
                      "楽しかったです。 — (It) was fun."]),

        GrammarEntry("n5", "て form (Verb Connective)",
                     "The て-form connects verbs, makes requests (〜てください), and describes ongoing states (〜ている).",
                     ["食べてください。 — Please eat.",
                      "本を読んでいます。 — (I) am reading a book.",
                      "朝起きて、顔を洗って、朝ご飯を食べます。 — I wake up, wash my face, and eat breakfast."]),

        GrammarEntry("n5", "ている (Ongoing State / Habitual Action)",
                     "Expresses an action in progress, a habitual action, or a resultant state.",
                     ["今、食べています。 — I am eating now.",
                      "東京に住んでいます。 — I live in Tokyo.",
                      "窓が開いています。 — The window is open."]),

        GrammarEntry("n5", "たい (Want to ~)",
                     "Expresses the speaker's desire. Attach たい to the verb stem (ます form minus ます).",
                     ["日本に行きたいです。 — I want to go to Japan.",
                      "水が飲みたいです。 — I want to drink water.",
                      "新しいゲームを買いたいです。 — I want to buy a new game."]),

        GrammarEntry("n5", "てもいい (Permission)",
                     "Expresses permission — 'may I?', 'it's OK to'. Attach てもいい to the て-form.",
                     ["写真を撮ってもいいですか。 — May I take a photo?",
                      "ここに座ってもいいですか。 — May I sit here?",
                      "帰ってもいいですよ。 — You may go home."]),

        GrammarEntry("n5", "てはいけない (Prohibition)",
                     "Expresses prohibition — 'must not'. Attach てはいけない to the て-form.",
                     ["ここで食べてはいけません。 — You must not eat here.",
                      "写真を撮ってはいけません。 — You must not take photos.",
                      "遅く来てはいけません。 — You must not come late."]),

        GrammarEntry("n5", "なければならない (Must / Have to)",
                     "Expresses obligation — 'must', 'have to'. Formed from the negative stem + ければならない.",
                     ["勉強しなければなりません。 — I must study.",
                      "薬を飲まなければなりません。 — I must take medicine.",
                      "早く起きなければなりません。 — I must wake up early."]),

        GrammarEntry("n5", "ましょう (Let's ~)",
                     "Polite volitional form expressing suggestion — 'let's do ~'.",
                     ["食べましょう。 — Let's eat.",
                      "一緒に行きましょう。 — Let's go together.",
                      "休みましょう。 — Let's take a break."]),

        GrammarEntry("n5", "たことがある (Experience)",
                     "Expresses past experience — 'have done ~'. Uses the た-form + ことがある.",
                     ["日本に行ったことがあります。 — I have been to Japan.",
                      "寿司を食べたことがありますか。 — Have you ever eaten sushi?",
                      "富士山を見たことがあります。 — I have seen Mt. Fuji."]),

        GrammarEntry("n5", "つもり (Intention)",
                     "Expresses the speaker's intention or plan. Dictionary form + つもり.",
                     ["明日勉強するつもりです。 — I intend to study tomorrow.",
                      "来年日本に行くつもりです。 — I plan to go to Japan next year.",
                      "週末に映画を見るつもりです。 — I plan to watch a movie on the weekend."]),

        GrammarEntry("n5", "あげる / もらう / くれる (Giving & Receiving)",
                     "Three verbs for giving and receiving: あげる (I give), もらう (I receive), くれる (someone gives to me).",
                     ["友達にプレゼントをあげました。 — I gave a present to a friend.",
                      "友達にプレゼントをもらいました。 — I received a present from a friend.",
                      "母が本をくれました。 — My mother gave me a book."]),

        GrammarEntry("n5", "方 (かた) (How to ~)",
                     "Attach 方 (かた) to the verb stem to express 'how to do ~'.",
                     ["この漢字の読み方を教えてください。 — Please teach me how to read this kanji.",
                      "使い方が分かりません。 — I don't understand how to use it.",
                      "作り方は簡単です。 — The way to make it is simple."]),

        GrammarEntry("n5", "すぎる (Too much)",
                     "Attached to verb stems or adjective stems to mean 'too much / overly'.",
                     ["食べすぎました。 — I ate too much.",
                      "この本は難しすぎます。 — This book is too difficult.",
                      "高すぎます。 — It is too expensive."]),

        GrammarEntry("n5", "ながら (While doing ~)",
                     "Expresses two simultaneous actions. Verb stem + ながら.",
                     ["音楽を聞きながら勉強します。 — I study while listening to music.",
                      "歩きながら話しましょう。 — Let's talk while walking.",
                      "テレビを見ながら食べます。 — I eat while watching TV."]),

        GrammarEntry("n5", "この / その / あの / どの (Demonstratives)",
                     "これ/この (this, near speaker), それ/その (that, near listener), あれ/あの (that over there), どれ/どの (which).",
                     ["この本は面白いです。 — This book is interesting.",
                      "その靴はいくらですか。 — How much are those shoes?",
                      "あの山は富士山です。 — That mountain over there is Mt. Fuji."]),

        GrammarEntry("n5", "ここ / そこ / あそこ / どこ (Location Words)",
                     "ここ (here), そこ (there, near listener), あそこ (over there), どこ (where).",
                     ["ここは図書館です。 — Here is the library.",
                      "トイレはどこですか。 — Where is the restroom?",
                      "あそこに猫がいます。 — There is a cat over there."]),

        GrammarEntry("n5", "けど / が (But / However)",
                     "Conjunctions meaning 'but' or 'however'. が is more formal; けど is casual.",
                     ["日本語は難しいですが、楽しいです。 — Japanese is difficult, but fun.",
                      "高いけど、買います。 — It's expensive, but I'll buy it.",
                      "行きたいですが、時間がありません。 — I want to go, but I don't have time."]),
    ]


# ---------------------------------------------------------------------------
# Database generation
# ---------------------------------------------------------------------------

def create_database(db_path: str, level: str) -> dict[str, int]:
    """Create the SQLite database and return insertion counts."""
    os.makedirs(os.path.dirname(db_path), exist_ok=True)

    if os.path.exists(db_path):
        os.remove(db_path)

    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.executescript(SCHEMA_SQL)

    counts: dict[str, int] = {}

    # --- Data selection by level ---
    data_map: dict[str, tuple] = {
        "n5": (n5_radicals, n5_kanji, n5_vocabulary, n5_sentences, n5_grammar),
    }

    if level not in data_map:
        conn.close()
        raise ValueError(f"Unsupported level: {level}. Supported: {', '.join(data_map)}")

    get_radicals, get_kanji, get_vocab, get_sentences, get_grammar = data_map[level]

    # --- Radicals ---
    radicals = get_radicals()
    cur.executemany(
        "INSERT OR IGNORE INTO radicals VALUES (?, ?, ?)",
        [(r.character, r.meaning, r.stroke_count) for r in radicals],
    )
    counts["radicals"] = len(radicals)

    # --- Kanji ---
    kanji_list = get_kanji()
    for k in kanji_list:
        cur.execute(
            "INSERT OR IGNORE INTO kanji VALUES (?, ?, ?, ?, ?, ?, ?)",
            (
                k.character,
                json.dumps(k.on_readings, ensure_ascii=False),
                json.dumps(k.kun_readings, ensure_ascii=False),
                json.dumps(k.meanings, ensure_ascii=False),
                level,
                k.stroke_count,
                None,
            ),
        )
        for rad in k.radical_chars:
            cur.execute(
                "INSERT OR IGNORE INTO kanji_radical_edges VALUES (?, ?)",
                (rad, k.character),
            )
    counts["kanji"] = len(kanji_list)

    # --- Vocabulary ---
    vocab_list = get_vocab()
    for i, v in enumerate(vocab_list, 1):
        cur.execute(
            "INSERT OR IGNORE INTO vocabulary VALUES (?, ?, ?, ?, ?, ?, ?)",
            (i, v.word, v.reading, v.meaning, v.kanji_character, v.jlpt_level, v.list_source),
        )
    counts["vocabulary"] = len(vocab_list)

    # --- Sentences ---
    sentence_list = get_sentences()
    for i, s in enumerate(sentence_list, 1):
        cur.execute(
            "INSERT OR IGNORE INTO sentences VALUES (?, ?, ?, ?)",
            (i, s.japanese, s.english, s.vocabulary_word),
        )
    counts["sentences"] = len(sentence_list)

    # --- Grammar ---
    grammar_list = get_grammar()
    for i, g in enumerate(grammar_list, 1):
        cur.execute(
            "INSERT OR IGNORE INTO grammar_points VALUES (?, ?, ?, ?, ?)",
            (i, g.jlpt_level, g.title, g.explanation, json.dumps(g.examples, ensure_ascii=False)),
        )
    counts["grammar_points"] = len(grammar_list)

    conn.commit()
    conn.close()
    return counts


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)
    default_output_dir = os.path.join(project_root, "Ikeru", "Resources", "ContentBundles")

    parser = argparse.ArgumentParser(
        description="Generate SQLite content bundles for the Ikeru Japanese learning app.",
    )
    parser.add_argument(
        "--output-dir",
        default=default_output_dir,
        help=f"Output directory (default: {default_output_dir})",
    )
    parser.add_argument(
        "--level",
        default="n5",
        choices=["n5"],
        help="JLPT level to generate (default: n5)",
    )
    args = parser.parse_args()

    db_filename = f"{args.level}-content.sqlite"
    db_path = os.path.join(args.output_dir, db_filename)

    print(f"Generating {db_filename} ...")
    counts = create_database(db_path, args.level)

    print(f"\nGenerated: {db_path}")
    print("─" * 40)
    for table, count in counts.items():
        print(f"  {table:20s} {count:>5d}")
    print("─" * 40)
    print(f"  {'total':20s} {sum(counts.values()):>5d}")


if __name__ == "__main__":
    main()
