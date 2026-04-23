import SwiftUI
import SwiftData
import IkeruCore
import os

// MARK: - ActiveSessionView

/// Full-screen immersive session view with exercise transitions.
/// Hides the tab bar and status bar for complete immersion.
/// Supports swipe-down pause gesture and abandon confirmation.
struct ActiveSessionView: View {

    @Bindable var viewModel: SessionViewModel
    @State private var showPauseOverlay = false
    @State private var hapticTriggerCorrect = false
    @State private var hapticTriggerIncorrect = false
    @State private var xpGained: Int?
    @State private var levelUpLevel: Int?
    @State private var lootDrop: LootItem?
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            IkeruScreenBackground()

            if viewModel.isSessionComplete {
                SessionSummaryView(viewModel: viewModel)
            } else if viewModel.sessionExercises.isEmpty {
                emptySessionView
            } else {
                immersiveSessionContent
            }

            // Pause overlay
            if showPauseOverlay {
                pauseOverlay
            }

            // Abandon confirmation — custom app-styled sheet (replaces
            // generic iOS confirmationDialog).
            if viewModel.showAbandonConfirmation {
                abandonConfirmationOverlay
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .xpGainOverlay(xpGained: $xpGained)
        .levelUpOverlay(level: $levelUpLevel)
        .lootDropOverlay(item: $lootDrop)
        .sensoryFeedback(.success, trigger: hapticTriggerCorrect)
        .sensoryFeedback(.warning, trigger: hapticTriggerIncorrect)
        .animation(
            .spring(response: 0.38, dampingFraction: 0.82),
            value: viewModel.showAbandonConfirmation
        )
        .onChange(of: viewModel.lastXPGained) { _, newValue in
            if let xp = newValue {
                xpGained = xp
                viewModel.clearXPGain()
            }
        }
        .onChange(of: viewModel.levelUpLevel) { _, newValue in
            if let level = newValue {
                levelUpLevel = level
                viewModel.clearLevelUp()
            }
        }
        .onChange(of: viewModel.lastLootDrop?.id) { _, newValue in
            if newValue != nil, let drop = viewModel.lastLootDrop {
                lootDrop = drop
                viewModel.clearLootDrop()
            }
        }
    }

    // MARK: - Abandon Confirmation Overlay

    private var abandonConfirmationOverlay: some View {
        ZStack {
            // Scrim — tapping dismisses.
            Rectangle()
                .fill(Color.black.opacity(0.55))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.cancelAbandon()
                }
                .transition(.opacity)

            VStack(spacing: IkeruTheme.Spacing.lg) {
                VStack(spacing: IkeruTheme.Spacing.sm) {
                    Image(systemName: "arrow.uturn.left.circle")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(LinearGradient.ikeruGold)

                    Text("END SESSION")
                        .font(.ikeruMicro)
                        .ikeruTracking(.micro)
                        .foregroundStyle(Color.ikeruTextTertiary)

                    Text("Leave this session?")
                        .font(.ikeruHeading2)
                        .foregroundStyle(Color.ikeruTextPrimary)
                        .multilineTextAlignment(.center)

                    Text(viewModel.abandonProgressDescription)
                        .font(.ikeruBody)
                        .foregroundStyle(Color.ikeruTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, IkeruTheme.Spacing.sm)
                }
                .padding(.top, IkeruTheme.Spacing.md)

                VStack(spacing: IkeruTheme.Spacing.sm) {
                    Button {
                        viewModel.endSession()
                        showPauseOverlay = false
                    } label: {
                        Text("End Session")
                            .frame(maxWidth: .infinity)
                    }
                    .ikeruButtonStyle(.danger)

                    Button {
                        viewModel.cancelAbandon()
                    } label: {
                        Text("Keep Going")
                            .frame(maxWidth: .infinity)
                    }
                    .ikeruButtonStyle(.ghost)
                }
            }
            .padding(IkeruTheme.Spacing.xl)
            .frame(maxWidth: 360)
            .ikeruCard(.elevated)
            .padding(.horizontal, IkeruTheme.Spacing.lg)
            .transition(
                .scale(scale: 0.92).combined(with: .opacity)
            )
        }
    }

    // MARK: - Immersive Session Content

    private var immersiveSessionContent: some View {
        VStack(spacing: 0) {
            // Drag indicator pill + visible close button row.
            // The pause-swipe gesture exists but is invisible to first-time
            // users; the explicit X is the discoverable escape route.
            ZStack {
                dragIndicatorPill
                HStack {
                    Button {
                        viewModel.requestAbandon()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.ikeruTextSecondary)
                            .frame(width: 36, height: 36)
                            .background {
                                Circle().fill(.ultraThinMaterial)
                            }
                    }
                    .accessibilityLabel("End session")
                    Spacer()
                }
                .padding(.horizontal, IkeruTheme.Spacing.md)
            }
            .padding(.top, IkeruTheme.Spacing.xs)

            // Progress bar at top
            SessionProgressBar(
                exercises: viewModel.sessionExercises,
                currentIndex: viewModel.currentExerciseIndex,
                elapsedTime: viewModel.elapsedTime,
                estimatedTotalTime: viewModel.estimatedTotalTime
            )
            .padding(.top, IkeruTheme.Spacing.xs)

            // Compact XP bar below progress
            XPBarView(
                totalXP: viewModel.totalXP,
                level: viewModel.currentLevel,
                variant: .compact
            )
            .padding(.horizontal, IkeruTheme.Spacing.md)
            .padding(.top, IkeruTheme.Spacing.xs)

            // Exercise transition container
            ExerciseTransitionContainer(
                exercise: viewModel.currentExercise,
                onSwipeGrade: { direction in
                    Task {
                        triggerHaptic(for: direction.grade)
                        await viewModel.gradeFromSwipe(direction: direction)
                    }
                },
                onButtonGrade: { grade in
                    Task {
                        triggerHaptic(for: grade)
                        await viewModel.gradeAndAdvance(grade: grade)
                    }
                },
                currentCard: viewModel.currentCard,
                upcomingCards: viewModel.upcomingCards,
                feedbackState: viewModel.feedbackState
            )
            .frame(maxHeight: .infinity)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .simultaneousGesture(pauseSwipeGesture)
    }

    // MARK: - Drag Indicator Pill

    private var dragIndicatorPill: some View {
        Capsule()
            .fill(Color.white.opacity(0.18))
            .frame(width: 42, height: 4)
            .padding(.top, IkeruTheme.Spacing.sm)
    }

    // MARK: - Pause Overlay

    private var pauseOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: IkeruTheme.Spacing.xl) {
                Spacer()

                VStack(spacing: IkeruTheme.Spacing.lg) {
                    Image(systemName: "pause.circle")
                        .font(.system(size: 64, weight: .light))
                        .foregroundStyle(LinearGradient.ikeruGold)

                    VStack(spacing: 6) {
                        Text("PAUSED")
                            .font(.ikeruMicro)
                            .ikeruTracking(.micro)
                            .foregroundStyle(Color.ikeruTextTertiary)

                        Text("Session Paused")
                            .font(.ikeruDisplaySmall)
                            .ikeruTracking(.display)
                            .foregroundStyle(Color.ikeruTextPrimary)

                        Text(viewModel.abandonProgressDescription)
                            .font(.ikeruBody)
                            .foregroundStyle(Color.ikeruTextSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(IkeruTheme.Spacing.xl)
                .ikeruCard(.elevated)
                .padding(.horizontal, IkeruTheme.Spacing.lg)

                Spacer()

                VStack(spacing: IkeruTheme.Spacing.md) {
                    Button("Resume Session") {
                        resumeFromPause()
                    }
                    .ikeruButtonStyle(.primary)
                    .frame(maxWidth: .infinity)

                    Button("End Session") {
                        viewModel.requestAbandon()
                    }
                    .ikeruButtonStyle(.danger)
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, IkeruTheme.Spacing.lg)
                .padding(.bottom, IkeruTheme.Spacing.xl)
            }
        }
        .transition(
            .opacity.combined(with: .scale(scale: 0.96))
        )
    }

    // MARK: - Empty Session View

    private var emptySessionView: some View {
        VStack(spacing: IkeruTheme.Spacing.lg) {
            Image(systemName: "tray")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Color.ikeruTextTertiary)

            VStack(spacing: 6) {
                Text("ALL CLEAR")
                    .font(.ikeruMicro)
                    .ikeruTracking(.micro)
                    .foregroundStyle(Color.ikeruTextTertiary)
                Text("No exercises available")
                    .font(.ikeruHeading2)
                    .foregroundStyle(Color.ikeruTextPrimary)
                Text("Come back later when you have cards to review.")
                    .font(.ikeruBody)
                    .foregroundStyle(Color.ikeruTextSecondary)
                    .multilineTextAlignment(.center)
            }

            Button("Dismiss") {
                viewModel.dismissSession()
            }
            .ikeruButtonStyle(.primary)
            .padding(.top, IkeruTheme.Spacing.md)
        }
        .padding(IkeruTheme.Spacing.xl)
        .ikeruCard(.elevated)
        .padding(.horizontal, IkeruTheme.Spacing.lg)
    }

    // MARK: - Pause Swipe Gesture

    private var pauseSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 80)
            .onChanged { value in
                let isDownward = value.translation.height > 0
                let startedNearTop = value.startLocation.y < 150
                if isDownward && startedNearTop {
                    dragOffset = value.translation.height
                }
            }
            .onEnded { value in
                dragOffset = 0

                let isDownward = value.translation.height > 100
                let isVerticalDominant =
                    abs(value.translation.height) > abs(value.translation.width) * 1.5
                let startedNearTop = value.startLocation.y < 150

                if isDownward && isVerticalDominant && startedNearTop {
                    withAnimation(.spring(duration: IkeruTheme.Animation.standardDuration)) {
                        viewModel.pauseSession()
                        showPauseOverlay = true
                    }
                }
            }
    }

    // MARK: - Helpers

    private func resumeFromPause() {
        withAnimation(.spring(duration: IkeruTheme.Animation.standardDuration)) {
            showPauseOverlay = false
            viewModel.resumeSession()
        }
    }

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

#Preview("ActiveSessionView") {
    let schema = Schema([UserProfile.self, Card.self, ReviewLog.self, RPGState.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    let repo = CardRepository(modelContainer: container)
    let planner = PlannerService(cardRepository: repo)
    let viewModel = SessionViewModel(
        plannerService: planner,
        cardRepository: repo,
        modelContainer: container
    )

    ActiveSessionView(viewModel: viewModel)
        .preferredColorScheme(.dark)
        .task {
            await viewModel.startSession()
        }
}
