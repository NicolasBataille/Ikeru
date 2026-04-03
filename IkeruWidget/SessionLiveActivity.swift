import ActivityKit
import WidgetKit
import SwiftUI
import IkeruCore

// MARK: - Session Live Activity

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
                        Text(formatTime(context.state.elapsedSeconds))
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
                    .foregroundStyle(.orange)
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
                                    .fill(.orange)
                                    .frame(width: geo.size.width * context.state.progressFraction)
                            }
                        }
                        .frame(height: 4)

                        Text("\(context.state.completedCount)/\(context.state.totalCount)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.streakCount > 2 {
                        Text("🔥 \(context.state.streakCount) streak")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            } compactLeading: {
                // Compact: timer
                HStack(spacing: 2) {
                    Image(systemName: "timer")
                        .font(.system(size: 10))
                    Text(formatTime(context.state.elapsedSeconds))
                        .font(.system(size: 12, design: .monospaced))
                }
                .foregroundStyle(.white)
            } compactTrailing: {
                // Compact: streak count
                Text("\(context.state.streakCount)🔥")
                    .font(.system(size: 12))
            } minimal: {
                Image(systemName: "book.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
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
                Text(formatTime(context.state.elapsedSeconds))
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)

                Text("\(context.state.completedCount)/\(context.state.totalCount)")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
