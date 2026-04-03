import SwiftUI
import IkeruCore

// MARK: - MnemonicView

/// Displays an AI-generated mnemonic for a kanji character.
/// Shows loading, content, error, and empty states with a regenerate button.
struct MnemonicView: View {

    let mnemonicText: String?
    let loadingState: LoadingState<Void>
    let onRegenerate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.sm) {
            header
            content
        }
        .ikeruCard(.elevated)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "lightbulb.max")
                .font(.system(size: IkeruTheme.Typography.Size.body))
                .foregroundStyle(Color(hex: IkeruTheme.Colors.primaryAccent))

            Text("Mnemonic")
                .font(.system(size: IkeruTheme.Typography.Size.heading3, weight: .semibold))
                .foregroundStyle(Color(hex: IkeruTheme.Colors.textPrimary))

            Spacer()

            regenerateButton
        }
    }

    // MARK: - Regenerate Button

    private var regenerateButton: some View {
        Button {
            onRegenerate()
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: IkeruTheme.Typography.Size.caption, weight: .medium))
        }
        .ikeruButtonStyle(.secondary)
        .disabled(loadingState.isLoading)
        .accessibilityLabel("Regenerate mnemonic")
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch loadingState {
        case .idle:
            emptyState

        case .loading:
            loadingIndicator

        case .loaded:
            if let text = mnemonicText, !text.isEmpty {
                Text(text)
                    .font(.system(size: IkeruTheme.Typography.Size.body))
                    .foregroundStyle(Color(hex: IkeruTheme.Colors.textPrimary))
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                emptyState
            }

        case .failed:
            errorState
        }
    }

    // MARK: - States

    private var loadingIndicator: some View {
        HStack(spacing: IkeruTheme.Spacing.sm) {
            ProgressView()
                .tint(Color(hex: IkeruTheme.Colors.primaryAccent))

            Text("Generating mnemonic...")
                .font(.system(size: IkeruTheme.Typography.Size.caption))
                .foregroundStyle(
                    Color(hex: IkeruTheme.Colors.textPrimary)
                        .opacity(IkeruTheme.Colors.textSecondaryOpacity)
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, IkeruTheme.Spacing.sm)
    }

    private var emptyState: some View {
        Text("No mnemonic available yet.")
            .font(.system(size: IkeruTheme.Typography.Size.caption))
            .foregroundStyle(
                Color(hex: IkeruTheme.Colors.textPrimary)
                    .opacity(IkeruTheme.Colors.textSecondaryOpacity)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, IkeruTheme.Spacing.sm)
    }

    private var errorState: some View {
        HStack(spacing: IkeruTheme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: IkeruTheme.Typography.Size.caption))
                .foregroundStyle(Color(hex: IkeruTheme.Colors.secondaryAccent))

            Text("Failed to generate mnemonic. Tap regenerate to try again.")
                .font(.system(size: IkeruTheme.Typography.Size.caption))
                .foregroundStyle(
                    Color(hex: IkeruTheme.Colors.textPrimary)
                        .opacity(IkeruTheme.Colors.textSecondaryOpacity)
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, IkeruTheme.Spacing.sm)
    }
}
