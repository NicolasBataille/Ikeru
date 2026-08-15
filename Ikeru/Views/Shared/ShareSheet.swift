import SwiftUI
import UIKit

/// The system share sheet, presentable the way a *command* is — right when
/// the thing to share finally exists.
///
/// SwiftUI's `ShareLink` is a **view you tap**, not something you can invoke.
/// That is fine when the payload is known up front, and useless when it is
/// the result of async work: "Export data" writes a file first, so the URL
/// does not exist until after the tap. The previous shape here presented a
/// sheet whose entire content was a bare `ShareLink` — which rendered as a
/// small blue "Share…" link stranded on a full-screen grey background, and
/// put the learner two sheets deep to save one file.
///
/// `UIActivityViewController` has no such constraint: it *is* imperative.
/// Wrapping it means the tap opens the real share sheet, once.
struct ShareSheet: UIViewControllerRepresentable {

    let items: [Any]

    /// Called when the sheet goes away — completed, cancelled, or dismissed
    /// by swipe. The caller uses this to delete the temporary export file;
    /// `.sheet(onDismiss:)` alone would not fire for every one of those
    /// paths, and a missed call leaks the file into the temp directory.
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            onFinish()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // Nothing to update: the activity items are fixed for the lifetime
        // of one presentation. A new file means a new presentation.
    }
}
