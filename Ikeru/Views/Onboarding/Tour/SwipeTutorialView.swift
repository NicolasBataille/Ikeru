import SwiftUI
import IkeruCore

// MARK: - Swipe Tutorial
//
// A one-shot, in-context demo shown the first time a learner reaches the SRS
// flashcards. A mock card leans toward each of the four swipe directions in
// turn — Tinder-style — while Sakura explains what each direction means. The
// real SwipeDirection enum (from SRSCardView) drives the colors so the demo
// always matches the live card.

struct SwipeTutorialView: View {

    let onDismiss: () -> Void

    /// Demo timeline: a nudge toward each direction, separated by a rest beat
    /// (nil). Right (Good) first — the most common answer. Driven by `timer`.
    private let phaseSequence: [SwipeDirection?] = [
        nil, .right, nil, .left, nil, .up, nil, .down,
    ]
    @State private var phaseIndex = 0
    private let timer = Timer.publish(every: 0.85, on: .main, in: .common).autoconnect()

    private let nudgeDistance: CGFloat = 78

    /// Currently-demonstrated direction (nil between nudges).
    private var activeDirection: SwipeDirection? {
        phaseSequence[phaseIndex % phaseSequence.count]
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.86))
                .ignoresSafeArea()
                .contentShape(Rectangle())

            VStack(spacing: IkeruTheme.Spacing.lg) {
                header

                Spacer(minLength: 0)

                demoStage

                caption

                Spacer(minLength: 0)

                Button(action: onDismiss) {
                    Text("SwipeTutorial.GotIt")
                        .frame(maxWidth: .infinity)
                }
                .ikeruButtonStyle(.primary)
            }
            .padding(.horizontal, IkeruTheme.Spacing.xl)
            .padding(.vertical, IkeruTheme.Spacing.xxl)
        }
        .onReceive(timer) { _ in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                phaseIndex = (phaseIndex + 1) % phaseSequence.count
            }
        }
    }

    // MARK: - Header (Sakura voice)

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            SakuraMark(size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "Sakura")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(Color.ikeruPrimaryAccent)
                Text("SwipeTutorial.Intro")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.ikeruTextPrimary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Demo stage (mock card + directional labels)

    private var demoStage: some View {
        ZStack {
            directionLabel(.up,    title: "SwipeTutorial.Easy.Title",  arrow: "chevron.up")
                .offset(y: -168)
            directionLabel(.down,  title: "SwipeTutorial.Hard.Title",  arrow: "chevron.down")
                .offset(y: 168)
            directionLabel(.left,  title: "SwipeTutorial.Again.Title", arrow: "chevron.left")
                .offset(x: -120)
            directionLabel(.right, title: "SwipeTutorial.Good.Title",  arrow: "chevron.right")
                .offset(x: 120)

            mockCard
                .offset(cardOffset)
                .rotationEffect(cardRotation)
        }
        .frame(height: 420)
        .frame(maxWidth: .infinity)
    }

    private var mockCard: some View {
        VStack(spacing: 10) {
            Text("\u{3042}") // あ — hiragana "a", the very first character learners meet
                .font(.system(size: 72, weight: .regular, design: .serif))
                .foregroundStyle(Color.ikeruTextPrimary)
            Text(verbatim: "a")
                .font(.system(size: 18, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.ikeruPrimaryAccent)
        }
        .frame(width: 168, height: 224)
        .background(
            RoundedRectangle(cornerRadius: IkeruTheme.Radius.md, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: IkeruTheme.Radius.md, style: .continuous)
                .strokeBorder(
                    (activeDirection?.color ?? Color.white.opacity(0.15)),
                    lineWidth: activeDirection == nil ? 1 : 3
                )
        )
        .shadow(
            color: (activeDirection?.color ?? .black).opacity(activeDirection == nil ? 0.3 : 0.55),
            radius: activeDirection == nil ? 16 : 28
        )
    }

    private func directionLabel(
        _ direction: SwipeDirection,
        title: LocalizedStringKey,
        arrow: String
    ) -> some View {
        let isActive = activeDirection == direction
        return VStack(spacing: 4) {
            Image(systemName: arrow)
                .font(.system(size: 14, weight: .bold))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(direction.color)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(direction.color.opacity(isActive ? 0.22 : 0.08))
        )
        .overlay(
            Capsule().strokeBorder(direction.color.opacity(isActive ? 0.9 : 0.3), lineWidth: 1)
        )
        .scaleEffect(isActive ? 1.12 : 1.0)
        .opacity(isActive ? 1.0 : 0.55)
    }

    // MARK: - Dynamic caption

    @ViewBuilder
    private var caption: some View {
        Group {
            if let direction = activeDirection {
                Text(captionKey(for: direction))
            } else {
                Text("SwipeTutorial.Idle")
            }
        }
        .font(.system(size: 14))
        .foregroundStyle(Color.ikeruTextSecondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 44)
        .animation(.easeInOut(duration: 0.2), value: activeDirection)

        Text("SwipeTutorial.Buttons")
            .font(.system(size: 12))
            .foregroundStyle(Color.ikeruTextTertiary)
            .multilineTextAlignment(.center)
            .padding(.top, 2)
    }

    private func captionKey(for direction: SwipeDirection) -> LocalizedStringKey {
        switch direction {
        case .left:  "SwipeTutorial.Again.Body"
        case .right: "SwipeTutorial.Good.Body"
        case .up:    "SwipeTutorial.Easy.Body"
        case .down:  "SwipeTutorial.Hard.Body"
        }
    }

    // MARK: - Card transform

    private var cardOffset: CGSize {
        switch activeDirection {
        case .left:  CGSize(width: -nudgeDistance, height: 0)
        case .right: CGSize(width: nudgeDistance, height: 0)
        case .up:    CGSize(width: 0, height: -nudgeDistance)
        case .down:  CGSize(width: 0, height: nudgeDistance)
        case nil:    .zero
        }
    }

    private var cardRotation: Angle {
        switch activeDirection {
        case .left:  .degrees(-9)
        case .right: .degrees(9)
        default:     .degrees(0)
        }
    }
}

// MARK: - Preview

#Preview("SwipeTutorialView") {
    SwipeTutorialView(onDismiss: {})
        .preferredColorScheme(.dark)
}
