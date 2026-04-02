import SwiftUI
import IkeruCore

// MARK: - Swipe Direction

enum SwipeDirection: Sendable {
    case left
    case right
    case up
    case down

    var grade: Grade {
        switch self {
        case .left: .again
        case .right: .good
        case .up: .easy
        case .down: .hard
        }
    }

    var label: String {
        switch self {
        case .left: "Again"
        case .right: "Good"
        case .up: "Easy"
        case .down: "Hard"
        }
    }

    var color: Color {
        switch self {
        case .left: Color(hex: IkeruTheme.Colors.secondaryAccent) // vermillion
        case .right: Color(hex: 0xFFB347) // amber
        case .up: Color(hex: IkeruTheme.Colors.success) // jade
        case .down: Color(hex: 0xFF8C42) // orange
        }
    }
}

// MARK: - SRSCardView

struct SRSCardView: View {

    let card: CardDTO
    let nextCard: CardDTO?
    let onSwipe: (SwipeDirection) -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false

    /// Minimum drag distance before a grade registers.
    private let swipeThreshold: CGFloat = 100

    var body: some View {
        ZStack {
            // Peeking card behind (next card preview)
            if let nextCard {
                peekingCard(for: nextCard)
            }

            // Current interactive card
            currentCard
                .offset(dragOffset)
                .rotationEffect(cardRotation)
                .gesture(dragGesture)
                .overlay(alignment: .top) {
                    gradeIndicator
                }
        }
    }

    // MARK: - Current Card

    private var currentCard: some View {
        cardContent(for: card)
            .ikeruCard(.interactive)
    }

    // MARK: - Peeking Card

    private func peekingCard(for card: CardDTO) -> some View {
        cardContent(for: card)
            .ikeruCard(.standard)
            .offset(y: 8)
            .scaleEffect(0.96)
            .opacity(0.6)
            .allowsHitTesting(false)
    }

    // MARK: - Card Content

    private func cardContent(for card: CardDTO) -> some View {
        VStack(spacing: IkeruTheme.Spacing.md) {
            cardFrontContent(for: card)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 280)
    }

    @ViewBuilder
    private func cardFrontContent(for card: CardDTO) -> some View {
        switch card.type {
        case .kanji:
            Text(card.front)
                .font(.kanjiHero)
                .foregroundStyle(Color.ikeruKanjiText)

        case .vocabulary:
            Text(card.front)
                .font(.kanjiDisplay)
                .foregroundStyle(Color.ikeruKanjiText)

        case .grammar:
            Text(card.front)
                .font(.ikeruHeading2)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

        case .listening:
            VStack(spacing: IkeruTheme.Spacing.sm) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.ikeruPrimaryAccent)
                Text(card.front)
                    .font(.ikeruBody)
                    .foregroundStyle(.ikeruTextSecondary)
            }
        }
    }

    // MARK: - Card Rotation

    private var cardRotation: Angle {
        let maxRotation: Double = 15
        let normalizedOffset = dragOffset.width / 300
        let clampedRotation = max(-maxRotation, min(maxRotation, normalizedOffset * maxRotation))
        return .degrees(clampedRotation)
    }

    // MARK: - Grade Indicator

    @ViewBuilder
    private var gradeIndicator: some View {
        if let direction = dominantDirection, isDragging {
            Text(direction.label)
                .font(.ikeruHeading2)
                .foregroundStyle(direction.color)
                .padding(.horizontal, IkeruTheme.Spacing.md)
                .padding(.vertical, IkeruTheme.Spacing.sm)
                .background {
                    RoundedRectangle(cornerRadius: IkeruTheme.Radius.sm)
                        .fill(direction.color.opacity(0.2))
                }
                .padding(.top, IkeruTheme.Spacing.md)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.15), value: direction.label)
        }
    }

    // MARK: - Dominant Direction

    private var dominantDirection: SwipeDirection? {
        let absWidth = abs(dragOffset.width)
        let absHeight = abs(dragOffset.height)
        let maxDimension = max(absWidth, absHeight)

        guard maxDimension >= swipeThreshold else { return nil }

        if absWidth > absHeight {
            return dragOffset.width < 0 ? .left : .right
        } else {
            return dragOffset.height < 0 ? .up : .down
        }
    }

    // MARK: - Drag Gesture

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
                isDragging = true
            }
            .onEnded { value in
                isDragging = false
                if let direction = dominantDirection {
                    // Fly off screen in the swipe direction
                    let flyDistance: CGFloat = 500
                    let flyOffset: CGSize
                    switch direction {
                    case .left:
                        flyOffset = CGSize(width: -flyDistance, height: 0)
                    case .right:
                        flyOffset = CGSize(width: flyDistance, height: 0)
                    case .up:
                        flyOffset = CGSize(width: 0, height: -flyDistance)
                    case .down:
                        flyOffset = CGSize(width: 0, height: flyDistance)
                    }
                    withAnimation(.spring(duration: 0.2)) {
                        dragOffset = flyOffset
                    }
                    // Notify after a brief delay to allow fly-off animation to start
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        onSwipe(direction)
                        dragOffset = .zero
                    }
                } else {
                    // Snap back
                    withAnimation(.spring(duration: 0.3, bounce: 0.4)) {
                        dragOffset = .zero
                    }
                }
            }
    }
}

// MARK: - Swipe Direction Helpers

extension SwipeDirection {
    /// Determines the dominant swipe direction from a drag offset, or nil if below threshold.
    static func from(offset: CGSize, threshold: CGFloat) -> SwipeDirection? {
        let absWidth = abs(offset.width)
        let absHeight = abs(offset.height)
        let maxDimension = max(absWidth, absHeight)

        guard maxDimension >= threshold else { return nil }

        if absWidth > absHeight {
            return offset.width < 0 ? .left : .right
        } else {
            return offset.height < 0 ? .up : .down
        }
    }
}

// MARK: - Preview

#Preview("SRSCardView") {
    let card = CardDTO(
        id: UUID(),
        front: "\u{6F22}",
        back: "kanji",
        type: .kanji,
        fsrsState: FSRSState(),
        easeFactor: 2.5,
        interval: 0,
        dueDate: Date(),
        lapseCount: 0,
        leechFlag: false
    )
    let nextCard = CardDTO(
        id: UUID(),
        front: "\u{5B66}",
        back: "study",
        type: .kanji,
        fsrsState: FSRSState(),
        easeFactor: 2.5,
        interval: 0,
        dueDate: Date(),
        lapseCount: 0,
        leechFlag: false
    )

    ZStack {
        Color.ikeruBackground.ignoresSafeArea()
        SRSCardView(card: card, nextCard: nextCard) { direction in
            print("Swiped: \(direction.label)")
        }
        .padding(IkeruTheme.Spacing.lg)
    }
    .preferredColorScheme(.dark)
}
