import SwiftUI

/// GAP-10 bisection experiment (2026-08-16): swaps the real `App` entry point
/// for an empty one when the process is `xcodebuild test`'s test host.
///
/// Why this exists: gating `IkeruApp`'s `.task { }` on
/// `isRunningUnderXCTest` (see `IkeruApp.swift`) stopped that block's startup
/// work from running, but `IkeruApp.init()` still ran UNCONDITIONALLY as
/// part of mounting the real `WindowGroup` scene — it still built its own
/// real `ModelContainer`, still registered a `BGTaskScheduler` handler. That
/// second container was the leading suspect for the
/// `SwiftData/BackingData.swift:940: Fatal error: Never access a full future
/// backing data` crash, which reproduced even for a SINGLE test run in
/// complete isolation.
///
/// RESULT (measured, not supposé): the suspicion was WRONG. With this swap
/// in place — `TestHostApp` never touches SwiftData, `ActiveProfileResolver`,
/// or `UserDefaults.standard`'s active-profile key, and `IkeruApp` is never
/// instantiated under test — `HomeViewModelTests.loadDataLoadsRPGState()`,
/// run alone, still crashed with the byte-for-byte identical fatal error
/// (verified via `-resultBundlePath` + `xcrun xcresulttool export
/// diagnostics`). So `IkeruApp`'s own `ModelContainer` is RULED OUT as the
/// (sole) cause. This file is kept as a permanent isolation instrument — an
/// empty test host is good hygiene regardless — and as the falsification
/// record for that hypothesis; see GAP-10's final report for what evidence
/// remains (two distinct crash signatures under `xcodebuild test`, no other
/// reachable `ModelContainer(` construction found by a repo-wide grep, root
/// mechanism still unidentified).
@main
struct IkeruMain {
    static func main() {
        if IkeruApp.isRunningUnderXCTest {
            TestHostApp.main()
        } else {
            IkeruApp.main()
        }
    }
}

/// Minimal `App` conformance used only as the `xcodebuild test` test host —
/// see `IkeruMain` above for why it exists. Deliberately does nothing: no
/// `ModelContainer`, no background task registration, no `UserDefaults`
/// reads.
private struct TestHostApp: App {
    var body: some Scene {
        WindowGroup {
            Text("IkeruTests host")
        }
    }
}
