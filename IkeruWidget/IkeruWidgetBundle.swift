import WidgetKit
import SwiftUI

@main
struct IkeruWidgetBundle: WidgetBundle {
    var body: some Widget {
        IkeruWidget()
        SessionLiveActivity()
        StandByFlashcardWidget()
    }
}

struct IkeruWidget: Widget {
    let kind: String = "IkeruWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: IkeruTimelineProvider()) { entry in
            IkeruWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Ikeru")
        .description("Track your Japanese learning progress.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Timeline Provider

struct IkeruTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> IkeruWidgetEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (IkeruWidgetEntry) -> Void) {
        completion(IkeruWidgetEntry.current())
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<IkeruWidgetEntry>) -> Void) {
        let entry = IkeruWidgetEntry.current()
        let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600)))
        completion(timeline)
    }
}

// MARK: - Entry

struct IkeruWidgetEntry: TimelineEntry {
    let date: Date
    let dueCount: Int
    let level: Int

    /// Shown before the app has ever written a snapshot (fresh install, or
    /// the app-group container isn't reachable). Note: shows "Lv. 1" — the
    /// pre-channel widget had no level line at all, so this is a neutral
    /// default rather than a byte-identical recreation of the old look.
    static let placeholder = IkeruWidgetEntry(date: Date(), dueCount: 0, level: 1)

    /// Reads the app-group snapshot written by `WidgetSnapshotRefresher`,
    /// falling back to `placeholder` when nothing has been written yet.
    static func current() -> IkeruWidgetEntry {
        guard let snapshot = WidgetSnapshotStore.read() else { return .placeholder }
        return IkeruWidgetEntry(date: Date(), dueCount: snapshot.dueCount, level: snapshot.level)
    }
}

// MARK: - Widget View

struct IkeruWidgetEntryView: View {
    let entry: IkeruWidgetEntry

    /// The "%lld due" / "Study time!" / "Lv. %lld" text below resolve
    /// against Localizable.xcstrings exactly like the rest of the app, but
    /// the IkeruWidget target currently has NO Resources build phase at all
    /// (see CLAUDE.md and JOURNAL.md), so the catalog isn't embedded in the
    /// extension yet and this stays English-only until that pbxproj
    /// membership is added.
    var body: some View {
        VStack {
            Image(systemName: "book.fill")
                .font(.title)
            Text("Ikeru")
                .font(.headline)
            if entry.dueCount > 0 {
                Text("\(entry.dueCount) due")
                    .font(.caption)
            } else {
                Text("Study time!")
                    .font(.caption)
            }
            Text("Lv. \(entry.level)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .widgetURL(WidgetDeepLink.review)
    }
}
