import SwiftUI
import IkeruCore

// MARK: - ToastView

public struct ToastView: View {

    let item: ToastItem
    let onDismiss: () -> Void

    public var body: some View {
        HStack(spacing: IkeruTheme.Spacing.sm) {
            Image(systemName: iconName)
                .font(.system(size: IkeruTheme.Typography.Size.body, weight: .semibold))

            Text(item.message)
                .font(.system(size: IkeruTheme.Typography.Size.body))
                .lineLimit(3)

            Spacer()

            if item.type == .error {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: IkeruTheme.Typography.Size.caption, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, IkeruTheme.Spacing.md)
        .padding(.vertical, IkeruTheme.Spacing.sm + IkeruTheme.Spacing.xs)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: IkeruTheme.Radius.md))
        .padding(.horizontal, IkeruTheme.Spacing.md)
    }

    private var iconName: String {
        switch item.type {
        case .info:
            return "info.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    private var backgroundColor: Color {
        switch item.type {
        case .info:
            return Color(hex: IkeruTheme.Colors.primaryAccent)
        case .error:
            return Color(hex: IkeruTheme.Colors.secondaryAccent)
        }
    }
}

// MARK: - Toast Overlay Modifier

public struct ToastOverlayModifier: ViewModifier {

    @Environment(\.toastManager) private var toastManager

    public func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast = toastManager.currentToast {
                    ToastView(item: toast) {
                        toastManager.dismiss()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(
                        .spring(duration: IkeruTheme.Animation.standardDuration),
                        value: toastManager.currentToast?.id
                    )
                    .padding(.top, IkeruTheme.Spacing.xl)
                }
            }
    }
}

extension View {
    public func toastOverlay() -> some View {
        modifier(ToastOverlayModifier())
    }
}

// MARK: - Preview

#Preview("Toast Variants") {
    ZStack {
        Color(hex: IkeruTheme.Colors.background)
            .ignoresSafeArea()

        VStack(spacing: IkeruTheme.Spacing.lg) {
            ToastView(
                item: ToastItem(message: "Study session complete! +50 XP", type: .info),
                onDismiss: {}
            )

            ToastView(
                item: ToastItem(message: "Network error. Please try again.", type: .error),
                onDismiss: {}
            )
        }
    }
    .preferredColorScheme(.dark)
}
