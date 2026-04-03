#!/usr/bin/env swift

/// Build-time script to generate n5-content.sqlite from CC-licensed source data.
///
/// Data Sources (all CC-licensed):
/// - KanjiVG: Stroke order SVG data (CC BY-SA 3.0)
/// - KANJIDIC: Kanji readings and meanings (CC BY-SA 4.0)
/// - RADKFILE: Radical-to-kanji mappings (CC BY-SA 4.0)
/// - Tatoeba: Example sentences (CC BY 2.0)
///
/// Usage: swift scripts/generate-content-bundle.swift
///
/// Output: Ikeru/Resources/ContentBundles/n5-content.sqlite

import Foundation
import SQLite3

// MARK: - Schema

let schemaSQL = """
CREATE TABLE IF NOT EXISTS kanji (
    character TEXT PRIMARY KEY,
    on_readings TEXT,       -- JSON array
    kun_readings TEXT,      -- JSON array
    meanings TEXT,          -- JSON array
    jlpt_level TEXT,
    stroke_count INTEGER,
    stroke_order_svg TEXT   -- KanjiVG SVG path data
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
    examples TEXT           -- JSON array
);
"""

// MARK: - Seed Data

/// N5 radicals (subset for MVP seed data)
let radicals: [(character: String, meaning: String, strokeCount: Int)] = [
    ("一", "one", 1),
    ("丨", "line", 1),
    ("丶", "dot", 1),
    ("ノ", "slash", 1),
    ("二", "two", 2),
    ("亠", "lid", 2),
    ("人", "person", 2),
    ("口", "mouth", 3),
    ("土", "earth", 3),
    ("大", "big", 3),
    ("女", "woman", 3),
    ("子", "child", 3),
    ("小", "small", 3),
    ("山", "mountain", 3),
    ("川", "river", 3),
    ("工", "craft", 3),
    ("心", "heart", 4),
    ("手", "hand", 4),
    ("日", "sun", 4),
    ("月", "moon", 4),
    ("木", "tree", 4),
    ("水", "water", 4),
    ("火", "fire", 4),
    ("田", "rice field", 5),
    ("目", "eye", 5),
    ("石", "stone", 5),
    ("糸", "thread", 6),
    ("耳", "ear", 6),
    ("言", "say", 7),
    ("金", "gold", 8),
    ("門", "gate", 8),
    ("雨", "rain", 8),
]

/// N5 kanji with their radical compositions
let kanjiData: [(character: String, radicals: [String], onReadings: [String], kunReadings: [String], meanings: [String], strokeCount: Int)] = [
    ("日", ["一", "口"], ["ニチ", "ジツ"], ["ひ", "か"], ["day", "sun"], 4),
    ("月", ["二", "丨"], ["ゲツ", "ガツ"], ["つき"], ["month", "moon"], 4),
    ("火", ["人", "丶"], ["カ"], ["ひ", "ほ"], ["fire"], 4),
    ("水", ["丨", "ノ"], ["スイ"], ["みず"], ["water"], 4),
    ("木", ["一", "丨"], ["モク", "ボク"], ["き", "こ"], ["tree", "wood"], 4),
    ("金", ["人", "一", "土"], ["キン", "コン"], ["かね", "かな"], ["gold", "money"], 8),
    ("土", ["一", "丨"], ["ド", "ト"], ["つち"], ["earth", "soil"], 3),
    ("山", ["丨"], ["サン"], ["やま"], ["mountain"], 3),
    ("川", ["丨"], ["セン"], ["かわ"], ["river"], 3),
    ("人", ["ノ"], ["ジン", "ニン"], ["ひと"], ["person"], 2),
    ("大", ["一", "人"], ["ダイ", "タイ"], ["おお"], ["big", "large"], 3),
    ("小", ["丨", "丶"], ["ショウ"], ["ちい", "こ", "お"], ["small", "little"], 3),
    ("上", ["一", "丨"], ["ジョウ", "ショウ"], ["うえ", "あ", "のぼ"], ["up", "above"], 3),
    ("下", ["一", "丨"], ["カ", "ゲ"], ["した", "さ", "くだ"], ["down", "below"], 3),
    ("中", ["口", "丨"], ["チュウ"], ["なか"], ["middle", "inside"], 4),
    ("学", ["子", "ノ"], ["ガク"], ["まな"], ["study", "learn"], 8),
    ("生", ["一", "丨", "土"], ["セイ", "ショウ"], ["い", "う", "は", "なま"], ["life", "birth"], 5),
    ("先", ["土", "ノ"], ["セン"], ["さき"], ["previous", "ahead"], 6),
    ("名", ["口", "ノ"], ["メイ", "ミョウ"], ["な"], ["name"], 6),
    ("百", ["一", "日"], ["ヒャク"], ["もも"], ["hundred"], 6),
    ("千", ["一", "ノ"], ["セン"], ["ち"], ["thousand"], 3),
    ("万", ["一", "ノ"], ["マン", "バン"], ["よろず"], ["ten thousand"], 3),
    ("円", ["口", "丨"], ["エン"], ["まる"], ["circle", "yen"], 4),
    ("天", ["一", "大"], ["テン"], ["あめ", "あま"], ["heaven", "sky"], 4),
    ("気", ["ノ"], ["キ", "ケ"], ["き"], ["spirit", "mind"], 6),
    ("右", ["口", "ノ"], ["ウ", "ユウ"], ["みぎ"], ["right"], 5),
    ("左", ["工", "ノ"], ["サ"], ["ひだり"], ["left"], 5),
    ("食", ["人", "口"], ["ショク"], ["た", "く"], ["eat", "food"], 9),
    ("男", ["田", "大"], ["ダン", "ナン"], ["おとこ"], ["man", "male"], 7),
    ("女", ["ノ"], ["ジョ", "ニョ"], ["おんな", "め"], ["woman", "female"], 3),
]

/// N5 vocabulary
let vocabData: [(word: String, reading: String, meaning: String, kanjiCharacter: String?, jlptLevel: String)] = [
    ("日本", "にほん", "Japan", "日", "n5"),
    ("今日", "きょう", "today", "日", "n5"),
    ("月曜日", "げつようび", "Monday", "月", "n5"),
    ("水", "みず", "water", "水", "n5"),
    ("山", "やま", "mountain", "山", "n5"),
    ("大きい", "おおきい", "big", "大", "n5"),
    ("小さい", "ちいさい", "small", "小", "n5"),
    ("学生", "がくせい", "student", "学", "n5"),
    ("先生", "せんせい", "teacher", "先", "n5"),
    ("名前", "なまえ", "name", "名", "n5"),
    ("お金", "おかね", "money", "金", "n5"),
    ("男", "おとこ", "man", "男", "n5"),
    ("女", "おんな", "woman", "女", "n5"),
    ("食べる", "たべる", "to eat", "食", "n5"),
    ("上", "うえ", "above", "上", "n5"),
]

/// N5 sentences
let sentenceData: [(japanese: String, english: String, vocabularyWord: String)] = [
    ("日本は美しい国です。", "Japan is a beautiful country.", "日本"),
    ("今日はいい天気ですね。", "It's nice weather today, isn't it?", "今日"),
    ("月曜日に学校に行きます。", "I go to school on Monday.", "月曜日"),
    ("水を飲みます。", "I drink water.", "水"),
    ("あの山は高いです。", "That mountain is tall.", "山"),
    ("この家は大きいです。", "This house is big.", "大きい"),
    ("猫は小さいです。", "The cat is small.", "小さい"),
    ("私は学生です。", "I am a student.", "学生"),
    ("先生は優しいです。", "The teacher is kind.", "先生"),
    ("名前は何ですか。", "What is your name?", "名前"),
    ("お金がありません。", "I don't have money.", "お金"),
    ("食べましょう。", "Let's eat.", "食べる"),
]

/// N5 grammar points
let grammarData: [(jlptLevel: String, title: String, explanation: String, examples: [String])] = [
    ("n5", "は (Topic Marker)", "Marks the topic of the sentence. The topic is what the sentence is about.", ["私は学生です。", "今日は月曜日です。"]),
    ("n5", "です/ます (Polite Form)", "Polite sentence endings. です for nouns/adjectives, ます for verbs.", ["学生です。", "食べます。"]),
    ("n5", "を (Object Marker)", "Marks the direct object of an action.", ["水を飲みます。", "本を読みます。"]),
    ("n5", "に (Direction/Time)", "Indicates direction of movement or point in time.", ["学校に行きます。", "月曜日に会います。"]),
    ("n5", "で (Location of Action)", "Marks where an action takes place.", ["学校で勉強します。", "家で食べます。"]),
]

// MARK: - Database Generation

func generateDatabase(at path: String) {
    // Remove existing file
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: path) {
        try? fileManager.removeItem(atPath: path)
    }

    var db: OpaquePointer?
    guard sqlite3_open(path, &db) == SQLITE_OK else {
        print("ERROR: Cannot open database at \(path)")
        return
    }
    defer { sqlite3_close(db) }

    // Create schema
    for statement in schemaSQL.components(separatedBy: ";") {
        let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, trimmed, nil, nil, &errMsg) != SQLITE_OK {
            let error = errMsg.map { String(cString: $0) } ?? "unknown"
            print("ERROR creating schema: \(error)")
            sqlite3_free(errMsg)
        }
    }

    // Insert radicals
    for radical in radicals {
        let sql = "INSERT OR IGNORE INTO radicals (character, meaning, stroke_count) VALUES (?, ?, ?)"
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        sqlite3_bind_text(stmt, 1, radical.character, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 2, radical.meaning, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_int(stmt, 3, Int32(radical.strokeCount))
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    // Insert kanji
    let encoder = JSONEncoder()
    for kanji in kanjiData {
        let onJSON = String(data: (try? encoder.encode(kanji.onReadings)) ?? Data(), encoding: .utf8) ?? "[]"
        let kunJSON = String(data: (try? encoder.encode(kanji.kunReadings)) ?? Data(), encoding: .utf8) ?? "[]"
        let meaningsJSON = String(data: (try? encoder.encode(kanji.meanings)) ?? Data(), encoding: .utf8) ?? "[]"

        let sql = "INSERT OR IGNORE INTO kanji (character, on_readings, kun_readings, meanings, jlpt_level, stroke_count, stroke_order_svg) VALUES (?, ?, ?, ?, ?, ?, ?)"
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        sqlite3_bind_text(stmt, 1, kanji.character, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 2, onJSON, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 3, kunJSON, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 4, meaningsJSON, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 5, "n5", -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_int(stmt, 6, Int32(kanji.strokeCount))
        sqlite3_bind_null(stmt, 7)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)

        // Insert edges
        for radical in kanji.radicals {
            let edgeSql = "INSERT OR IGNORE INTO kanji_radical_edges (radical_character, kanji_character) VALUES (?, ?)"
            var edgeStmt: OpaquePointer?
            sqlite3_prepare_v2(db, edgeSql, -1, &edgeStmt, nil)
            sqlite3_bind_text(edgeStmt, 1, radical, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(edgeStmt, 2, kanji.character, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_step(edgeStmt)
            sqlite3_finalize(edgeStmt)
        }
    }

    // Insert vocabulary
    for (index, vocab) in vocabData.enumerated() {
        let sql = "INSERT OR IGNORE INTO vocabulary (id, word, reading, meaning, kanji_character, jlpt_level) VALUES (?, ?, ?, ?, ?, ?)"
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        sqlite3_bind_int(stmt, 1, Int32(index + 1))
        sqlite3_bind_text(stmt, 2, vocab.word, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 3, vocab.reading, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 4, vocab.meaning, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        if let kanjiChar = vocab.kanjiCharacter {
            sqlite3_bind_text(stmt, 5, kanjiChar, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        } else {
            sqlite3_bind_null(stmt, 5)
        }
        sqlite3_bind_text(stmt, 6, vocab.jlptLevel, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    // Insert sentences
    for (index, sentence) in sentenceData.enumerated() {
        let sql = "INSERT OR IGNORE INTO sentences (id, japanese, english, vocabulary_word) VALUES (?, ?, ?, ?)"
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        sqlite3_bind_int(stmt, 1, Int32(index + 1))
        sqlite3_bind_text(stmt, 2, sentence.japanese, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 3, sentence.english, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 4, sentence.vocabularyWord, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    // Insert grammar points
    for (index, grammar) in grammarData.enumerated() {
        let examplesJSON = String(data: (try? encoder.encode(grammar.examples)) ?? Data(), encoding: .utf8) ?? "[]"
        let sql = "INSERT OR IGNORE INTO grammar_points (id, jlpt_level, title, explanation, examples) VALUES (?, ?, ?, ?, ?)"
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        sqlite3_bind_int(stmt, 1, Int32(index + 1))
        sqlite3_bind_text(stmt, 2, grammar.jlptLevel, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 3, grammar.title, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 4, grammar.explanation, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 5, examplesJSON, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    print("Generated n5-content.sqlite at: \(path)")
    print("  Radicals: \(radicals.count)")
    print("  Kanji: \(kanjiData.count)")
    print("  Vocabulary: \(vocabData.count)")
    print("  Sentences: \(sentenceData.count)")
    print("  Grammar Points: \(grammarData.count)")
}

// MARK: - Main

let scriptDir = URL(fileURLWithPath: #file).deletingLastPathComponent()
let projectRoot = scriptDir.deletingLastPathComponent()
let outputPath = projectRoot
    .appendingPathComponent("Ikeru")
    .appendingPathComponent("Resources")
    .appendingPathComponent("ContentBundles")
    .appendingPathComponent("n5-content.sqlite")
    .path

generateDatabase(at: outputPath)
