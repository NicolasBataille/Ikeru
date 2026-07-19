import SwiftUI
import SwiftData
import IkeruCore
import os

// MARK: - NameEntryView (onboarding coordinator)
//
// A single full-screen onboarding flow. Previously each step presented the
// next via a nested `fullScreenCover`, so finishing peeled them away one slow
// dismissal at a time. Now all steps live inside ONE cover (the one presented
// by `IkeruApp`) and are swapped with a calm cross-fade; finishing calls
// `dismiss()` exactly once, so the app drops straight to Home in a single
// transition. The feature tour then fires from `IkeruApp`'s `showOnboarding`
// change, as before.

struct NameEntryView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.profileViewModel) private var profileViewModel

    @State private var step: Step = .name

    // AI setup was removed from onboarding (owner decision, 2026-07-19): asking
    // for a Gemini key before the user has even seen the app was premature.
    // The BYO-key CTA inside Sakura's chat (ConversationView) now carries that
    // moment — it appears exactly when the user first needs AI.
    private enum Step: Hashable { case name, placement, tour }

    var body: some View {
        ZStack {
            content
        }
        .animation(.easeInOut(duration: 0.4), value: step)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .name:
            NameEntryStep(onContinue: { name in
                profileViewModel?.createProfile(name: name)
                advance(to: .placement)
            })
            .transition(.opacity)
        case .placement:
            PlacementStep(onContinue: { advance(to: .tour) })
                .transition(.opacity)
        case .tour:
            OnboardingTourView(onFinish: { dismiss() })
                .transition(.opacity)
        }
    }

    private func advance(to next: Step) {
        withAnimation(.easeInOut(duration: 0.4)) { step = next }
    }
}

// MARK: - NameEntryStep

private struct NameEntryStep: View {

    let onContinue: (String) -> Void

    @State private var name: String = ""
    @State private var contentAppeared = false
    @FocusState private var isNameFieldFocused: Bool

    private var isNameValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            IkeruScreenBackground()

            VStack(spacing: 0) {
                Spacer()

                heroBlock
                    .opacity(contentAppeared ? 1 : 0)
                    .offset(y: contentAppeared ? 0 : 16)

                Spacer().frame(height: IkeruTheme.Spacing.xxl)

                nameInputSection
                    .opacity(contentAppeared ? 1 : 0)
                    .offset(y: contentAppeared ? 0 : 16)

                Spacer().frame(height: IkeruTheme.Spacing.xl)

                continueButton
                    .opacity(contentAppeared ? 1 : 0)
                    .offset(y: contentAppeared ? 0 : 16)

                Spacer()
                Spacer()
            }
            .padding(.horizontal, IkeruTheme.Spacing.xl)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.86).delay(0.1)) {
                contentAppeared = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isNameFieldFocused = true
            }
        }
    }

    // MARK: - Hero block

    private var heroBlock: some View {
        VStack(spacing: IkeruTheme.Spacing.md) {
            // Japanese kanji ornament
            Text("\u{4E2D}")
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

            VStack(spacing: 8) {
                Text("YOUR JOURNEY BEGINS")
                    .font(.ikeruMicro)
                    .ikeruTracking(.micro)
                    .foregroundStyle(Color.ikeruTextTertiary)

                Text("What should\nwe call you?")
                    .ikeruScaledFont(36, weight: .light, relativeTo: .title)
                    .ikeruTracking(.display)
                    .foregroundStyle(Color.ikeruTextPrimary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Name Input

    private var nameInputSection: some View {
        TextField(
            "",
            text: $name,
            prompt: Text("Your name").foregroundStyle(TatamiTokens.paperGhost)
        )
        .ikeruScaledFont(22, design: .serif, relativeTo: .title2)
        .foregroundStyle(Color.ikeruTextPrimary)
        .multilineTextAlignment(.center)
        .padding(.vertical, IkeruTheme.Spacing.md)
        .padding(.horizontal, IkeruTheme.Spacing.lg)
        .background(Color.ikeruBackground.opacity(isNameFieldFocused ? 0.45 : 0.55))
        .sumiCorners(
            color: isNameFieldFocused ? .ikeruPrimaryAccent : TatamiTokens.goldDim,
            size: 10,
            weight: isNameFieldFocused ? 1.5 : 1.0,
            inset: -1
        )
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isNameFieldFocused)
        .focused($isNameFieldFocused)
        .submitLabel(.continue)
        .onSubmit { submit() }
        .textInputAutocapitalization(.words)
        .autocorrectionDisabled()
    }

    // MARK: - Continue Button

    private var continueButton: some View {
        Button {
            submit()
        } label: {
            HStack(spacing: 10) {
                Text("\u{7D9A}\u{3051}\u{308B}")  // 続ける
                    .ikeruScaledFont(15, design: .serif, relativeTo: .body)
                Text("·")
                    .ikeruScaledFont(15, weight: .light, relativeTo: .body)
                    .foregroundStyle(Color(red: 0.16, green: 0.11, blue: 0.05).opacity(0.55))
                Text("Continue")
                    .ikeruScaledFont(14, weight: .semibold, relativeTo: .body)
                    .tracking(1.0)
                    .textCase(.uppercase)
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
        }
        .ikeruButtonStyle(.primary)
        .disabled(!isNameValid)
        .opacity(isNameValid ? 1.0 : 0.45)
        .scaleEffect(isNameValid ? 1.0 : 0.98)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isNameValid)
    }

    // MARK: - Actions

    private func submit() {
        guard isNameValid else { return }
        Logger.ui.info("Name submitted for profile creation")
        isNameFieldFocused = false
        onContinue(name)
    }
}

// MARK: - PlacementStep
//
// One calm question after name entry: are you starting fresh, or do you
// already know some Japanese? The answer sets the app's `DisplayMode` —
// `.beginner` (reading aids on, the default) or `.tatami` (kanji-first,
// translations hidden) — so experienced learners opt into density upfront
// instead of having to discover the Settings toggle. Fully reversible there
// ("Tatami interface"), so this is a gentle nudge, not a lock-in.

private struct PlacementStep: View {

    let onContinue: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var contentAppeared = false

    var body: some View {
        ZStack {
            IkeruScreenBackground()

            VStack(spacing: 0) {
                Spacer()

                heroBlock
                    .opacity(contentAppeared ? 1 : 0)
                    .offset(y: contentAppeared ? 0 : 16)

                Spacer().frame(height: IkeruTheme.Spacing.xxl)

                VStack(spacing: IkeruTheme.Spacing.md) {
                    choice(
                        kanji: "\u{521D}",  // 初 — beginning
                        title: "I'm just starting",
                        subtitle: "Kana, romaji, and reading aids on. The gentle path.",
                        mode: .beginner
                    )
                    choice(
                        kanji: "\u{7573}",  // 畳 — tatami (mirrors the Settings toggle)
                        title: "I know some already",
                        subtitle: "Kanji-first, translations hidden. Change anytime in Settings.",
                        mode: .tatami
                    )
                }
                .opacity(contentAppeared ? 1 : 0)
                .offset(y: contentAppeared ? 0 : 16)

                Spacer()
                Spacer()
            }
            .padding(.horizontal, IkeruTheme.Spacing.xl)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.86).delay(0.1)) {
                contentAppeared = true
            }
        }
    }

    // MARK: - Hero

    private var heroBlock: some View {
        VStack(spacing: 8) {
            Text("ONE QUESTION")
                .font(.ikeruMicro)
                .ikeruTracking(.micro)
                .foregroundStyle(Color.ikeruTextTertiary)

            Text("Have you studied\nJapanese before?")
                .ikeruScaledFont(30, weight: .light, relativeTo: .title)
                .ikeruTracking(.display)
                .foregroundStyle(Color.ikeruTextPrimary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Choice card

    private func choice(
        kanji: String,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        mode: DisplayMode
    ) -> some View {
        Button {
            select(mode)
        } label: {
            HStack(spacing: IkeruTheme.Spacing.md) {
                Text(kanji)
                    .font(.system(size: 30, weight: .light, design: .serif))
                    .foregroundStyle(Color.ikeruPrimaryAccent)
                    .frame(width: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .ikeruScaledFont(17, weight: .regular, relativeTo: .body)
                        .foregroundStyle(Color.ikeruTextPrimary)
                    Text(subtitle)
                        .ikeruScaledFont(12, relativeTo: .caption2)
                        .foregroundStyle(Color.ikeruTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TatamiTokens.goldDim)
            }
            .contentShape(Rectangle())
            .tatamiRoom(.standard, padding: 18)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func select(_ mode: DisplayMode) {
        makeDisplayModeRepo().set(mode)
        NotificationCenter.default.post(name: .displayModeDidChange, object: nil)
        Logger.ui.info("Placement chosen — displayMode=\(mode.rawValue, privacy: .public)")
        onContinue()
    }

    /// Builds a repository the same way `MainTabView` does. The profile created
    /// at name entry is already the active profile, so `set` writes to the
    /// correct profile-scoped key.
    private func makeDisplayModeRepo() -> UserDefaultsDisplayModePreferenceRepository {
        let container = modelContext.container
        return UserDefaultsDisplayModePreferenceRepository(
            defaults: .standard,
            activeProfileID: { ActiveProfileResolver.activeProfileID() },
            profileCreatedAt: { id in
                let descriptor = FetchDescriptor<UserProfile>(
                    predicate: #Predicate { $0.id == id }
                )
                return (try? container.mainContext.fetch(descriptor))?.first?.createdAt
            }
        )
    }
}

// MARK: - Preview

#Preview("NameEntryView") {
    NameEntryView()
        .preferredColorScheme(.dark)
}
