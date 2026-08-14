import SwiftUI
import SwiftData
import AuthenticationServices
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
//
// ### The `.welcome` step and the restore path (2026-08, cloud-sync lot 3 gap)
//
// Cloud backup + Sign in with Apple shipped as a feature, but onboarding
// never mentioned either — a reinstalling learner was creating a brand-new,
// throwaway profile without ever being told their real progress was one tap
// away. `.welcome` is the fix: it offers the existing `.name` path
// (unchanged, still the frictionless default) alongside "I already have an
// account", which drives Apple sign-in → consent → a full `syncNow()` pull
// before this view decides anything. See `restoreAccount()` and
// `performRestoreSync()` below for the full sequencing, and
// `OnboardingRestoreDecision` for the decision itself (kept as a pure,
// non-SwiftUI type specifically so it can be unit-tested without a live
// `ModelContainer` or a real Apple identity).
struct NameEntryView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.profileViewModel) private var profileViewModel
    @Environment(\.modelContext) private var modelContext

    /// Set to `true` right before `dismiss()` on the restore-success path
    /// ONLY — `IkeruApp` reads it (and resets it) to skip posting
    /// `.requestFeatureTour`, which its `onChange(of: showOnboarding)`
    /// otherwise fires on every onboarding dismissal. A returning learner
    /// whose progress was just restored has already seen the tour, on
    /// whichever device backed it up. Defaults to a no-op binding so
    /// previews and any other caller that doesn't care about this distinction
    /// don't need to supply one.
    var finishedViaRestore: Binding<Bool> = .constant(false)

    @State private var step: Step = .welcome
    /// Shown on `.welcome` after a failed restore attempt — cleared at the
    /// start of every new attempt. `nil` the rest of the time.
    @State private var restoreErrorMessage: String?
    /// Shown once on `.name`, only when this session's restore attempt
    /// signed in successfully with Apple but the pull came back with no
    /// profile — a genuine, verified account that simply never backed
    /// anything up. Never set outside that one path.
    @State private var noBackupFoundNotice = false
    @State private var isSigningIn = false

    // AI setup was removed from onboarding (owner decision, 2026-07-19): asking
    // for a Gemini key before the user has even seen the app was premature.
    // The BYO-key CTA inside Sakura's chat (ConversationView) now carries that
    // moment — it appears exactly when the user first needs AI.
    private enum Step: Hashable { case welcome, restoring, name, placement, tour }

    var body: some View {
        ZStack {
            content
        }
        .animation(.easeInOut(duration: 0.4), value: step)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            WelcomeStep(
                errorMessage: restoreErrorMessage,
                isRestoringSignIn: isSigningIn,
                onStart: { advance(to: .name) },
                onRestoreAccount: { restoreAccount() }
            )
            .transition(.opacity)
        case .restoring:
            RestoringStep()
                .transition(.opacity)
        case .name:
            NameEntryStep(
                onContinue: { name in
                    profileViewModel?.createProfile(name: name)
                    advance(to: .placement)
                },
                noBackupFoundNotice: noBackupFoundNotice
            )
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

    // MARK: - Restore an existing account

    /// Entry point for the welcome screen's "I already have an account"
    /// button. Runs the native Apple sign-in sheet first; only once THAT
    /// succeeds does this hand off to `performRestoreSync()`. Consent is
    /// deliberately left untouched until sign-in has actually succeeded — a
    /// cancel or an auth failure must leave this device exactly as
    /// unconsented as it was before the tap, never half-decided.
    ///
    /// Three distinct failure shapes, each with its own message, all
    /// returning cleanly to `.welcome` (trivially true here — sign-in
    /// failures never leave `.welcome` in the first place):
    /// - a deliberate cancel (silent, not an error);
    /// - the identity token itself being rejected by the server
    ///   (`SyncAuthError.requestFailed` with a 4xx auth status, or the
    ///   link-identity guard tripping);
    /// - anything else, which in practice is almost always network-adjacent
    ///   (the same generic copy `SettingsView+AppleSignIn` already uses for
    ///   this bucket).
    private func restoreAccount() {
        guard !isSigningIn else { return }
        isSigningIn = true
        restoreErrorMessage = nil
        Task { @MainActor in
            defer { isSigningIn = false }
            do {
                let flow = AppleSignInFlow(identity: CloudSyncTriggers.shared.sharedIdentityManager)
                _ = try await flow.signIn()
                advance(to: .restoring)
                await performRestoreSync()
            } catch AppleSignInFlow.SignInError.userCanceled {
                // Deliberately silent — dismissing the system sheet is a
                // choice, not a failure.
                Logger.ui.info("Onboarding restore: sign-in canceled")
            } catch SyncAuthError.requestFailed(let status, _, _) where [400, 401, 403].contains(status) {
                restoreErrorMessage = String(localized: "Your Apple sign-in couldn't be verified. Please try again.")
            } catch AppleLinkError.linkIdentityGuardTripped {
                restoreErrorMessage = String(localized: "We couldn't verify your account connection. Nothing was changed — please try again.")
            } catch {
                Logger.ui.error("Onboarding restore sign-in failed: \(String(describing: error))")
                restoreErrorMessage = String(localized: "Couldn't sign in with Apple. Check your connection and try again.")
            }
        }
    }

    /// Runs once Apple sign-in has succeeded, on `.restoring`. Turns on
    /// backup consent — this IS the moment the welcome screen's disclosure
    /// sentence promised — then AWAITS a full `syncNow()` pull/push cycle
    /// before deciding anything. The one failure mode this whole step
    /// exists to prevent is dismissing onto an empty home screen while a
    /// pull is still in flight; nothing here returns early.
    private func performRestoreSync() async {
        let coordinator = CloudSyncTriggers.shared.sharedCoordinator(modelContainer: modelContext.container)
        await coordinator.setConsent(true)
        let outcome = await coordinator.syncNow()

        // Re-fetch from the store rather than trusting `outcome` alone —
        // see `OnboardingRestoreDecision.decide`'s doc comment for why a
        // profile can legitimately arrive even when this specific call
        // reports something other than a clean `.success`.
        profileViewModel?.loadProfile()
        let decision = OnboardingRestoreDecision.decide(
            outcome: outcome,
            hasProfile: profileViewModel?.hasProfile ?? false
        )

        switch decision {
        case .profileRestored:
            Logger.ui.info("Onboarding restore: profile found — skipping name/placement/tour")
            finishedViaRestore.wrappedValue = true
            dismiss()
        case .noBackupFound:
            Logger.ui.info("Onboarding restore: signed in, but no backup was found on the server")
            noBackupFoundNotice = true
            advance(to: .name)
        case .retryShortly:
            restoreErrorMessage = String(localized: "Still finishing up — please wait a moment and try again.")
            advance(to: .welcome)
        case .syncFailed(let message):
            Logger.ui.error("Onboarding restore sync failed: \(message, privacy: .public)")
            restoreErrorMessage = String(localized: "Couldn't reach the server. Check your connection and try again.")
            advance(to: .welcome)
        }
    }
}

// MARK: - OnboardingRestoreDecision (pure, testable)
//
// What `performRestoreSync()` above does next, once `CloudSyncCoordinator
// .syncNow()` has returned — expressed as a free function over plain,
// `Sendable`, `Equatable` values so it can be exercised directly from
// `IkeruTests` (`@testable import Ikeru`) without a live `ModelContainer`,
// a real Apple identity, or any SwiftUI machinery at all.
enum OnboardingRestoreDecision: Equatable {
    /// A profile arrived during the pull — this is a returning learner.
    /// Skip name entry, placement, and the tour entirely; go straight home.
    case profileRestored
    /// The pull completed (cleanly, or via the cold-start "seeded from
    /// local" path) but no profile came down — a genuine, verified Apple
    /// account that has simply never backed up from this or any other
    /// device. Falls through to ordinary profile creation, with an honest
    /// notice on that screen.
    case noBackupFound
    /// The sync didn't actually run this attempt — the throttle window, or
    /// another cycle already in flight (a foreground/network-regain
    /// trigger can race this exact call). Not evidence either way about
    /// whether a backup exists, so this is kept distinct from
    /// `.syncFailed`: the honest copy is "try again in a moment," not
    /// "something's wrong."
    case retryShortly
    /// The sync genuinely failed (network, server, or an explicit
    /// consent-off race) — this attempt cannot tell whether a backup
    /// exists. Never falls through to profile creation, which would risk
    /// creating a throwaway duplicate profile for someone whose real data
    /// simply couldn't be reached this time.
    case syncFailed(message: String)

    /// `hasProfile` — read from the store AFTER `syncNow()` returns — wins
    /// over everything else `outcome` reports. Two reasons this matters,
    /// not one:
    /// 1. Pull runs before push (`CloudSyncCoordinator`'s own doc comment);
    ///    a `.failure` outcome is the PUSH half failing, but the pull half
    ///    can have already landed a profile row moments earlier in the
    ///    same cycle.
    /// 2. A concurrent trigger (foreground, network-regain) can race this
    ///    exact call and independently deliver the profile while THIS call
    ///    reports `.skippedAlreadySyncing` — checking the actual database
    ///    state, not just this one call's return value, resolves that race
    ///    in the learner's favor instead of showing a spurious error.
    static func decide(outcome: CloudSyncCoordinator.SyncOutcome, hasProfile: Bool) -> OnboardingRestoreDecision {
        if hasProfile { return .profileRestored }

        switch outcome {
        case .success(_, let pull):
            switch pull {
            case .seededFromLocal, .applied:
                return .noBackupFound
            case .failed(let message):
                return .syncFailed(message: message)
            }
        case .failure(let message):
            return .syncFailed(message: message)
        case .skippedThrottled, .skippedAlreadySyncing:
            return .retryShortly
        case .skippedConsentOff:
            // Should be unreachable — this call sets consent true
            // immediately before calling `syncNow()` — but if it somehow
            // fires anyway, "can't tell" is the honest read, not "no
            // backup found".
            return .syncFailed(message: "consent unexpectedly off")
        }
    }
}

// MARK: - WelcomeStep

private struct WelcomeStep: View {

    let errorMessage: String?
    let isRestoringSignIn: Bool
    let onStart: () -> Void
    let onRestoreAccount: () -> Void

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

                startButton
                    .opacity(contentAppeared ? 1 : 0)
                    .offset(y: contentAppeared ? 0 : 16)

                Spacer().frame(height: IkeruTheme.Spacing.lg)

                restoreSection
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

    // MARK: - Hero block

    private var heroBlock: some View {
        VStack(spacing: IkeruTheme.Spacing.md) {
            // Japanese kanji ornament — 門, "gateway"
            Text("\u{9580}")
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
                Text("WELCOME")
                    .font(.ikeruMicro)
                    .ikeruTracking(.micro)
                    .foregroundStyle(Color.ikeruTextTertiary)

                Text("Let's get\nstarted")
                    .ikeruScaledFont(36, weight: .light, relativeTo: .title)
                    .ikeruTracking(.display)
                    .foregroundStyle(Color.ikeruTextPrimary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Start (default path, unchanged)

    private var startButton: some View {
        Button(action: onStart) {
            HStack(spacing: 10) {
                Text("\u{59CB}\u{3081}\u{308B}")  // 始める
                    .ikeruScaledFont(15, design: .serif, relativeTo: .body)
                Text("·")
                    .ikeruScaledFont(15, weight: .light, relativeTo: .body)
                    .foregroundStyle(Color(red: 0.16, green: 0.11, blue: 0.05).opacity(0.55))
                Text("Start")
                    .ikeruScaledFont(14, weight: .semibold, relativeTo: .body)
                    .tracking(1.0)
                    .textCase(.uppercase)
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
        }
        .ikeruButtonStyle(.primary)
        .disabled(isRestoringSignIn)
    }

    // MARK: - Restore an existing account

    private var restoreSection: some View {
        VStack(spacing: 6) {
            Text("Already used Ikeru before?")
                .ikeruScaledFont(12, relativeTo: .caption)
                .foregroundStyle(Color.ikeruTextTertiary)

            HStack(spacing: 10) {
                restoreAccountButton
                if isRestoringSignIn {
                    ProgressView().tint(Color.ikeruPrimaryAccent)
                }
            }

            Text("Signing in turns on backup, so we can restore your progress if you saved it before.")
                .ikeruScaledFont(11, relativeTo: .caption2)
                .foregroundStyle(TatamiTokens.paperGhost)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, IkeruTheme.Spacing.lg)

            if let errorMessage {
                Text(errorMessage)
                    .ikeruScaledFont(11, relativeTo: .caption2)
                    .foregroundStyle(Color.ikeruDanger)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        }
    }

    /// Apple's own button as pure chrome (hit-testing off, VoiceOver-hidden)
    /// — taps route through `onRestoreAccount`. The `.contentShape(Rectangle())`
    /// is load-bearing, not decoration: see `SettingsView+AppleSignIn
    /// .appleSignInRow`'s doc comment for the exact bug this avoids (a
    /// `Button` derives its tappable region from its label's content; a
    /// label with hit-testing disabled and no explicit content shape ends
    /// up with NO tappable region at all).
    private var restoreAccountButton: some View {
        Button(action: onRestoreAccount) {
            SignInWithAppleButton(.signIn) { _ in } onCompletion: { _ in }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .signInWithAppleButtonStyle(.whiteOutline)
                .frame(height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isRestoringSignIn)
        .accessibilityLabel(Text("I already have an account", comment: "Accessibility label for the Sign in with Apple button on onboarding's welcome screen"))
    }
}

// MARK: - RestoringStep

private struct RestoringStep: View {
    var body: some View {
        ZStack {
            IkeruScreenBackground()

            VStack(spacing: IkeruTheme.Spacing.lg) {
                ProgressView()
                    .tint(Color.ikeruPrimaryAccent)
                    .scaleEffect(1.3)

                Text("Restoring your progress…")
                    .ikeruScaledFont(17, weight: .light, relativeTo: .body)
                    .foregroundStyle(Color.ikeruTextPrimary)

                Text("This only takes a moment.")
                    .ikeruScaledFont(12, relativeTo: .caption)
                    .foregroundStyle(Color.ikeruTextTertiary)
            }
        }
    }
}

// MARK: - NameEntryStep

private struct NameEntryStep: View {

    let onContinue: (String) -> Void
    /// Set only when this screen was reached via a failed "no backup found"
    /// restore attempt (see `NameEntryView.performRestoreSync()`) — shows a
    /// small, honest notice above the usual hero, then behaves exactly like
    /// ordinary first-time name entry otherwise. `false` (no notice) for
    /// every other entry into this step.
    var noBackupFoundNotice: Bool = false

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

                if noBackupFoundNotice {
                    noBackupFoundBanner
                        .opacity(contentAppeared ? 1 : 0)
                        .padding(.bottom, IkeruTheme.Spacing.md)
                }

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

    // MARK: - No-backup notice

    private var noBackupFoundBanner: some View {
        Text("No backup was found for that Apple account — let's set up your profile.")
            .ikeruScaledFont(12, relativeTo: .caption)
            .foregroundStyle(Color.ikeruTextSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, IkeruTheme.Spacing.lg)
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
