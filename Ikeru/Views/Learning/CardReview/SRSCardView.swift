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

// MARK: - SRSCardView (deck)

/// A 3-layer deck showing the current card plus up to two peeks stacked
/// behind it. Promotions are smooth: when the front card flies off, the
/// second layer rises into the current slot (matched via `matchedGeometryEffect`
/// using each card's stable id), the third layer slides into the second, and
/// a brand-new third layer fades in at the back.
struct SRSCardView: View {

    let card: CardDTO
    /// Upcoming cards (first is slot-1 peek, second is slot-2, third is slot-3).
    /// The deck dynamically renders as many peeks as the array provides — so
    /// the visible stack depth naturally reflects how many reviews remain.
    let upcomingCards: [CardDTO]
    @Binding var isRevealed: Bool
    let onSwipe: (SwipeDirection) -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var isFlyingOff = false
    @State private var thresholdCrossed = false

    // Ephemeral "flying" state: when the user commits a swipe, we freeze the
    // outgoing card's visuals here and advance the deck data IMMEDIATELY.
    // The flying card animates off-screen as an overlay on top of the deck,
    // letting the peek promote upward in parallel (no sequential dead-time).
    @State private var flyingCard: CardDTO?
    @State private var flyingOffset: CGSize = .zero
    @State private var flyingRotation: Angle = .zero
    @State private var flyingRevealed: Bool = false
    @State private var flyingDirection: SwipeDirection?

    @Namespace private var deckNamespace

    /// Distance (in points) at which the grade indicator starts appearing.
    private let indicatorAppearanceDistance: CGFloat = 20
    /// Distance at which the grade is "committed" (haptic + visual snap).
    private let commitThreshold: CGFloat = 110
    /// Max rotation angle (degrees) at full drag extension.
    private let maxRotation: Double = 12
    /// Reference distance used to normalize rotation/tilt scaling.
    private let rotationReference: CGFloat = 320

    // Deck layer styling helpers — a single formula drives offset/scale/opacity
    // per depth so the stack visually thickens with more remaining cards.
    private func layerYOffset(forDepth depth: Int) -> CGFloat {
        CGFloat(depth) * 18
    }
    private func layerScale(forDepth depth: Int) -> CGFloat {
        max(0.80, 1.0 - CGFloat(depth) * 0.06)
    }
    private func layerOpacity(forDepth depth: Int) -> Double {
        max(0.30, 1.0 - Double(depth) * 0.22)
    }

    var body: some View {
        ZStack {
            // Peeks rendered back-to-front. Each layer's styling comes from
            // `layerYOffset/Scale/Opacity(forDepth:)` so the stack naturally
            // thickens with more remaining cards and collapses when few
            // reviews remain.
            ForEach(Array(upcomingCards.enumerated().reversed()), id: \.element.id) { index, peek in
                let depth = index + 1
                deckLayer(card: peek)
                    .offset(y: layerYOffset(forDepth: depth))
                    .scaleEffect(layerScale(forDepth: depth))
                    .opacity(layerOpacity(forDepth: depth))
                    .matchedGeometryEffect(id: peek.id, in: deckNamespace)
                    .allowsHitTesting(false)
                    .zIndex(Double(upcomingCards.count - index))
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }

            // Current card (interactive front) ---------------------------------
            // Hide the current slot while the very same card is still flying
            // off. Otherwise there's a brief window (between our sync state
            // reset and the async viewModel advance) where the stale card
            // data re-renders at the centre, making it look like the swiped
            // card "pops back" onto the stack.
            //
            // `.id(card.id)` forces a fresh view instance when the card
            // changes so SwiftUI doesn't interpolate visual properties
            // (border tint, shadow colour) from the outgoing card onto the
            // incoming one. The matchedGeometryEffect still runs because it
            // matches by namespace+id, not by view identity.
            if flyingCard?.id != card.id {
                currentCard
                    .overlay(dragBorderOverlay)
                    .overlay(alignment: .top) { gradeIndicator }
                    .shadow(color: swipeGlowColor, radius: swipeGlowRadius, y: 0)
                    .matchedGeometryEffect(id: card.id, in: deckNamespace)
                    .id(card.id)
                    .offset(dragOffset)
                    .rotationEffect(cardRotation, anchor: .bottom)
                    .rotation3DEffect(
                        cardTiltY,
                        axis: (x: 0, y: 1, z: 0),
                        anchor: .center,
                        anchorZ: 0,
                        perspective: 0.4
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !isFlyingOff, flyingCard == nil else { return }
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
                            isRevealed.toggle()
                        }
                    }
                    .highPriorityGesture(dragGesture, including: isRevealed ? .all : .subviews)
                    .sensoryFeedback(.impact(weight: .medium), trigger: thresholdCrossed)
                    .zIndex(1000)
            }

            // Flying card overlay (ephemeral) ----------------------------------
            // Rendered ON TOP of the deck while the old card animates off-screen.
            // The deck data has already advanced, so the new current card is
            // rising into place behind this overlay.
            if let flying = flyingCard {
                flyingCardView(for: flying)
                    .zIndex(2000)
            }
        }
        .onChange(of: card.id) { _, _ in
            dragOffset = .zero
            isFlyingOff = false
            thresholdCrossed = false
        }
    }

    // MARK: - Flying Card Overlay

    @ViewBuilder
    private func flyingCardView(for card: CardDTO) -> some View {
        cardContent(for: card, revealed: flyingRevealed)
            .tatamiRoom(.glass, padding: EdgeInsets(top: 28, leading: 28, bottom: 28, trailing: 28))
            .overlay(flyingBorderOverlay)
            .offset(flyingOffset)
            .rotationEffect(flyingRotation, anchor: .bottom)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var flyingBorderOverlay: some View {
        if let direction = flyingDirection {
            RoundedRectangle(cornerRadius: IkeruTheme.Radius.md, style: .continuous)
                .strokeBorder(direction.color.opacity(0.85), lineWidth: 3)
        }
    }

    // MARK: - Card Layers

    private var currentCard: some View {
        cardContent(for: card, revealed: isRevealed)
            .tatamiRoom(.glass, padding: EdgeInsets(top: 28, leading: 28, bottom: 28, trailing: 28))
    }

    /// A peek layer. Always shows the front of the card (never the answer)
    /// and uses the slightly softer `.standard` Tatami room surface.
    private func deckLayer(card: CardDTO) -> some View {
        cardContent(for: card, revealed: false)
            .tatamiRoom(.standard, padding: EdgeInsets(top: 28, leading: 28, bottom: 28, trailing: 28))
    }

    // MARK: - Card Content
    //
    // The card is now framed like a traditional scroll mount (掛軸): faint
    // corner ticks in each corner, a discreet category micro-label at the
    // top, glyph centered, and a row of hint chips at the bottom. The answer
    // state layers a kintsugi gold hairline between the kana and romaji —
    // the literal "repair seam" between what you saw and what you know.

    private func cardContent(for card: CardDTO, revealed: Bool) -> some View {
        ZStack {
            if revealed {
                cardBackContent(for: card)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            } else {
                cardFrontContent(for: card)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }

            // Bilingual deck label pinned to the top of the card. Replaces the
            // earlier tracked-uppercase category chip — the Tatami direction
            // uses serif Japanese + uppercase Latin chrome for category copy.
            VStack {
                let pair = bilingualLabelPair(for: card)
                BilingualLabel(japanese: pair.japanese, chrome: pair.chrome)
                    .padding(.top, 6)
                Spacer()
            }
            .allowsHitTesting(false)

            // Hint chips pinned to the bottom of the card.
            VStack {
                Spacer()
                HStack(spacing: 8) {
                    if revealed {
                        HintChip(icon: "ear", label: "Card.Hint.Listen")
                        HintChip(icon: "pencil.line", label: "Card.Hint.Strokes")
                        HintChip(icon: "text.bubble", label: "Card.Hint.Example")
                    } else {
                        HintChip(icon: "ear", label: "Card.Hint.Listen")
                        HintChip(icon: "eye", label: "Card.Hint.Hint")
                        HintChip(icon: "star", label: "Card.Hint.Mark")
                    }
                }
                .padding(.bottom, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 360)
    }

    /// Returns the `(japanese, chrome)` pair used by `BilingualLabel` at the
    /// top of every card. The chrome value is a `LocalizedStringKey` so it
    /// flows through `Localizable.xcstrings` and switches with the active
    /// app language.
    ///
    /// Beginner kana cards are seeded with type `.kanji` upstream, so a
    /// pure switch on `CardType` would mislabel hiragana/katakana as 漢字.
    /// Detection by scalar range stays authoritative for `.kanji` cards.
    private func bilingualLabelPair(for card: CardDTO) -> (japanese: String, chrome: LocalizedStringKey) {
        switch card.type {
        case .kanji:
            return kanjiOrKanaLabelPair(front: card.front)
        case .vocabulary:
            return ("\u{8A9E}\u{5F59}", "Vocabulary")          // 語彙
        case .grammar:
            return ("\u{6587}\u{6CD5}", "Grammar")             // 文法
        case .listening:
            return ("\u{8074}\u{89E3}", "Listening")           // 聴解
        }
    }

    private func kanjiOrKanaLabelPair(front: String) -> (japanese: String, chrome: LocalizedStringKey) {
        guard let scalar = front.unicodeScalars.first else {
            return ("\u{6F22}\u{5B57}", "Kanji")               // 漢字
        }
        let v = scalar.value
        // Hiragana block: U+3040..U+309F
        if (0x3040...0x309F).contains(v) {
            return ("\u{5E73}\u{4EEE}\u{540D}", "Hiragana")    // 平仮名
        }
        // Katakana block: U+30A0..U+30FF (and the phonetic extensions
        // U+31F0..U+31FF for completeness)
        if (0x30A0...0x30FF).contains(v) || (0x31F0...0x31FF).contains(v) {
            return ("\u{7247}\u{4EEE}\u{540D}", "Katakana")    // 片仮名
        }
        // Default: treat as kanji (CJK Unified Ideographs and extensions).
        return ("\u{6F22}\u{5B57}", "Kanji")                   // 漢字
    }

    @ViewBuilder
    private func cardFrontContent(for card: CardDTO) -> some View {
        switch card.type {
        case .kanji:
            // Tatami: large light serif with a warm gold shadow. The kana is
            // the room's centrepiece — let it breathe.
            Text(card.front)
                .font(.system(size: 200, weight: .light, design: .serif))
                .foregroundStyle(Color.ikeruTextPrimary)
                .shadow(color: Color.ikeruPrimaryAccent.opacity(0.25), radius: 32, y: 4)
                .minimumScaleFactor(0.4)
                .lineLimit(1)

        case .vocabulary:
            Text(card.front)
                .font(.system(size: 96, weight: .light, design: .serif))
                .foregroundStyle(Color.ikeruTextPrimary)
                .shadow(color: Color.ikeruPrimaryAccent.opacity(0.22), radius: 28, y: 4)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.4)
                .lineLimit(2)

        case .grammar:
            Text(card.front)
                .font(.system(size: 36, weight: .regular, design: .serif))
                .foregroundStyle(Color.ikeruTextPrimary)
                .multilineTextAlignment(.center)

        case .listening:
            VStack(spacing: IkeruTheme.Spacing.sm) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.ikeruPrimaryAccent)
                Text(card.front)
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .foregroundStyle(.ikeruTextSecondary)
            }
        }
    }

    @ViewBuilder
    private func cardBackContent(for card: CardDTO) -> some View {
        VStack(spacing: IkeruTheme.Spacing.md) {
            Text(card.front)
                .font(.system(size: 64, weight: .regular, design: .serif))
                .foregroundStyle(Color.ikeruTextSecondary)

            // Kintsugi repair seam — the gold hairline between what you saw
            // and what you now know. Fades at the edges so it reads as a
            // quiet thread, not a rule.
            KintsugiHairline()
                .frame(maxWidth: 140)

            Text(card.back)
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.ikeruPrimaryAccent)
                .multilineTextAlignment(.center)
                .padding(.horizontal, IkeruTheme.Spacing.md)
        }
    }

    // MARK: - Dominant Direction (progressive)

    private var currentDirection: SwipeDirection? {
        let absWidth = abs(dragOffset.width)
        let absHeight = abs(dragOffset.height)
        let maxDimension = max(absWidth, absHeight)
        guard maxDimension > indicatorAppearanceDistance else { return nil }

        if absWidth > absHeight {
            return dragOffset.width < 0 ? .left : .right
        } else {
            return dragOffset.height < 0 ? .up : .down
        }
    }

    private var commitProgress: CGFloat {
        let absWidth = abs(dragOffset.width)
        let absHeight = abs(dragOffset.height)
        let maxDimension = max(absWidth, absHeight)
        let appearance = indicatorAppearanceDistance
        guard maxDimension > appearance else { return 0 }
        let commit = commitThreshold
        let value = (maxDimension - appearance) / (commit - appearance)
        return min(1, max(0, value))
    }

    // MARK: - Transforms

    private var cardRotation: Angle {
        let normalizedOffset = dragOffset.width / rotationReference
        let clamped = max(-1, min(1, Double(normalizedOffset)))
        return .degrees(clamped * maxRotation)
    }

    private var cardTiltY: Angle {
        let normalized = dragOffset.width / (rotationReference * 2)
        let clamped = max(-1, min(1, Double(normalized)))
        return .degrees(clamped * 4)
    }

    // MARK: - Overlays

    /// Colored border that grows thicker as the user approaches the commit
    /// threshold. Gated on `isDragging && flyingCard == nil` so it can only
    /// ever appear during an active drag on the live front card — never on
    /// the promoted card or the ghost overlay.
    @ViewBuilder
    private var dragBorderOverlay: some View {
        if let direction = currentDirection, isDragging, flyingCard == nil {
            RoundedRectangle(cornerRadius: IkeruTheme.Radius.md, style: .continuous)
                .strokeBorder(direction.color.opacity(0.5 + 0.45 * commitProgress),
                              lineWidth: 1.5 + 2.5 * commitProgress)
                .allowsHitTesting(false)
        }
    }

    /// Soft outer glow that tints the card's shadow with the swipe color.
    /// Also gated on active drag with no flying ghost.
    private var swipeGlowColor: Color {
        guard isDragging, flyingCard == nil, let direction = currentDirection else {
            return Color.black.opacity(0.45)
        }
        return direction.color.opacity(0.35 + 0.35 * commitProgress)
    }

    private var swipeGlowRadius: CGFloat {
        let base: CGFloat = 18
        guard isDragging, flyingCard == nil, currentDirection != nil else { return base }
        return base + 16 * commitProgress
    }

    @ViewBuilder
    private var gradeIndicator: some View {
        if let direction = currentDirection, isDragging {
            Text(direction.label)
                .font(.ikeruHeading2)
                .foregroundStyle(direction.color)
                .padding(.horizontal, IkeruTheme.Spacing.md)
                .padding(.vertical, IkeruTheme.Spacing.sm)
                .background {
                    Capsule()
                        .fill(direction.color.opacity(0.15 + 0.15 * commitProgress))
                        .overlay {
                            Capsule()
                                .strokeBorder(direction.color.opacity(0.6 * commitProgress),
                                              lineWidth: 1)
                        }
                }
                .scaleEffect(0.85 + 0.15 * commitProgress)
                .opacity(0.6 + 0.4 * commitProgress)
                .padding(.top, -IkeruTheme.Spacing.md)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
                .animation(.spring(response: 0.25, dampingFraction: 0.75), value: direction.label)
                .animation(.spring(response: 0.2, dampingFraction: 0.8), value: commitProgress)
        }
    }

    // MARK: - Drag Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard !isFlyingOff, isRevealed else { return }

                let raw = value.translation
                let rubberBanded = rubberBand(raw)
                dragOffset = rubberBanded
                if !isDragging { isDragging = true }

                let crossed = dominantDistance(of: raw) >= commitThreshold
                if crossed && !thresholdCrossed {
                    thresholdCrossed = true
                } else if !crossed && thresholdCrossed {
                    thresholdCrossed = false
                }
            }
            .onEnded { value in
                isDragging = false
                guard !isFlyingOff, isRevealed else {
                    snapBack()
                    return
                }

                let committed = dominantDistance(of: value.translation) >= commitThreshold
                guard committed, let direction = currentDirection else {
                    snapBack()
                    thresholdCrossed = false
                    return
                }

                flyOff(direction: direction, predictedEndLocation: value.predictedEndTranslation)
            }
    }

    // MARK: - Gesture Helpers

    private func dominantDistance(of translation: CGSize) -> CGFloat {
        max(abs(translation.width), abs(translation.height))
    }

    private func rubberBand(_ translation: CGSize) -> CGSize {
        func band(_ value: CGFloat) -> CGFloat {
            let absValue = abs(value)
            guard absValue > commitThreshold else { return value }
            let excess = absValue - commitThreshold
            let dampened = commitThreshold + excess * 0.45
            return value < 0 ? -dampened : dampened
        }
        return CGSize(width: band(translation.width), height: band(translation.height))
    }

    private func snapBack() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.68)) {
            dragOffset = .zero
        }
        thresholdCrossed = false
    }

    /// Commits a swipe: snapshots the outgoing card into a flying overlay,
    /// advances the deck data immediately, and animates the overlay off-screen
    /// in parallel with the peek-to-current promotion (matchedGeometryEffect).
    private func flyOff(direction: SwipeDirection, predictedEndLocation: CGSize) {
        let minTravel: CGFloat = 700
        let target: CGSize = {
            switch direction {
            case .left:
                let x = min(-minTravel, predictedEndLocation.width)
                return CGSize(width: x, height: predictedEndLocation.height)
            case .right:
                let x = max(minTravel, predictedEndLocation.width)
                return CGSize(width: x, height: predictedEndLocation.height)
            case .up:
                let y = min(-minTravel, predictedEndLocation.height)
                return CGSize(width: predictedEndLocation.width, height: y)
            case .down:
                let y = max(minTravel, predictedEndLocation.height)
                return CGSize(width: predictedEndLocation.width, height: y)
            }
        }()

        // Capture the outgoing card's visual state BEFORE resetting dragOffset.
        let capturedOffset = dragOffset
        let capturedRotation = cardRotation

        // Apply the ghost's starting state AND reset the interactive drag
        // state in a single animation-disabled transaction. Wrapping both in
        // the same Transaction guarantees SwiftUI commits these values
        // instantly for the current render — otherwise the withAnimation
        // below would animate `flyingOffset` from its previous value (.zero)
        // instead of from `capturedOffset`, causing the ghost to briefly
        // appear at the centre before flying off.
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            flyingCard = card
            flyingRevealed = isRevealed
            flyingDirection = direction
            flyingOffset = capturedOffset
            flyingRotation = capturedRotation

            dragOffset = .zero
            isFlyingOff = true
            thresholdCrossed = false
            // Hide the answer BEFORE the new current card renders — otherwise
            // the promoted peek briefly inherits isRevealed=true and flashes
            // its answer for one frame.
            isRevealed = false
        }

        // Advance data IMMEDIATELY — peek promotion starts now (this change
        // IS animated by the parent's spring since it changes currentCard.id).
        onSwipe(direction)

        // Defer the fly-off animation to the NEXT run-loop tick so SwiftUI
        // has already committed `flyingOffset = capturedOffset` above. Without
        // this deferral, both assignments land in the same render pass and
        // SwiftUI animates from the prior `.zero` — making the ghost appear
        // to pop at the centre before flying off.
        let flyOffDuration: TimeInterval = 0.34
        let spinBias: Double = direction == .left ? -18 : (direction == .right ? 18 : 0)
        DispatchQueue.main.async {
            withAnimation(.timingCurve(0.25, 0.0, 0.25, 1.0, duration: flyOffDuration)) {
                self.flyingOffset = target
                self.flyingRotation = capturedRotation + .degrees(spinBias)
            }
        }

        // Clear the overlay once it's safely off-screen and unlock interaction.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(flyOffDuration + 0.05))
            flyingCard = nil
            flyingDirection = nil
            isFlyingOff = false
        }
    }
}

// MARK: - Swipe Direction Helpers

extension SwipeDirection {
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
    let after = CardDTO(
        id: UUID(),
        front: "\u{751F}",
        back: "life",
        type: .kanji,
        fsrsState: FSRSState(),
        easeFactor: 2.5,
        interval: 0,
        dueDate: Date(),
        lapseCount: 0,
        leechFlag: false
    )

    struct PreviewWrapper: View {
        @State var revealed = true
        let card: CardDTO
        let upcoming: [CardDTO]
        var body: some View {
            ZStack {
                Color.ikeruBackground.ignoresSafeArea()
                SRSCardView(
                    card: card,
                    upcomingCards: upcoming,
                    isRevealed: $revealed
                ) { direction in
                    print("Swiped: \(direction.label)")
                }
                .padding(IkeruTheme.Spacing.lg)
            }
            .preferredColorScheme(.dark)
        }
    }
    return PreviewWrapper(card: card, upcoming: [nextCard, after])
}
