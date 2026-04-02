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

    /// UI events and navigation
    public static let ui = Logger(subsystem: subsystem, category: "ui")
}
