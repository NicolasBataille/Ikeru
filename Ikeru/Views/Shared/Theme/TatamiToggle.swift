import SwiftUI
import IkeruCore

/// Wabi-minimal on/off toggle. A thin hairline track with a small dot
/// that slides to one end on tap. Gold + filled when ON, paper-ghost +
/// empty stroke when OFF. Replaces the iOS native Toggle on rows where
/// the chrome shouldn't shout.
struct TatamiToggle: View {

    @Binding var isOn: Bool
    let onChange: (Bool) -> Void

    private let trackWidth: CGFloat = 36
    private let trackHeight: CGFloat = 16
    private let knobSize: CGFloat = 10

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                isOn.toggle()
            }
            onChange(isOn)
        } label: {
            ZStack {
                Capsule()
                    .stroke(
                        isOn ? Color.ikeruPrimaryAccent : TatamiTokens.goldDim.opacity(0.55),
                        lineWidth: 1
                    )
                    .background(
                        Capsule()
                            .fill(
                                isOn
                                    ? Color.ikeruPrimaryAccent.opacity(0.18)
                                    : Color.white.opacity(0.02)
                            )
                    )
                    .frame(width: trackWidth, height: trackHeight)

                HStack(spacing: 0) {
                    if isOn { Spacer(minLength: 0) }
                    Circle()
                        .fill(
                            isOn ? Color.ikeruPrimaryAccent : TatamiTokens.paperGhost.opacity(0.7)
                        )
                        .frame(width: knobSize, height: knobSize)
                    if !isOn { Spacer(minLength: 0) }
                }
                .frame(width: trackWidth - 6, height: knobSize)
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? Text("On") : Text("Off"))
    }
}

#Preview("TatamiToggle") {
    struct Wrapper: View {
        @State var on = false
        var body: some View {
            VStack(spacing: 18) {
                TatamiToggle(isOn: $on, onChange: { _ in })
                Text(on ? "ON" : "OFF").foregroundStyle(.white)
            }
            .padding(40)
            .background(Color.ikeruBackground)
        }
    }
    return Wrapper().preferredColorScheme(.dark)
}
