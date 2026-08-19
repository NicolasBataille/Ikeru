import UIKit
import SwiftUI
import UniformTypeIdentifiers
import IkeruCore

/// Ce que le partage a donné : soit un texte, soit rien d'exploitable.
/// Déclaré au niveau du fichier parce que la vue de confirmation le lit —
/// le nicher dans le contrôleur obligeait à un alias qui n'apprenait rien.
private enum ShareState { case saved, nothingUsable }

// MARK: - ShareViewController

/// The share destination: any Japanese text selected anywhere on the phone can
/// be sent to Ikeru without leaving the app it was met in.
///
/// ## What it deliberately does NOT do
///
/// It does not analyse, look anything up, or open the main app. A share
/// extension runs in a memory-tight process, and the dictionary is 27 Mo —
/// loading it here to show a preview would be the surest way to be killed
/// mid-share. And no share extension can reliably open its host app on iOS: the
/// tricks that appear to work walk the responder chain for a `UIApplication`,
/// which is undocumented and a review risk.
///
/// So it does one thing: drop the text in the shared App Group and say so. The
/// learner opens Ikeru when they want to, and the text is waiting. See
/// `SharedTextInbox` for why it is one slot rather than a queue.
final class ShareViewController: UIViewController {

    private let inbox = SharedTextInbox()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        Task { await handleShare() }
    }

    private func handleShare() async {
        guard let text = await extractedText(), inbox.deposit(text) else {
            present(state: .nothingUsable)
            return
        }
        present(state: .saved)
    }

    /// The first text-bearing attachment. Both the plain-text type and the
    /// `NSExtensionItem`'s own `attributedContentText` are checked: Safari hands
    /// a selection over as the latter, Notes and Messages as the former, and
    /// only handling one of the two makes the extension look broken in half the
    /// apps it appears in.
    private func extractedText() async -> String? {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return nil }
        for item in items {
            if let attributed = item.attributedContentText?.string,
               !attributed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return attributed
            }
            for provider in item.attachments ?? [] {
                for type in [UTType.plainText.identifier, UTType.text.identifier, UTType.url.identifier]
                where provider.hasItemConformingToTypeIdentifier(type) {
                    if let loaded = try? await provider.loadItem(forTypeIdentifier: type),
                       let text = Self.string(from: loaded),
                       !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return text
                    }
                }
            }
        }
        return nil
    }

    /// A shared item arrives as `String`, `NSAttributedString`, `URL` or `Data`
    /// depending on the sending app. A URL is kept as its absolute string: it is
    /// rarely Japanese, but silently dropping it would look like the share
    /// failed, and the learner can delete it in the field.
    private static func string(from item: NSSecureCoding) -> String? {
        switch item {
        case let text as String: return text
        case let attributed as NSAttributedString: return attributed.string
        case let url as URL: return url.absoluteString
        case let data as Data: return String(data: data, encoding: .utf8)
        default: return nil
        }
    }

    // MARK: - Confirmation

    private func present(state: ShareState) {
        let confirmation = ShareConfirmationView(state: state) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
        let host = UIHostingController(rootView: confirmation)
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}

// MARK: - ShareConfirmationView

private struct ShareConfirmationView: View {

    let state: ShareState
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: state == .saved ? "checkmark.seal" : "questionmark.text.page")
                .font(.system(size: 40, weight: .light))
            Text(message)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Button("Done", action: onDismiss)
                .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    private var message: LocalizedStringKey {
        state == .saved
            ? "Saved. Open Ikeru and the text will be waiting."
            : "Nothing to read in what was shared."
    }
}
