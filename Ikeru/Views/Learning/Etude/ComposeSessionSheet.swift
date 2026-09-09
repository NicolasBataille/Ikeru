import SwiftUI
import IkeruCore

// MARK: - ComposeSessionSheet
//
// Étude → « Composer une séance » : the explicit opt-in door.
//
// `DefaultSessionPlanner.untaughtContentTypes` keeps listening, speaking and
// vocabulary quizzes out of the HOME session because their generators quiz
// raw content the learner never met (owner decision, 2026-07-19). The same
// decision said « Étude custom sessions keep every type — there the learner
// opts in explicitly ». That sheet did not exist: `startStudyCustomSession`
// had no caller from 2026-07-19 to 2026-09-09. This is it.
//
// What it does NOT offer, on purpose: a JLPT level (the planner ignores it
// today and says so in its logs), Sakura (her own row), kana (its own drill),
// and the two retired types. See `ExerciseType.composableInStudySession`.

struct ComposeSessionSheet: View {

    @Bindable var viewModel: ComposeSessionViewModel
    /// Called with the learner's choice; returns whether a session started.
    /// `false` keeps the sheet open and shows why.
    let onStart: () async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var isStarting = false
    @State private var composedNothing = false

    var body: some View {
        NavigationStack {
            ZStack {
                IkeruScreenBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: IkeruTheme.Spacing.lg) {
                        intro
                        typesCard
                        durationCard
                        if composedNothing {
                            composedNothingCard
                        }
                        startButton
                        Spacer(minLength: IkeruTheme.Spacing.xl)
                    }
                    .padding(.horizontal, IkeruTheme.Spacing.lg)
                    .padding(.top, IkeruTheme.Spacing.lg)
                }
            }
            .navigationTitle("Compose a session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task { await viewModel.load() }
    }

    // MARK: - Sections

    private var intro: some View {
        Text("Pick what you want to practice. The home session chooses for you; here, you choose.")
            .font(.ikeruCaption)
            .foregroundStyle(Color.ikeruTextSecondary)
    }

    private var typesCard: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
            IkeruSectionHeader(title: "Exercises", eyebrow: "Choose one or more")
            if !viewModel.hasLoaded {
                ProgressView().tint(Color.ikeruTextSecondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(viewModel.offers.enumerated()), id: \.element.id) { index, offer in
                    offerRow(offer)
                    if index < viewModel.offers.count - 1 { IkeruDivider() }
                }
            }
        }
        .tatamiRoom(.standard)
    }

    private func offerRow(_ offer: ComposeSessionViewModel.Offer) -> some View {
        Button {
            viewModel.toggle(offer.type)
        } label: {
            HStack(spacing: IkeruTheme.Spacing.md) {
                Image(systemName: viewModel.isSelected(offer.type) ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(offer.isUnlocked ? Color.ikeruPrimaryAccent : Color.ikeruTextTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.title(for: offer.type))
                        .font(.ikeruBody)
                        .foregroundStyle(offer.isUnlocked ? Color.ikeruTextPrimary : Color.ikeruTextTertiary)
                    Text(offer.isUnlocked ? Self.subtitle(for: offer.type) : Self.lockText(for: offer.unlockState))
                        .font(.ikeruCaption)
                        .foregroundStyle(Color.ikeruTextSecondary)
                }
                Spacer()
                if !offer.isUnlocked {
                    Image(systemName: "lock")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.ikeruTextTertiary)
                }
            }
            .padding(.vertical, IkeruTheme.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!offer.isUnlocked)
        .accessibilityIdentifier("compose.type.\(offer.type.rawValue)")
    }

    private var durationCard: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
            IkeruSectionHeader(title: "Duration", eyebrow: "Minutes")
            Picker("Duration", selection: $viewModel.durationMinutes) {
                ForEach(ComposeSessionViewModel.durationChoices, id: \.self) { minutes in
                    Text(verbatim: "\(minutes)").tag(minutes)
                }
            }
            .pickerStyle(.segmented)
        }
        .tatamiRoom(.standard)
    }

    /// Shown instead of dismissing when the selection composed nothing —
    /// a card-backed drill with no card behind it, typically. The learner
    /// changes the selection; nothing opened, nothing was graded.
    private var composedNothingCard: some View {
        Text("Nothing could be composed from this selection — writing and kanji drills need kanji cards you have already started. Try another mix.")
            .font(.ikeruCaption)
            .foregroundStyle(Color.ikeruDanger)
            .frame(maxWidth: .infinity, alignment: .leading)
            .tatamiRoom(.standard)
    }

    private var startButton: some View {
        Button {
            guard !isStarting else { return }
            isStarting = true
            composedNothing = false
            Task {
                let started = await onStart()
                isStarting = false
                if started {
                    dismiss()
                } else {
                    composedNothing = true
                }
            }
        } label: {
            Text("Start")
                .frame(maxWidth: .infinity)
        }
        .ikeruButtonStyle(.primary)
        .disabled(!viewModel.canStart || isStarting)
        .accessibilityIdentifier("compose.start")
    }

    // MARK: - Labels

    /// Catalogue keys, one per offered type. `LocalizedStringKey`, never
    /// `String` (OBS2-050).
    static func title(for type: ExerciseType) -> LocalizedStringKey {
        switch type {
        case .kanjiStudy: "Kanji"
        case .vocabularyStudy: "Vocabulary"
        case .grammarExercise: "Grammar"
        case .sentenceConstruction: "Sentence building"
        case .writingPractice: "Writing"
        case .listeningSubtitled, .listeningUnsubtitled: "Listening"
        case .speakingPractice: "Speaking"
        case .kanaStudy: "Kana"
        case .sakuraConversation: "Talk with Sakura"
        case .fillInBlank, .readingPassage: "Retired"
        }
    }

    static func subtitle(for type: ExerciseType) -> LocalizedStringKey {
        switch type {
        case .kanjiStudy: "Trace a kanji from your deck"
        case .vocabularyStudy: "Multiple-choice recall of N5 words"
        case .grammarExercise: "Fill the gap in an N5 sentence pattern"
        case .sentenceConstruction: "Put the words of a sentence in order"
        case .writingPractice: "Handwriting drill on a kanji you started"
        case .listeningSubtitled, .listeningUnsubtitled: "Hear a word, pick its meaning"
        case .speakingPractice: "Shadow a word out loud"
        case .kanaStudy: "Hiragana & katakana"
        case .sakuraConversation: "AI conversation partner"
        case .fillInBlank, .readingPassage: "Retired"
        }
    }

    /// Why a type is locked, as the learner should read it.
    static func lockText(for state: ExerciseUnlockState) -> LocalizedStringKey {
        guard case .locked(let reason) = state else { return "" }
        switch reason {
        case .vocabularyMastered(let required, let current):
            return "Unlocks at \(required) familiar words — you have \(current)"
        case .kanjiMastered(let required, let current):
            return "Unlocks at \(required) familiar kanji — you have \(current)"
        case .kanaMastered(let syllabary):
            return syllabary == .hiragana ? "Unlocks once the hiragana are familiar" : "Unlocks once the katakana are familiar"
        case .grammarPointsMastered(let required, let current):
            return "Unlocks at \(required) familiar grammar points — you have \(current)"
        // The percentage is formatted as a `String` first (`%@`), never
        // interpolated next to a literal « % » — that would put a stray
        // format specifier in the catalogue key.
        case .listeningAccuracyOver(let required, _, _):
            return "Unlocks at \(Self.percent(required)) listening accuracy"
        case .listeningRecallOver(let required, _, _):
            return "Unlocks at \(Self.percent(required)) listening recall"
        case .jlptLevelReached(let required, _):
            return "Unlocks at JLPT \(required.rawValue.uppercased())"
        case .retired:
            return "Retired"
        }
    }

    private static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))\u{00A0}%"
    }
}
