import SwiftUI
import IkeruCore
import os

// MARK: - Onboarding Page Model

private struct OnboardingPage: Identifiable {
    let id: Int
    let icon: String
    let title: String
    let subtitle: String
    let description: String
}

// MARK: - OnboardingTourView

struct OnboardingTourView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            id: 0,
            icon: "map.fill",
            title: "Your Journey",
            subtitle: "A path from curious to fluent",
            description: "Master kana, kanji, grammar, and conversation — one step at a time, at your own pace."
        ),
        OnboardingPage(
            id: 1,
            icon: "bubble.left.fill",
            title: "Your Companion",
            subtitle: "A guide by your side",
            description: "Your AI companion adapts to you, celebrates your wins, and helps when things get tough."
        ),
        OnboardingPage(
            id: 2,
            icon: "sparkles",
            title: "Ready?",
            subtitle: "Your first lesson awaits",
            description: "You'll start with hiragana — the first writing system. Let's begin your Japanese adventure."
        ),
    ]

    var body: some View {
        ZStack {
            Color.ikeruBackground
                .ignoresSafeArea()

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
                .animation(.easeInOut(duration: IkeruTheme.Animation.standardDuration), value: currentPage)

                pageIndicator
                    .padding(.bottom, IkeruTheme.Spacing.xxl)
            }
        }
    }

    // MARK: - Page Indicator

    private var pageIndicator: some View {
        HStack(spacing: IkeruTheme.Spacing.sm) {
            ForEach(0..<pages.count, id: \.self) { index in
                Circle()
                    .fill(index == currentPage
                          ? Color.ikeruPrimaryAccent
                          : Color.white.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .scaleEffect(index == currentPage ? 1.2 : 1.0)
                    .animation(
                        .spring(duration: IkeruTheme.Animation.quickDuration),
                        value: currentPage
                    )
            }
        }
    }

    // MARK: - Actions

    private func startLearning() {
        Logger.ui.info("Onboarding tour completed — navigating to home")
        dismiss()
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

            iconSection

            contentCard

            if isLastPage {
                startButton
            }

            Spacer()
        }
        .padding(.horizontal, IkeruTheme.Spacing.lg)
        .onAppear {
            withAnimation(
                .easeInOut(duration: 2.0)
                .repeatForever(autoreverses: true)
            ) {
                isAnimating = true
            }
        }
    }

    // MARK: - Icon Section

    private var iconSection: some View {
        ZStack {
            Circle()
                .fill(Color.ikeruPrimaryAccent.opacity(0.15))
                .frame(width: 120, height: 120)
                .scaleEffect(isAnimating ? 1.1 : 1.0)

            Image(systemName: page.icon)
                .font(.system(size: 48))
                .foregroundStyle(Color.ikeruPrimaryAccent)
                .scaleEffect(isAnimating ? 1.05 : 0.95)
        }
    }

    // MARK: - Content Card

    private var contentCard: some View {
        VStack(spacing: IkeruTheme.Spacing.md) {
            Text(page.title)
                .font(.ikeruHeading1)
                .foregroundStyle(.white)

            Text(page.subtitle)
                .font(.ikeruHeading3)
                .foregroundStyle(Color.ikeruPrimaryAccent)

            Text(page.description)
                .font(.ikeruBody)
                .foregroundStyle(.ikeruTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(IkeruTheme.Spacing.lg)
        .ikeruCard(.elevated)
    }

    // MARK: - Start Button

    private var startButton: some View {
        Button("Start Learning") {
            onStartLearning()
        }
        .ikeruButtonStyle(.primary)
        .padding(.horizontal, IkeruTheme.Spacing.lg)
    }
}

// MARK: - Preview

#Preview("OnboardingTourView") {
    OnboardingTourView()
        .preferredColorScheme(.dark)
}
