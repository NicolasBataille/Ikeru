import SwiftUI
import SwiftData
import IkeruCore
import os

// MARK: - HomeView

/// "Your World" home screen showing RPG status, learning summary, and session CTA.
struct HomeView: View {

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: HomeViewModel?
    @State private var sessionViewModel: SessionViewModel?
    @State private var showSession = false

    var body: some View {
        ZStack {
            Color.ikeruBackground
                .ignoresSafeArea()

            if let vm = viewModel {
                homeContent(vm)
            } else {
                // Brief loading placeholder (stays under 2s)
                Color.ikeruBackground.ignoresSafeArea()
            }
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
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
        }
        .onAppear {
            // Refresh data when returning from session or other tabs
            if viewModel != nil {
                Task {
                    await viewModel?.loadData()
                }
            }
        }
    }

    // MARK: - Home Content

    @ViewBuilder
    private func homeContent(_ vm: HomeViewModel) -> some View {
        ScrollView {
            VStack(spacing: IkeruTheme.Spacing.lg) {
                heroSection(vm)
                learningSummaryCard(vm)
                sessionCTASection(vm)
            }
            .padding(.horizontal, IkeruTheme.Spacing.md)
            .padding(.top, IkeruTheme.Spacing.xl)
            .padding(.bottom, IkeruTheme.Spacing.xxl)
        }
    }

    // MARK: - Hero Section

    @ViewBuilder
    private func heroSection(_ vm: HomeViewModel) -> some View {
        MeshHeroView(
            level: vm.level,
            totalXP: vm.xp,
            displayName: vm.displayName,
            recentAchievement: vm.recentAchievement
        )
    }

    // MARK: - Learning Summary Card

    @ViewBuilder
    private func learningSummaryCard(_ vm: HomeViewModel) -> some View {
        VStack(spacing: IkeruTheme.Spacing.sm) {
            HStack {
                Image(systemName: "book.fill")
                    .foregroundStyle(Color.ikeruPrimaryAccent)

                Text("Learning")
                    .font(.ikeruHeading3)
                    .foregroundStyle(.white)

                Spacer()
            }

            HStack {
                Text(vm.learningSummaryText)
                    .font(.ikeruBody)
                    .foregroundStyle(.ikeruTextSecondary)

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ikeruCard(.standard)
    }

    // MARK: - Session CTA

    @ViewBuilder
    private func sessionCTASection(_ vm: HomeViewModel) -> some View {
        VStack(spacing: IkeruTheme.Spacing.md) {
            Button {
                startSession()
            } label: {
                HStack(spacing: IkeruTheme.Spacing.sm) {
                    Image(systemName: "play.fill")
                    Text("Start Session")
                }
                .frame(maxWidth: .infinity)
            }
            .ikeruButtonStyle(.primary)

            // Session preview
            Text(vm.sessionPreviewText)
                .font(.ikeruCaption)
                .foregroundStyle(.ikeruTextSecondary)
        }
    }

    // MARK: - Helpers

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
            // Seed content if needed
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
