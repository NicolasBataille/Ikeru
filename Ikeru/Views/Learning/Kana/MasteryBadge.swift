import SwiftUI
import IkeruCore

/// Tiny visual indicator for a `MasteryLevel`: emoji with optional label.
struct MasteryBadge: View {

    let level: MasteryLevel
    var showLabel: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            Text(level.emoji)
                .font(.system(size: 11))
            if showLabel {
                Text(level.label)
                    .font(.ikeruMicro)
                    .ikeruTracking(.micro)
                    .foregroundStyle(Color.ikeruTextSecondary)
            }
        }
    }
}

#Preview("MasteryBadge") {
    VStack(spacing: 8) {
        ForEach(MasteryLevel.allCases, id: \.self) { level in
            MasteryBadge(level: level, showLabel: true)
        }
    }
    .padding()
    .background(Color.ikeruBackground)
    .preferredColorScheme(.dark)
}
