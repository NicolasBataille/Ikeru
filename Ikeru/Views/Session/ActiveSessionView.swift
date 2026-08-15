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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.toastManager) private var toastManager
    @State private var showPauseOverlay = false
    @State private var hapticTriggerCorrect = false
    @State private var hapticTriggerIncorrect = false
    @State private var dragOffset: CGFloat = 0
    @State private var showOneMinuteToast = false
    @State private var showSwipeTutorial = false

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

            // First-run coach-mark teaching the four card swipe directions.
            if showSwipeTutorial {
                SwipeTutorialView(onDismiss: dismissSwipeTutorial)
                    .transition(.opacity)
                    .zIndex(20)
            }

            // Level-up celebration — sits above everything else in this
            // ZStack (drawn last), including the pause/abandon overlays.
            if let level = viewModel.levelUpLevel {
                LevelUpView(level: level) {
                    viewModel.clearLevelUp()
                }
                .transition(.opacity)
                .zIndex(30)
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear { maybeShowSwipeTutorial() }
        .onChange(of: viewModel.currentCard?.id) { _, _ in maybeShowSwipeTutorial() }
        .animation(.easeInOut(duration: 0.3), value: showSwipeTutorial)
        .animation(.easeInOut(duration: 0.25), value: viewModel.levelUpLevel)
        .sensoryFeedback(.success, trigger: hapticTriggerCorrect)
        .sensoryFeedback(.warning, trigger: hapticTriggerIncorrect)
        .animation(
            .spring(response: 0.38, dampingFraction: 0.82),
            value: viewModel.showAbandonConfirmation
        )
        // XP-gain is otherwise silent to VoiceOver (no dedicated visual
        // toast exists yet) — announce it directly, following ToastView's
        // pattern. Cleared right after so the next identical award (same
        // XP amount twice in a row) still triggers a fresh announcement.
        // On a level-up rep both lastXPGained and levelUpLevel are set in the
        // same grading call — skip the XP announcement then so it doesn't
        // collide with LevelUpView's own (more important) announcement.
        .onChange(of: viewModel.lastXPGained) { _, xp in
            guard let xp else { return }
            defer { viewModel.clearXPGain() }
            guard viewModel.levelUpLevel == nil else { return }
            let format = String(localized: "+%@ XP")
            AccessibilityNotification.Announcement(String(format: format, "\(xp)")).post()
        }
        // Pause the session timer when the app moves to background or becomes
        // inactive so background time is not counted toward session duration.
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background, .inactive:
                viewModel.suspendTimer()
            case .active:
                viewModel.resumeTimer()
            @unknown default:
                break
            }
        }
        // Persistence-failure warning: a grade whose save failed may not count
        // toward scheduling. Local `.toastOverlay()` is required — the root
        // overlay in IkeruApp sits below this fullScreenCover.
        .onChange(of: viewModel.gradeSaveFailureCount) { _, count in
            guard count > 0 else { return }
            toastManager.showError(
                String(localized: "Couldn't save your review — it may not count.")
            )
        }
        .toastOverlay()
        .overlay(alignment: .top) {
            if showOneMinuteToast {
                Text(
                    "Session.OneMinuteRemaining",
                    comment: "Toast shown 60s before time budget ends the session"
                )
                .ikeruScaledFont(12, weight: .medium, relativeTo: .caption2)
                .foregroundStyle(Color.ikeruTextPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .tatamiRoom(.glass, padding: 0)
                .padding(.top, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onChange(of: viewModel.oneMinuteRemainingFired) { _, fired in
            guard fired else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                showOneMinuteToast = true
            }
            Task {
                try? await Task.sleep(for: .seconds(3))
                withAnimation(.easeInOut(duration: 0.25)) {
                    showOneMinuteToast = false
                }
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
                        .ikeruScaledFont(22, weight: .regular, design: .serif, relativeTo: .title2)
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
                        Task { await viewModel.endSession() }
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
            .frame(maxWidth: 360)
            .tatamiRoom(.glass, padding: IkeruTheme.Spacing.xl)
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
                onExerciseComplete: { grade in
                    Task {
                        triggerHaptic(for: grade)
                        await viewModel.completeCurrentExercise(grade: grade)
                    }
                },
                currentCard: viewModel.currentCard,
                upcomingCards: viewModel.upcomingCards,
                feedbackState: viewModel.feedbackState,
                vocabularyPool: viewModel.vocabularyPool,
                desiredRetention: viewModel.desiredRetention,
                isPresentingNewCard: viewModel.isPresentingNewCard,
                isPaused: viewModel.isPaused,
                onPresentationAcknowledged: {
                    Task { await viewModel.completeNewCardPresentation() }
                }
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
                .tatamiRoom(.glass, padding: 0)
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
        .tatamiRoom(.glass, padding: 0)
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

    // MARK: - Swipe Tutorial

    /// Shows the swipe coach-mark the first time this profile reaches a real
    /// SRS card (sessions are SRS-only after the rework).
    ///
    /// Gated on `!isPresentingNewCard`: a fresh profile's very first
    /// exercise can be a new-card presentation pass (no due reviews yet, all
    /// new kana) — that view has no swipe gesture at all, so the coach-mark
    /// would render over it and be dismissed/consumed before any swipeable
    /// card ever appears.
    private func maybeShowSwipeTutorial() {
        guard !showSwipeTutorial, viewModel.currentCard != nil, !viewModel.isPresentingNewCard else { return }
        guard let id = ActiveProfileResolver.activeProfileID() else { return }
        guard !OnboardingFlags.hasSeenSwipeTutorial(profileID: id) else { return }
        showSwipeTutorial = true
    }

    private func dismissSwipeTutorial() {
        if let id = ActiveProfileResolver.activeProfileID() {
            OnboardingFlags.markSwipeTutorialSeen(profileID: id)
        }
        showSwipeTutorial = false
    }
}

// MARK: - Preview

#Preview("ActiveSessionView") {
    let schema = Schema([UserProfile.self, Card.self, ReviewLog.self, RPGState.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)

    if let container = try? ModelContainer(for: schema, configurations: [config]) {
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
    } else {
        Text(verbatim: "Preview container unavailable")
    }
}
