import SwiftUI
import IkeruCore

// MARK: - Kanji Section

/// Collapsible sections in the kanji study view.
private enum KanjiSection: String, CaseIterable, Sendable {
    case radicals = "Radicals"
    case readings = "Readings"
    case vocabulary = "Vocabulary"

    var iconName: String {
        switch self {
        case .radicals: "square.grid.2x2"
        case .readings: "character.book.closed"
        case .vocabulary: "text.book.closed"
        }
    }
}

// MARK: - KanjiStudyView

/// Main view for studying a kanji with radical decomposition, readings, and vocabulary.
/// Uses collapsible sections with progressive disclosure.
struct KanjiStudyView: View {

    @State private var viewModel: KanjiStudyViewModel
    @State private var expandedSections: Set<KanjiSection> = [.radicals, .readings]

    init(viewModel: KanjiStudyViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: IkeruTheme.Spacing.lg) {
                // Always visible kanji display
                KanjiDisplayView(kanji: viewModel.kanji)

                // Content sections based on loading state
                contentSections
            }
            .padding(.horizontal, IkeruTheme.Spacing.md)
            .padding(.vertical, IkeruTheme.Spacing.lg)
        }
        .background(Color(hex: IkeruTheme.Colors.background))
        .task {
            await viewModel.loadContent()
        }
    }

    // MARK: - Content Sections

    @ViewBuilder
    private var contentSections: some View {
        switch viewModel.loadingState {
        case .idle, .loading:
            loadingIndicator

        case .loaded:
            collapsibleSection(.radicals) {
                RadicalDecompositionView(radicals: viewModel.radicals)
            }

            collapsibleSection(.readings) {
                ReadingsView(
                    onReadings: viewModel.kanji.onReadings,
                    kunReadings: viewModel.kanji.kunReadings
                )
            }

            collapsibleSection(.vocabulary) {
                VocabularyExamplesView(vocabulary: viewModel.vocabulary)
            }

        case .failed(let error):
            errorView(error)
        }
    }

    // MARK: - Collapsible Section

    private func collapsibleSection<Content: View>(
        _ section: KanjiSection,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            sectionHeader(section)

            if expandedSections.contains(section) {
                content()
                    .padding(.top, IkeruTheme.Spacing.sm)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func sectionHeader(_ section: KanjiSection) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                if expandedSections.contains(section) {
                    expandedSections.remove(section)
                } else {
                    expandedSections.insert(section)
                }
            }
        } label: {
            HStack {
                Image(systemName: section.iconName)
                    .font(.system(size: IkeruTheme.Typography.Size.body))
                    .foregroundStyle(Color(hex: IkeruTheme.Colors.primaryAccent))

                Text(section.rawValue)
                    .font(.system(size: IkeruTheme.Typography.Size.heading3, weight: .semibold))
                    .foregroundStyle(Color(hex: IkeruTheme.Colors.textPrimary))

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.system(size: IkeruTheme.Typography.Size.caption, weight: .semibold))
                    .foregroundStyle(
                        Color(hex: IkeruTheme.Colors.textPrimary)
                            .opacity(IkeruTheme.Colors.textSecondaryOpacity)
                    )
                    .rotationEffect(
                        expandedSections.contains(section)
                        ? .degrees(0)
                        : .degrees(-90)
                    )
            }
            .padding(.vertical, IkeruTheme.Spacing.sm)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(section.rawValue) section")
        .accessibilityHint(
            expandedSections.contains(section)
            ? "Collapse"
            : "Expand"
        )
    }

    // MARK: - Loading & Error

    private var loadingIndicator: some View {
        VStack(spacing: IkeruTheme.Spacing.md) {
            ProgressView()
                .tint(Color(hex: IkeruTheme.Colors.primaryAccent))
            Text("Loading content...")
                .font(.system(size: IkeruTheme.Typography.Size.caption))
                .foregroundStyle(
                    Color(hex: IkeruTheme.Colors.textPrimary)
                        .opacity(IkeruTheme.Colors.textSecondaryOpacity)
                )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, IkeruTheme.Spacing.xl)
    }

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: IkeruTheme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: IkeruTheme.Typography.Size.heading1))
                .foregroundStyle(Color(hex: IkeruTheme.Colors.secondaryAccent))

            Text("Failed to load content")
                .font(.system(size: IkeruTheme.Typography.Size.body, weight: .medium))
                .foregroundStyle(Color(hex: IkeruTheme.Colors.textPrimary))

            Text(error.localizedDescription)
                .font(.system(size: IkeruTheme.Typography.Size.caption))
                .foregroundStyle(
                    Color(hex: IkeruTheme.Colors.textPrimary)
                        .opacity(IkeruTheme.Colors.textSecondaryOpacity)
                )
                .multilineTextAlignment(.center)

            Button("Retry") {
                Task {
                    await viewModel.loadContent()
                }
            }
            .foregroundStyle(Color(hex: IkeruTheme.Colors.primaryAccent))
            .padding(.top, IkeruTheme.Spacing.sm)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, IkeruTheme.Spacing.xl)
    }
}
