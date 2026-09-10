import Testing
import Foundation
import AVFoundation
@testable import IkeruCore

// MARK: - AudioService lifecycle
//
// Ajoutes le 2026-08-19 en enquetant sur [GAP-19] — une corruption de tas
// (`pointer being freed was not allocated`) vue UNE fois dans
// `ListeningIntegrationTests.audioServiceStopSafe`, et jamais reproduite.
//
// Ces tests n'ont PAS reproduit le crash : rotation de 300 instances, 60
// instances simultanees, lecture et `stop()` mis en concurrence — tous verts,
// avant comme apres le correctif. Ils sont gardes quand meme, parce que le
// cycle de vie d'`AudioService` n'avait aucune couverture de ce genre et que
// l'app en cree six par ecran depuis `ListenButton`.
//
// Ne pas les lire comme « GAP-19 est ferme ». Ils disent seulement que ces
// chemins-la tiennent.

@Suite("AudioService lifecycle")
@MainActor
struct AudioServiceLifecycleTests {

    @Test("Creer, arreter et relacher en boucle ne corrompt rien")
    func churnDoesNotCorrupt() {
        for _ in 0..<300 {
            let service = AudioService()
            service.stop()
            #expect(service.isPlaying == false)
        }
    }

    @Test("stop() pendant une lecture en cours laisse le service au repos")
    func stopDuringPlayback() async {
        let service = AudioService()
        for _ in 0..<30 {
            async let played: Void = service.playTTS(text: "水を飲みたいです。")
            try? await Task.sleep(nanoseconds: 5_000_000)
            service.stop()
            _ = await played
        }
        #expect(service.isPlaying == false)
    }

    @Test("Lecture puis arret immediat, en rotation")
    func playThenStopChurn() async {
        for _ in 0..<40 {
            let service = AudioService()
            async let played: Void = service.playTTS(text: "みず")
            service.stop()
            _ = await played
            service.stop()
        }
        #expect(true)
    }

    @Test("Soixante instances simultanees se relachent sans incident")
    func manyLiveInstances() {
        var services: [AudioService] = []
        for _ in 0..<60 { services.append(AudioService()) }
        for service in services { service.stop() }
        services.removeAll()
        #expect(true)
    }

    /// Le seul test qui epingle le correctif : sans `deinit`, chaque service
    /// laissait son observateur d'interruption inscrit a vie. Poster la
    /// notification apres relachement doit rester sans effet et sans crash.
    @Test("Un service relache ne reagit plus aux interruptions audio")
    func releasedServiceIgnoresInterruptions() {
        weak var weakService: AudioService?
        autoreleasepool {
            let service = AudioService()
            weakService = service
            service.stop()
        }
        #expect(weakService == nil, "le service doit se liberer — sinon l'observateur le retient")

        #if os(iOS)
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        #endif
    }
}
