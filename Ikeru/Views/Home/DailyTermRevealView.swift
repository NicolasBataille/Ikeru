import SwiftUI
import IkeruCore

// MARK: - DailyTermRevealView

/// The popup shown when the learner opens the daily term.
/// Plays a short reveal animation: the kanji block scales and fades up
/// from behind a soft veil, then the reading, meaning, and caption
/// fade in in sequence.
struct DailyTermRevealView: View {

    let term: DailyTermDTO
    let isAddedToDictionary: Bool
    var onAddToDictionary: () -> Void
    var onDismiss: () -> Void
    var onShowHistory: () -> Void

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
        .task {
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
                .opacity(phase == .veiled ? 1.0 : 0.0)

            VStack(spacing: 6) {
                Text(term.word)
                    .font(.kanjiHero)
                    .foregroundStyle(Color.ikeruTextPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .scaleEffect(phase >= .kanjiVisible ? 1.0 : 0.6)
                    .opacity(phase >= .kanjiVisible ? 1.0 : 0.0)
                    .blur(radius: phase >= .kanjiVisible ? 0 : 8)
                    .animation(.spring(response: 0.7, dampingFraction: 0.78), value: phase)
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
        .offset(y: phase >= .readingVisible ? 0 : 12)
        .animation(.spring(response: 0.55, dampingFraction: 0.85), value: phase)
    }

    private var meaningBlock: some View {
        Text(term.meaning)
            .font(.ikeruBodyLarge)
            .foregroundStyle(Color.ikeruTextPrimary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, IkeruTheme.Spacing.md)
            .opacity(phase >= .meaningVisible ? 1 : 0)
            .offset(y: phase >= .meaningVisible ? 0 : 12)
            .animation(.spring(response: 0.55, dampingFraction: 0.85), value: phase)
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
        .offset(y: phase >= .captionVisible ? 0 : 12)
        .animation(.spring(response: 0.55, dampingFraction: 0.85), value: phase)
    }

    private var actions: some View {
        VStack(spacing: IkeruTheme.Spacing.sm) {
            Button {
                onAddToDictionary()
            } label: {
                HStack(spacing: IkeruTheme.Spacing.sm) {
                    Image(systemName: isAddedToDictionary ? "checkmark.seal.fill" : "plus.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text(isAddedToDictionary ? "Added to dictionary" : "Add to dictionary")
                        .font(.ikeruBody)
                }
                .frame(maxWidth: .infinity)
            }
            .ikeruButtonStyle(.primary)
            .disabled(isAddedToDictionary)
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
        .offset(y: phase >= .complete ? 0 : 12)
        .animation(.spring(response: 0.55, dampingFraction: 0.85), value: phase)
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

    private func runRevealAnimation() async {
        try? await Task.sleep(nanoseconds: 200_000_000)
        phase = .kanjiVisible
        try? await Task.sleep(nanoseconds: 600_000_000)
        phase = .readingVisible
        try? await Task.sleep(nanoseconds: 350_000_000)
        phase = .meaningVisible
        try? await Task.sleep(nanoseconds: 350_000_000)
        phase = .captionVisible
        try? await Task.sleep(nanoseconds: 350_000_000)
        phase = .complete
    }

    // MARK: - Helpers

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
