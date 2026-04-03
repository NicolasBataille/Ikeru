import SwiftUI
import SwiftData
import IkeruCore

// MARK: - LootBoxOpenView

/// Full-screen lootbox opening flow: challenge → reveal → dismiss.
/// Presented as a full-screen cover from the RPG profile or session summary.
struct LootBoxOpenView: View {

    let lootBox: LootBox
    var onComplete: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @State private var phase: Phase = .challenge
    @State private var revealItems: [LootItem] = []

    var body: some View {
        ZStack {
            Color.ikeruBackground
                .ignoresSafeArea()

            switch phase {
            case .challenge:
                LootBoxChallengeView(
                    lootBox: lootBox,
                    onComplete: { rewards in
                        revealItems = rewards
                        persistOpening()
                        phase = .reveal
                    },
                    onDismiss: {
                        onComplete?()
                    }
                )

            case .reveal:
                LootRevealView(
                    items: revealItems,
                    onDismiss: {
                        onComplete?()
                    }
                )
            }
        }
    }

    // MARK: - Persistence

    private func persistOpening() {
        let context = modelContext
        let descriptor = FetchDescriptor<RPGState>()
        guard let state = try? context.fetch(descriptor).first else { return }
        state.openLootBox(id: lootBox.id)
        try? context.save()
    }

    enum Phase {
        case challenge
        case reveal
    }
}

// MARK: - Preview

#Preview("LootBoxOpenView") {
    LootBoxOpenView(
        lootBox: LootBox(
            challengeType: .kanaBlitz,
            requiredScore: 3,
            rewards: [
                LootItem(category: .badge, rarity: .epic, name: "Dragon Scale", iconName: "shield.lefthalf.filled"),
            ]
        )
    )
    .preferredColorScheme(.dark)
}
