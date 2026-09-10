import AuthenticationServices
import CryptoKit
import Foundation
import IkeruCore
import UIKit

/// Drives the native "Sign in with Apple" system UI and hands the result to
/// `AnonymousIdentityManager.linkOrSignInWithApple` — cloud-sync lot 3
/// (`docs/design-specs/2026-08-10-cloud-sync-design.md` §4).
///
/// `AuthenticationServices` has no place in `IkeruCore` (that package is
/// dependency-free by design and carries zero UIKit/AppKit surface) — this
/// type is the ONLY place in the app that talks to `ASAuthorizationController`
/// directly. Everything past "I have a verified Apple identity token" is
/// Core's job (`AnonymousIdentityManager.linkOrSignInWithApple`, including
/// the link_identity guard) — this file's entire responsibility is getting
/// that token, safely, and nothing more.
///
/// ### The nonce
///
/// A fresh, cryptographically random nonce is generated per attempt. Its
/// SHA-256 hex digest goes into `ASAuthorizationAppleIDRequest.nonce` (Apple
/// signs the identity token over the HASH); the RAW nonce is what gets sent
/// to Supabase afterward (`AnonymousIdentityManager.linkOrSignInWithApple`'s
/// `rawNonce` parameter — Supabase hashes it server-side to verify against
/// the token's own embedded hash claim). Getting this backwards — sending
/// Supabase the hash instead of the raw value — only fails at request time,
/// on a real device, with a real Apple token: nothing about it is visible in
/// a unit test, which is exactly why it is called out here, explicitly, for
/// whoever next touches this file.
///
/// ### Full name is deliberately never requested
///
/// `request.requestedScopes` is left empty — `.fullName` is NOT requested.
/// The app's own locally-set profile name is already the learner's
/// reference identity and is already synced independently of this flow.
/// Apple hands back the real name on the FIRST authorization ever and
/// **never again on any subsequent one** (a well-documented Apple
/// limitation, not a bug to work around) — capturing it here would silently
/// diverge from the profile name on every later reinstall/relink, for no
/// benefit this app actually needs. Do not "fix" this by adding `.fullName`
/// back without re-reading this paragraph.
@MainActor
public final class AppleSignInFlow: NSObject {

    public enum SignInError: Error, Sendable, Equatable {
        /// The system sheet has no identity token to hand back — a
        /// non-Apple-ID credential type came back instead, or
        /// `identityToken` was nil/not UTF-8. Should not happen in
        /// practice; surfaced rather than force-unwrapped.
        case missingIdentityToken
        /// The learner dismissed the system Sign in with Apple sheet.
        /// Distinguished from every other error so the caller can stay
        /// silent instead of showing an alert for a deliberate cancel.
        case userCanceled
        /// `signIn()` was called again while a previous attempt on this
        /// SAME instance was still in flight. Never silently drops the
        /// first caller's continuation — see `signIn()`'s reentrancy guard.
        case alreadyInProgress
        /// Any other `ASAuthorizationController` failure (not
        /// `.canceled`) — network-adjacent failures the system framework
        /// itself reports, not something this type can distinguish further.
        case underlying(String)
    }

    private let identity: AnonymousIdentityManager

    /// Holds everything the two `ASAuthorizationControllerDelegate`
    /// callbacks touch, OUTSIDE this type's own `@MainActor` isolation —
    /// deliberately, not an oversight. Apple's documentation does not
    /// commit `ASAuthorizationController`'s delegate callbacks to arriving
    /// on the main thread. If this class's delegate conformance methods
    /// were themselves `@MainActor`-isolated (the default for methods on an
    /// `@MainActor` type), Swift 6's dynamic actor-isolation checking
    /// (SE-0423) inserts a runtime assertion into their `@objc` thunks —
    /// an off-main callback would not race this state (a lock would have
    /// handled that fine), it would **trap**, crashing mid-sign-in. Boxing
    /// the mutable state in its own `@unchecked Sendable` class and marking
    /// the delegate methods `nonisolated` below sidesteps the isolation
    /// question entirely rather than assuming a guarantee Apple's docs
    /// don't make.
    private final class InFlightBox: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<AppleLinkOutcome, Error>?
        private var rawNonce: String?
        /// `ASAuthorizationController.delegate` is `weak`, so a purely-local
        /// `controller` in `signIn()` would risk deallocating mid-flight
        /// (the method suspends on the continuation, nothing else keeps the
        /// controller alive) and silently losing every callback, hanging
        /// the caller forever. Held here for the lifetime of one `signIn()`
        /// call instead.
        private var controller: ASAuthorizationController?

        var isInFlight: Bool {
            lock.withLock { continuation != nil }
        }

        func start(continuation: CheckedContinuation<AppleLinkOutcome, Error>, rawNonce: String, controller: ASAuthorizationController) {
            lock.withLock {
                self.continuation = continuation
                self.rawNonce = rawNonce
                self.controller = controller
            }
        }

        /// Atomically takes (and clears) the in-flight continuation +
        /// nonce — called from both delegate callbacks so exactly one of
        /// them ever resumes the continuation, regardless of which thread
        /// they land on.
        func take() -> (continuation: CheckedContinuation<AppleLinkOutcome, Error>?, rawNonce: String?) {
            lock.withLock {
                let result = (continuation, rawNonce)
                continuation = nil
                rawNonce = nil
                controller = nil
                return result
            }
        }
    }

    private let box = InFlightBox()

    public init(identity: AnonymousIdentityManager) {
        self.identity = identity
        super.init()
    }

    /// Presents the system Sign in with Apple sheet and, on success, calls
    /// through to `AnonymousIdentityManager.linkOrSignInWithApple` — see
    /// that method's doc comment for the full link-vs-sign-in decision tree
    /// and the guard that protects it. Throws `SignInError.alreadyInProgress`
    /// immediately (rather than clobbering the first call's continuation,
    /// which would hang it forever) if called again before a previous
    /// attempt on this SAME instance has finished.
    public func signIn() async throws -> AppleLinkOutcome {
        guard !box.isInFlight else { throw SignInError.alreadyInProgress }

        let rawNonce = Self.randomNonceString()

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.nonce = Self.sha256Hex(rawNonce)
        // Deliberately empty — see this type's doc comment.
        request.requestedScopes = []

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self

        return try await withCheckedThrowingContinuation { continuation in
            box.start(continuation: continuation, rawNonce: rawNonce, controller: controller)
            controller.performRequests()
        }
    }

    // MARK: - Nonce generation
    // Standard, widely-documented Apple Sign In sample pattern — a
    // `SecRandomCopyBytes`-sourced random string, SHA-256 hashed for the
    // request's `nonce` field.

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed with OSStatus \(status)")
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256Hex(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AppleSignInFlow: ASAuthorizationControllerDelegate {

    /// `nonisolated` — see `InFlightBox`'s doc comment for why these two
    /// callbacks must NOT be `@MainActor`-isolated. `identity` (a Sendable
    /// actor reference) and `box` (`@unchecked Sendable`, its own lock) are
    /// both safe to touch from any isolation context; the `Task { }` below
    /// is what actually calls into the (actor-isolated) identity manager.
    nonisolated public func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        let (continuation, rawNonce) = box.take()
        guard let continuation else { return } // already resumed, or a stray callback after a reentrancy rejection

        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = credential.identityToken,
            let idToken = String(data: tokenData, encoding: .utf8),
            let rawNonce
        else {
            continuation.resume(throwing: SignInError.missingIdentityToken)
            return
        }

        Task {
            do {
                let outcome = try await identity.linkOrSignInWithApple(idToken: idToken, rawNonce: rawNonce)
                continuation.resume(returning: outcome)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    nonisolated public func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let (continuation, _) = box.take()
        guard let continuation else { return }

        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            continuation.resume(throwing: SignInError.userCanceled)
        } else {
            continuation.resume(throwing: SignInError.underlying(String(describing: error)))
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AppleSignInFlow: ASAuthorizationControllerPresentationContextProviding {

    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Called synchronously from `performRequests()`, which `signIn()`
        // above only ever calls from `@MainActor` context — `UIApplication
        // .shared`'s window lookup is safe here for that reason, not by
        // accident. Deliberately left `@MainActor`-isolated (the default,
        // unlike the two callbacks above) since nothing forces this one
        // off-main and UIKit window access needs to stay on it.
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        return keyWindow ?? ASPresentationAnchor()
    }
}
