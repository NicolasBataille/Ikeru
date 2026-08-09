# Journal de bord

Trace de ce qui a été **fait**, **testé**, **gardé** ou **écarté** sur l'app.

Git dit *ce qui a changé*. Ce journal dit *ce qu'on a essayé, ce qu'on a vérifié,
et pourquoi on a tranché comme ça* — c'est-à-dire tout ce que le diff ne raconte
pas et qu'on regrette de ne pas retrouver trois mois plus tard.

## Comment écrire une entrée

Une entrée par session de travail, la plus récente **en haut**. On y met :

- **Fait** — les changements livrés, avec le SHA du commit.
- **Testé** — ce qui a été vérifié et *comment* (device, simulateur, CI, test
  unitaire). Préciser ce qui n'a **pas** pu être vérifié et pourquoi : une
  vérification manquante qu'on croit faite est pire que pas de vérification.
- **Écarté** — les pistes explorées puis abandonnées, avec la raison. C'est la
  partie la plus précieuse : elle évite de refaire deux fois la même impasse.
- **Ouvert** — ce qui reste en suspens, et ce qui débloque.

Ne pas recopier le contenu des commits. Renvoyer au SHA et garder ici le
raisonnement, les mesures, et les décisions.

---

## Pass de test device (artifact `bb08a30e`) — état au 2026-08-09

~40 items sur 13 étapes. **31 faits, 9 restants.** Le relevé détaillé vivait
dans un scratchpad temporaire et a été perdu avec la session : d'où ce résumé
ici, qui est désormais la source de vérité.

### Restants et pourquoi
| Item | Blocage |
|---|---|
| `s7-key`, `s7-multiturn`, `s7-chips`, `s7-furigana`, `s7-mnemonics` | Exigent la clé Gemini. Claude ne saisit pas de clés API → à faire par Nico. |
| `s12-silent` | Switch muet : pas de commutateur matériel en simulateur. |
| `s11-voiceover` | VoiceOver n'existe pas en simulateur. |
| `s9-liveactivity` | Partiel : s'affiche et **n'est pas figée** (< 1 min → 1 min → 2 min), mais rendu par paliers d'une minute au lieu du mm:ss du code. Probable limite du simulateur sur l'écran verrouillé → à confirmer sur device. |
| `s5-levelup` | **Structurellement inobservable via l'outil dev** : `TestFixtures.grantLevelUp` bump `state.xp` sans toucher `state.level`, et `HomeViewModel` normalise `state.level = levelForXP(state.xp)`. Le passage par Home absorbe le bump avant d'atteindre une session. Il faut un level-up gagné en session, ou corriger l'outil dev. |

### Correction d'un vert abusif
`s12-offline` avait été coché **vert à tort**. La vérification portait sur la
présence des fichiers (447 clips, clés résolues, 92/92 kana) — pas sur le
comportement. L'audio ne sortait en réalité **aucun son** sur device. Item
réellement vert seulement après le fix `282f41f`, confirmé à l'oreille.

Leçon : distinguer *vérifié* de *supposé*. Une présence de fichier n'est pas
une lecture.

### Nits relevés, non corrigés
- `s2-slides` — « Un chemin de curieux à courant » est un calque de *from
  curious to fluent* ; « courant » ne s'emploie pas ainsi pour une personne.
- `s6-replay` — au rejeu, l'ancre suit bien le bon bouton (COMMENCER), mais la
  copy dit encore « Choisis d'abord tes kana » alors qu'ils le sont déjà.
- `s11-dyntype` — le numéral hero ne tronque jamais ✅, mais le CTA bilingue
  casse aux tailles accessibilité (`稽古を始...` sur 2 lignes, `COMM…` tronqué).

---

## 2026-08-09 — Déblocage TestFlight, versioning, audio

### Fait
- `282f41f` — **fix(audio)** : la prononciation était totalement muette sur
  device. Remplacement du graphe `AVAudioEngine` + `AVAudioUnitTimePitch` par
  `AVAudioPlayer`.
- `7cde020` — **fix(ci)** : retrait de `CODE_SIGN_IDENTITY = "iPhone Developer"`
  de la config *Release* de `com.ikeru.app` ; la version marketing envoyée à
  TestFlight est désormais calculée (`MAJOR.MINOR` du projet + nombre de commits
  en patch) au lieu du `1.0.0` figé.

### Testé
- Audio : 447 clips embarqués dans le bundle construit, **0 corrompu**, durées
  0,43–2,94 s, niveau moyen ≈ −27 dBFS. Couverture **92/92 kana**. Rendu
  `AVAudioPlayer` validé sur un clip 24 kHz (`successfully=true`). **Confirmé
  audible sur iPhone 14 Pro par l'utilisateur.**
- Suite Core verte (235 tests / 25 suites) ; CI `dev` entièrement verte.
- Version : le job a bien émis `MARKETING_VERSION=1.0.274`.
- Watch : embed vérifié **empiriquement** sur le build device —
  `Ikeru.app/Watch/IkeruWatch.app` présent. Elle partira donc avec TestFlight.

### Écarté
Pistes suivies puis éliminées sur le bug audio, avant de trouver la vraie cause :
- *Session audio jamais configurée* — faux, `configureAudioSession()` est bien
  appelé depuis `init()` (mon premier grep était mal formé).
- *Skip mode silencieux* — bien retiré en 7.9, aucun gating résiduel.
- *`playerNode.play()` jamais appelé* — il l'est (ligne 256).
- *`PlaybackRate.rawValue` à 0* — non, 0.5/0.75/1.0/1.25.
- *Session laissée en `.record` par la reco vocale* — les deux chemins
  restaurent `.playback`, et le HUD volume affichait bien « média ».
- *`deinit` désactivant la session* — il n'y a pas de `deinit`.

**Cause réelle** : le graphe épinglait le format du fichier (**24 kHz mono**)
sur la connexion vers le mixer, alors que la sortie iOS tourne à 48 kHz. Le
moteur démarre, `play()` renvoie `true`, aucune exception — et rien n'est rendu.
macOS l'absorbe, le device non : c'est pour ça que le repro local passait.

### Ouvert
- **TestFlight bloqué** : `Your account has reached the maximum number of
  certificates`. `xcodebuild archive` signe l'archive en **développement**
  (comportement Xcode normal — la distribution est appliquée à l'export), or le
  runner éphémère n'a aucun certificat de dev et ne peut plus en créer.
  Débloquer = révoquer un certificat de développement sur developer.apple.com.
  Correctif durable à faire : ne plus dépendre d'une création de certificat au
  runtime CI (importer aussi un certificat de dev en secret, ou passer l'archive
  en signature manuelle distribution).
- **Fuites i18n systémiques** : écran Fournisseurs IA, widget, Live Activity,
  Watch app — toutes ces surfaces sont en anglais en dur. L'i18n Lint de la CI
  est vert dessus : il ne couvre que la cible principale. Le vrai correctif est
  d'élargir le lint aux targets d'extension.
- **s5-levelup** jamais observé visuellement : `TestFixtures.grantLevelUp` bump
  `state.xp` sans toucher `state.level`, et `HomeViewModel` normalise
  `state.level = levelForXP(state.xp)` — le passage par Home absorbe le bump
  avant qu'on atteigne une session. Le raccourci dev ne peut structurellement
  pas déclencher la célébration.
- **s12-silent** et **s11-voiceover** : device-only, non testables en simulateur.
