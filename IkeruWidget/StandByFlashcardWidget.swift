import WidgetKit
import SwiftUI
import IkeruCore

// MARK: - StandBy Flashcard Widget

/// Widget for StandBy mode that cycles through flashcards.
/// Shows a single large kanji with its reading, cycling every 10 seconds.
struct StandByFlashcardWidget: Widget {
    let kind = "StandByFlashcard"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FlashcardTimelineProvider()) { entry in
            StandByFlashcardView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Japanese Flashcard")
        .description("Learn kanji in StandBy mode.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Entry

struct FlashcardEntry: TimelineEntry {
    let date: Date
    let character: String
    let reading: String
    let meaning: String
}

// MARK: - Timeline Provider

struct FlashcardTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> FlashcardEntry {
        FlashcardEntry(date: .now, character: "漢", reading: "かん", meaning: "Sino-, Chinese")
    }

    func getSnapshot(in context: Context, completion: @escaping (FlashcardEntry) -> Void) {
        let entry = FlashcardEntry(
            date: .now,
            character: "日", reading: "にち", meaning: "Day, Sun"
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FlashcardEntry>) -> Void) {
        // Generate entries cycling every 10 seconds for StandBy
        let flashcards: [(character: String, reading: String, meaning: String)] = [
            ("日", "にち", "Day, Sun"),
            ("月", "げつ", "Moon, Month"),
            ("火", "か", "Fire"),
            ("水", "すい", "Water"),
            ("木", "もく", "Tree, Wood"),
            ("金", "きん", "Gold, Metal"),
            ("土", "ど", "Earth, Soil"),
            ("山", "さん", "Mountain"),
            ("川", "かわ", "River"),
            ("人", "じん", "Person"),
            ("大", "だい", "Large"),
            ("小", "しょう", "Small"),
        ]

        var entries: [FlashcardEntry] = []
        let now = Date()

        for (index, card) in flashcards.enumerated() {
            let entryDate = now.addingTimeInterval(Double(index) * 10)
            entries.append(FlashcardEntry(
                date: entryDate,
                character: card.character,
                reading: card.reading,
                meaning: card.meaning
            ))
        }

        let timeline = Timeline(entries: entries, policy: .after(
            now.addingTimeInterval(Double(flashcards.count) * 10)
        ))
        completion(timeline)
    }
}

// MARK: - StandBy View

struct StandByFlashcardView: View {
    let entry: FlashcardEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        VStack(spacing: family == .systemLarge ? 16 : 8) {
            // Large kanji character
            Text(entry.character)
                .font(.system(size: family == .systemLarge ? 80 : 48, weight: .bold))
                .foregroundStyle(.white)

            // Reading in hiragana
            Text(entry.reading)
                .font(.system(size: family == .systemLarge ? 24 : 16))
                .foregroundStyle(.orange)

            // Meaning
            Text(entry.meaning)
                .font(.system(size: family == .systemLarge ? 16 : 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview("StandBy Large", as: .systemLarge) {
    StandByFlashcardWidget()
} timeline: {
    FlashcardEntry(date: .now, character: "日", reading: "にち", meaning: "Day, Sun")
    FlashcardEntry(date: .now, character: "月", reading: "げつ", meaning: "Moon, Month")
}
