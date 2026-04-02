import WidgetKit
import SwiftUI

@main
struct IkeruWidgetBundle: WidgetBundle {
    var body: some Widget {
        IkeruWidget()
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
        IkeruWidgetEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (IkeruWidgetEntry) -> Void) {
        completion(IkeruWidgetEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<IkeruWidgetEntry>) -> Void) {
        let entry = IkeruWidgetEntry(date: Date())
        let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600)))
        completion(timeline)
    }
}

// MARK: - Entry

struct IkeruWidgetEntry: TimelineEntry {
    let date: Date
}

// MARK: - Widget View

struct IkeruWidgetEntryView: View {
    let entry: IkeruWidgetEntry

    var body: some View {
        VStack {
            Image(systemName: "book.fill")
                .font(.title)
            Text("Ikeru")
                .font(.headline)
            Text("Study time!")
                .font(.caption)
        }
    }
}
