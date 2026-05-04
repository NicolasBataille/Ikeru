import SwiftUI
import IkeruCore
import SwiftData

// MARK: - EtudeView
//
// Practice library (Étude tab). Combines the JLPT-estimate hero on
// `tatamiRoom(.glass)`, the 11-tile `EtudeBrowseGrid`, and a Compose row
// that opens `CustomPlannerSheet` to feed the session planner.

struct EtudeView: View {

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: EtudeViewModel?
    @State private var showCompose = false
    @State private var snapshot: LearnerSnapshot = .empty
    @State private var unlockedTypes: Set<ExerciseType> = []
    @State private var sessionViewModel: SessionViewModel?
    @State private var showSession = false
    private let unlockService: any ExerciseUnlockService = DefaultExerciseUnlockService()

    var body: some View {
        ZStack {
            IkeruScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if let vm = viewModel { jlptHero(vm) }
                    BilingualLabel(japanese: "\u{7A3D}\u{53E4}\u{5834}", chrome: "Practice ground", mon: .asanoha)
                    EtudeBrowseGrid(
                        snapshot: snapshot,
                        unlockService: unlockService,
                        onTap: { type in viewModel?.startSingleSurface(type: type) }
                    )
                    composeRow
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 140)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await initialize() }
        .sheet(isPresented: $showCompose) {
            CustomPlannerSheet(unlockedTypes: unlockedTypes) { types, levels, duration in
                launchCustomSession(types: types, levels: levels, duration: duration)
            }
        }
        .fullScreenCover(isPresented: $showSession) {
            if let svm = sessionViewModel {
                ActiveSessionView(viewModel: svm)
                    .onChange(of: svm.isActive) { _, isActive in
                        if !isActive { showSession = false }
                    }
            }
        }
    }

    /// Composes a session via `SessionViewModel` from the Compose sheet's
    /// chosen types / levels / duration, then presents `ActiveSessionView`
    /// full-screen. Replaces the previous behaviour where Compose-submit
    /// only stored `lastComposedPlan` and never navigated.
    private func launchCustomSession(
        types: Set<ExerciseType>,
        levels: Set<JLPTLevel>,
        duration: Int
    ) {
        let container = modelContext.container
        if sessionViewModel == nil {
            let repo = CardRepository(modelContainer: container)
            let planner = PlannerService(cardRepository: repo)
            sessionViewModel = SessionViewModel(
                plannerService: planner,
                cardRepository: repo,
                modelContainer: container
            )
        }
        guard let svm = sessionViewModel else { return }
        Task {
            await svm.startStudyCustomSession(
                types: types,
                levels: levels,
                duration: duration
            )
            showSession = true
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            BilingualLabel(japanese: "\u{5B66}\u{7FD2}", chrome: "Study")
            Text("Etude.Title")
                .font(.system(size: 28, weight: .light, design: .serif))
                .foregroundStyle(Color.ikeruTextPrimary)
        }
    }

    @ViewBuilder
    private func jlptHero(_ vm: EtudeViewModel) -> some View {
        let level = vm.jlptEstimate.level
        let percent = Int(vm.jlptEstimate.masteryFraction * 100)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                BilingualLabel(japanese: "\u{63A8}\u{5B9A}", chrome: "JLPT estimate")
                Spacer()
                HankoStamp(kanji: level, size: 36)
            }
            HStack(alignment: .firstTextBaseline) {
                SerifNumeral(percent, size: 40)
                Text("%").foregroundStyle(TatamiTokens.paperGhost).tracking(1.4)
            }
        }
        .tatamiRoom(.glass, padding: 20)
    }

    private var composeRow: some View {
        Button { showCompose = true } label: {
            HStack {
                Text("\u{7DE8}\u{6210}") // 編成
                    .font(.system(size: 14, design: .serif))
                    .foregroundStyle(TatamiTokens.paperGhost)
                Text("Etude.Compose.Row")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.ikeruTextPrimary)
                Spacer()
                Text("\u{203A}").foregroundStyle(TatamiTokens.goldDim)
            }
            .padding(14)
            .overlay(Rectangle().strokeBorder(TatamiTokens.goldDim, lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }

    private func initialize() async {
        if viewModel == nil {
            viewModel = EtudeViewModel(modelContainer: modelContext.container)
        }
        await viewModel?.loadData()
        snapshot = await viewModel?.buildSnapshot() ?? .empty
        unlockedTypes = unlockService.unlockedTypes(profile: snapshot)
    }
}
