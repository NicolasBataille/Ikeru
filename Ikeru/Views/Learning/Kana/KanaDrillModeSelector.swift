import SwiftUI
import IkeruCore

// MARK: - KanaDrillModeSelector

/// Intermediate screen between the pool selector and the actual drill view.
/// Lets the user choose between the deep-learning Flashcard mode and the
/// rapid 4-choice Quiz mode.
struct KanaDrillModeSelector: View {

    @Environment(\.modelContext) private var modelContext
    let mode: KanaDrillMode
    let cards: [CardDTO]

    @State private var goFlashcard = false
    @State private var goQuiz = false

    private var cardRepository: CardRepository {
        CardRepository(modelContainer: modelContext.container)
    }

    private var vocabularyRepository: VocabularyRepository {
        VocabularyRepository(modelContainer: modelContext.container)
    }

    var body: some View {
        ZStack {
            IkeruScreenBackground()

            VStack(alignment: .leading, spacing: IkeruTheme.Spacing.lg) {
                header
                modeCard(
                    title: "Flashcard",
                    subtitle: "Classic SRS review",
                    description: "Tap to reveal the answer, then grade your recall. Ideal for long-term retention.",
                    icon: "rectangle.on.rectangle.angled",
                    action: { goFlashcard = true }
                )
                modeCard(
                    title: "Quiz",
                    subtitle: "4 quick choices",
                    description: "Recognise the romaji among 4 options. Bonus for quick correct answers.",
                    icon: "checkmark.circle.badge.questionmark",
                    action: { goQuiz = true }
                )
                Spacer()
            }
            .padding(IkeruTheme.Spacing.lg)
            .padding(.bottom, 88) // Floating tab bar clearance
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Mode")
        .navigationDestination(isPresented: $goFlashcard) {
            KanaFlashcardView(viewModel: KanaDrillViewModel(
                mode: mode,
                queue: cards,
                cardRepository: cardRepository,
                vocabularyRepository: vocabularyRepository
            ))
        }
        .navigationDestination(isPresented: $goQuiz) {
            KanaQuizView(viewModel: KanaDrillViewModel(
                mode: mode,
                queue: cards,
                cardRepository: cardRepository,
                vocabularyRepository: vocabularyRepository
            ))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TRAINING MODE")
                .font(.ikeruMicro)
                .ikeruTracking(.micro)
                .foregroundStyle(Color.ikeruTextTertiary)
            Text(mode.displayName)
                .font(.ikeruDisplaySmall)
                .ikeruTracking(.display)
                .foregroundStyle(Color.ikeruTextPrimary)
            Text("\(cards.count) cards ready")
                .font(.ikeruCaption)
                .foregroundStyle(Color.ikeruTextSecondary)
        }
    }

    @ViewBuilder
    private func modeCard(
        title: String,
        subtitle: String,
        description: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: IkeruTheme.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Color.ikeruPrimaryAccent)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.ikeruHeading2)
                        .ikeruTracking(.heading)
                        .foregroundStyle(Color.ikeruTextPrimary)
                    Text(subtitle)
                        .font(.ikeruMicro)
                        .ikeruTracking(.micro)
                        .foregroundStyle(Color.ikeruPrimaryAccent)
                    Text(description)
                        .font(.ikeruCaption)
                        .foregroundStyle(Color.ikeruTextSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .ikeruCard(.interactive)
        .disabled(cards.isEmpty)
        .opacity(cards.isEmpty ? 0.5 : 1.0)
    }
}
