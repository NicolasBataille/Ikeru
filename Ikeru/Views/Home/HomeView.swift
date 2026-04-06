import SwiftUI
import SwiftData
import IkeruCore
import os

// MARK: - HomeView

/// Premium "Your World" home screen.
/// Layout philosophy: generous breathing space, glass surfaces, calm typography.
struct HomeView: View {

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: HomeViewModel?
    @State private var sessionViewModel: SessionViewModel?
    @State private var showSession = false
    @State private var heroAppeared = false

    var body: some View {
        ZStack {
            IkeruScreenBackground()

            if let vm = viewModel {
                homeContent(vm)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showSession) {
            if let svm = sessionViewModel {
                ActiveSessionView(viewModel: svm)
                    .onChange(of: svm.isActive) { _, isActive in
                        if !isActive {
                            showSession = false
                        }
                    }
            }
        }
        .task {
            initializeViewModels()
            await viewModel?.loadData()
            withAnimation(.spring(response: 0.55, dampingFraction: 0.86).delay(0.05)) {
                heroAppeared = true
            }
            if CommandLine.arguments.contains("-autoStartSession") {
                startSession()
            }
        }
        .onAppear {
            if viewModel != nil {
                Task { await viewModel?.loadData() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .startQuizFromShortcut)) { _ in
            initializeViewModels()
            startSession()
        }
        .onReceive(NotificationCenter.default.publisher(for: .startReviewFromShortcut)) { _ in
            initializeViewModels()
            startSession()
        }
    }

    // MARK: - Home Content

    @ViewBuilder
    private func homeContent(_ vm: HomeViewModel) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: IkeruTheme.Spacing.xl) {
                topBar(vm)
                heroSection(vm)
                statsRow(vm)
                primaryAction(vm)
                if vm.hasLoaded && vm.dueCardCount == 0 {
                    quietState
                }
            }
            .padding(.horizontal, IkeruTheme.Spacing.lg)
            .padding(.top, IkeruTheme.Spacing.md)
            .padding(.bottom, 140) // Space for floating tab bar
            .opacity(heroAppeared ? 1 : 0)
            .offset(y: heroAppeared ? 0 : 16)
        }
    }

    // MARK: - Quiet state (when no cards due)

    private var quietState: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.ikeruSuccess)
            Text("All caught up — enjoy the calm")
                .font(.ikeruCaption)
                .foregroundStyle(Color.ikeruTextTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            Capsule().fill(.ultraThinMaterial)
        }
        .overlay(
            Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.6)
        )
    }

    // MARK: - Top Bar

    @ViewBuilder
    private func topBar(_ vm: HomeViewModel) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(timeOfDayGreeting().uppercased())
                    .font(.ikeruMicro)
                    .ikeruTracking(.micro)
                    .foregroundStyle(Color.ikeruTextTertiary)

                Text(vm.displayName.isEmpty ? "Welcome" : vm.displayName)
                    .font(.ikeruDisplaySmall)
                    .ikeruTracking(.display)
                    .foregroundStyle(Color.ikeruTextPrimary)
            }
            Spacer()
            // Streak / status pill
            IkeruStatPill(
                icon: "flame.fill",
                value: "\(max(1, vm.level))",
                label: "lvl",
                tint: .ikeruPrimaryAccent
            )
        }
        .padding(.top, IkeruTheme.Spacing.xs)
    }

    // MARK: - Hero

    @ViewBuilder
    private func heroSection(_ vm: HomeViewModel) -> some View {
        MeshHeroView(
            level: vm.level,
            totalXP: vm.xp,
            displayName: vm.displayName,
            recentAchievement: vm.recentAchievement
        )
        .frame(height: 260)
    }

    // MARK: - Stats Row

    @ViewBuilder
    private func statsRow(_ vm: HomeViewModel) -> some View {
        HStack(spacing: IkeruTheme.Spacing.sm) {
            statCard(
                icon: "tray.full",
                value: "\(vm.dueCardCount)",
                label: "Due",
                tint: .ikeruPrimaryAccent
            )
            statCard(
                icon: "character.book.closed",
                value: "\(vm.kanjiLearnedCount)",
                label: "Learned",
                tint: .ikeruTertiaryAccent
            )
            statCard(
                icon: "shippingbox",
                value: "\(vm.unopenedLootBoxCount)",
                label: "Lootboxes",
                tint: .ikeruSecondaryAccent
            )
        }
    }

    @ViewBuilder
    private func statCard(icon: String, value: String, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Icon in a small tinted circle
            ZStack {
                Circle()
                    .fill(tint.opacity(0.14))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 32, weight: .light, design: .default))
                    .ikeruTracking(.heading)
                    .foregroundStyle(Color.ikeruTextPrimary)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: value)

                Text(label.uppercased())
                    .font(.ikeruMicro)
                    .ikeruTracking(.micro)
                    .foregroundStyle(Color.ikeruTextTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, IkeruTheme.Spacing.md)
        .padding(.horizontal, IkeruTheme.Spacing.md)
        .background {
            IkeruGlassSurface(
                cornerRadius: IkeruTheme.Radius.lg,
                tint: tint,
                tintOpacity: 0.04,
                highlight: 0.14,
                strokeOpacity: 0.16
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: IkeruTheme.Radius.lg, style: .continuous))
        .shadow(color: Color.black.opacity(0.4), radius: 18, y: 8)
    }

    // MARK: - Primary action

    @ViewBuilder
    private func primaryAction(_ vm: HomeViewModel) -> some View {
        VStack(spacing: IkeruTheme.Spacing.sm) {
            Button {
                startSession()
            } label: {
                HStack(spacing: IkeruTheme.Spacing.sm) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Begin Session")
                }
                .frame(maxWidth: .infinity)
            }
            .ikeruButtonStyle(.primary)

            Text(vm.sessionPreviewText)
                .font(.ikeruCaption)
                .foregroundStyle(Color.ikeruTextTertiary)
        }
        .padding(.top, IkeruTheme.Spacing.xs)
    }

    // MARK: - Helpers

    private func timeOfDayGreeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Good night"
        }
    }

    private func initializeViewModels() {
        guard viewModel == nil else { return }
        let container = modelContext.container

        viewModel = HomeViewModel(modelContainer: container)

        let repo = CardRepository(modelContainer: container)
        let planner = PlannerService(cardRepository: repo)
        sessionViewModel = SessionViewModel(
            plannerService: planner,
            cardRepository: repo,
            modelContainer: container
        )
    }

    private func startSession() {
        guard let svm = sessionViewModel else { return }
        Task {
            let container = modelContext.container
            let repo = CardRepository(modelContainer: container)
            let allCards = await repo.allCards()
            await ContentSeedService.seedBeginnerKanaIfNeeded(
                repository: repo,
                existingCardCount: allCards.count
            )
            await svm.startSession()
            showSession = true
        }
    }
}

// MARK: - Preview

#Preview("HomeView") {
    NavigationStack {
        HomeView()
    }
    .preferredColorScheme(.dark)
}
