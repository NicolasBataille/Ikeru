import SwiftUI
import SwiftData
import IkeruCore

// MARK: - KanaPoolSelectorView

/// Screen where the user picks which kana groups to study, sees per-character
/// and per-group mastery, and launches one of three drill modes.
struct KanaPoolSelectorView: View {

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: KanaPoolViewModel?
    @State private var pendingMode: KanaDrillMode?
    @State private var pendingCards: [CardDTO] = []
    @State private var pendingGroups: Set<KanaGroup> = []
    /// Set only by the confusion-pair drills (chantier #24b) — see
    /// `launchConfusionCluster`. Reset to `nil` by the three main drill
    /// buttons so a prior cluster launch never leaks into a normal session.
    @State private var pendingCharacterFilter: Set<String>?
    @State private var pendingSessionLabel: LocalizedStringKey?
    @State private var showDrill = false
    @State private var showDrillModesExplainer = false

    // MARK: Sequencing guard (chantier #24c)

    @State private var pendingSequencingPreset: KanaPreset?
    @State private var showSequencingConfirmation = false

    /// When set, the selector runs as the first-run "study-set chooser" presented
    /// from Home: the bottom bar shows a single "Start learning these" button
    /// instead of the drill buttons. Confirming seeds the chosen groups + marks
    /// the study set, then invokes this closure (which dismisses back to Home).
    /// nil (the default) preserves the normal Explore behaviour.
    var onStudySetConfirmed: (() -> Void)? = nil

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: IkeruTheme.Spacing.sm),
        GridItem(.flexible(), spacing: IkeruTheme.Spacing.sm)
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            IkeruScreenBackground()

            if let vm = viewModel {
                content(vm)
                bottomBar(vm)
            }

            // One-time Sakura explainer for the three drill modes — the
            // bottom-bar buttons are three unexplained labels to a first-time
            // visitor (owner request, device pass 2026-07-19). Étude context
            // only: the first-run chooser sheet has a single confirm button.
            if showDrillModesExplainer {
                drillModesExplainerOverlay
                    .zIndex(10)
                    .transition(.opacity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            initializeIfNeeded()
            await viewModel?.loadMasteries()
            evaluateDrillModesExplainer()
        }
        .navigationDestination(isPresented: $showDrill) {
            if let mode = pendingMode {
                KanaDrillModeSelector(
                    mode: mode,
                    groups: pendingGroups,
                    cards: pendingCards,
                    characterFilter: pendingCharacterFilter,
                    sessionLabel: pendingSessionLabel
                )
            }
        }
        .confirmationDialog(
            "Kana.Sequencing.Title",
            isPresented: $showSequencingConfirmation,
            titleVisibility: .visible
        ) {
            Button {
                if let vm = viewModel {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        vm.applyPreset(.hiraganaBase)
                    }
                }
                pendingSequencingPreset = nil
            } label: {
                Text("Kana.Sequencing.SwitchToHiragana")
            }
            Button {
                if let vm = viewModel, let preset = pendingSequencingPreset {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        vm.applyPreset(preset)
                    }
                }
                pendingSequencingPreset = nil
            } label: {
                Text("Kana.Sequencing.ContinueAnyway")
            }
            Button("Cancel", role: .cancel) { pendingSequencingPreset = nil }
        } message: {
            Text("Kana.Sequencing.Message")
        }
    }

    // MARK: Drill-modes explainer (Sakura, one-time)

    private func evaluateDrillModesExplainer() {
        guard onStudySetConfirmed == nil,   // Étude context only
              let profileID = ActiveProfileResolver.activeProfileID(),
              !OnboardingFlags.hasSeenKanaDrillModesExplainer(profileID: profileID)
        else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            showDrillModesExplainer = true
        }
    }

    private func dismissDrillModesExplainer() {
        if let profileID = ActiveProfileResolver.activeProfileID() {
            OnboardingFlags.markKanaDrillModesExplainerSeen(profileID: profileID)
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            showDrillModesExplainer = false
        }
    }

    private var drillModesExplainerOverlay: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismissDrillModesExplainer() }

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 10) {
                    SakuraMark(size: 30)
                    Text(verbatim: "Sakura")
                        .ikeruScaledFont(12, weight: .bold, relativeTo: .caption2)
                        .tracking(1.5)
                        .foregroundStyle(Color.ikeruPrimaryAccent)
                    Spacer()
                }

                Text("KanaDrill.Modes.Title")
                    .ikeruScaledFont(20, weight: .semibold, relativeTo: .title3)
                    .foregroundStyle(Color.ikeruTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 10) {
                    Text("KanaDrill.Modes.Review")
                    Text("KanaDrill.Modes.Free")
                    Text("KanaDrill.Modes.Weak")
                }
                .ikeruScaledFont(15, relativeTo: .body)
                .foregroundStyle(Color.ikeruTextSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

                Button {
                    dismissDrillModesExplainer()
                } label: {
                    Text("Sakura.CaughtUp.Dismiss")
                        .frame(maxWidth: .infinity)
                }
                .ikeruButtonStyle(.primary)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.ikeruPrimaryAccent.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.45), radius: 24, y: 8)
            .padding(.horizontal, 28)
        }
    }

    // MARK: Init

    private func initializeIfNeeded() {
        guard viewModel == nil else { return }
        let cardRepo = CardRepository(modelContainer: modelContext.container)
        let kanaRepo = KanaCardRepository(cardRepository: cardRepo)
        viewModel = KanaPoolViewModel(repository: kanaRepo)
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ vm: KanaPoolViewModel) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: IkeruTheme.Spacing.lg) {
                header
                presetBar(vm)
                scriptSection(vm, script: .hiragana, title: "Hiragana")
                scriptSection(vm, script: .katakana, title: "Katakana")
                confusionPairsSection(vm)
                Spacer(minLength: 200)
            }
            .padding(.horizontal, IkeruTheme.Spacing.lg)
            .padding(.top, IkeruTheme.Spacing.md)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LEARNING")
                .font(.ikeruMicro)
                .ikeruTracking(.micro)
                .foregroundStyle(Color.ikeruTextTertiary)
            Text("Kana Training")
                .font(.ikeruDisplaySmall)
                .ikeruTracking(.display)
                .foregroundStyle(Color.ikeruTextPrimary)
            Text("Select groups to study")
                .font(.ikeruCaption)
                .foregroundStyle(Color.ikeruTextSecondary)
        }
    }

    // MARK: Presets
    //
    // This row is presets (quick selections), not tabs — a real trap for a
    // first-time visitor because a scrollable chip row that ends flush with
    // the screen edge reads as complete. An expert playtest spent five
    // minutes convinced this was a broken segmented control before
    // discovering "All"/"Clear" only by accidentally scrolling (chantier
    // #24 affordance fix). Two independent, low-risk cues instead of a
    // full relayout: the native scroll indicator (previously hidden) plus a
    // trailing fade that visibly cuts the last chip whenever more content
    // sits off-screen to the right.

    @ViewBuilder
    private func presetBar(_ vm: KanaPoolViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(spacing: 8) {
                ForEach(KanaPreset.allCases) { preset in
                    Button {
                        applyPresetRespectingSequencing(vm, preset: preset)
                    } label: {
                        Text(LocalizedStringKey(preset.displayName))
                            .font(.ikeruCaption)
                            .foregroundStyle(Color.ikeruTextPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial)
                            .overlay(Rectangle().strokeBorder(TatamiTokens.goldDim.opacity(0.5), lineWidth: 1))
                            .sumiCorners(color: TatamiTokens.goldDim, size: 6, weight: 1.1)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        vm.clearSelection()
                    }
                } label: {
                    Text("Clear")
                        .font(.ikeruCaption)
                        .foregroundStyle(Color.ikeruTextSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.ikeruSurface.opacity(0.3))
                        .overlay(Rectangle().strokeBorder(TatamiTokens.goldDim.opacity(0.25), lineWidth: 0.8))
                        .sumiCorners(color: TatamiTokens.goldDim.opacity(0.5), size: 5, weight: 0.9)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 2)
            // Trailing padding must be ≥ the fade's width below (28pt) so
            // "Clear" fully clears the gradient once the row is scrolled all
            // the way — otherwise the fade would still be dimming the last
            // chip at rest, standing in as a false "more content" cue.
            .padding(.trailing, 32)
        }
        .overlay(alignment: .trailing) {
            LinearGradient(
                colors: [Color.ikeruBackground.opacity(0), Color.ikeruBackground.opacity(0.85)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 28)
            .allowsHitTesting(false)
        }
    }

    /// Applies `preset` directly, unless it would introduce katakana before
    /// the learner has made real progress on hiragana — then it stashes the
    /// preset and asks first (chantier #24c).
    private func applyPresetRespectingSequencing(_ vm: KanaPoolViewModel, preset: KanaPreset) {
        guard vm.presetNeedsSequencingConfirmation(preset) else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                vm.applyPreset(preset)
            }
            return
        }
        pendingSequencingPreset = preset
        showSequencingConfirmation = true
    }

    // MARK: Script Sections

    @ViewBuilder
    private func scriptSection(_ vm: KanaPoolViewModel, script: KanaScript, title: String) -> some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
            IkeruSectionHeader(title: title, eyebrow: scriptEyebrow(script))
            subSection(
                vm, script: script, section: .base,
                title: "Base (gojūon)",
                description: "The 46 core sounds in the classic table: five vowels, then consonant + vowel rows."
            )
            subSection(
                vm, script: script, section: .dakuten,
                title: "Dakuten (voiced)",
                description: "Same signs, softened by a mark: ゛voices the consonant (か ka → が ga), ゜turns h into p (は ha → ぱ pa)."
            )
            subSection(
                vm, script: script, section: .combined,
                title: "Combined (yōon)",
                description: "A consonant kana + small ゃ・ゅ・ょ merge into one syllable: き + ゃ = きゃ kya."
            )
        }
    }

    private func scriptEyebrow(_ script: KanaScript) -> String {
        script == .hiragana
            ? String(localized: "Fluid syllabary")
            : String(localized: "Angular syllabary")
    }

    @ViewBuilder
    private func subSection(
        _ vm: KanaPoolViewModel,
        script: KanaScript,
        section: KanaSection,
        title: LocalizedStringKey,
        description: LocalizedStringKey
    ) -> some View {
        let groups = KanaGroup.allCases.filter { $0.script == script && $0.section == section }
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: IkeruTheme.Spacing.sm) {
                HStack {
                    Text(title)
                        .font(.ikeruCaption)
                        .foregroundStyle(Color.ikeruTextSecondary)
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            vm.toggleAllInSection(section, script: script)
                        }
                    } label: {
                        Text(vm.isSectionFullySelected(section, script: script)
                             ? LocalizedStringKey("Deselect all") : LocalizedStringKey("Select all"))
                            .font(.ikeruMicro)
                            .ikeruTracking(.micro)
                            .foregroundStyle(Color.ikeruPrimaryAccent)
                    }
                    .buttonStyle(.plain)
                }

                // One-line primer on what this slice of the syllabary IS —
                // gojūon/dakuten/yōon are jargon to the beginners this screen
                // exists for (owner request, 2026-07-19).
                Text(description)
                    .font(.ikeruMicro)
                    .foregroundStyle(Color.ikeruTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, -4)

                LazyVGrid(columns: columns, spacing: IkeruTheme.Spacing.sm) {
                    ForEach(groups) { group in
                        KanaGroupCard(
                            group: group,
                            isSelected: vm.selectedGroups.contains(group),
                            mastery: vm.masteries[group],
                            charMastery: vm.characterMastery
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                vm.toggleGroup(group)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Bottom bar

    /// Vertical clearance reserved for the floating Liquid Glass tab bar so
    /// the action buttons stay above the tab bar's hit-zone.
    private static let floatingTabBarClearance: CGFloat = 120

    @ViewBuilder
    private func bottomBar(_ vm: KanaPoolViewModel) -> some View {
        VStack(spacing: 10) {
            Text("\(vm.selectedCharacterCount) characters selected")
                .font(.ikeruCaption)
                .foregroundStyle(Color.ikeruTextSecondary)

            if onStudySetConfirmed != nil {
                confirmStudySetButton(vm)
            } else {
                HStack(spacing: 8) {
                    drillButton(vm, mode: .dueReview, label: "Review Due", primary: true)
                    drillButton(vm, mode: .freePractice, label: "Free Practice", primary: false)
                    drillButton(vm, mode: .weakReinforcement, label: "Weak Spots", primary: false)
                }
            }
        }
        .padding(.horizontal, IkeruTheme.Spacing.lg)
        .padding(.top, IkeruTheme.Spacing.md)
        // The 120pt clearance exists for the floating tab bar in the Étude
        // context only. As a sheet (first-run chooser from Home) there is no
        // tab bar — the full clearance left a huge dead band under the CTA.
        .padding(.bottom, onStudySetConfirmed != nil
                 ? IkeruTheme.Spacing.md
                 : Self.floatingTabBarClearance)
        .frame(maxWidth: .infinity)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    LinearGradient(
                        colors: [Color.ikeruBackground.opacity(0.0), Color.ikeruBackground.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .ignoresSafeArea(edges: .bottom)
        }
    }

    @ViewBuilder
    private func drillButton(
        _ vm: KanaPoolViewModel,
        mode: KanaDrillMode,
        label: LocalizedStringKey,
        primary: Bool
    ) -> some View {
        Button {
            launchDrill(vm, mode: mode)
        } label: {
            Text(label)
                .font(.ikeruCaption)
                .frame(maxWidth: .infinity)
        }
        .ikeruButtonStyle(primary ? .primary : .secondary)
        .disabled(vm.selectedGroups.isEmpty)
        .opacity(vm.selectedGroups.isEmpty ? 0.5 : 1.0)
    }

    private func launchDrill(_ vm: KanaPoolViewModel, mode: KanaDrillMode) {
        Task { @MainActor in
            let cards = await vm.cards(for: mode)
            pendingMode = mode
            pendingCards = cards
            pendingGroups = vm.selectedGroups
            // Clear any filter/label left over from a confusion-pair launch
            // (see `launchConfusionCluster`) — this is a normal, unscoped session.
            pendingCharacterFilter = nil
            pendingSessionLabel = nil
            showDrill = true
        }
    }

    // MARK: Confusable pairs (chantier #24b)
    //
    // The classic katakana interference pairs (シ/ツ, ソ/ン, ...) otherwise
    // only ever surface at random, mixed in among an entire group's cards.
    // This section drills each cluster on its own — the queue IS the
    // cluster, so the quiz distractors are guaranteed to include the
    // actual look-alike (see `KanaDrillViewModel.buildQuiz`'s queue-first
    // distractor priority).

    @ViewBuilder
    private func confusionPairsSection(_ vm: KanaPoolViewModel) -> some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Kana.ConfusionPairs.Title")
                    .font(.ikeruMicro)
                    .ikeruTracking(.micro)
                    .foregroundStyle(Color.ikeruTextTertiary)
                Text("Kana.ConfusionPairs.Description")
                    .font(.ikeruMicro)
                    .foregroundStyle(Color.ikeruTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(columns: columns, spacing: IkeruTheme.Spacing.sm) {
                ForEach(KanaConfusionClusters.all) { cluster in
                    confusionClusterCard(vm, cluster: cluster)
                }
            }
        }
    }

    @ViewBuilder
    private func confusionClusterCard(_ vm: KanaPoolViewModel, cluster: KanaConfusionCluster) -> some View {
        Button {
            launchConfusionCluster(vm, cluster: cluster)
        } label: {
            VStack(spacing: 6) {
                Text(cluster.displayLabel)
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .foregroundStyle(Color.ikeruTextPrimary)
                Text("Kana.ConfusionPairs.PracticeLabel")
                    .font(.ikeruMicro)
                    .ikeruTracking(.micro)
                    .foregroundStyle(Color.ikeruPrimaryAccent)
            }
            .frame(maxWidth: .infinity)
            .tatamiRoom(.standard, padding: CGFloat(IkeruTheme.Spacing.md))
        }
        .buttonStyle(.plain)
    }

    private func launchConfusionCluster(_ vm: KanaPoolViewModel, cluster: KanaConfusionCluster) {
        Task { @MainActor in
            let cards = await vm.cards(forConfusionCluster: cluster)
            pendingMode = .freePractice
            pendingCards = cards
            pendingGroups = vm.groups(forConfusionCluster: cluster)
            pendingCharacterFilter = Set(cluster.characters)
            pendingSessionLabel = LocalizedStringKey(cluster.displayLabel)
            showDrill = true
        }
    }

    // MARK: Study-set confirm (first-run chooser)

    @ViewBuilder
    private func confirmStudySetButton(_ vm: KanaPoolViewModel) -> some View {
        Button {
            Task { @MainActor in
                await vm.confirmStudySet()
                onStudySetConfirmed?()
            }
        } label: {
            Text("Kana.StudySet.Start")
                .font(.ikeruCaption)
                .frame(maxWidth: .infinity)
        }
        .ikeruButtonStyle(.primary)
        .disabled(vm.selectedGroups.isEmpty)
        .opacity(vm.selectedGroups.isEmpty ? 0.5 : 1.0)
    }
}

// MARK: - KanaDrillPlaceholderView

/// Temporary destination while Crew C builds the real drill views.
struct KanaDrillPlaceholderView: View {
    let mode: KanaDrillMode
    let cards: [CardDTO]

    var body: some View {
        ZStack {
            IkeruScreenBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MODE")
                            .font(.ikeruMicro)
                            .ikeruTracking(.micro)
                            .foregroundStyle(Color.ikeruTextTertiary)
                        Text(mode.displayName)
                            .font(.ikeruDisplaySmall)
                            .ikeruTracking(.display)
                            .foregroundStyle(Color.ikeruTextPrimary)
                        Text("\(cards.count) cards")
                            .font(.ikeruCaption)
                            .foregroundStyle(Color.ikeruTextSecondary)
                    }
                    .padding(.bottom, IkeruTheme.Spacing.sm)

                    if cards.isEmpty {
                        Text("No cards available for this mode.")
                            .font(.ikeruCaption)
                            .foregroundStyle(Color.ikeruTextTertiary)
                            .tatamiRoom(.standard)
                    } else {
                        LazyVGrid(
                            columns: [
                                GridItem(.adaptive(minimum: 56), spacing: 8)
                            ],
                            spacing: 8
                        ) {
                            ForEach(cards) { card in
                                Text(card.front)
                                    .font(.system(size: 28, weight: .regular, design: .serif))
                                    .foregroundStyle(Color.ikeruTextPrimary)
                                    .frame(width: 56, height: 56)
                                    .background(.ultraThinMaterial)
                                    .overlay(Rectangle().strokeBorder(TatamiTokens.goldDim.opacity(0.4), lineWidth: 0.8))
                                    .sumiCorners(color: TatamiTokens.goldDim, size: 5, weight: 1.0)
                            }
                        }
                    }
                }
                .padding(IkeruTheme.Spacing.lg)
            }
        }
        .navigationTitle(mode.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
