import SwiftUI
import IkeruCore
import os

// MARK: - GrammarListView
//
// The reader the grammar points never had.
//
// The bundle has carried grammar since the first content build, and **nothing
// displayed it** — verified 2026-08-19: `GrammarPointView` was instantiated
// nowhere, `VocabularyStudyViewModel` (which loads the points) was instantiated
// nowhere, and a session's `.grammarExercise` renders a placeholder card
// reading "Grammar Exercise / Grammar point" rather than any real content.
//
// That was the same shape as the example sentences before they were wired: the
// content grew (31 → 51 points on 2026-08-19, closing the official N5 list at
// 40/40) while no screen could show it.
//
// This view is deliberately the smallest thing that makes them readable: a list
// under Étude, mirroring the vocabulary dictionary's path exactly, feeding the
// `GrammarPointView` that already existed. Turning grammar into a graded
// exercise — replacing that placeholder, and giving `LearnerSnapshotBuilder`
// something other than the hardcoded `grammarPointsFamiliarPlus: 0` — is a
// separate piece of work and is NOT attempted here.

/// Lists the bundled grammar points, in the learner's language.
struct GrammarListView: View {

    @State private var points: [GrammarPoint] = []
    @State private var hasLoaded = false

    var body: some View {
        ZStack {
            IkeruScreenBackground()

            if !hasLoaded {
                ProgressView()
                    .tint(Color.ikeruPrimaryAccent)
            } else if points.isEmpty {
                // Reachable only if the bundle is missing or unreadable. Say so
                // rather than showing an empty list, which reads as "you have
                // no grammar" instead of "the content failed to load".
                Text("Grammar.Empty")
                    .font(.ikeruBody)
                    .foregroundStyle(Color.ikeruTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(IkeruTheme.Spacing.xl)
            } else {
                ScrollView {
                    VStack(spacing: IkeruTheme.Spacing.sm) {
                        header
                        ForEach(points) { point in
                            NavigationLink {
                                ScrollView { GrammarPointView(grammarPoint: point) }
                                    .background(IkeruScreenBackground().ignoresSafeArea())
                            } label: {
                                row(point)
                            }
                            .buttonStyle(.plain)
                        }
                        // Clears the floating tab bar (76.33pt measured, see
                        // `IkeruTabBar`) for scrolling content.
                        Spacer(minLength: 140)
                    }
                    .padding(.horizontal, IkeruTheme.Spacing.lg)
                }
            }
        }
        .task { await load() }
        .accessibilityIdentifier("grammar.list")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Grammar.Title")
                .ikeruScaledFont(11, weight: .semibold, relativeTo: .caption2)
                .tracking(2)
                .textCase(.uppercase)
                .foregroundStyle(Color.ikeruTextTertiary)
            Text("Grammar.Count \(points.count)")
                .font(.ikeruBody)
                .foregroundStyle(Color.ikeruTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, IkeruTheme.Spacing.md)
        .padding(.bottom, IkeruTheme.Spacing.sm)
    }

    private func row(_ point: GrammarPoint) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(point.title)
                .ikeruScaledFont(16, weight: .regular, relativeTo: .body)
                .foregroundStyle(Color.ikeruTextPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(point.explanation)
                .ikeruScaledFont(13, weight: .regular, relativeTo: .footnote)
                .foregroundStyle(Color.ikeruTextTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(IkeruTheme.Spacing.md)
        .background {
            Rectangle()
                .fill(Color.white.opacity(0.03))
                .overlay { Rectangle().strokeBorder(TatamiTokens.goldDim.opacity(0.35), lineWidth: 0.6) }
        }
        .sumiCorners(color: TatamiTokens.goldDim, size: 5, weight: 0.9)
        // One element per point, so VoiceOver reads the title with its
        // explanation instead of two orphaned strings.
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        defer { hasLoaded = true }
        guard let repository = BundledContent.makeRepository() else {
            Logger.ui.error("grammar list: bundled content unavailable")
            return
        }
        points = await repository.grammarPointsByLevel(.n5)
    }
}
