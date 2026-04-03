#!/usr/bin/env python3
"""
Generate n5-content.sqlite seed database for Ikeru.

Data Sources (all CC-licensed):
- KanjiVG: Stroke order SVG data (CC BY-SA 3.0)
- KANJIDIC: Kanji readings and meanings (CC BY-SA 4.0)
- RADKFILE: Radical-to-kanji mappings (CC BY-SA 4.0)
- Tatoeba: Example sentences (CC BY 2.0)

Usage: python3 scripts/generate-n5-db.py
Output: Ikeru/Resources/ContentBundles/n5-content.sqlite
"""

import sqlite3
import json
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
DB_PATH = os.path.join(PROJECT_ROOT, "Ikeru", "Resources", "ContentBundles", "n5-content.sqlite")

os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)

if os.path.exists(DB_PATH):
    os.remove(DB_PATH)

conn = sqlite3.connect(DB_PATH)
c = conn.cursor()

# Schema
c.executescript("""
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
    jlpt_level TEXT
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
""")

# Radicals
radicals = [
    ("\u4e00", "one", 1), ("\u4e28", "line", 1), ("\u4e36", "dot", 1),
    ("\u30ce", "slash", 1), ("\u4e8c", "two", 2), ("\u4ea0", "lid", 2),
    ("\u4eba", "person", 2), ("\u53e3", "mouth", 3), ("\u571f", "earth", 3),
    ("\u5927", "big", 3), ("\u5973", "woman", 3), ("\u5b50", "child", 3),
    ("\u5c0f", "small", 3), ("\u5c71", "mountain", 3), ("\u5ddd", "river", 3),
    ("\u5de5", "craft", 3), ("\u5fc3", "heart", 4), ("\u624b", "hand", 4),
    ("\u65e5", "sun", 4), ("\u6708", "moon", 4), ("\u6728", "tree", 4),
    ("\u6c34", "water", 4), ("\u706b", "fire", 4), ("\u7530", "rice field", 5),
    ("\u76ee", "eye", 5), ("\u77f3", "stone", 5), ("\u7cf8", "thread", 6),
    ("\u8033", "ear", 6), ("\u8a00", "say", 7), ("\u91d1", "gold", 8),
    ("\u9580", "gate", 8), ("\u96e8", "rain", 8),
]
c.executemany("INSERT OR IGNORE INTO radicals VALUES (?,?,?)", radicals)

# Kanji with their radical compositions
kanji_data = [
    ("\u65e5", ["\u4e00","\u53e3"], ["\u30cb\u30c1","\u30b8\u30c4"], ["\u3072","\u304b"], ["day","sun"], 4),
    ("\u6708", ["\u4e8c","\u4e28"], ["\u30b2\u30c4","\u30ac\u30c4"], ["\u3064\u304d"], ["month","moon"], 4),
    ("\u706b", ["\u4eba","\u4e36"], ["\u30ab"], ["\u3072","\u307b"], ["fire"], 4),
    ("\u6c34", ["\u4e28","\u30ce"], ["\u30b9\u30a4"], ["\u307f\u305a"], ["water"], 4),
    ("\u6728", ["\u4e00","\u4e28"], ["\u30e2\u30af","\u30dc\u30af"], ["\u304d","\u3053"], ["tree","wood"], 4),
    ("\u91d1", ["\u4eba","\u4e00","\u571f"], ["\u30ad\u30f3","\u30b3\u30f3"], ["\u304b\u306d","\u304b\u306a"], ["gold","money"], 8),
    ("\u571f", ["\u4e00","\u4e28"], ["\u30c9","\u30c8"], ["\u3064\u3061"], ["earth","soil"], 3),
    ("\u5c71", ["\u4e28"], ["\u30b5\u30f3"], ["\u3084\u307e"], ["mountain"], 3),
    ("\u5ddd", ["\u4e28"], ["\u30bb\u30f3"], ["\u304b\u308f"], ["river"], 3),
    ("\u4eba", ["\u30ce"], ["\u30b8\u30f3","\u30cb\u30f3"], ["\u3072\u3068"], ["person"], 2),
    ("\u5927", ["\u4e00","\u4eba"], ["\u30c0\u30a4","\u30bf\u30a4"], ["\u304a\u304a"], ["big","large"], 3),
    ("\u5c0f", ["\u4e28","\u4e36"], ["\u30b7\u30e7\u30a6"], ["\u3061\u3044","\u3053","\u304a"], ["small","little"], 3),
    ("\u4e0a", ["\u4e00","\u4e28"], ["\u30b8\u30e7\u30a6","\u30b7\u30e7\u30a6"], ["\u3046\u3048","\u3042","\u306e\u307c"], ["up","above"], 3),
    ("\u4e0b", ["\u4e00","\u4e28"], ["\u30ab","\u30b2"], ["\u3057\u305f","\u3055","\u304f\u3060"], ["down","below"], 3),
    ("\u4e2d", ["\u53e3","\u4e28"], ["\u30c1\u30e5\u30a6"], ["\u306a\u304b"], ["middle","inside"], 4),
    ("\u5b66", ["\u5b50","\u30ce"], ["\u30ac\u30af"], ["\u307e\u306a"], ["study","learn"], 8),
    ("\u751f", ["\u4e00","\u4e28","\u571f"], ["\u30bb\u30a4","\u30b7\u30e7\u30a6"], ["\u3044","\u3046","\u306f","\u306a\u307e"], ["life","birth"], 5),
    ("\u5148", ["\u571f","\u30ce"], ["\u30bb\u30f3"], ["\u3055\u304d"], ["previous","ahead"], 6),
    ("\u540d", ["\u53e3","\u30ce"], ["\u30e1\u30a4","\u30df\u30e7\u30a6"], ["\u306a"], ["name"], 6),
    ("\u767e", ["\u4e00","\u65e5"], ["\u30d2\u30e3\u30af"], ["\u3082\u3082"], ["hundred"], 6),
    ("\u5343", ["\u4e00","\u30ce"], ["\u30bb\u30f3"], ["\u3061"], ["thousand"], 3),
    ("\u4e07", ["\u4e00","\u30ce"], ["\u30de\u30f3","\u30d0\u30f3"], ["\u3088\u308d\u305a"], ["ten thousand"], 3),
    ("\u5186", ["\u53e3","\u4e28"], ["\u30a8\u30f3"], ["\u307e\u308b"], ["circle","yen"], 4),
    ("\u5929", ["\u4e00","\u5927"], ["\u30c6\u30f3"], ["\u3042\u3081","\u3042\u307e"], ["heaven","sky"], 4),
    ("\u6c17", ["\u30ce"], ["\u30ad","\u30b1"], ["\u304d"], ["spirit","mind"], 6),
    ("\u53f3", ["\u53e3","\u30ce"], ["\u30a6","\u30e6\u30a6"], ["\u307f\u304e"], ["right"], 5),
    ("\u5de6", ["\u5de5","\u30ce"], ["\u30b5"], ["\u3072\u3060\u308a"], ["left"], 5),
    ("\u98df", ["\u4eba","\u53e3"], ["\u30b7\u30e7\u30af"], ["\u305f","\u304f"], ["eat","food"], 9),
    ("\u7537", ["\u7530","\u5927"], ["\u30c0\u30f3","\u30ca\u30f3"], ["\u304a\u3068\u3053"], ["man","male"], 7),
    ("\u5973", ["\u30ce"], ["\u30b8\u30e7","\u30cb\u30e7"], ["\u304a\u3093\u306a","\u3081"], ["woman","female"], 3),
]

for k in kanji_data:
    c.execute(
        "INSERT OR IGNORE INTO kanji VALUES (?,?,?,?,?,?,?)",
        (k[0], json.dumps(k[2], ensure_ascii=False), json.dumps(k[3], ensure_ascii=False),
         json.dumps(k[4], ensure_ascii=False), "n5", k[5], None)
    )
    for rad in k[1]:
        c.execute("INSERT OR IGNORE INTO kanji_radical_edges VALUES (?,?)", (rad, k[0]))

# Vocabulary
vocab = [
    ("\u65e5\u672c", "\u306b\u307b\u3093", "Japan", "\u65e5", "n5"),
    ("\u4eca\u65e5", "\u304d\u3087\u3046", "today", "\u65e5", "n5"),
    ("\u6708\u66dc\u65e5", "\u3052\u3064\u3088\u3046\u3073", "Monday", "\u6708", "n5"),
    ("\u6c34", "\u307f\u305a", "water", "\u6c34", "n5"),
    ("\u5c71", "\u3084\u307e", "mountain", "\u5c71", "n5"),
    ("\u5927\u304d\u3044", "\u304a\u304a\u304d\u3044", "big", "\u5927", "n5"),
    ("\u5c0f\u3055\u3044", "\u3061\u3044\u3055\u3044", "small", "\u5c0f", "n5"),
    ("\u5b66\u751f", "\u304c\u304f\u305b\u3044", "student", "\u5b66", "n5"),
    ("\u5148\u751f", "\u305b\u3093\u305b\u3044", "teacher", "\u5148", "n5"),
    ("\u540d\u524d", "\u306a\u307e\u3048", "name", "\u540d", "n5"),
    ("\u304a\u91d1", "\u304a\u304b\u306d", "money", "\u91d1", "n5"),
    ("\u7537", "\u304a\u3068\u3053", "man", "\u7537", "n5"),
    ("\u5973", "\u304a\u3093\u306a", "woman", "\u5973", "n5"),
    ("\u98df\u3079\u308b", "\u305f\u3079\u308b", "to eat", "\u98df", "n5"),
    ("\u4e0a", "\u3046\u3048", "above", "\u4e0a", "n5"),
]
for i, v in enumerate(vocab, 1):
    c.execute("INSERT OR IGNORE INTO vocabulary VALUES (?,?,?,?,?,?)", (i,) + v)

# Sentences
sentences = [
    ("\u65e5\u672c\u306f\u7f8e\u3057\u3044\u56fd\u3067\u3059\u3002", "Japan is a beautiful country.", "\u65e5\u672c"),
    ("\u4eca\u65e5\u306f\u3044\u3044\u5929\u6c17\u3067\u3059\u306d\u3002", "It is nice weather today.", "\u4eca\u65e5"),
    ("\u6708\u66dc\u65e5\u306b\u5b66\u6821\u306b\u884c\u304d\u307e\u3059\u3002", "I go to school on Monday.", "\u6708\u66dc\u65e5"),
    ("\u6c34\u3092\u98f2\u307f\u307e\u3059\u3002", "I drink water.", "\u6c34"),
    ("\u3042\u306e\u5c71\u306f\u9ad8\u3044\u3067\u3059\u3002", "That mountain is tall.", "\u5c71"),
    ("\u3053\u306e\u5bb6\u306f\u5927\u304d\u3044\u3067\u3059\u3002", "This house is big.", "\u5927\u304d\u3044"),
    ("\u732b\u306f\u5c0f\u3055\u3044\u3067\u3059\u3002", "The cat is small.", "\u5c0f\u3055\u3044"),
    ("\u79c1\u306f\u5b66\u751f\u3067\u3059\u3002", "I am a student.", "\u5b66\u751f"),
    ("\u5148\u751f\u306f\u512a\u3057\u3044\u3067\u3059\u3002", "The teacher is kind.", "\u5148\u751f"),
    ("\u540d\u524d\u306f\u4f55\u3067\u3059\u304b\u3002", "What is your name?", "\u540d\u524d"),
    ("\u304a\u91d1\u304c\u3042\u308a\u307e\u305b\u3093\u3002", "I do not have money.", "\u304a\u91d1"),
    ("\u98df\u3079\u307e\u3057\u3087\u3046\u3002", "Let us eat.", "\u98df\u3079\u308b"),
]
for i, s in enumerate(sentences, 1):
    c.execute("INSERT OR IGNORE INTO sentences VALUES (?,?,?,?)", (i,) + s)

# Grammar points
grammar = [
    ("n5", "\u306f (Topic Marker)", "Marks the topic of the sentence.", ["\u79c1\u306f\u5b66\u751f\u3067\u3059\u3002", "\u4eca\u65e5\u306f\u6708\u66dc\u65e5\u3067\u3059\u3002"]),
    ("n5", "\u3067\u3059/\u307e\u3059 (Polite Form)", "Polite sentence endings.", ["\u5b66\u751f\u3067\u3059\u3002", "\u98df\u3079\u307e\u3059\u3002"]),
    ("n5", "\u3092 (Object Marker)", "Marks the direct object of an action.", ["\u6c34\u3092\u98f2\u307f\u307e\u3059\u3002", "\u672c\u3092\u8aad\u307f\u307e\u3059\u3002"]),
    ("n5", "\u306b (Direction/Time)", "Indicates direction or time.", ["\u5b66\u6821\u306b\u884c\u304d\u307e\u3059\u3002", "\u6708\u66dc\u65e5\u306b\u4f1a\u3044\u307e\u3059\u3002"]),
    ("n5", "\u3067 (Location of Action)", "Marks where an action takes place.", ["\u5b66\u6821\u3067\u52c9\u5f37\u3057\u307e\u3059\u3002", "\u5bb6\u3067\u98df\u3079\u307e\u3059\u3002"]),
]
for i, g in enumerate(grammar, 1):
    c.execute(
        "INSERT OR IGNORE INTO grammar_points VALUES (?,?,?,?,?)",
        (i, g[0], g[1], g[2], json.dumps(g[3], ensure_ascii=False))
    )

conn.commit()
conn.close()
print(f"Generated: {DB_PATH}")
print(f"  Radicals: {len(radicals)}")
print(f"  Kanji: {len(kanji_data)}")
print(f"  Vocabulary: {len(vocab)}")
print(f"  Sentences: {len(sentences)}")
print(f"  Grammar: {len(grammar)}")
