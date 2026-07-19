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
    @State private var showDrill = false

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
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            initializeIfNeeded()
            await viewModel?.loadMasteries()
        }
        .navigationDestination(isPresented: $showDrill) {
            if let mode = pendingMode {
                KanaDrillModeSelector(mode: mode, groups: pendingGroups, cards: pendingCards)
            }
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

    @ViewBuilder
    private func presetBar(_ vm: KanaPoolViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(KanaPreset.allCases) { preset in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            vm.applyPreset(preset)
                        }
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
        }
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
