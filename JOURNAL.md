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

## 2026-08-14 — Onboarding : l'écran d'accueil ne dit jamais qu'un compte existe

### Fait

SHA : non commité (arbre de travail, branche `feature/onboarding-restore`).
La synchro cloud + Sign in with Apple (lots 1-3) étaient livrés mais invisibles
depuis l'onboarding : quelqu'un qui réinstallait créait un profil neuf sans
jamais savoir que sa progression l'attendait sur le serveur.

- **`Ikeru/Views/Onboarding/NameEntryView.swift`** — nouvelle étape `.welcome`
  insérée avant `.name` dans la machine à états (`Step` gagne `.welcome` et
  `.restoring`), et devient le step initial (`step = .welcome`, avant c'était
  `step = .name`). **Correction (vérification a posteriori) : ce n'est PAS
  « zéro friction ajoutée » comme écrit initialement ici — un nouvel écran
  (« Let's get started » / 門, avec un bouton « Commencer ») s'intercale
  désormais devant TOUT le monde, y compris un nouvel utilisateur, avant la
  saisie du prénom. C'est un tap et un écran de plus par rapport à l'ancien
  flux, qui démarrait directement sur `.name`. À partir du tap sur
  « Commencer », le reste du chemin (`.name → .placement → .tour`) est
  strictement inchangé. Ce compromis est probablement le bon — il fallait un
  endroit pour poser le CTA « J'ai déjà un compte » — mais il faut le nommer
  correctement : c'est un changement de flux par défaut, pas une addition
  invisible.** « J'ai déjà un compte » réutilise le chrome natif
  `SignInWithAppleButton` (même motif
  `.contentShape(Rectangle())` que `SettingsView+AppleSignIn.appleSignInRow` —
  sans lui le bouton n'a aucune zone tappable, bug déjà livré une fois) →
  `AppleSignInFlow.signIn()` → `.restoring` (spinner honnête, pas de sortie
  avant la fin) → `CloudSyncCoordinator.setConsent(true)` puis `syncNow()`
  **attendu en entier** avant toute décision. Le consentement n'est activé
  qu'*après* le succès de la connexion Apple (jamais avant, jamais sur un
  cancel/échec) — la phrase de disclosure sur l'écran d'accueil ("Signing in
  turns on backup...") est affichée *avant* le tap, formulée conditionnellement
  (« si tu l'avais enregistrée »), jamais une promesse inconditionnelle.
  3 messages d'erreur distincts (annulation → silencieux ; jeton refusé
  `SyncAuthError.requestFailed` 400/401/403 ou `AppleLinkError
  .linkIdentityGuardTripped` ; échec générique/réseau), tous ramènent
  proprement à `.welcome`.
- **`OnboardingRestoreDecision`** (même fichier, type pur sans SwiftUI) —
  décide quoi faire une fois `syncNow()` revenu : `hasProfile` (relu depuis le
  store après le pull) l'emporte toujours sur `outcome`, y compris sur un
  `.failure` ou un `.skippedAlreadySyncing` concurrent (le pull tourne avant
  le push, et un trigger foreground/network-regain peut livrer le profil en
  parallèle de cet appel). Sans profil : `.applied`/`.seededFromLocal` →
  « pas de sauvegarde » (bascule sur `.name` avec un bandeau honnête, pas de
  promesse) ; `.failed`/`.failure` → échec réel, ne JAMAIS conclure « pas de
  sauvegarde » sur un échec réseau ; `.skippedThrottled`/`.skippedAlreadySyncing`
  → « réessaie dans un instant », distinct d'un vrai échec.
- **`Ikeru/App/IkeruApp.swift`** — piège trouvé par le relecteur avant
  d'écrire une ligne de vue : `onChange(of: showOnboarding)` postait
  `.requestFeatureTour` sur **toute** fermeture de l'onboarding, y compris un
  utilisateur restauré qui a déjà vu le tour sur un autre appareil.
  `onboardingFinishedViaRestore` (nouveau `@State`, binding passé à
  `NameEntryView`) coupe le post uniquement sur le chemin restore-succès.
- **`Ikeru/Localization/Localizable.xcstrings`** — 14 nouvelles clés (fr+en),
  édition chirurgicale (insertions ciblées via `Edit`, jamais de réécriture
  JSON complète). Diff : 226 lignes, entièrement additif, 0 suppression,
  0 réordonnancement — au-delà des « quelques dizaines » indiquées dans la
  consigne, mais proportionnel (14 clés × ~16 lignes chacune) ; deux messages
  d'erreur réutilisent verbatim des clés déjà existantes de `SettingsView+AppleSignIn`
  (pas de doublon créé).
- **`IkeruTests/OnboardingRestoreDecisionTests.swift`** (nouveau, hors
  périmètre déclaré de la tâche — justifié par la consigne elle-même :
  « si une part de la logique est testable hors SwiftUI, extrais-la et
  teste-la ») + 4 lignes d'enregistrement pbxproj (`PBXBuildFile`,
  `PBXFileReference`, entrée de groupe, entrée Sources build phase pour la
  cible `IkeruTests`, gabarit exact de `ProfileViewModelTests.swift`).
  10 tests, tous les cas de `OnboardingRestoreDecision.decide`.

### Testé

- **`xcodebuild build` (scheme `Ikeru`, generic/platform=iOS, no signing)** —
  succès, avant et après chaque changement significatif.
- **`xcodebuild test -only-testing:IkeruTests/OnboardingRestoreDecisionTests`**
  sur simulateur iPhone Air (boot réel de l'app dans le simulateur, log
  confirmant `[ui] No profile found — showing onboarding` donc le gating
  onboarding-si-pas-de-profil est intact) — 10/10 tests passent.
- **`cd IkeruCore && swift test --no-parallel --filter "Sync|CloudData|AppleIdentity"`**
  — 117 tests, tous verts (non-régression sur le pull/push/consent existants).
- **`python3 scripts/i18n-lint.py --baseline scripts/i18n-lint-baseline.json`**
  — 0 NEW (26 total, tous dans la baseline).
- **`swiftlint lint --quiet`** sur les 3 fichiers touchés — 0 nouvelle
  violation ; le seul warning (`function_body_length` sur
  `initializeProfileViewModel`, 104 lignes) est préexistant, vérifié en
  lintant la version `HEAD` du fichier séparément (même 104 lignes avant mes
  changements — ma modif touche une fonction différente).
- **PAS testé** (et je le dis clairement plutôt que de le maquiller) : le
  parcours restore de bout en bout avec un vrai identifiant Apple → pull
  Supabase réel → profil qui arrive. Je n'ai ni compte Apple de test ni accès
  réseau au projet Supabase depuis cet environnement. L'hypothèse
  architecturale (les écritures de `SyncPullActor` sur le `ModelContainer`
  partagé sont visibles par un `fetch` frais sur `mainContext` dans
  `loadProfile()`) est saine sur le papier — même conteneur, même schéma —
  mais seul un passage device la prouve. L'UI SwiftUI elle-même
  (`WelcomeStep`, `RestoringStep`, le bandeau sur `NameEntryStep`) n'est pas
  testable dans cet environnement — vérifiée seulement par lecture de code et
  par le fait que l'app boote et affiche l'onboarding sans crash dans le
  simulateur.

### Écarté

- **Découper `NameEntryView.swift` en plusieurs fichiers dans `Onboarding/`**
  (la consigne l'autorisait explicitement) — écarté au profit d'un seul
  fichier (767 lignes, sous le plafond de 800). Le pbxproj de ce repo est un
  format classique, pas une `PBXFileSystemSynchronizedRootGroup`
  (`grep -c PBXFileSystemSynchronizedRootGroup` → 0) : tout nouveau fichier de
  *production* y exige un enregistrement manuel (`PBXFileReference` +
  `PBXBuildFile` + entrée de groupe + entrée Sources build phase). Le risque
  de casser la compilation de la cible `Ikeru` pour un gain de style
  (plusieurs petits fichiers vs un seul sous la limite) n'en valait pas la
  chandelle. Seul le fichier de *test* (dont l'échec n'affecte pas le build
  de l'app) a reçu cet enregistrement pbxproj.
- **Bouton "J'ai déjà un compte" en `Button` custom (icône + texte)** plutôt
  que le chrome natif `SignInWithAppleButton` — écarté : Apple exige son
  composant natif comme point d'entrée Sign in with Apple (App Store Review
  4.8), et ce repo a déjà un pattern éprouvé + un bug déjà corrigé une fois
  (`.contentShape(Rectangle())` manquant) pour ce cas précis. Réutiliser au
  lieu de réinventer.
- **Utiliser `outcome` seul pour décider "pas de sauvegarde"** — écarté au
  profit de "relire `hasProfile` depuis le store, l'outcome ne sert qu'en
  absence de profil" : le pull tourne avant le push dans `syncNow()`, et un
  trigger concurrent (foreground, retour réseau) peut livrer le profil
  indépendamment de ce que CET appel précis rapporte.

### Ouvert

- **CI ne fait pas tourner `OnboardingRestoreDecisionTests`** — le filtre CI
  actuel (`.github/workflows/ci.yml`) ne cible qu'un sous-ensemble vert
  explicite (Core filtré + `KanaDrillViewModelTests`). Le nouveau fichier est
  hors du périmètre déclaré de cette tâche (`IkeruTests/`) donc je ne l'ai pas
  ajouté au workflow — à faire en 1 ligne si on veut cette couverture en CI.
- **Passage device réel requis** avant de considérer le chemin restore
  fiable en production : compte Apple de test + compte Supabase avec une
  sauvegarde existante, pour vérifier le pull → `loadProfile()` → sortie
  directe vers l'accueil (le point le plus à risque de tout ce lot).
- **Utilisateur restauré atterrit en `DisplayMode.beginner`** — la
  préférence tatami/beginner est `UserDefaults` locale à l'appareil, pas
  synchronisée ; comme `.placement` est sauté sur le chemin restore, la
  personne restaurée retrouve le mode par défaut même si elle avait choisi
  tatami ailleurs. Limite connue, pas corrigée ici (changement de schéma /
  sync du réglage nécessaire).
- **Retry après un restore échoué** : si le sign-in Apple a réussi mais le
  pull échoue (réseau), le consentement reste activé (correct — la
  disclosure promettait exactement ça) et l'utilisateur peut retomber sur
  "Commencer" pour créer un profil neuf. Une synchro ultérieure en arrière-plan
  peut alors faire redescendre le VRAI profil comme second profil inactif à
  côté du profil jetable. C'est le dégradé que la tâche accepte déjà
  explicitement (« il aura créé un profil jetable entre-temps ») — rendu plus
  rare par ce lot, pas éliminé.

---

## 2026-08-14 — Lot 2 (pull) : correction chirurgicale des 2 défauts survivants (ronde 4)

### Fait

SHA : non commité (arbre de travail, branche `feature/cloud-lot2-pull`). Deux
correctifs précisément spécifiés par le relecteur de la ronde 3 (voir entrée
ci-dessous, sondes 1 et 2), appliqués tels quels :

- **Défaut 1 (identité re-provisionnée)** — `IkeruCore/Sources/Services/Sync/SyncIdentityStore.swift`
  (nouveau : protocole + `UserDefaultsSyncIdentityStore` + `MockSyncIdentityStore`,
  même motif « pas de schéma » que le curseur). `CloudSyncCoordinator.swift`
  (`syncNow()`, juste après `validAccessToken()` et avant `runPull`) : compare
  `identity.currentUserID()` au dernier `user_id` connu ; un changement
  déclenche `cursorStore.resetAll()` + `skipTracker.resetAll()`, rien au premier
  appel (pas de faux positif). Commentaire faux corrigé dans
  `SyncModelActor.swift` (`markEverythingUnsynced`, ~L200) : il prétendait que
  le site coordinateur suffisait au cas refresh-token rejeté — faux tant que
  les curseurs ne sont pas remis à zéro par ailleurs.
- **Défaut 2 (3-strikes ne distingue pas permanent/transitoire)** — nouveau
  type `RowApplyOutcome` (`SyncPullActor+RowDecoding.swift`) : `.applied` /
  `.skippedPermanent` (payload indécodable) / `.skippedTransient` (FK non
  résolue — seulement `review_logs`→`cards` et `vocabulary_encounters`→`vocabulary_entries` ;
  `exercise_outcome_logs.profile_id` est un champ scalaire, pas un lookup, donc
  toujours permanent). `SyncSkipTracker` gagne `recordTransientSkip` (compteur
  et clé UserDefaults séparés de `recordSkip`). Nouveau seuil
  `SyncPullActor.transientPoisonDropThreshold = 50` (vs `poisonDropThreshold = 3`)
  pour borner l'attente sans jamais consommer un strike permanent — sinon on
  rouvre la CRITIQUE A (parent qui n'arrive jamais épinglerait le curseur sans
  fin). Logique d'abandon extraite dans un nouveau fichier
  `SyncPullActor+StuckRowResolution.swift` (`strikeCountAndThreshold`,
  `resolveStuckRow`) pour rester sous les budgets SwiftLint après l'ajout.

### Testé

- **Défaut 1** : `CloudSyncCoordinatorTests.swift` — l'ancien test
  `seedFromLocalPushesCardsAndLogsNotJustProfileAndRPGState` prétendait couvrir
  la re-provisioning mais utilisait une fixture `MockSyncCursorStore()` NUE
  (donc testait un cold start, pas une re-provisioning — curseurs déjà
  synchronisés = jamais nuls). Remplacé par
  `identityReprovisioningResetsSeededCursorsAndPushesCardsAndLogs` :
  `makeSeededCursorStore()` + un `MockSyncIdentityStore` pré-rempli avec un
  ancien `user_id` + un `AnonymousIdentityManager` qui signe sous un
  `user_id` différent. **Rouge vérifié empiriquement** (neutralisé le `if`
  du reset avec `if false, …` — le test échoue avec `cards`/`review_logs`
  vides) puis **vert restauré**. Reste de la suite (11 tests) inchangé, preuve
  qu'aucun cycle `syncNow()` « premier appel » n'est cassé par le nouveau
  garde-fou.
- **Défaut 2** : nouveau fichier
  `SyncPullDivergenceTests+TransientSkip.swift`, 2 tests. Le premier reproduit
  le scénario exact du relecteur (log dont la carte arrive tardivement,
  au-delà de `poisonDropThreshold`) et vérifie en plus le MÉCANISME — pas
  seulement l'absence du symptôme : `skipTracker.currentCount` (permanent)
  reste `nil`, `currentTransientCount` grimpe. Le second prouve que le seuil
  de 50 borne quand même l'attente si le parent n'arrive jamais.
  **Rouge vérifié empiriquement** (routé `.skippedTransient` vers
  `recordSkip`/`poisonDropThreshold`, seuil 3 partagé comme avant le
  correctif) → échec exact à cycle 3-4, correspondant au symptôme décrit ;
  restauré, vert. Régression `poisonRowIsDroppedAfterThreeCyclesAndUnblocksLaterRows`
  (fichier `+PoisonRow.swift`, préexistant) toujours verte — confirme que le
  chemin permanent garde son seuil de 3.
- Suite complète : `swift test --no-parallel --filter "Sync|CloudData"` → 94
  tests verts (92 + 2 nouveaux), 0 régression.
- `swift build` propre. `xcodebuild … -destination "generic/platform=iOS"` →
  BUILD SUCCEEDED (relancé après le découpage en fichier séparé, donc reflète
  l'état final). `python3 scripts/i18n-lint.py --baseline …` → 0 NEW (aucune
  string visible touchée — service Core uniquement). `swiftlint lint` sur les
  10 fichiers touchés (lancé depuis la racine du repo, avec `.swiftlint.yml`
  du projet — piège rencontré : lancé depuis `IkeruCore/`, swiftlint retombe
  sur ses seuils par défaut bien plus stricts et fait croire à des violations
  qui n'existent pas dans la vraie config CI) → 0 violation.

Pas testé : device réel / TestFlight (hors périmètre de cette ronde
chirurgicale, aucun changement de schéma ni de flux UI).

### Écarté

- **Un test coordinateur séparé pour le cold start « bare fixture »** (en plus
  du test de re-provisioning) : envisagé pour ne pas perdre de couverture,
  finalement écarté — la seule différence entre les deux scénarios est *ce qui
  vide les curseurs*, pas le code aval (`seededFromLocal` → `markEverythingUnsynced`
  → push), déjà exercé par le test modifié. Le cold start générique reste
  couvert au niveau `SyncPullActor` par `SyncPullDivergenceTests:297`
  (« Empty cloud, populated local »).
- **Un protocole `resetAll()` sur `SyncIdentityStore`** : pas nécessaire, le
  type n'expose que `lastKnownUserID()`/`setLastKnownUserID(_:)` — rien
  d'autre à réinitialiser, et un `resetAll()` non appelé nulle part aurait été
  du code mort.
- **`UserDefaults.standard` en défaut de test pour `SyncIdentityStore`** :
  jamais envisagé sérieusement — les mocks de ce fichier de tests partagent
  déjà le même process Swift Testing (`--no-parallel` ne les isole pas les
  uns des autres), donc un vrai `UserDefaults.standard` aurait fait fuiter
  l'état entre tests.

### Ouvert

Rien de nouveau. Les deux défauts nommés par la ronde 3 sont fermés et
prouvés rouge→vert. Pas de nouvelle piste ouverte par cette ronde.

---

## 2026-08-14 — Lot 2 (pull) : contre-relecture adversariale, ronde 3

### Fait

Aucune modification de code. Relecture adversariale de l'arbre de travail
(base `e1312cf` + modifications non commitées), avec **rejeu empirique** des
7 scénarios nommés plutôt que lecture de « code qui ressemble au correctif ».

⚠️ Piège de méthode à retenir : `git diff dev...HEAD` **ne montre pas** ce
travail — l'essentiel de la ronde 2 est non commité. Il faut `git diff` (arbre
de travail) + les 3 fichiers `??`. Le vérificateur précédent s'était déjà fait
avoir là-dessus sur l'étape SwiftLint.

### Testé

3 sondes jetables (`ZZReviewProbeTests.swift`, supprimée après coup, archivée
dans le scratchpad de session) exécutées via `swift test --no-parallel` :

- **Sonde 1 — identité re-provisionnée** : curseurs non-nuls + compte serveur
  vide → `profiles`=1, `rpg_states`=1, **`cards`=0, `review_logs`=0**. CRITIQUE B
  n'est PAS fermé sur ce chemin (voir Ouvert).
- **Sonde 2 — cascade parent/enfant** : `cards` bloquée derrière 2 lignes poison
  (pageSize 1, `FakeSyncServer`) → le `review_logs` en attente brûle ses 3
  strikes au cycle 3 et est abandonné définitivement ; la carte arrive au cycle
  5, le log est perdu pour de bon (`logs=0`).
- **Sonde 3 — abandon chirurgical dans un paquet d'ex æquo** : 3 lignes d'un
  même upsert, la poison ayant le plus petit uuid → au cycle 3 elle est
  abandonnée et **les 2 sœurs s'appliquent** (`["一","二"]`). Le curseur
  composite tient sa promesse. Cette sonde mérite d'être adoptée comme test de
  non-régression.

Vérifié aussi hors sonde : `ISO8601DateFormatter` **tronque à la milliseconde**
(snippet Swift autonome : `…22.968936+00:00` et `…22.968999+00:00` donnent le
même `Date`). Conséquence analysée : redélivrance possible de la queue d'une
même milliseconde, jamais de perte — le curseur est toujours posé sur une ligne
réellement présente dans la page, donc strictement en avant.

Suites filtrées relancées après suppression de la sonde : 72 tests, 5 suites,
vertes (`SyncPullDivergence|SyncMergeRules|SyncCursorStore|CloudSyncCoordinator|CloudDataDeletion`).

### Écarté

- **Première version de la sonde 2** (transport FIFO `MockSyncPullTransport`,
  page `[poisonA, poisonB, realCard]`) : ne prouvait rien. `apply()` traite
  **toute** la page, y compris les lignes situées après la ligne bloquante —
  seul le *curseur* est limité au préfixe. La carte était donc appliquée dès le
  cycle 1 et le log s'attachait. Il faut `FakeSyncServer` + `pageSize` petit
  pour que le parent reste hors de portée. À ne pas refaire.
- **Soupçon d'aller-retour `Date` dans le curseur** : cherché activement
  (`grep SyncCursorPosition(` sur tout le code de prod → un seul site,
  `SyncPullActor.swift:493`, qui réutilise la chaîne verbatim de la ligne).
  Rien à signaler, scénario 4 fermé.
- **Soupçon de boucle non bornée dans `pullAndApply`** : chaque `continue`
  avance le curseur strictement (drop poison) ou consomme une page pleine dont
  le curseur a bougé. Borné.

### Ouvert

- **CRITIQUE** — `SyncModelActor.markEverythingUnsynced()` n'est jamais appelé
  quand l'identité anonyme est silencieusement re-provisionnée (refresh token
  rejeté) : la règle 1 exige `isColdStart` (TOUS les curseurs nuls), ce qu'un
  appareil déjà synchronisé n'est jamais. Le commentaire de la méthode affirme
  pourtant l'inverse. Correctif proposé : mémoriser le dernier `user_id` connu
  (UserDefaults) et, dans `syncNow()` juste après `validAccessToken()` et
  **avant** `runPull`, réinitialiser curseurs + skip tracker si l'id a changé —
  le compte neuf étant vide, la règle 1 refire et la machinerie CRITIQUE B
  existante fait le reste, sans second site d'appel.
- **IMPORTANT** — la politique 3 strikes ne distingue pas « payload
  indécodable » (permanent) de « FK pas encore arrivée » (transitoire) : voir
  sonde 2. Piste : ne pas compter de strike sur une table enfant tant que sa
  table parente n'a pas atteint « caught up » dans le même cycle.
- **MINEUR** — une ligne en tête de page avec un `server_updated_at` non-`.string`
  ne peut jamais être force-abandonnée (`SyncPullActor.swift:479-480`) : elle
  n'est pas positionnable, donc « documenter + logger fort » est la réponse
  honnête.

---

## 2026-08-14 — Lot 2 (pull) : vérification indépendante de la ronde 2

### Fait

Contre-vérification (pas d'implémentation nouvelle) de l'entrée ci-dessous, sur
le même arbre de travail non commité (base `e1312cf`). Toutes les commandes
demandées passent (build IkeruCore, filtres de tests Sync + non-régression,
suite Sync complète 86 tests, builds `Ikeru`/`IkeruWidget` iOS et `IkeruWatch`
watchOS, i18n-lint 0 NEW, diff du catalogue = 18 lignes chirurgicales, filtre
CI contient bien SyncCursorStore/SyncMergeRules/SyncPullDivergence sans
collision). Contrôle manuel du code (pas seulement des tests) : le curseur
stocke `timestamp: String` verbatim sans aller-retour `Date` (confirmé dans
`SyncCursorStore.swift`), `setConsent(false)` n'appelle jamais
`markEverythingUnsynced` (seuls `cursorStore.resetAll()` /
`skipTracker.resetAll()`, éventuellement différés), et le consentement est
re-testé entre pull et push dans `CloudSyncCoordinator.syncNow()` juste avant
le premier `pushDirty*`. Repris moi-même le disable/restore du site d'appel
(a) (`CloudDataDeletionService.swift:197`, `markEverythingUnsynced` sous
`if false`) que le rapport de l'implémenteur laissait non revérifié : le test
`deletionMarksLocalRowsUnsynced` passe bien au rouge, restauré ensuite
octet-pour-octet (hash SHA-256 identique avant/après). Corrigé un commentaire
inexact repéré par l'implémenteur lui-même : `SyncPullActor+RowDecoding.swift`
prétendait que `SyncCursorTimestampParsing` était « hors du périmètre de
fichiers de ce lot » — faux, les deux types vivent dans `Services/Sync/` et
rien n'empêchait un appel direct ; reformulé pour dire honnêtement que la
duplication est volontairement laissée telle quelle (deux petits formatters
privés, sans risque de correction) plutôt que refactorée.

### Testé

Voir ci-dessus. Non revérifié moi-même (fait confiance au rapport de
l'implémenteur, lui-même journalisé) : l'isolation de `pendingCursorReset` en
dehors du test combiné `consentRevokedMidPullSkipsPushAndStillResetsCursors`,
et le wiring de `pullDegradedMessagePrefix`/`cloudSyncStatusValue` (vérifié
seulement en lisant le code, pas en le désactivant). La contrainte
SwiftLint « lignes touchées après commit, diff contre `origin/dev` » n'a pas
pu tourner à l'identique puisque rien n'est commité sur cette branche ; j'ai
reproduit sa logique (`swiftlint-diff-filter.py`) à la main sur l'arbre de
travail non commité contre `origin/dev` — 0 violation sur les lignes
touchées, mais c'est une approximation, à refaire pour de vrai après commit.
Rien vérifié contre le backend Supabase réel ce tour-ci (seul le curl manuel
documenté dans les commentaires du code l'a été, avant cette session).

### Écarté

Rien.

### Ouvert

Même limite résiduelle documentée par l'implémenteur, non retestée par moi :
une ligne en tête de page dont l'`id` est valide mais dont
`server_updated_at` ne parse pas retente indéfiniment sans jamais être
force-abandonnée (`SyncPullActor.swift` autour de la ligne 454-476,
comportement volontaire mais non couvert par un test). Rien n'a été commité
par cette session de vérification — un seul fichier corrigé
(`SyncPullActor+RowDecoding.swift`, non suivi par git), le reste de l'arbre
inchangé.

---

## 2026-08-14 — Lot 2 (pull) : curseur composite + politique de ligne poison (remédiation ronde 2)

### Fait

Branche `feature/cloud-lot2-pull`, **pas encore commité** (pas de SHA — travail
en cours au moment de cette entrée, sur la base WIP `e1312cf`). Deuxième ronde
de relecture adversariale sur le pull engine : la racine commune des bugs
n'était pas une suite de défauts isolés mais le choix de design du curseur —
un `Date` scalaire ne peut pas à la fois « ne perdre aucune ligne » et
« progresser toujours ». Cinq points traités :

1. **Curseur composite `(timestamp: String, id: UUID)`** — `SyncCursorPosition`,
   nouveau type dans `SyncCursorStore.swift`. Le `timestamp` est stocké
   **verbatim**, jamais reconstruit depuis un `Date` (6 chiffres de
   microsecondes + `+00:00`, jamais `Z`, fraction supprimée à la seconde
   exacte — vérifié en réel contre `aiayzlarixlogcoyswna`). `SyncPullTransport`
   construit désormais la requête PostgREST validée par curl :
   `or=(server_updated_at.gt.{TS},and(server_updated_at.eq.{TS},id.gt.{ID}))`.
   Piège découvert en cours de route et corrigé : `URLComponents` laisse `+`
   non échappé dans la query (RFC 3986 l'autorise, mais PostgREST — comme la
   plupart des serveurs — le décode comme un espace, suivant la convention
   `application/x-www-form-urlencoded`). Un `+00:00` non échappé aurait
   silencieusement corrompu le filtre `eq`. Fix : post-traitement
   `percentEncodedQuery.replacingOccurrences(of: "+", with: "%2B")`.
   `IkeruCore/Sources/Services/Sync/{SyncCursorStore,SyncPullTransport}.swift`.
   Tests : `SyncCursorStoreTests` (formats réels PostgREST, tie-break par id),
   `tiedClusterWiderThanOnePageIsFullyTraversed` +
   `exAequoTieClusterAgainstRealKeysetFilter` (`SyncPullDivergenceTests+PoisonRow.swift`).

2. **Politique de ligne poison (CRITIQUE A)** — nouveau protocole
   `SyncSkipTracker` (`SyncSkipTracker.swift`, persisté UserDefaults comme le
   curseur — un compteur en mémoire seule ne survivrait pas à un relaunch
   entre deux cycles). `SyncPullActor.pullAndApply` trace, par table, l'id de
   la ligne de tête bloquée ; au bout de 3 cycles consécutifs sur le même id,
   avance le curseur exactement au-delà d'elle (`setCursor`, pas
   `advanceCursor` — cette ligne n'a jamais été appliquée, le contrat
   « after durably applied » de `advanceCursor` aurait menti), compte la
   ligne dans `permanentlyDroppedRowCounts`, log `Logger.sync.error`. Autre
   fix structurel dans le même geste : `pullAll` attrape désormais
   `SyncPullActorError` **par table** au lieu de laisser l'erreur remonter et
   tuer tout le cycle — avant, une ligne poison sur `cards` empêchait
   `review_logs` à `exercise_outcome_logs` d'être même interrogées. Le garde-fou
   « page pleine sans avancée » original reste en place comme filet
   d'anomalie résiduel (tous les rows d'une page s'appliquent mais aucun n'a
   de `server_updated_at` exploitable) — plus jamais atteint en usage normal,
   mais toujours attrapé par le même `catch` par table s'il se déclenche.
   `IkeruCore/Sources/Services/Sync/{SyncPullActor,SyncSkipTracker}.swift`.
   Tests : `poisonRowOnFullPageDoesNotAbortSubsequentTables` (page pleine),
   `poisonRowIsDroppedAfterThreeCyclesAndUnblocksLaterRows` (page courte),
   `residualAnomalyGuardOnFullPageDoesNotAbortSubsequentTables` (le filet
   résiduel) — les trois dans `SyncPullDivergenceTests+PoisonRow.swift`.

3. **Seed après effacement ne seedait rien (CRITIQUE B)** — `SyncModelActor.markEverythingUnsynced()`
   (fetch + `syncedAt = nil` sur les 7 types + save), appelé (a) depuis
   `CloudDataDeletionService.deleteAllCloudData()` juste après
   `cursorStore.resetAll()`, et (b) depuis `CloudSyncCoordinator.syncNow()`
   quand le pull renvoie `.seededFromLocal`, **avant** le push. Sans (b), le
   cas « refresh token rejeté → nouvelle identité anonyme silencieuse »
   (`AnonymousIdentityManager`) ne passe jamais par (a) et restait cassé.
   `CloudDataDeletionService` prend maintenant un `modelContainer` requis
   (appel site : `SettingsView.deleteCloudDataFromServer()`,
   `modelContext.container`). Commentaire de `PullSummary.seededFromLocal`
   corrigé : il affirmait que le push seede toujours le serveur — vrai
   seulement parce que (b) existe maintenant, précisé explicitement.
   Tests : `seedFromLocalPushesCardsAndLogsNotJustProfileAndRPGState`
   (`CloudSyncCoordinatorTests.swift`), `deletionMarksLocalRowsUnsynced`
   (`CloudDataDeletionServiceTests.swift`).

4. **Réentrance d'acteur (IMPORTANT C)** — `setConsent(false)` posait
   `cursorStore.resetAll()` immédiatement, y compris pendant qu'un
   `syncNow()` était suspendu (réentrance des acteurs Swift à chaque
   `await`) — le cycle en vol réécrivait des curseurs par-dessus juste
   après, défaisant le reset silencieusement. Fix : `pendingCursorReset`,
   honoré dans le `defer` de `syncNow()`. Deuxième moitié, plus grave :
   `syncNow()` ne vérifiait le consentement qu'à l'entrée — une révocation
   à mi-cycle laissait les 7 `pushDirty*` partir quand même (violation de
   consentement, pas un détail UX). Fix : re-check entre le pull et le
   premier push, sortie sur `.skippedConsentOff`.
   `IkeruCore/Sources/Services/Sync/CloudSyncCoordinator.swift`. Test :
   `consentRevokedMidPullSkipsPushAndStillResetsCursors` — utilise un
   `GatedPullTransport` + `PullGate` (deux `CheckedContinuation` dans une
   boîte `@unchecked Sendable`) pour suspendre réellement `syncNow()` au
   milieu d'un `fetchRows`, révoquer depuis le test, puis relâcher.

5. **Observabilité (mineurs E/F/G)** — `PullSummary.skippedRowCounts` /
   `permanentlyDroppedRowCounts` étaient calculés et lus par personne.
   Câblés jusqu'au statut via un second préfixe,
   `CloudSyncCoordinator.pullDegradedMessagePrefix` (même mécanisme que
   `pullFailureMessagePrefix`) ; `SettingsView` gagne un 3ᵉ statut, « Backed
   up, restore incomplete » / « Sauvegardé, restauration incomplète »
   (catalogue de localisation, fr+en, édition chirurgicale). Commentaire
   corrigé dans `SettingsView` : les curseurs/skip-tracker sont de l'état
   `UserDefaults` **local**, pas « server-side » comme l'affirmait le
   commentaire précédent. Distinction `applied` vs `alreadyPresent` pour les
   3 tables append-only — une ligne déjà présente incrémentait `applied`,
   surestimant le travail d'un cycle qui ne fait en réalité que re-fetcher
   la même borne. Test : `degradedPullSurfacesVisibleStatus`
   (`CloudSyncCoordinatorTests.swift`).

**Découpage fichiers pour rester sous les seuils SwiftLint** (`file_length`
1200, `type_body_length` 600) : `SyncPullActor.swift` a débordé à 1237 lignes
après l'ajout de la politique poison → extrait `SyncRowDecoding` /
`SyncPullDateParsing` / `SyncIdentifiable` dans
`SyncPullActor+RowDecoding.swift` (redescend à 1100). Même chose côté tests :
`SyncPullDivergenceTests.swift` à 602 lignes de corps de struct (limite 600)
après les 5 nouveaux tests → extraits dans
`SyncPullDivergenceTests+PoisonRow.swift` (`extension SyncPullDivergenceTests`,
`makeContainer()` remonté de `private` à `internal` pour l'accès cross-fichier).

### Testé

- `cd IkeruCore && swift build` — propre (avertissements pré-existants
  ailleurs dans le repo, aucun nouveau).
- `swift test --no-parallel --filter "SyncPullDivergence|SyncMergeRules|SyncCursorStore"`
  — 55 tests, verts.
- `swift test --no-parallel --filter "CloudSyncCoordinator|CloudDataDeletion|FSRSService"`
  — 45 tests, verts.
- `swift test --no-parallel --filter "Sync"` (filet plus large, toute la
  suite Sync) — 86 tests, verts.
- **Chaque correctif désactivé manuellement puis re-testé** (exigence de la
  tâche) : seuil poison → `Int.max` (seul `poisonRowIsDroppedAfterThreeCyclesAndUnblocksLaterRows`
  rouge), `catch` par table → `throw` (seul `residualAnomalyGuardOnFullPageDoesNotAbortSubsequentTables`
  rouge), `markEverythingUnsynced` (b) commenté (seul `seedFromLocalPushesCardsAndLogsNotJustProfileAndRPGState`
  rouge), `markEverythingUnsynced` (a) commenté (seul `deletionMarksLocalRowsUnsynced`
  rouge), re-check consentement mi-cycle retiré (données parties après
  révocation — `dataTransport.calls` non vide, exactement la violation
  décrite), reset différé retiré (le cycle en vol réécrit le curseur
  par-dessus le reset — reproduit puis re-vérifié corrigé), câblage du statut
  dégradé commenté (seul `degradedPullSurfacesVisibleStatus` rouge). À
  chaque fois, fichier restauré et diff vérifié identique à l'original avant
  de continuer.
- `xcodebuild build -project Ikeru.xcodeproj -scheme Ikeru -destination
  "generic/platform=iOS" -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO`
  — `BUILD SUCCEEDED` (valide que `SettingsView.swift` et
  `CloudSyncTriggers.swift` compilent contre la nouvelle API IkeruCore).
- `swiftlint lint` sur le périmètre modifié — aucune violation nouvelle
  (`file_length`/`type_body_length` déjà au vert après le découpage ; les
  seuls dépassements restants dans le rapport global — `HomeView.swift`,
  `SettingsView.swift`, `DailyTermCatalog.swift` — sont pré-existants,
  vérifié via `git show HEAD:...` avant mon edit).
- **Non vérifié** : pas de run réel contre le vrai backend Supabase pour
  cette ronde (le curseur composite lui-même a été validé par curl par
  l'utilisateur avant la tâche — voir le prompt de tâche — mais le code
  Swift qui le reproduit n'a été exercé qu'en tests unitaires/fakes, jamais
  en intégration réseau réelle). À vérifier au premier device-pass.

### Écarté

- **Test 7 original (`fullyTiedFullPageThrowsInsteadOfLooping`) réécrit, pas
  gardé tel quel.** Il asserait qu'une page pleine entièrement ex-æquo
  DEVAIT lever `cursorStalledOnFullPage` — correct pour l'ancien curseur
  `Date` scalaire, qui ne pouvait distinguer deux lignes de même timestamp.
  Le curseur composite supprime le hazard structurellement (chaque ligne a
  une position unique). Garder l'assertion originale aurait revalidé une
  régression exactement au point que ce lot corrige. Remplacé par
  `tiedClusterWiderThanOnePageIsFullyTraversed` (traversée complète, pas
  d'exception) + `exAequoTieClusterAgainstRealKeysetFilter` (même scénario
  contre le vrai filtre `FakeSyncServer`, une seule transaction `upsert`
  pour les 3 lignes — l'ancien fake bumpait l'horloge par ligne, ce qui ne
  pouvait jamais produire un vrai ex-æquo).
- **Poison-row tracking par table unique, pas multi-candidats.** Le tracker
  ne suit qu'UN candidat par table à la fois (le premier row bloqué). Si
  deux lignes poison différentes se trouvent dans la même page, la seconde
  n'est comptabilisée qu'après que la première ait été droppée (au cycle
  suivant, via un re-fetch). Plus simple et plus prévisible qu'un tracking
  multi-id par table ; le coût est un délai supplémentaire de cycles pour
  des pages contenant plusieurs poisons distinctes simultanément — jugé
  acceptable, ce cas devrait être rarissime en pratique.
- **`FakeSyncServer` : basculé de « un timestamp par ligne » à « un
  timestamp par transaction `upsert` ».** L'ancienne version ne pouvait
  jamais produire un vrai ex-æquo (chaque ligne recevait un tick d'horloge
  différent), donc tout ancien test « tie cluster » ne prouvait rien sur le
  vrai hazard. Signalé par la relecture avant que ça devienne un trou de
  couverture silencieux.

### Ouvert

- Le résidu documenté dans `pullAndApply` (ligne de tête avec `id` valide
  mais `server_updated_at` manquant/illisible à la 3ᵉ frappe) ne progresse
  jamais — pas de crash, pas de position fabriquée, mais pas de résolution
  non plus (retente indéfiniment sans jamais dropper). Comportement
  délibéré et documenté (« mieux vaut ne rien faire que fabriquer une
  position fausse ») mais reste un cas résiduel non couvert par un test
  dédié — jugé assez pathologique (colonne serveur absente alors que
  `updated_at` est présent) pour ne pas justifier plus de temps sur cette
  ronde.
- Rien commité sur cette branche pour l'instant — à faire sur demande
  explicite, avec un message de commit qui distingue les 5 points listés
  ci-dessus.

---

## 2026-08-14 — Lot 4 : la sauvegarde cloud devient annonçable (conformité)

### Fait

Branche `feature/cloud-lot4-compliance`. Le lot 1 avait livré une sauvegarde
push-only qui ne pouvait pas être annoncée : la politique de confidentialité
affirmait que les données d'apprentissage ne quittaient pas l'appareil, et
l'interrupteur était derrière `IKERU_DEV_TOOLS`.

**Le gate ne protégeait rien.** `IKERU_DEV_TOOLS` est actif en configuration
**Release** (pbxproj ligne 1727, c'est documenté dans CLAUDE.md — les outils dev
partent volontairement en TestFlight). J'avais affirmé le contraire à l'oral la
veille : faux. Ce qui a sauvé la mise, c'est que le code de synchro n'a jamais
été mergé dans `master` — donc aucun build TestFlight ne l'a embarqué. À la
première release, l'interrupteur serait devenu accessible aux testeurs avec une
politique mensongère. D'où l'ordre lot 4 avant lot 2.

Livré : `privacy.html` (FR+EN, section « Sauvegarde cloud (optionnelle) »),
`PrivacyInfo.xcprivacy` (3 types ajoutés), Edge Function de suppression +
`CloudDataDeletionService` + entrée Réglages, dégatage de l'interrupteur.

**Deux découvertes côté serveur, vérifiées en SQL** (`pg_constraint`,
`information_schema.triggers`), qui ont changé des décisions :

1. Les 8 tables ont leur `user_id` en `REFERENCES auth.users(id) ON DELETE
   CASCADE`. Supprimer l'utilisateur auth suffit donc à tout effacer — y compris
   une table qu'on ajouterait plus tard sans y penser. Les `delete` par table de
   la fonction Edge ne sont **pas** porteurs de la correction ; ils servent à
   rendre un compte de lignes honnête plutôt qu'un « faites confiance au
   cascade », et à survivre à une migration qui retirerait le CASCADE.
2. Chaque table porte un `server_updated_at` alimenté par un trigger
   `BEFORE INSERT OR UPDATE`. C'est le curseur de pull du lot 2, daté par
   l'horloge du **serveur** — insensible à un téléphone mal réglé. Le lot 2 ne
   touchera ni au schéma serveur ni au schéma SwiftData (pas de V5, donc pas de
   nouveau process CI isolé à créer).

**Le défaut le plus coûteux, trouvé en relecture adversariale.** La première
version du service traitait **tout** échec d'obtention de jeton comme « rien à
supprimer » et renvoyait un succès. Trois conséquences en cascade : un apprenant
hors ligne s'entendait dire que ses données étaient effacées alors qu'elles
étaient intactes ; l'UI remettait les trois compteurs à zéro, donc
`hasEverBackedUp` repassait à `false` et **la ligne de suppression disparaissait
de l'écran** — plus aucun moyen de réessayer. Pire encore en ligne : si le
refresh token était rejeté, `validAccessToken()` mintait une **nouvelle**
identité, la suppression portait sur ce compte neuf et vide, et les lignes de
l'ancien `user_id` devenaient orphelines définitivement, avec un succès affiché.

Correctif en amont plutôt qu'en surface : `AnonymousIdentityManager` expose
`existingSessionAccessToken()`, qui ne travaille qu'avec ce qui est déjà dans le
Trousseau et **ne mint jamais** d'identité de repli. Seul un Trousseau vide est
un no-op légitime ; tout le reste remonte comme erreur. La distinction est
volontairement dans Core et pas dans la vue : c'est une propriété du domaine
(« une demande d'effacement ne doit jamais viser le mauvais compte »), pas un
détail d'affichage.

### Testé

- `swift build` + `swift test --no-parallel --filter "CloudDataDeletion"` : 5/5.
  Deux tests réécrits parce que leur sémantique a changé, un ajouté pour la
  régression ci-dessus (session présente mais non rafraîchissable → doit lever,
  ne doit ni appeler l'endpoint ni se connecter en repli).
- `--filter "AnonymousIdentity|CloudSyncCoordinator|SyncPayloadBuilder"` : 24/24.
- Builds `Ikeru` (iOS), `IkeruWatch` (watchOS), `IkeruWidget` : les trois OK.
  ⚠️ Pour la Watch, `-destination "generic/platform=iOS"` échoue en tapant sur la
  montre physique appairée ; c'est `generic/platform=watchOS` qu'il faut.
- `plutil -lint` sur le manifeste : OK. `privacy.html` reparsé : OK.
- **Non testé** : le bouton de suppression sur device. La fonction Edge n'est pas
  déployée (voir Ouvert), donc le chemin nominal n'a jamais été exercé en réel —
  seulement contre un transport factice.

### Écarté

- **Réécrire `Localizable.xcstrings` via `json.dump`** : à ne jamais refaire. Le
  fichier n'est **pas** trié alphabétiquement et Xcode sépare les clés par
  `" : "` (espace avant le deux-points). Une sérialisation naïve a produit
  7923 insertions / 7736 suppressions pour 2 clés ajoutées. Reconstruit en
  conservant l'ordre d'origine et en n'ajoutant les nouvelles clés qu'à la fin :
  187 insertions, 0 suppression. Si le diff du catalogue dépasse quelques
  dizaines de lignes, c'est qu'on l'a cassé.
- **L'opt-in séparé pour l'historique Sakura** (prévu au lot 4 par la spec) :
  reporté, et déclaré plutôt que passé sous silence. Rien ne pousse
  `companion_chat_messages` aujourd'hui — construire l'opt-in *et* le push serait
  un élargissement de périmètre. Choix retenu : le chat reste local, la politique
  le dit explicitement, l'opt-in arrivera avec le push du chat s'il arrive.
- **Concaténer `error.localizedDescription` dans le toast d'échec** :
  `CloudDeletionError` ne conforme pas à `LocalizedError`, donc l'apprenant
  lisait « The operation couldn't be completed. (IkeruCore.CloudDeletionError
  error 1.) » — bruit technique qui fuite en plus un nom de type dans l'UI. Le
  détail va au log ; l'utilisateur reçoit le seul fait qui change sa prochaine
  action : rien n'a été supprimé, réessayez.

### Ouvert

- **La fonction Edge n'est pas déployée** (`list_edge_functions` renvoie `[]`).
  Tant qu'elle ne l'est pas, le bouton renvoie 404 et `privacy.html` promet une
  suppression qui n'existe pas. **Bloquant avant tout merge `dev → master`**,
  puisque c'est ce merge qui publie la page sur GitHub Pages. Rien dans le repo
  ne rejoue ce déploiement : à documenter dans CLAUDE.md une fois fait.
- Deux réglages Supabase pour le lot 3 (dashboard, hors portée MCP) :
  « Client IDs » = `com.ikeru.app` (le jeton natif porte le bundle id dans `aud`,
  activer le provider ne suffit pas) et **Manual linking**, sans quoi le
  rattachement du compte anonyme est indisponible. Le lot 3 devra utiliser
  `linkIdentityWithIdToken` et **pas** `signInWithIdToken` — le second crée un
  autre utilisateur et abandonne l'historique poussé.
- Toujours dû : le test device de la suppression de profil (actif puis non actif).

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
