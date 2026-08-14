import SwiftUI
import IkeruCore
import AuthenticationServices
import os

// MARK: - Sign in with Apple (lot 3)
//
// Split out of `SettingsView.swift` purely to keep that file under
// SwiftLint's `file_length` error threshold (it was already at 1799/1800
// lines before this lot touched it — zero headroom for the outcome-handling
// this remediation needed). No behavior change from the split itself: same
// `SettingsView` type, same state, just a second file. The handful of
// properties/helpers this extension touches (`isLinkedWithApple`,
// `isSigningInWithApple`, `appleSignInErrorMessage`, `cloudSyncLastError`,
// `settingRow`, `cloudSyncCoordinatorInstance()`) had to drop their
// `private` access — Swift's `private` is file-scoped, so a same-type
// extension in a different file cannot see them otherwise. They stay
// internal to the app module either way; nothing outside `Ikeru` could see
// them before or after.
extension SettingsView {

    /// Reauth > connected > restored-but-disconnected > not-yet-signed-in;
    /// not-yet-linked wraps Apple's own button as pure chrome.
    ///
    /// The two `isLinkedWithApple` rows above are tappable whenever they
    /// show (Critique #1) — a device that still has SOME stored session
    /// (dead or alive) always has a way back in. What Critique #1 did NOT
    /// solve, and this branch (2026-08 lot-3 round-2 remediation, IMPORTANT)
    /// does: a device restored from an iCloud backup taken AFTER linking
    /// Apple has an EMPTY Keychain, so `isLinkedWithApple` reads `false` —
    /// none of the branches above ever fire, and the learner lands on the
    /// plain, never-linked sign-in row with no hint that their progress is
    /// one tap away. `hasEverHeldLinkedSessionOnThisDevice` (backed by
    /// `AnonymousIdentityManager.hasEverHeldLinkedSession()`, which reads
    /// the `UserDefaults`-persisted marker that DOES survive a restore,
    /// unlike the Keychain) is what makes that case discoverable.
    @ViewBuilder
    var appleSignInBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isLinkedWithApple && cloudSyncLastError == SyncAuthError.reauthenticationRequiredMessage {
                settingRow(
                    jp: "サインイン", label: "Sign in again to keep syncing",
                    value: isSigningInWithApple ? String(localized: "Signing in…") : "",
                    showChevron: !isSigningInWithApple, action: isSigningInWithApple ? nil : { handleAppleSignIn() }
                )
            } else if isLinkedWithApple {
                settingRow(
                    jp: "サインイン", label: "Connected with Apple",
                    value: isSigningInWithApple ? String(localized: "Signing in…") : "",
                    showChevron: !isSigningInWithApple, action: isSigningInWithApple ? nil : { handleAppleSignIn() }
                )
            } else if hasEverHeldLinkedSessionOnThisDevice {
                // Restored device: the Keychain is empty (so none of the
                // `isLinkedWithApple` branches above fire), but this device
                // has held a linked session before — tapping runs the exact
                // same `handleAppleSignIn()` flow, which for a restored
                // learner re-authenticates as the SAME account (see
                // `AnonymousIdentityManager.linkOrSignInWithApple`'s
                // `.reauthenticatedAfterDeadSession` case).
                settingRow(
                    jp: "サインイン", label: "Your progress is waiting — sign in to reconnect",
                    value: isSigningInWithApple ? String(localized: "Signing in…") : "",
                    showChevron: !isSigningInWithApple, action: isSigningInWithApple ? nil : { handleAppleSignIn() }
                )
            } else {
                appleSignInRow
            }
            if let appleSignInErrorMessage {
                Text(appleSignInErrorMessage)
                    .ikeruScaledFont(11, relativeTo: .caption2).foregroundStyle(Color.ikeruDanger).padding(.horizontal, 16).padding(.bottom, 4)
            }
            Text("Sign in to pick up your progress on another device.", comment: "Explainer under the Sign in with Apple row")
                .ikeruScaledFont(11, relativeTo: .caption2).foregroundStyle(TatamiTokens.paperGhost).padding(.horizontal, 16).padding(.bottom, 12)
        }
    }

    /// Apple's own button as pure chrome (hit-testing off, VoiceOver-hidden) — taps route through `handleAppleSignIn()`.
    ///
    /// The `.contentShape(Rectangle())` is load-bearing, not decoration. A
    /// `Button` derives its tappable region from its label's content, and this
    /// label's only content has hit-testing disabled (so Apple's own button
    /// can't run its own flow). Without an explicit content shape the Button
    /// ends up with NO hit region at all and taps fall straight through it —
    /// which shipped, and looked exactly like "the button does nothing":
    /// silent, with no error and no log, because `handleAppleSignIn()` was
    /// never reached. Verified on device by instrumenting the flow and seeing
    /// zero output on tap.
    private var appleSignInRow: some View {
        HStack(spacing: 12) {
            Text(verbatim: "サインイン")
                .ikeruScaledFont(13, design: .serif, relativeTo: .caption).foregroundStyle(TatamiTokens.paperGhost)
            Button(action: handleAppleSignIn) {
                SignInWithAppleButton(.signIn) { _ in } onCompletion: { _ in }
                    .allowsHitTesting(false).accessibilityHidden(true).signInWithAppleButtonStyle(.whiteOutline).frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(isSigningInWithApple)
            .accessibilityLabel(Text("Sign in with Apple", comment: "Accessibility label for the sign-in row"))
            if isSigningInWithApple { ProgressView().tint(Color.ikeruPrimaryAccent) }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(TatamiTokens.goldDim.opacity(0.2)).frame(height: 1).padding(.horizontal, 16)
        }
    }

    /// Drives `AppleSignInFlow.signIn()` and CONSUMES its `AppleLinkOutcome`
    /// (Important #4 — was `_ = try await flow.signIn()`), so a switch to a
    /// DIFFERENT existing account is actually disclosed, not silently shown
    /// as an ordinary success. `.switchedIdentity` alone can't tell that
    /// apart from "reconnected as myself" (the post-restore recovery path
    /// hits the same case) — comparing `userID` against `lastKnownUserID()`
    /// (survives a restore; the Keychain session doesn't) resolves it.
    /// Known gap: "Delete my data from the server" never clears
    /// `lastKnownUserID`, so a stale value there can still misfire this.
    private func handleAppleSignIn() {
        guard !isSigningInWithApple else { return }
        isSigningInWithApple = true
        appleSignInErrorMessage = nil
        // Captured before the call — see this method's doc comment.
        let previousUserID = UserDefaultsSyncIdentityStore().lastKnownUserID()
        Task { @MainActor in
            defer { isSigningInWithApple = false }
            do {
                // Shared instance (Mineur #7) — see
                // `CloudSyncTriggers.sharedIdentityManager`'s doc comment.
                let flow = AppleSignInFlow(identity: CloudSyncTriggers.shared.sharedIdentityManager)
                let outcome = try await flow.signIn()
                isLinkedWithApple = true
                hasEverHeldLinkedSessionOnThisDevice = true // keeps both flags consistent after a fresh link/reconnect
                cloudSyncLastError = "" // clears a stale reconnect-required banner

                switch outcome {
                case .linkedExistingIdentity, .reauthenticatedAfterDeadSession:
                    break // same account this device already knew about
                case .switchedIdentity(let userID, let wasAlreadyLinkedElsewhere):
                    // userID equality wins over the case label — a re-tap
                    // on an account already linked to SELF must stay silent
                    // even if Core happens to label it `.switchedIdentity`
                    // (`wasAlreadyLinkedElsewhere: true`); see this
                    // method's doc comment.
                    if userID != previousUserID && (previousUserID != nil || wasAlreadyLinkedElsewhere) {
                        appleSignInErrorMessage = String(
                            localized: "This Apple ID is already linked to another account. You're now signed in as that account — this device's earlier backup is no longer reachable."
                        )
                    }
                }

                // Mineur #7, second half: push the newly linked session's
                // data now, rather than waiting on the next unrelated
                // foreground/network-regain trigger.
                await cloudSyncCoordinatorInstance().syncNow()
            } catch AppleSignInFlow.SignInError.userCanceled {
                // Deliberately silent for the learner: dismissing the sheet is
                // a choice, not a failure. Logged anyway, because Apple also
                // reports `.canceled` when the sheet CANNOT be presented —
                // so a genuine misconfiguration is otherwise indistinguishable
                // from a tap on "Cancel", and both look like nothing happened.
                Logger.ui.info("Sign in with Apple: canceled (user dismissal, or the sheet could not be presented)")
            } catch AppleLinkError.linkIdentityGuardTripped {
                appleSignInErrorMessage = String(localized: "We couldn't verify your account connection. Nothing was changed — please try again.")
            } catch {
                Logger.ui.error("Sign in with Apple failed: \(String(describing: error))")
                appleSignInErrorMessage = String(localized: "Couldn't sign in with Apple. Check your connection and try again.")
            }
        }
    }
}
