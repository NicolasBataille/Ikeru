import SwiftUI
import UIKit
import IkeruCore

/// A destructive-action button that requires a sustained press to fire.
/// While held, a progress fill sweeps left-to-right and a haptic ramp builds
/// in intensity and cadence so the user physically feels the commitment
/// growing. Releasing before completion cancels with a soft tap.
///
/// Inspired by the "hold to confirm" pattern used by Instagram, Things, and
/// other apps that guard irreversible operations.
struct HoldToConfirmButton: View {

    let title: String
    let icon: String?
    let duration: TimeInterval
    let onConfirm: () -> Void

    init(
        title: String,
        icon: String? = nil,
        duration: TimeInterval = 1.4,
        onConfirm: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.duration = duration
        self.onConfirm = onConfirm
    }

    // MARK: - State

    @State private var progress: Double = 0
    @State private var isHolding = false
    @State private var didComplete = false
    @State private var timer: Timer?
    @State private var holdStart: Date?
    @State private var lastHapticTime: Date?

    // Reusable haptic generators — prepared once per hold to reduce latency.
    private let impactGen = UIImpactFeedbackGenerator(style: .medium)
    private let successGen = UINotificationFeedbackGenerator()
    private let cancelGen = UIImpactFeedbackGenerator(style: .light)

    // MARK: - Body

    /// Total height of the pill.
    private let pillHeight: CGFloat = 76

    var body: some View {
        Color.clear
            .frame(height: pillHeight)
            .overlay(buttonBody)
    }

    private var buttonBody: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Base surface — danger-tinted glass pill.
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)

                Capsule(style: .continuous)
                    .fill(Color.ikeruDanger.opacity(0.10))

                // Progress fill — clipped to the pill. Gradient escalates
                // from danger (start) to a brighter warning at the leading edge
                // so the bar visibly "heats up" as it fills.
                ZStack(alignment: .leading) {
                    LinearGradient(
                        colors: [
                            Color.ikeruDanger.opacity(0.95),
                            Color.ikeruDanger.opacity(0.70),
                            Color(hex: IkeruTheme.Colors.warning).opacity(0.65)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: max(0, geo.size.width * CGFloat(progress)))

                    // Bright leading edge — gives the fill a crisp head.
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0),
                                    Color.white.opacity(0.25)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: progress > 0 ? 24 : 0,
                            height: pillHeight
                        )
                        .offset(x: max(0, geo.size.width * CGFloat(progress) - 24))
                        .blendMode(.plusLighter)
                        .opacity(isHolding ? 1 : 0)
                }
                .clipShape(Capsule(style: .continuous))
                .animation(isHolding ? nil : .easeOut(duration: 0.32), value: progress)

                // Border.
                Capsule(style: .continuous)
                    .strokeBorder(
                        Color.ikeruDanger.opacity(isHolding ? 0.85 : 0.55),
                        lineWidth: 1.2
                    )

                // Label — icon + title centered.
                HStack(spacing: IkeruTheme.Spacing.sm) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 17, weight: .semibold))
                    }
                    Text(labelText)
                        .font(.system(size: 17, weight: .semibold))
                        .ikeruTracking(.body)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .foregroundStyle(labelColor)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, IkeruTheme.Spacing.lg)
                .animation(.easeInOut(duration: 0.18), value: isHolding)
            }
            .contentShape(Capsule(style: .continuous))
            .scaleEffect(isHolding ? 0.985 : 1.0)
            .shadow(
                color: Color.ikeruDanger.opacity(isHolding ? 0.4 : 0.18),
                radius: isHolding ? 26 : 14,
                y: 8
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.86), value: isHolding)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isHolding && !didComplete { beginHold() }
                    }
                    .onEnded { _ in
                        if !didComplete { cancelHold() }
                    }
            )
        }
        .frame(height: pillHeight)
    }

    // MARK: - Dynamic label / color

    private var labelText: String {
        if didComplete { return "Deleting…" }
        if isHolding {
            return progress >= 0.95 ? "Release" : "Hold to confirm"
        }
        return title
    }

    private var labelColor: Color {
        progress > 0.35 ? Color(hex: 0xFFF5EC) : Color.ikeruDanger
    }

    // MARK: - Gesture handling

    private func beginHold() {
        isHolding = true
        holdStart = Date()
        lastHapticTime = nil
        impactGen.prepare()
        successGen.prepare()

        // Initial subtle tap to acknowledge contact.
        impactGen.impactOccurred(intensity: 0.25)

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            Task { @MainActor in tick() }
        }
    }

    @MainActor
    private func tick() {
        guard isHolding, let start = holdStart else {
            timer?.invalidate()
            timer = nil
            return
        }

        let now = Date()
        let elapsed = now.timeIntervalSince(start)
        let newProgress = min(1.0, elapsed / duration)
        progress = newProgress

        // Ramp haptic cadence: start ~130ms between pulses, accelerate to ~40ms.
        let cadence = max(0.04, 0.13 - newProgress * 0.09)
        let intensity = CGFloat(0.25 + newProgress * 0.75)
        if let last = lastHapticTime {
            if now.timeIntervalSince(last) >= cadence {
                impactGen.impactOccurred(intensity: intensity)
                lastHapticTime = now
            }
        } else {
            impactGen.impactOccurred(intensity: intensity)
            lastHapticTime = now
        }

        if newProgress >= 1.0 {
            timer?.invalidate()
            timer = nil
            complete()
        }
    }

    private func cancelHold() {
        timer?.invalidate()
        timer = nil
        isHolding = false
        holdStart = nil
        lastHapticTime = nil
        cancelGen.impactOccurred(intensity: 0.5)
        withAnimation(.easeOut(duration: 0.28)) {
            progress = 0
        }
    }

    private func complete() {
        didComplete = true
        isHolding = false
        holdStart = nil
        successGen.notificationOccurred(.success)
        onConfirm()
    }
}

// MARK: - Preview

#Preview("HoldToConfirmButton") {
    ZStack {
        Color.ikeruBackground.ignoresSafeArea()

        VStack(spacing: IkeruTheme.Spacing.xl) {
            HoldToConfirmButton(
                title: "Delete Nico",
                icon: "trash.fill"
            ) {
                print("Confirmed")
            }
        }
        .padding(IkeruTheme.Spacing.lg)
    }
    .preferredColorScheme(.dark)
}
