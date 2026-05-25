import SwiftUI

// MARK: - Feature Tour Overlay
//
// The visible layer of the tour: a dimming scrim with a punched-out spotlight
// around the current target plus a floating callout in Sakura's voice. Placed
// via `.overlayPreferenceValue(TourAnchorKey.self)` so it can resolve the live
// frames of tagged elements through the supplied GeometryProxy.

struct FeatureTourOverlay: View {

    let controller: FeatureTourController
    let anchors: [TourTarget: Anchor<CGRect>]
    let proxy: GeometryProxy

    private enum Layout {
        static let spotlightInsetX: CGFloat = -12
        static let spotlightInsetY: CGFloat = -10
        static let spotlightRadius: CGFloat = 16
        static let bubbleGap: CGFloat = 22
        static let bubbleMaxWidth: CGFloat = 360
        static let edgePadding: CGFloat = 80
    }

    var body: some View {
        if let step = controller.currentStep {
            let spotlight = spotlightRect(for: step)
            ZStack {
                dimLayer(spotlight: spotlight)

                if let rect = spotlight {
                    RoundedRectangle(cornerRadius: Layout.spotlightRadius, style: .continuous)
                        .stroke(Color.ikeruPrimaryAccent.opacity(0.85), lineWidth: 1.5)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .shadow(color: Color.ikeruPrimaryAccent.opacity(0.45), radius: 12)
                        .allowsHitTesting(false)
                }

                bubbleContainer(step: step, spotlight: spotlight)
            }
            .ignoresSafeArea()
            .animation(.spring(response: 0.45, dampingFraction: 0.86), value: controller.index)
            .transition(.opacity)
        }
    }

    // MARK: - Dim + spotlight cutout

    @ViewBuilder
    private func dimLayer(spotlight: CGRect?) -> some View {
        ZStack {
            Rectangle().fill(Color.black.opacity(0.82))

            if let rect = spotlight {
                RoundedRectangle(cornerRadius: Layout.spotlightRadius, style: .continuous)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .blendMode(.destinationOut) // punches a transparent hole
            }
        }
        .compositingGroup()
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { controller.next() } // tap anywhere on the scrim advances
    }

    // MARK: - Callout bubble placement
    //
    // The bubble keeps its intrinsic height and is pinned by one edge relative
    // to the spotlight (above for bottom-half targets like the tab bar, below
    // otherwise). This avoids measuring the bubble, so localized copy of any
    // length lays out correctly.

    @ViewBuilder
    private func bubbleContainer(step: TourStep, spotlight: CGRect?) -> some View {
        let height = proxy.size.height
        let maxWidth = min(proxy.size.width - 40, Layout.bubbleMaxWidth)

        if let rect = spotlight {
            if rect.midY > height / 2 {
                bubble(step: step)
                    .frame(width: maxWidth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, max(Layout.edgePadding, height - rect.minY + Layout.bubbleGap))
            } else {
                bubble(step: step)
                    .frame(width: maxWidth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, min(height - Layout.edgePadding, rect.maxY + Layout.bubbleGap))
            }
        } else {
            bubble(step: step)
                .frame(width: maxWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    @ViewBuilder
    private func bubble(step: TourStep) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Sakura is the voice of the tour — her mark + name head every step.
            HStack(alignment: .center, spacing: 10) {
                SakuraMark(size: 30)
                Text(verbatim: "Sakura")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(Color.ikeruPrimaryAccent)
                Spacer()
                Button { controller.skip() } label: {
                    Text("Tour.Button.Skip")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.ikeruTextTertiary)
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(step.title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.ikeruTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let kanji = step.kanji {
                    Text(kanji)
                        .font(.system(size: 22, weight: .regular, design: .serif))
                        .foregroundStyle(LinearGradient.ikeruGold)
                }
            }

            Text(step.message)
                .font(.system(size: 15))
                .foregroundStyle(Color.ikeruTextSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            progressDots
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 2)

            HStack(spacing: 12) {
                if !controller.isFirstStep {
                    Button { controller.back() } label: {
                        Text("Tour.Button.Back")
                            .frame(maxWidth: .infinity)
                    }
                    .ikeruButtonStyle(.ghost)
                }

                Button { controller.next() } label: {
                    Text(controller.isLastStep ? "Tour.Button.Start" : "Tour.Button.Next")
                        .frame(maxWidth: .infinity)
                }
                .ikeruButtonStyle(.primary)
            }
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
    }

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<controller.totalSteps, id: \.self) { i in
                Capsule()
                    .fill(
                        i == controller.index
                            ? AnyShapeStyle(LinearGradient.ikeruGold)
                            : AnyShapeStyle(Color.white.opacity(0.2))
                    )
                    .frame(width: i == controller.index ? 18 : 6, height: 5)
            }
        }
    }

    // MARK: - Geometry

    private func spotlightRect(for step: TourStep) -> CGRect? {
        guard let target = step.target, let anchor = anchors[target] else { return nil }
        let rect = proxy[anchor]
        guard rect.width > 0, rect.height > 0 else { return nil }
        return rect.insetBy(dx: Layout.spotlightInsetX, dy: Layout.spotlightInsetY)
    }
}
