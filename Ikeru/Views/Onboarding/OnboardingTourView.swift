import SwiftUI
import IkeruCore
import os

// MARK: - Onboarding Page Model

private struct OnboardingPage: Identifiable {
    let id: Int
    let kanji: String
    let romaji: String
    let title: String
    let subtitle: String
    let description: String
}

// MARK: - OnboardingTourView

struct OnboardingTourView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 0
    @State private var showAISetup = false

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            id: 0,
            kanji: "\u{9053}",
            romaji: "michi",
            title: "Your Journey",
            subtitle: "A path from curious to fluent",
            description: "Master kana, kanji, grammar, and conversation — one step at a time, at your own pace."
        ),
        OnboardingPage(
            id: 1,
            kanji: "\u{53CB}",
            romaji: "tomo",
            title: "Your Companion",
            subtitle: "A guide by your side",
            description: "Your AI companion adapts to you, celebrates your wins, and helps when things get tough."
        ),
        OnboardingPage(
            id: 2,
            kanji: "\u{59CB}",
            romaji: "hajime",
            title: "Begin",
            subtitle: "Your first lesson awaits",
            description: "You'll start with hiragana — the first writing system. Let's begin your Japanese adventure."
        ),
    ]

    var body: some View {
        ZStack {
            IkeruScreenBackground()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    ForEach(pages) { page in
                        OnboardingPageView(
                            page: page,
                            isLastPage: page.id == pages.count - 1,
                            onStartLearning: startLearning
                        )
                        .tag(page.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.spring(response: 0.5, dampingFraction: 0.86), value: currentPage)

                pageIndicator
                    .padding(.bottom, IkeruTheme.Spacing.xxl)
            }
        }
        .fullScreenCover(isPresented: $showAISetup, onDismiss: {
            dismiss()
        }) {
            AISetupView()
        }
    }

    // MARK: - Page Indicator

    private var pageIndicator: some View {
        HStack(spacing: IkeruTheme.Spacing.sm) {
            ForEach(0..<pages.count, id: \.self) { index in
                Capsule()
                    .fill(
                        index == currentPage
                            ? AnyShapeStyle(LinearGradient.ikeruGold)
                            : AnyShapeStyle(Color.white.opacity(0.18))
                    )
                    .frame(width: index == currentPage ? 24 : 8, height: 6)
                    .animation(.spring(response: 0.42, dampingFraction: 0.78), value: currentPage)
            }
        }
    }

    // MARK: - Actions

    private func startLearning() {
        Logger.ui.info("Onboarding tour completed — showing AI setup")
        showAISetup = true
    }
}

// MARK: - OnboardingPageView

private struct OnboardingPageView: View {

    let page: OnboardingPage
    let isLastPage: Bool
    let onStartLearning: () -> Void

    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: IkeruTheme.Spacing.xl) {
            Spacer()

            kanjiOrnament

            Spacer().frame(height: IkeruTheme.Spacing.md)

            contentBlock

            if isLastPage {
                startButton
                    .padding(.top, IkeruTheme.Spacing.lg)
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, IkeruTheme.Spacing.xl)
        .onAppear {
            withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }

    // MARK: - Kanji ornament

    private var kanjiOrnament: some View {
        VStack(spacing: 8) {
            Text(page.kanji)
                .font(.kanjiHero)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(hex: 0xF5DBB6),
                            Color(hex: 0xD4A574),
                            Color(hex: 0xB88A5C)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color(hex: 0xD4A574, opacity: 0.4), radius: 32)
                .scaleEffect(isAnimating ? 1.02 : 0.98)

            Text(page.romaji)
                .font(.ikeruMicro)
                .ikeruTracking(.micro)
                .foregroundStyle(Color.ikeruTextTertiary)
        }
    }

    // MARK: - Content block

    private var contentBlock: some View {
        VStack(spacing: IkeruTheme.Spacing.md) {
            VStack(spacing: 6) {
                Text(page.title)
                    .font(.ikeruDisplaySmall)
                    .ikeruTracking(.display)
                    .foregroundStyle(Color.ikeruTextPrimary)

                Text(page.subtitle)
                    .font(.ikeruBody)
                    .foregroundStyle(Color.ikeruPrimaryAccent.opacity(0.85))
            }

            Text(page.description)
                .font(.ikeruBody)
                .foregroundStyle(Color.ikeruTextSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, IkeruTheme.Spacing.md)
        }
    }

    // MARK: - Start button

    private var startButton: some View {
        Button {
            onStartLearning()
        } label: {
            HStack(spacing: 10) {
                Text("Start Learning")
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
        }
        .ikeruButtonStyle(.primary)
    }
}

// MARK: - Preview

#Preview("OnboardingTourView") {
    OnboardingTourView()
        .preferredColorScheme(.dark)
}
