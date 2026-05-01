import SwiftUI
import SwiftData
import IkeruCore

// MARK: - CardReviewView

struct CardReviewView: View {

    @State private var viewModel: CardReviewViewModel
    @State private var hapticTriggerCorrect = false
    @State private var hapticTriggerIncorrect = false
    @State private var isRevealed = false

    init(cardRepository: CardRepository, vocabularyRepository: VocabularyRepository? = nil) {
        _viewModel = State(initialValue: CardReviewViewModel(
            cardRepository: cardRepository,
            vocabularyRepository: vocabularyRepository
        ))
    }

    var body: some View {
        ZStack {
            IkeruScreenBackground(variant: .session)
                .ignoresSafeArea()

            content
        }
        .sensoryFeedback(.success, trigger: hapticTriggerCorrect)
        .sensoryFeedback(.warning, trigger: hapticTriggerIncorrect)
        .task {
            await viewModel.loadDueCards()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            loadingView
        } else if viewModel.isSessionComplete {
            emptyStateView
        } else {
            reviewContent
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: IkeruTheme.Spacing.md) {
            ProgressView()
                .tint(Color.ikeruPrimaryAccent)
            Text("Loading cards...")
                .font(.ikeruBody)
                .foregroundStyle(.ikeruTextSecondary)
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: IkeruTheme.Spacing.lg) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.ikeruSuccess)

            Text("All caught up!")
                .font(.ikeruHeading1)
                .foregroundStyle(.white)

            Text("Great work! Come back later for more reviews.")
                .font(.ikeruBody)
                .foregroundStyle(.ikeruTextSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(IkeruTheme.Spacing.xl)
    }

    // MARK: - Review Content

    private var reviewContent: some View {
        VStack(spacing: IkeruTheme.Spacing.md) {
            // Header with remaining count and progress
            headerView

            Spacer()

            // Card with swipe gesture and feedback overlay
            if let card = viewModel.currentCard {
                cardWithFeedback(card: card)
            }

            Spacer()

            // Grade buttons only appear after the user has revealed the answer.
            if isRevealed {
                GradeButtonsView { grade in
                    Task {
                        triggerHaptic(for: grade)
                        await viewModel.gradeCard(grade: grade)
                    }
                }
                .padding(.horizontal, IkeruTheme.Spacing.md)
                .padding(.bottom, IkeruTheme.Spacing.md)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Button {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                        isRevealed = true
                    }
                } label: {
                    Text("Show answer")
                        .frame(maxWidth: .infinity)
                }
                .ikeruButtonStyle(.primary)
                .padding(.horizontal, IkeruTheme.Spacing.md)
                .padding(.bottom, IkeruTheme.Spacing.md)
                .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isRevealed)
        .onChange(of: viewModel.currentCard?.id) { _, _ in
            isRevealed = false
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: IkeruTheme.Spacing.xs) {
            Text("\(viewModel.remainingCount) cards remaining")
                .font(.ikeruCaption)
                .foregroundStyle(.ikeruTextSecondary)

            // Tatami fusuma rail: a 3px gold-dim base with a 1px live-progress
            // rail inset, glowing softly with the primary accent. Replaces the
            // earlier rounded `ProgressView` pill — Tatami is sharp-edged.
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(TatamiTokens.goldDim.opacity(0.3))
                    .frame(height: 3)
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.ikeruPrimaryAccent)
                        .frame(
                            width: geo.size.width * CGFloat(viewModel.sessionProgress),
                            height: 1
                        )
                        .shadow(color: Color.ikeruPrimaryAccent.opacity(0.6), radius: 6)
                }
                .frame(height: 3)
            }
            .padding(.horizontal, 22)
        }
        .padding(.top, IkeruTheme.Spacing.md)
    }

    // MARK: - Card With Feedback

    private func cardWithFeedback(card: CardDTO) -> some View {
        SRSCardView(
            card: card,
            upcomingCards: viewModel.upcomingCards,
            isRevealed: $isRevealed
        ) { direction in
            Task {
                triggerHaptic(for: direction.grade)
                await viewModel.gradeFromSwipe(direction: direction)
            }
        }
        .padding(.horizontal, IkeruTheme.Spacing.lg)
        .overlay {
            feedbackOverlay
        }
    }

    // MARK: - Feedback Overlay

    @ViewBuilder
    private var feedbackOverlay: some View {
        if let feedback = viewModel.feedbackState {
            RoundedRectangle(cornerRadius: IkeruTheme.Radius.md)
                .strokeBorder(feedback.color, lineWidth: 3)
                .padding(.horizontal, IkeruTheme.Spacing.lg)
                .transition(.opacity)
                .animation(.easeOut(duration: 0.3), value: viewModel.feedbackState)
        }
    }

    // MARK: - Haptic Triggers

    private func triggerHaptic(for grade: Grade) {
        let isCorrect = grade == .good || grade == .easy
        if isCorrect {
            hapticTriggerCorrect.toggle()
        } else {
            hapticTriggerIncorrect.toggle()
        }
    }
}

// MARK: - Preview

#Preview("CardReviewView") {
    // Preview requires a model container
    CardReviewView(
        cardRepository: {
            let schema = Schema([UserProfile.self, Card.self, ReviewLog.self, RPGState.self])
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            let container = try! ModelContainer(for: schema, configurations: [config])
            return CardRepository(modelContainer: container)
        }()
    )
    .preferredColorScheme(.dark)
}
