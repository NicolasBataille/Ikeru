import SwiftUI
import SwiftData
import IkeruCore
import os

// MARK: - ActiveSessionView

/// Full-screen immersive session view that presents cards sequentially.
/// Presented as .fullScreenCover to hide the tab bar.
struct ActiveSessionView: View {

    var viewModel: SessionViewModel
    @State private var showPauseSheet = false
    @State private var hapticTriggerCorrect = false
    @State private var hapticTriggerIncorrect = false
    @State private var timerTick: Int = 0

    /// Timer to update elapsed time display.
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.ikeruBackground
                .ignoresSafeArea()

            if viewModel.isSessionComplete {
                SessionSummaryView(viewModel: viewModel)
            } else {
                sessionContent
            }
        }
        .sensoryFeedback(.success, trigger: hapticTriggerCorrect)
        .sensoryFeedback(.warning, trigger: hapticTriggerIncorrect)
        .gesture(pauseSwipeGesture)
        .sheet(isPresented: $showPauseSheet) {
            PauseSheetView(
                onResume: {
                    showPauseSheet = false
                    viewModel.resumeSession()
                },
                onEndSession: {
                    showPauseSheet = false
                    viewModel.endSession()
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .onReceive(timer) { _ in
            if viewModel.isActive && !viewModel.isPaused {
                timerTick += 1
            }
        }
    }

    // MARK: - Session Content

    private var sessionContent: some View {
        VStack(spacing: 0) {
            // Progress bar at top
            SessionProgressBar(
                progress: viewModel.sessionProgress,
                exerciseCountText: "\(viewModel.currentIndex + 1)/\(viewModel.sessionQueue.count)",
                elapsedTime: viewModel.elapsedTimeFormatted
            )
            .padding(.top, IkeruTheme.Spacing.sm)

            Spacer()

            // Current card with swipe gestures
            if let card = viewModel.currentCard {
                cardWithFeedback(card: card)
            }

            Spacer()

            // Grade buttons fallback
            GradeButtonsView { grade in
                Task {
                    triggerHaptic(for: grade)
                    await viewModel.gradeAndAdvance(grade: grade)
                }
            }
            .padding(.horizontal, IkeruTheme.Spacing.md)
            .padding(.bottom, IkeruTheme.Spacing.md)
        }
    }

    // MARK: - Card With Feedback

    private func cardWithFeedback(card: CardDTO) -> some View {
        SRSCardView(
            card: card,
            nextCard: viewModel.nextCard
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

    // MARK: - Pause Swipe Gesture

    private var pauseSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 80)
            .onEnded { value in
                // Only trigger on a dominant downward swipe from near the top
                let isDownward = value.translation.height > 100
                let isVerticalDominant = abs(value.translation.height) > abs(value.translation.width) * 1.5
                let startedNearTop = value.startLocation.y < 150

                if isDownward && isVerticalDominant && startedNearTop {
                    viewModel.pauseSession()
                    showPauseSheet = true
                }
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

// MARK: - Pause Sheet View

private struct PauseSheetView: View {

    let onResume: () -> Void
    let onEndSession: () -> Void

    var body: some View {
        ZStack {
            Color.ikeruBackground
                .ignoresSafeArea()

            VStack(spacing: IkeruTheme.Spacing.xl) {
                Spacer()

                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(Color.ikeruPrimaryAccent)

                Text("Session Paused")
                    .font(.ikeruHeading1)
                    .foregroundStyle(.white)

                Spacer()

                VStack(spacing: IkeruTheme.Spacing.md) {
                    Button("Resume") {
                        onResume()
                    }
                    .ikeruButtonStyle(.primary)
                    .frame(maxWidth: .infinity)

                    Button("End Session") {
                        onEndSession()
                    }
                    .ikeruButtonStyle(.danger)
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, IkeruTheme.Spacing.lg)
                .padding(.bottom, IkeruTheme.Spacing.xl)
            }
        }
    }
}

// MARK: - Preview

#Preview("ActiveSessionView") {
    let schema = Schema([UserProfile.self, Card.self, ReviewLog.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    let repo = CardRepository(modelContainer: container)
    let planner = PlannerService(cardRepository: repo)
    let viewModel = SessionViewModel(plannerService: planner, cardRepository: repo)

    ActiveSessionView(viewModel: viewModel)
        .preferredColorScheme(.dark)
        .task {
            await viewModel.startSession()
        }
}
