import os

extension Logger {
    private static let subsystem = "com.ikeru"

    /// SRS (Spaced Repetition System) operations
    public static let srs = Logger(subsystem: subsystem, category: "srs")

    /// AI-related operations (local models, prompts)
    public static let ai = Logger(subsystem: subsystem, category: "ai")

    /// Study planner and scheduling
    public static let planner = Logger(subsystem: subsystem, category: "planner")

    /// Data synchronization
    public static let sync = Logger(subsystem: subsystem, category: "sync")

    /// RPG game mechanics
    public static let rpg = Logger(subsystem: subsystem, category: "rpg")

    /// Content management (kanji, vocabulary)
    public static let content = Logger(subsystem: subsystem, category: "content")

    /// Audio playback and listening exercises
    public static let audio = Logger(subsystem: subsystem, category: "audio")

    /// UI events and navigation
    public static let ui = Logger(subsystem: subsystem, category: "ui")

    /// Companion chat operations
    public static let companion = Logger(subsystem: subsystem, category: "companion")

    /// Vocabulary dictionary and encounter tracking
    public static let vocabulary = Logger(subsystem: subsystem, category: "vocabulary")
}
