import SwiftUI
import IkeruCore

/// 2-column grid of exercise types. `.sakuraConversation` is excluded
/// because it lives behind the Chat tab. 11 tiles total.
struct EtudeBrowseGrid: View {

    let snapshot: LearnerSnapshot
    let unlockService: any ExerciseUnlockService
    let onTap: (ExerciseType) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(ExerciseType.allCases.filter { $0 != .sakuraConversation }, id: \.self) { type in
                let state = unlockService.state(for: type, profile: snapshot)
                ExerciseTypeTile(type: type, state: state, onTap: { onTap(type) })
            }
        }
    }
}
