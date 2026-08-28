import ActivityKit
import WidgetKit
import SwiftUI
import IkeruCore

// MARK: - Session Live Activity
//
// Text literals below ("+%lld XP", "🔥 %lld streak") resolve against
// Localizable.xcstrings the same way the rest of the app does, but the
// IkeruWidget target has no Resources build phase yet (see CLAUDE.md /
// JOURNAL.md), so the catalog isn't embedded and this stays English-only
// until that pbxproj membership is added.

struct SessionLiveActivity: Widget {
    let kind = "SessionLiveActivity"

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            // Lock Screen view
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded regions
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                            .font(.caption2)
                        Text(startDate(for: context.state), style: .timer)
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.white)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                        Text("+\(context.state.xpEarned) XP")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(IkeruPlatformTheme.gold)
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 4) {
                        Text(context.state.exerciseType)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        // Progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(.gray.opacity(0.3))
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(IkeruPlatformTheme.gold)
                                    .frame(width: geo.size.width * context.state.progressFraction)
                            }
                        }
                        .frame(height: 4)

                        Text(verbatim: "\(context.state.completedCount)/\(context.state.totalCount)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.streakCount > 2 {
                        Text("🔥 \(context.state.streakCount) streak")
                            .font(.caption2)
                            .foregroundStyle(IkeruPlatformTheme.gold)
                    }
                }
            } compactLeading: {
                // Compact: timer
                HStack(spacing: 2) {
                    Image(systemName: "timer")
                        .font(.system(size: 10))
                    Text(startDate(for: context.state), style: .timer)
                        .font(.system(size: 12, design: .monospaced))
                }
                .foregroundStyle(.white)
            } compactTrailing: {
                // Compact: streak count
                // `verbatim:` — un nombre suivi d'un emoji ne se
                // traduit pas, et la clé « %lld🔥 » n'aurait aucun
                // sens dans un catalogue.
                Text(verbatim: "\(context.state.streakCount)🔥")
                    .font(.system(size: 12))
            } minimal: {
                Image(systemName: "book.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(IkeruPlatformTheme.gold)
            }
        }
    }

    // MARK: - Lock Screen View

    private func lockScreenView(context: ActivityViewContext<SessionActivityAttributes>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.sessionTitle)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(context.state.exerciseType)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(startDate(for: context.state), style: .timer)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)

                Text(verbatim: "\(context.state.completedCount)/\(context.state.totalCount)")
                    .font(.caption)
                    .foregroundStyle(IkeruPlatformTheme.gold)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    /// Derives the session start date from the elapsed-seconds snapshot so the
    /// timer keeps ticking between content-state updates.
    private func startDate(for state: SessionActivityAttributes.ContentState) -> Date {
        Date(timeIntervalSinceNow: -TimeInterval(state.elapsedSeconds))
    }
}
