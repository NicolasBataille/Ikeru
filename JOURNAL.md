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

## 2026-08-13 — P2 lot 2 : phase de présentation des cartes neuves, tracés kana, export confusions

### Fait

`5fff8e3`, sur `feature/pedagogy-p2`. Recommandation phare de la review
pédagogique : un kana jamais vu (`fsrsState.reps == 0`) reçoit d'abord une
rencontre **non notée** — glyphe, romaji, audio en autoplay, aucun bouton de
note — avant que son vrai test FSRS n'arrive, différé de quelques révisions
plus tard dans la même séance. La toute première note FSRS mesure enfin une
rétention plutôt qu'un bruit de première rencontre. Câblage bout en bout
vérifié par lecture : `NewCardPresentationScheduler.schedulingPresentations`
(`SessionComposer.swift`) repère les kana neufs dans le plan, insère une
seconde occurrence `.srsReview` 2 à 4 révisions plus loin, et alimente
`cardsNeedingPresentation` ; `SessionViewModel.isPresentingNewCard` bascule
`ExerciseTransitionContainer` vers `NewCardPresentationView` (struct privée du
même fichier, pas de fichier neuf) tant que l'id de la carte est dans ce set ;
`completeNewCardPresentation()` le retire à l'acquittement. Le critère de
sortie de la carte différée (si son test est raté) ne réinvente rien : il
retombe sur `requeueFailedCard` / `SessionRequeuePlanner` et leur plafond
existant `maxRetriesPerCard = 2` plutôt que d'ajouter un second compteur qui
pourrait boucler indépendamment.

À côté : tracés de coup pour 142 des 208 caractères kana
(`ContentRepository.kanaStrokeData(for:)`, 92 kana de base + 50 dakuten, un
seul codepoint chacun — les yōon à deux codepoints n'ont pas de fichier
KanjiVG source) ; export `confusions.json` (agrégat dérivé de `reviews.json`
à l'export, pas une table persistée) plus le bloc `grade_semantics` dans
`context.json` de `DataExportManager`, pour qu'un consommateur externe sache
que le grade 2 (hard) est un succès et pas un échec avant de calculer un taux
de rétention.

### Testé

- 3 schemes verts, SwiftLint et i18n-lint en exit 0, migration V1→V2→V3 verte
  en process isolés (contrainte `LegacyStoreMigration`, voir CLAUDE.md).
- 31 tests sur 4 suites d'app verts.
- Couverture des tracés kana mesurée par comptage direct dans le catalogue :
  142/208 caractères, les 66 manquants tous des yōon (きゃ, しゅ, …) — vérifié
  que c'est structurel (absence de fichier source KanjiVG à deux codepoints),
  pas un oubli de génération.

### Écarté

- **Ajouter un cas `.newCardPresentation` à `ExerciseItem`** : refusé.
  `DefaultSessionPlanner.isLive(_:)` est un `switch` exhaustif sans `default`
  sur `ExerciseItem` — un nouveau cas casse la compilation à ce site et à tout
  autre switch exhaustif sur l'enum. La présentation réutilise donc le cas
  `.srsReview` existant deux fois dans la file, et c'est un
  `Set<UUID>` côté view-model (`cardsNeedingPresentation`) qui distingue la
  rencontre non notée du vrai test — pas un type distinct.
- **Créer un fichier `NewCardPresentationScheduler.swift` / `NewCardPresentationView.swift` séparés** :
  le pbxproj de ce repo n'a aucun groupe synchronisé, chaque fichier source
  est listé explicitement (voir CLAUDE.md) — un fichier neuf non enregistré
  compile dans aucune cible et reste silencieusement mort. Le scheduler a été
  ajouté dans `SessionComposer.swift`, la vue dans
  `ExerciseTransitionContainer.swift`.
- **Replier sur « ajoute le test différé en fin de liste » quand la file est
  trop courte pour le délai visé (2-4 révisions)** : retiré après coup, pour
  deux raisons cumulées dans le code du scheduler. Un ajout en fin de liste
  place le test juste après sa propre présentation — gap nul, donc la mesure
  de rétention ne mesure rien. Et il fait cohabiter les deux occurrences du
  même `card.id` dans la fenêtre de peek à 3 niveaux du deck
  (`upcomingCards`), ce qui collisionne l'id `matchedGeometryEffect` de
  `SRSCardView`. Le planificateur calcule maintenant le nombre de
  `.srsReview` réellement disponibles après la carte neuve
  (`srsReviewCount(after:in:)`) et, si c'est sous `minimumSRSGap` (= 2, donc
  un gap garanti ≥ 3, prouvé disjoint de la fenêtre de peek), retire la carte
  de `cardsNeedingPresentation` : elle redevient une révision notée normale,
  une seule occurrence. Une séance très courte ne déclenche simplement pas la
  boucle de présentation plutôt que d'en jouer une version dégénérée.

### Ouvert

- **Les tracés kana n'ont AUCUN appelant à la livraison** : `grep` sur
  `kanaStrokeData` ne remonte que la définition dans `ContentRepository.swift`
  lui-même (couche publique + actor). Aucune vue, aucun view-model ne
  l'invoque — la donnée existe et est mesurée, mais rien à l'écran ne
  l'affiche encore. Couture restant à faire.
- **`CloudBackupManager` perd toujours les trois nouveaux champs de
  `ReviewLog`** : `ReviewSnapshot` (`BackupService.swift`) n'a que `id`,
  `cardId`, `timestamp`, `grade`, `responseTimeMs` — ni `answeredValue`, ni
  `exerciseType`, ni `surface`. La restauration (`CloudBackupManager.swift`
  ligne ~313) reconstruit un `ReviewLog` sans eux. Latent tant que
  `iCloudEnabled` vaut false ; régressif silencieusement le jour où iCloud
  s'active — un utilisateur restauré perdrait sa donnée de confusion sans
  erreur visible.
- **`confusions.json` sera kana-only en pratique** : `answeredValue` est un
  paramètre par défaut `nil` sur toute la chaîne `CardRepository` ; seul
  `KanaDrillViewModel.swift` l'appelle avec une vraie valeur. Vérifié par
  `grep` sur les autres view-models de la couche Learning — aucun autre appel
  non-nil.
- **`SessionViewModel.swift` fait 1315 lignes** — au-delà du garde-fou de 800
  lignes du repo (`coding-style.md`), constaté en relisant le fichier pour ce
  chantier, pas nouveau à ce lot mais pas résorbé non plus.
- Régénération audio VOICEVOX des kana concernés et test device de
  suppression de profil : toujours à la charge de Nico (cf. entrée
  précédente), non touchés par ce lot.
- Non vérifiable ici : la boucle de présentation en conditions réelles
  (device ou simulateur) — l'autoplay audio, le timer d'auto-avance
  (`.task(id: isPaused)`), et le comportement à plusieurs intros consécutives
  en mode fondation n'ont été relus que dans le code, pas exercés à l'écran.

---

## 2026-08-13 — P2 lot 1 : planificateur, confusions, livret de compétence

### Fait

Six chantiers de conception (branche `feature/pedagogy-p2`) : **cartes dues
prioritaires en absolu** sur les quotas + trois profils de séance par stade +
durées modulées par maturité ; **journalisation des paires de confusion**
(`answeredValue` / `exerciseType` / `surface` sur `ReviewLog`, **IkeruSchemaV3**) ;
**livret de compétence** sur l'accueil, avec l'arbitrage du système RPG orphelin ;
ponts か→カ et clusters de paires à interférence katakana ; mitigation du crash
widget.

### Testé

- 3 schemes verts, lint et i18n-lint en exit 0, migration **V1→V2→V3 verte en
  process isolés** (contrainte `LegacyStoreMigration`).
- Cas « 24 dues, budget 5 min » **exécuté** : 60 dues / 300 s → 20 révisions,
  budget intégralement consommé, 100 % de révisions. Les quotas s'appliquent
  bien au reste.
- Chaîne quiz → `ReviewLog` persisté **vérifiée en relisant la ligne depuis le
  store** (réponse fausse, réponse juste, et flashcard avec `answeredValue` nil).
- Miroir katakana↔hiragana vérifié **par programme** : 26/26 groupes ont un
  ensemble de romaji identique, zéro contre-exemple.

### Écarté

- **Le crash widget n'est PAS notre code.** Les 8 rapports `.ips` ont une pile
  entièrement dans les frameworks Apple (`xpc_connection_copy_bundle_id` ←
  BaseBoard ← BoardServices), aucune frame Ikeru, et `is_simulated: 1` sur les
  huit. Simulateur uniquement, aucun crash device observé. Livré comme
  **mitigation défensive documentée**, pas comme correctif.
- **Dues prioritaires « en absolu » : vrai en construction et en croisière,
  PAS en fondation** — le mode fondation garde son plafond à 50 % pour qu'un
  débutant voie de nouveaux kana. À dire tel quel plutôt que de sur-vendre.

### Ouvert

- **Bug attrapé en revue et corrigé ici** : `IkeruApp` déclarait encore
  `IkeruSchemaV2` alors que le schéma courant est V3. Le conteneur s'ouvrait
  sans erreur puis **trappait au premier insert**, y compris sur une
  installation neuve — et la récupération de store n'entoure que
  `makeModelContainer`, donc elle ne se déclenchait jamais. Boucle de crash non
  récupérable. Leçon : **la version déclarée à l'app doit être vérifiée à chaque
  ajout de version**, un test de migration vert ne la couvre pas.
- **Chantier #17 à moitié livré** : la donnée de confusion est capturée mais
  `DataExportManager` ne l'exporte pas — donc personne ne peut encore la relire.
- **Tracés kana non livrés** : l'agent a été bloqué par le classifieur de
  sécurité (incident transitoire), à relancer.
- Le badge « +N cette semaine » ne s'affiche qu'**une seule fois** par semaine :
  la baseline roule au même seuil que la comparaison, dans la même passe.
- Le pont hiragana s'affiche aussi dans le **quiz**, où il donne la réponse — et
  contamine l'`answeredValue` fraîchement journalisé.

---

## 2026-08-12/13 — Review pédagogique experte, puis 5 itérations de remédiation

### Fait

Une review pédagogique en quatre rounds par une instance jouant l'expert de
l'apprentissage du japonais (simulateur uniquement, sans accès au code), pendant
que cette session vérifiait chaque critique **dans le code** pour trancher *choix
de design* vs *accident*. Relevé complet :
[`docs/reviews/2026-08-10-expert-japonais-echange.md`](docs/reviews/2026-08-10-expert-japonais-echange.md),
30 observations dans `app-review-notes/`.

Puis cinq itérations de correctifs orchestrées en workflow (agents Sonnet en
parallèle par propriété de fichier disjointe, revue adversariale Opus à chaque
tour) : `2cc95ed` (docs + 2 specs), `353ac3e` (8 P0), `0d5606d` (retours + P1),
`3998a44` (retours), `49fd0e2` (P1), puis ce commit.

Verdict de la review : **~17 défauts d'implémentation pour 6 erreurs de
conception** — un produit à brancher, pas à repenser. Et les six erreurs de
conception ont des correctifs qui *renforcent* l'identité du produit : aucune ne
demande d'ajouter un streak.

### Testé

- **3 schemes verts** (iOS, watchOS, widget), **514 tests Core**, cible de test
  compilée, **SwiftLint et i18n-lint en exit 0** (commandes exactes du CI
  rejouées, pas approximées).
- **Vérifié sur le produit, pas sur le log** : `IkeruWidget.appex/fr.lproj/` et
  `IkeruWatch.app/fr.lproj/` existent — les deux extensions n'avaient aucune
  phase Resources, donc **aucune de leurs chaînes ne pouvait être traduite**.
- **Seeder mesuré** par un harnais rejouant la génération contre le vrai
  `FSRSService` : le compteur かな donne 12/92 au niveau 1, 42/92 au 5, 89/92 au
  15 — il restait cloué à **0** quels que soient les sliders.
- **Non testable ici, à faire sur device** : suppression d'un profil actif puis
  non actif (risque de crash sur un `@Model` supprimé, chemin jamais exercé
  avant ce chantier) ; audio réel ; drill d'accent au poignet.

### Écarté

- **Discriminer la purge de cartes par `CardType`** : impossible tel quel —
  `CardType` n'a **pas** de cas `.kana` et les trois sites de création taguent
  les kana en `.vocabulary`. Le type seul ne discrimine rien. Retenu à la place :
  le verso doit correspondre exactement au romaji du catalogue (vrai pour tout
  kana semé, faux pour une traduction).
- **Synchro cloud** ([spec écrite](docs/design-specs/2026-08-10-cloud-sync-design.md))
  volontairement **non lancée** : elle touche `IkeruSchemaV3` comme la
  journalisation des confusions, et dépend de la suppression de profil. Deux
  migrations de schéma concurrentes = collision indébogable.
- **Baseliner la violation i18n-lint** plutôt que la corriger : refusé par
  l'agent concerné, qui a préféré signaler que la clé manquante venait d'un agent
  voisin. Bonne décision — baseliner aurait masqué une vraie régression.

### Ouvert

- **Régénération audio VOICEVOX** des 116 nouveaux kana (dakuten + yōon) : le
  script est corrigé et gardé, mais la génération exige le moteur via Apple
  `container`. Sans ça, ces kana tombent sur la synthèse on-device — rendue
  audible en permanence par l'autoplay désormais actif.
- **Terme du jour : problème de CONTENU, pas d'algorithme.** Le filtrage par
  niveau est branché et vivant, mais le catalogue compte 57 entrées dont
  **0 en N5 et 1 seule en N4** (37 hors échelle). Un débutant obtient l'unique
  mot N4 puis retombe sur du jargon. Travail éditorial à faire.
- **`ProfileViewModelTests` : 18/18 crashent** (pré-existant, non lancé par la
  CI) — donc l'isolation inter-profils et la bascule à la suppression ne sont
  garanties que par lecture de code.
- **Personas du seeder incohérentes** avec ce qu'il produit : le niveau 30 est
  structurellement inatteignable (~10 400 révisions), et dès `due ≥ 40` le
  bucket « mastered » tombe à zéro. Dev-tools uniquement, donc non bloquant.
- **P2 non entamés** : dues prioritaires sur les quotas, profils de séance par
  stade, phase de présentation + critère de sortie de séance, livret de
  compétence, tracés kana, ponts katakana, arbitrage RPG, crash widget.

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
