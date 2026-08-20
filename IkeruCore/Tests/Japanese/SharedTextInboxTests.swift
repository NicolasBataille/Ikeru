import Testing
import Foundation
@testable import IkeruCore

/// The hand-off is a two-process contract with no compiler to enforce it, so
/// the tests stand in for the missing type-check.
@Suite("Boîte de dépôt du texte partagé")
struct SharedTextInboxTests {

    /// Une suite par test : deux tests qui se partagent une suite `UserDefaults`
    /// se marchent dessus dès qu'ils tournent dans le désordre.
    private func makeInbox(_ name: String = UUID().uuidString) -> SharedTextInbox {
        SharedTextInbox(suiteName: name)
    }

    @Test("Un texte déposé est retrouvé, puis consommé")
    func depositThenTake() {
        let inbox = makeInbox()
        #expect(!inbox.hasPending)
        #expect(inbox.deposit("今日は雨が降っている。"))
        #expect(inbox.hasPending)
        #expect(inbox.take() == "今日は雨が降っている。")
        // Consommé : rouvrir l'app ne doit pas reproposer le même texte.
        #expect(!inbox.hasPending)
        #expect(inbox.take() == nil)
    }

    @Test("Un partage vide ou blanc n'annonce rien")
    func blankSharesAreIgnored() {
        let inbox = makeInbox()
        #expect(!inbox.deposit(""))
        #expect(!inbox.deposit("   \n\t "))
        #expect(!inbox.hasPending)
    }

    /// Une seule place, la plus récente gagne : une file d'attente
    /// transformerait trois partages en une liste de tâches à trier, ce que la
    /// feature entière cherche à éviter.
    @Test("Un second partage remplace le premier")
    func lastWriteWins() {
        let inbox = makeInbox()
        inbox.deposit("最初のテキスト")
        inbox.deposit("二番目のテキスト")
        #expect(inbox.take() == "二番目のテキスト")
    }

    @Test("Le texte est rendu intact, espaces et sauts de ligne compris")
    func textIsStoredVerbatim() {
        let inbox = makeInbox()
        let original = "  今日は\n\n  雨。  "
        inbox.deposit(original)
        // Le trim ne sert qu'à DÉCIDER s'il y a quelque chose, jamais à
        // réécrire : le texte de l'utilisateur ressort tel quel.
        #expect(inbox.take() == original)
    }

    @Test("Refuser un texte le fait disparaître sans le lire")
    func discardClearsWithoutReading() {
        let inbox = makeInbox()
        inbox.deposit("要らないテキスト")
        inbox.discard()
        #expect(!inbox.hasPending)
        #expect(inbox.take() == nil)
    }

    @Test("La date de réception accompagne le texte, et part avec lui")
    func receivedAtTracksThePendingText() {
        let inbox = makeInbox()
        #expect(inbox.receivedAt == nil)
        let when = Date(timeIntervalSince1970: 1_787_000_000)
        inbox.deposit("テキスト", at: when)
        #expect(inbox.receivedAt == when)
        _ = inbox.take()
        #expect(inbox.receivedAt == nil)
    }
}
