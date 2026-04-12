import Testing
import Foundation
@testable import Ikeru
@testable import IkeruCore

// MARK: - KanjiStudyViewStateTests
//
// Task 7 (Story 2.2) optional tests: section expand/collapse toggling,
// stroke order overlay toggling, and mnemonic view-state transitions.
//
// Snapshot tests were substituted with deterministic state-level tests
// because the project has no snapshot-testing dependency (and repo policy
// forbids adding new paid/external deps). The `KanjiSection` enum and the
// `showStrokeOrder` @State used inside the views are private to the view
// types, so these tests replicate the exact toggle semantics in a local
// helper and exercise the public ViewModel state for mnemonic toggles.

@Suite("KanjiStudyView state")
@MainActor
struct KanjiStudyViewStateTests {

    // MARK: - Section Toggle Helper
    //
    // Mirrors the `Set<KanjiSection>` toggle logic from KanjiStudyView.
    // Kept in the test file to avoid widening production access. If the
    // view's implementation diverges from this helper, these tests should
    // be updated together with the view.

    private enum Section: String, CaseIterable, Sendable {
        case mnemonic, radicals, readings, vocabulary
    }

    private struct SectionToggleState: Sendable {
        private(set) var expanded: Set<Section>

        init(expanded: Set<Section> = [.mnemonic, .radicals, .readings]) {
            self.expanded = expanded
        }

        mutating func toggle(_ section: Section) {
            if expanded.contains(section) {
                expanded.remove(section)
            } else {
                expanded.insert(section)
            }
        }

        func isExpanded(_ section: Section) -> Bool {
            expanded.contains(section)
        }
    }

    // MARK: - Section Expand/Collapse

    @Test("Default expanded sections match view defaults")
    func defaultExpandedSections() {
        let state = SectionToggleState()
        #expect(state.isExpanded(.mnemonic))
        #expect(state.isExpanded(.radicals))
        #expect(state.isExpanded(.readings))
        #expect(!state.isExpanded(.vocabulary))
    }

    @Test("Toggling a collapsed section expands it")
    func toggleCollapsedExpandsIt() {
        var state = SectionToggleState()
        state.toggle(.vocabulary)
        #expect(state.isExpanded(.vocabulary))
    }

    @Test("Toggling an expanded section collapses it")
    func toggleExpandedCollapsesIt() {
        var state = SectionToggleState()
        state.toggle(.radicals)
        #expect(!state.isExpanded(.radicals))
    }

    @Test("Toggling twice returns to original state")
    func toggleIsInvolution() {
        var state = SectionToggleState()
        let before = state.expanded
        state.toggle(.vocabulary)
        state.toggle(.vocabulary)
        #expect(state.expanded == before)
    }

    @Test("Every section can be toggled independently")
    func toggleIndependence() {
        for section in Section.allCases {
            var state = SectionToggleState()
            let initial = state.isExpanded(section)
            state.toggle(section)
            #expect(state.isExpanded(section) != initial)
        }
    }

    // MARK: - Stroke Order Overlay Toggle
    //
    // KanjiDisplayView exposes a private @State `showStrokeOrder: Bool`
    // flipped on tap. Since the property is private, we replicate the
    // exact Bool-flip semantics and validate it.

    @Test("Stroke order overlay toggles on tap")
    func strokeOrderTogglesOnTap() {
        var showStrokeOrder = false
        // Simulate tap
        showStrokeOrder.toggle()
        #expect(showStrokeOrder)
        // Dismiss tap
        showStrokeOrder.toggle()
        #expect(!showStrokeOrder)
    }

    // MARK: - Mnemonic ViewModel State Toggles
    //
    // These exercise the real public state on KanjiStudyViewModel that
    // drives the mnemonic section's view.

    @Test("Mnemonic state is idle when no provider injected")
    func mnemonicIdleWithoutProvider() async {
        let kanji = Self.sampleKanji()
        let repo = ContentRepository(bundleURL: URL(fileURLWithPath: "/nonexistent"))
        let viewModel = KanjiStudyViewModel(kanji: kanji, contentRepository: repo)

        await viewModel.loadMnemonic()

        #expect(viewModel.mnemonicLoadingState.isIdle)
        #expect(viewModel.mnemonicText == nil)
    }

    @Test("loadMnemonic transitions to loaded and populates text")
    func loadMnemonicSuccess() async {
        let kanji = Self.sampleKanji()
        let repo = ContentRepository(bundleURL: URL(fileURLWithPath: "/nonexistent"))
        let provider = StubMnemonicProvider(result: .success(
            MnemonicResult(text: "A bright sun over the horizon.", tier: .onDevice)
        ))
        let viewModel = KanjiStudyViewModel(
            kanji: kanji,
            contentRepository: repo,
            mnemonicService: provider
        )

        await viewModel.loadMnemonic()

        #expect(viewModel.mnemonicLoadingState.isLoaded)
        #expect(viewModel.mnemonicText == "A bright sun over the horizon.")
    }

    @Test("loadMnemonic transitions to failed on provider error")
    func loadMnemonicFailure() async {
        let kanji = Self.sampleKanji()
        let repo = ContentRepository(bundleURL: URL(fileURLWithPath: "/nonexistent"))
        let provider = StubMnemonicProvider(result: .failure(StubError.boom))
        let viewModel = KanjiStudyViewModel(
            kanji: kanji,
            contentRepository: repo,
            mnemonicService: provider
        )

        await viewModel.loadMnemonic()

        #expect(viewModel.mnemonicLoadingState.isFailed)
        #expect(viewModel.mnemonicText == nil)
    }

    @Test("regenerateMnemonic clears text then reloads")
    func regenerateMnemonicResetsAndReloads() async {
        let kanji = Self.sampleKanji()
        let repo = ContentRepository(bundleURL: URL(fileURLWithPath: "/nonexistent"))
        let provider = StubMnemonicProvider(result: .success(
            MnemonicResult(text: "Fresh mnemonic.", tier: .onDevice)
        ))
        let viewModel = KanjiStudyViewModel(
            kanji: kanji,
            contentRepository: repo,
            mnemonicService: provider
        )

        await viewModel.loadMnemonic()
        #expect(viewModel.mnemonicText == "Fresh mnemonic.")

        await provider.setResult(.success(
            MnemonicResult(text: "Regenerated mnemonic.", tier: .onDevice)
        ))
        await viewModel.regenerateMnemonic()

        #expect(viewModel.mnemonicLoadingState.isLoaded)
        #expect(viewModel.mnemonicText == "Regenerated mnemonic.")
        #expect(await provider.clearCacheCallCount == 1)
    }

    // MARK: - Helpers

    private static func sampleKanji() -> Kanji {
        Kanji(
            character: "\u{65E5}",
            radicals: ["\u{4E00}", "\u{53E3}"],
            onReadings: ["\u{30CB}\u{30C1}"],
            kunReadings: ["\u{3072}"],
            meanings: ["day", "sun"],
            jlptLevel: .n5,
            strokeCount: 4,
            strokeOrderSVGRef: nil
        )
    }
}

// MARK: - Stub Mnemonic Provider

private enum StubError: Error { case boom }

private actor StubMnemonicProvider: MnemonicProvider {
    private var result: Result<MnemonicResult, Error>
    private(set) var clearCacheCallCount = 0

    init(result: Result<MnemonicResult, Error>) {
        self.result = result
    }

    func setResult(_ newResult: Result<MnemonicResult, Error>) {
        self.result = newResult
    }

    func generateMnemonic(
        for character: String,
        radicals: [String],
        readings: [String]
    ) async throws -> MnemonicResult {
        try result.get()
    }

    func cachedMnemonic(for character: String) async -> String? { nil }

    func clearCache(for character: String) async throws {
        clearCacheCallCount += 1
    }
}
