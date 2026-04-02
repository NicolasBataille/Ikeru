import Testing
import os
@testable import IkeruCore

@Suite("Logger Categories")
struct LoggersTests {

    @Test("SRS logger exists and can log")
    func srsLogger() {
        // Verify logger can be accessed without crashing
        let logger = Logger.srs
        logger.debug("Test SRS log")
        // If we get here, the logger is functional
        #expect(true)
    }

    @Test("AI logger exists and can log")
    func aiLogger() {
        let logger = Logger.ai
        logger.debug("Test AI log")
        #expect(true)
    }

    @Test("Planner logger exists and can log")
    func plannerLogger() {
        let logger = Logger.planner
        logger.debug("Test planner log")
        #expect(true)
    }

    @Test("Sync logger exists and can log")
    func syncLogger() {
        let logger = Logger.sync
        logger.debug("Test sync log")
        #expect(true)
    }

    @Test("RPG logger exists and can log")
    func rpgLogger() {
        let logger = Logger.rpg
        logger.debug("Test RPG log")
        #expect(true)
    }

    @Test("Content logger exists and can log")
    func contentLogger() {
        let logger = Logger.content
        logger.debug("Test content log")
        #expect(true)
    }

    @Test("UI logger exists and can log")
    func uiLogger() {
        let logger = Logger.ui
        logger.debug("Test UI log")
        #expect(true)
    }
}
