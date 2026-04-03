import SwiftUI
import WidgetKit

// MARK: - Progress Complication

/// Watch complication showing current level and due card count.
struct ProgressComplication: Widget {
    let kind = "com.ikeru.watch.progress"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ProgressTimelineProvider()) { entry in
            ProgressComplicationView(entry: entry)
        }
        .configurationDisplayName("Ikeru Progress")
        .description("Shows your level and due cards.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryInline,
            .accessoryRectangular,
        ])
    }
}

// MARK: - Timeline Entry

struct ProgressEntry: TimelineEntry {
    let date: Date
    let level: Int
    let dueCards: Int
}

// MARK: - Timeline Provider

struct ProgressTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> ProgressEntry {
        ProgressEntry(date: .now, level: 1, dueCards: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (ProgressEntry) -> Void) {
        let entry = ProgressEntry(
            date: .now,
            level: WatchSessionManager.shared.syncedLevel,
            dueCards: WatchSessionManager.shared.syncedDueCards
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ProgressEntry>) -> Void) {
        let entry = ProgressEntry(
            date: .now,
            level: WatchSessionManager.shared.syncedLevel,
            dueCards: WatchSessionManager.shared.syncedDueCards
        )
        // Refresh every 30 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Complication Views

struct ProgressComplicationView: View {
    let entry: ProgressEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryInline:
            inlineView
        case .accessoryRectangular:
            rectangularView
        default:
            circularView
        }
    }

    private var circularView: some View {
        VStack(spacing: 0) {
            Image(systemName: "shield.fill")
                .font(.system(size: 12))
            Text("Lv.\(entry.level)")
                .font(.system(size: 12, weight: .bold))
        }
    }

    private var inlineView: some View {
        Text("Lv.\(entry.level) · \(entry.dueCards) due")
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "shield.fill")
                    .font(.system(size: 10))
                Text("Level \(entry.level)")
                    .font(.system(size: 12, weight: .semibold))
            }
            Text("\(entry.dueCards) cards ready")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

#Preview("Circular", as: .accessoryCircular) {
    ProgressComplication()
} timeline: {
    ProgressEntry(date: .now, level: 5, dueCards: 12)
}

#Preview("Rectangular", as: .accessoryRectangular) {
    ProgressComplication()
} timeline: {
    ProgressEntry(date: .now, level: 5, dueCards: 12)
}
