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

            // Only offered once this device holds a linked Keychain session
            // — `isLinkedWithApple`, not `hasEverHeldLinkedSessionOnThisDevice`
            // (that second flag covers a RESTORED device with an already-empty
            // Keychain, which has nothing local left to sign out of). Shown
            // in BOTH `isLinkedWithApple` branches above, including the
            // reauth-required one: a dead session is still this device's own
            // claim to the account, and sign-out is the deliberate way to
            // let go of it instead of being stuck between "sign in again" and
            // nothing else.
            if isLinkedWithApple {
                signOutRow
            }
        }
        // Attached to the whole block (not just `signOutRow`) so the
        // dialog's `isPresented` binding stays next to the row that opens
        // it, same pattern as `SettingsView`'s own `.alert`/`.confirmationDialog`
        // modifiers next to their triggering rows.
        .confirmationDialog(
            "Sign out of Apple?",
            isPresented: $showSignOutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sign out") { handleSignOut() } // no `role: .destructive` — deliberate, see `signOutRow`'s doc comment
            Button("Cancel", role: .cancel) {}
        } message: {
            // Deliberately does NOT say backup "resumes" or "picks back up"
            // on its own once signed back in — it doesn't.
            // `handleAppleSignIn()` never re-enables `cloudSyncConsentEnabled`
            // (and must not: re-enabling a privacy consent just because
            // authentication succeeded is exactly what this project's
            // consent model exists to prevent — see this file's git history
            // for the remediation this text is part of), so a sync
            // immediately after reconnecting returns `.skippedConsentOff`
            // and nothing is pushed. The learner has to turn Cloud backup
            // back on themselves; this text says so instead of promising an
            // automatic resume the code doesn't deliver.
            Text(
                "Your progress stays on this device, and stays on your account on the server. Backup stops until you sign in again and turn Cloud backup back on.",
                comment: "Explains that signing out is not destructive (local progress and the server account both survive) and that resuming backup takes two explicit steps: signing in again, then turning Cloud backup back on"
            )
        }
    }

    /// Non-destructive, deliberately styled to look nothing like
    /// `SettingsView.deleteCloudDataRow` (that row's label is
    /// `Color.ikeruDanger`; this one uses the same plain `ikeruTextPrimary`
    /// every other tappable settings row uses, via `settingRow`). The two
    /// actions must never be confused: this one only detaches THIS device
    /// from the account — nothing is erased anywhere, and it is fully
    /// reversible by signing back in.
    private var signOutRow: some View {
        settingRow(
            jp: "サインアウト", label: "Sign out",
            value: isSigningOut ? String(localized: "Signing out…") : "",
            showChevron: !isSigningOut, action: isSigningOut ? nil : { showSignOutConfirmation = true }
        )
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

    /// Voluntary sign-out — NOT `SettingsView.deleteCloudDataFromServer()`,
    /// and must never be confused with it (see `signOutRow`'s doc comment).
    /// `CloudSyncCoordinator.signOut()` only forgets THIS device's local
    /// claim to the account; the account and every row it owns are
    /// untouched on the server. Local SwiftData is never touched either —
    /// Ikeru is local-first, and this is purely a server-identity reset.
    ///
    /// On success, mirrors the local bookkeeping `deleteCloudDataFromServer()`
    /// already resets (consent, both timestamps, the stale error slot) so
    /// `hasEverBackedUp` goes back to `false` too — see the doc comment on
    /// `cloudSyncConsentEnabled`'s declaration for why that gate matters
    /// here. Also resets BOTH linked-state flags (`isLinkedWithApple` AND
    /// `hasEverHeldLinkedSessionOnThisDevice` — deletion only needs the
    /// first, because the account itself is gone; sign-out needs the
    /// second too, so `appleSignInBlock` falls straight back to the
    /// ordinary, tappable "Sign in with Apple" row — the reconnect UI the
    /// learner asked for — instead of lingering on the "your progress is
    /// waiting" branch for an account this device chose to leave, not lose.
    private func handleSignOut() {
        guard !isSigningOut else { return }
        isSigningOut = true
        Task { @MainActor in
            defer { isSigningOut = false }
            do {
                try await cloudSyncCoordinatorInstance().signOut()
                isLinkedWithApple = false
                hasEverHeldLinkedSessionOnThisDevice = false
                cloudSyncConsentEnabled = false
                cloudSyncLastSuccessEpoch = 0
                cloudSyncLastAttemptEpoch = 0
                cloudSyncLastError = ""
                appleSignInErrorMessage = nil
                // Same honesty fix as the confirmation dialog above: signing
                // in alone does not restart backup (`cloudSyncConsentEnabled`
                // is reset to `false` by this same method, above, and
                // `handleAppleSignIn()` never flips it back) — say so.
                toastManager.showInfo(
                    String(localized: "You're signed out. Your progress is safe on this device and on your account. To back up again, sign in and turn Cloud backup back on.")
                )
            } catch {
                Logger.ui.error("Sign out failed: \(String(describing: error))")
                toastManager.showError(
                    String(localized: "Couldn't sign out on this device. Try again.")
                )
            }
        }
    }
}
