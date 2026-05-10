import SwiftUI
import IkeruCore

// MARK: - DailyTermRevealHostView

/// Host wrapper that owns the *local* DTO snapshot for the reveal sheet.
///
/// When the user taps "Add to dictionary", we update both the persistent
/// row (via the view model) and this local snapshot so the button
/// reflects the new state immediately, even for past terms (where the
/// view model's `today` doesn't match).
struct DailyTermRevealHostView: View {

    let initialTerm: DailyTermDTO
    let viewModel: DailyTermViewModel
    var onDismiss: () -> Void
    var onShowHistory: () -> Void

    @State private var term: DailyTermDTO
    @State private var addInFlight: Bool = false
    @Environment(\.toastManager) private var toastManager

    init(
        initialTerm: DailyTermDTO,
        viewModel: DailyTermViewModel,
        onDismiss: @escaping () -> Void,
        onShowHistory: @escaping () -> Void
    ) {
        self.initialTerm = initialTerm
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        self.onShowHistory = onShowHistory
        self._term = State(initialValue: initialTerm)
    }

    var body: some View {
        DailyTermRevealView(
            term: term,
            isAddedToDictionary: term.addedToDictionary,
            isAddInFlight: addInFlight,
            onAddToDictionary: {
                addToDictionary()
            },
            onDismiss: onDismiss,
            onShowHistory: onShowHistory
        )
        .task {
            // Mark revealed once on first appearance.
            if let updated = await viewModel.markRevealed(term) {
                term = updated
            }
        }
    }

    private func addToDictionary() {
        guard !addInFlight, !term.addedToDictionary else { return }
        addInFlight = true
        Task { @MainActor in
            defer { addInFlight = false }
            if let updated = await viewModel.addToDictionary(term) {
                term = updated
                toastManager.showInfo("Added to your dictionary")
            } else if !term.addedToDictionary {
                toastManager.showError("Couldn't add to dictionary")
            }
        }
    }
}

// MARK: - DailyTermRevealView

/// The popup shown when the learner opens the daily term.
///
/// Plays a short reveal animation: the kanji block scales and fades up
/// from behind a soft veil, then the reading, meaning, and caption
/// fade in in sequence. When `accessibilityReduceMotion` is on, the
/// animation collapses to a single fade-in.
struct DailyTermRevealView: View {

    let term: DailyTermDTO
    let isAddedToDictionary: Bool
    let isAddInFlight: Bool
    var onAddToDictionary: () -> Void
    var onDismiss: () -> Void
    var onShowHistory: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Reveal animation state
    @State private var phase: RevealPhase = .veiled

    private enum RevealPhase: Int, Comparable {
        case veiled
        case kanjiVisible
        case readingVisible
        case meaningVisible
        case captionVisible
        case complete

        static func < (lhs: RevealPhase, rhs: RevealPhase) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    var body: some View {
        ZStack {
            // Backdrop
            LinearGradient(
                colors: [
                    Color(hex: 0x12121A),
                    Color(hex: 0x0A0A0F)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Soft accent glow
            RadialGradient(
                colors: [
                    Color.ikeruPrimaryAccent.opacity(phase >= .kanjiVisible ? 0.22 : 0.0),
                    Color.clear
                ],
                center: .top,
                startRadius: 20,
                endRadius: 380
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.9), value: phase)

            content

            closeButton
        }
        .task(id: term.id) {
            await runRevealAnimation()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        VStack(spacing: IkeruTheme.Spacing.lg) {
            Spacer(minLength: 24)

            header

            kanjiBlock

            readingBlock

            meaningBlock

            captionBlock

            Spacer(minLength: 8)

            actions
        }
        .padding(.horizontal, IkeruTheme.Spacing.lg)
        .padding(.top, IkeruTheme.Spacing.xl)
        .padding(.bottom, IkeruTheme.Spacing.xl)
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("TERM OF THE DAY")
                .font(.ikeruMicro)
                .ikeruTracking(.micro)
                .foregroundStyle(Color.ikeruPrimaryAccent)
            Text(formattedDate(term.date))
                .font(.ikeruCaption)
                .foregroundStyle(Color.ikeruTextTertiary)
        }
        .opacity(phase >= .kanjiVisible ? 1 : 0)
        .animation(.easeOut(duration: 0.6), value: phase)
    }

    /// Hero kanji block — scales and rises from behind a soft veil.
    private var kanjiBlock: some View {
        ZStack {
            // The veil — a translucent panel that sits over the word
            // until the reveal phase begins.
            RoundedRectangle(cornerRadius: IkeruTheme.Radius.xl, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: IkeruTheme.Radius.xl, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6)
                }
                .opacity(phase == .veiled && !reduceMotion ? 1.0 : 0.0)

            VStack(spacing: 6) {
                Text(term.word)
                    .font(.kanjiHero)
                    .foregroundStyle(Color.ikeruTextPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .scaleEffect(phase >= .kanjiVisible || reduceMotion ? 1.0 : 0.6)
                    .opacity(phase >= .kanjiVisible ? 1.0 : 0.0)
                    .blur(radius: phase >= .kanjiVisible || reduceMotion ? 0 : 8)
                    .animation(reduceMotion ? .easeIn(duration: 0.2) : .spring(response: 0.7, dampingFraction: 0.78), value: phase)
            }
            .padding(.vertical, IkeruTheme.Spacing.lg)
            .padding(.horizontal, IkeruTheme.Spacing.lg)
        }
        .frame(minHeight: 180)
        .frame(maxWidth: .infinity)
    }

    private var readingBlock: some View {
        VStack(spacing: 4) {
            Text(term.reading)
                .font(.ikeruHeading3)
                .foregroundStyle(Color.ikeruTextSecondary)
            Text(term.pronunciation)
                .font(.ikeruCaption)
                .foregroundStyle(Color.ikeruTextTertiary)
                .textCase(.lowercase)
        }
        .opacity(phase >= .readingVisible ? 1 : 0)
        .offset(y: phase >= .readingVisible || reduceMotion ? 0 : 12)
        .animation(reduceMotion ? .easeIn(duration: 0.2) : .spring(response: 0.55, dampingFraction: 0.85), value: phase)
    }

    private var meaningBlock: some View {
        Text(term.meaning)
            .font(.ikeruBodyLarge)
            .foregroundStyle(Color.ikeruTextPrimary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, IkeruTheme.Spacing.md)
            .opacity(phase >= .meaningVisible ? 1 : 0)
            .offset(y: phase >= .meaningVisible || reduceMotion ? 0 : 12)
            .animation(reduceMotion ? .easeIn(duration: 0.2) : .spring(response: 0.55, dampingFraction: 0.85), value: phase)
    }

    private var captionBlock: some View {
        VStack(spacing: IkeruTheme.Spacing.xs) {
            if let level = term.jlptLevel {
                Text(level.displayLabel)
                    .font(.ikeruMicro)
                    .ikeruTracking(.micro)
                    .foregroundStyle(Color.ikeruTertiaryAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        Capsule().fill(Color.ikeruTertiaryAccent.opacity(0.14))
                    }
            }
            Text(term.caption)
                .font(.ikeruBody)
                .foregroundStyle(Color.ikeruTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, IkeruTheme.Spacing.md)
        }
        .opacity(phase >= .captionVisible ? 1 : 0)
        .offset(y: phase >= .captionVisible || reduceMotion ? 0 : 12)
        .animation(reduceMotion ? .easeIn(duration: 0.2) : .spring(response: 0.55, dampingFraction: 0.85), value: phase)
    }

    private var actions: some View {
        VStack(spacing: IkeruTheme.Spacing.sm) {
            Button {
                onAddToDictionary()
            } label: {
                HStack(spacing: IkeruTheme.Spacing.sm) {
                    if isAddInFlight {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: isAddedToDictionary ? "checkmark.seal.fill" : "plus.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    Text(isAddedToDictionary ? "Added to dictionary" : "Add to dictionary")
                        .font(.ikeruBody)
                }
                .frame(maxWidth: .infinity)
            }
            .ikeruButtonStyle(.primary)
            .disabled(isAddedToDictionary || isAddInFlight)
            .opacity(isAddedToDictionary ? 0.6 : 1.0)

            Button(action: onShowHistory) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Past terms")
                        .font(.ikeruCaption)
                }
                .foregroundStyle(Color.ikeruTextSecondary)
            }
            .buttonStyle(.plain)
        }
        .opacity(phase >= .complete ? 1 : 0)
        .offset(y: phase >= .complete || reduceMotion ? 0 : 12)
        .animation(reduceMotion ? .easeIn(duration: 0.2) : .spring(response: 0.55, dampingFraction: 0.85), value: phase)
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.ikeruTextSecondary)
                        .padding(10)
                        .background {
                            Circle().fill(.ultraThinMaterial)
                        }
                        .overlay(
                            Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.6)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.top, IkeruTheme.Spacing.md)
            .padding(.trailing, IkeruTheme.Spacing.md)
            Spacer()
        }
    }

    // MARK: - Animation

    /// Runs the phased reveal. When `reduceMotion` is on, jumps directly
    /// to `.complete`. Cancellation-safe: if the sheet is dismissed
    /// mid-animation, the chain stops at the current step.
    private func runRevealAnimation() async {
        if reduceMotion {
            phase = .complete
            return
        }
        let steps: [(RevealPhase, UInt64)] = [
            (.kanjiVisible,   200_000_000),
            (.readingVisible, 600_000_000),
            (.meaningVisible, 350_000_000),
            (.captionVisible, 350_000_000),
            (.complete,       350_000_000)
        ]
        for (next, delay) in steps {
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            if Task.isCancelled { return }
            phase = next
        }
    }

    // MARK: - Helpers

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
