import SwiftUI

// MARK: - SerifNumeral
//
// All numerals in the Tatami vocabulary render in Noto Serif JP. This view
// wraps the `Text` + `.font(.system(...design: .serif))` pattern so call
// sites stay readable and consistent.

struct SerifNumeral: View {
    let value: String
    var size: CGFloat = 32
    var weight: Font.Weight = .light
    var color: Color = .ikeruTextPrimary

    init(_ value: String, size: CGFloat = 32, weight: Font.Weight = .light, color: Color = .ikeruTextPrimary) {
        self.value = value
        self.size = size
        self.weight = weight
        self.color = color
    }

    init(_ value: Int, size: CGFloat = 32, weight: Font.Weight = .light, color: Color = .ikeruTextPrimary) {
        self.value = "\(value)"
        self.size = size
        self.weight = weight
        self.color = color
    }

    var body: some View {
        Text(value)
            .font(.system(size: size, weight: weight, design: .serif))
            .foregroundStyle(color)
    }
}

#Preview("SerifNumeral") {
    VStack(spacing: 24) {
        SerifNumeral(12, size: 56)
        SerifNumeral("84", size: 32)
        SerifNumeral("6:42", size: 40, color: .ikeruPrimaryAccent)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.ikeruBackground)
    .preferredColorScheme(.dark)
}
