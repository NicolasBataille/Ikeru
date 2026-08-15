# Registre des trous connus

**Ce qui n'est pas couvert, pas vérifié, ou volontairement reporté.** Une entrée
par trou, chacune rédigée pour être confiée telle quelle à un agent.

Pourquoi ce fichier : l'information existait déjà, mais éparpillée entre
`JOURNAL.md` (chronologique, verbeux — cinq entrées rien que pour le lot 2 de la
synchro), les descriptions de PR (enterrées dès le merge) et `TODO.md` (le
backlog produit, pas les trous de vérification). Rien de tout ça ne répond à
« qu'est-ce qui n'est pas testé, et par quoi je commence ».

**Convention.** Chaque entrée porte un identifiant stable (`GAP-nn`), une
sévérité, ce qui n'est **pas** couvert, **pourquoi** ça a été laissé, et **ce qui
le fermerait**. Une entrée fermée est supprimée d'ici et son histoire reste dans
`JOURNAL.md`. Ne pas laisser d'entrée cochée traîner : un registre à moitié
périmé est pire que pas de registre.

> Les affirmations ci-dessous ont été vérifiées dans le code au 2026-08-14 —
> pas recopiées depuis un rapport d'agent. Avant d'agir sur une entrée, vérifier
> quand même qu'elle est toujours vraie : le code bouge, ce fichier moins vite.

---

## A. Synchro cloud — jamais confrontée au réel

### GAP-01 — La fusion n'a jamais tourné entre deux vrais appareils
**Sévérité : haute.** Toute la logique de fusion du lot 2 (les 4 règles, le rejeu
FSRS, les tombstones, le curseur composite) est couverte par des tests contre un
`FakeSyncServer` en mémoire. **Aucun test à deux appareils réels n'a jamais été
fait**, et c'est précisément le scénario pour lequel le lot existe.

Ce qui le fermerait : deux appareils (ou un device + un simulateur) avec le même
compte anonyme — noter la même carte hors ligne des deux côtés, reconnecter,
vérifier que les deux convergent vers le même état FSRS. Puis : supprimer une
carte sur A pendant que B la modifie, vérifier qu'elle disparaît partout.

Note : l'identité anonyme est **liée à l'appareil** (jeton dans le Trousseau),
donc partager un compte entre deux appareils n'est pas possible aujourd'hui sans
copier le jeton à la main. **Le lot 3 (Sign in with Apple) est ce qui rend ce
test faisable proprement** — c'est un argument de plus pour le faire.

### GAP-02 — Le pull a tourné contre le vrai Supabase, mais sur le cas le plus simple possible
**Sévérité : moyenne — inchangée, requalifiée le 2026-08-15.** Ce qui était
déjà éprouvé en réel : l'auth anonyme, l'upsert et son idempotence,
l'isolation RLS entre deux utilisateurs, la fonction de suppression, et la
syntaxe du curseur composite (parcours d'un paquet d'ex æquo avec `limit=1`).

**Nouveau depuis le 2026-08-15** : `SyncPullActor` a tourné pour de vrai
contre le vrai PostgREST — pas seulement contre `FakeSyncServer`. En
reproduisant [GAP-15] sur device pour documenter cette PR (#86), une bascule
de l'interrupteur de sauvegarde (`CloudSyncCoordinator.setConsent` →
`cursorStore.resetAll()`) a remis le curseur à zéro et déclenché un pull à
froid réel contre le projet Supabase de **production**. Constaté en boîte
noire (le vocabulaire 風物詩, supprimé localement mais toujours vivant côté
serveur — `deleted_at = null`, vérifié en SQL direct — est réapparu après le
pull) et attribué par lecture du code à
`SyncPullActor+StandaloneTables` (réinsertion inconditionnelle d'une ligne
serveur absente en local). C'est la première confirmation que le chemin de
pull s'exécute et applique correctement contre le vrai PostgREST, pas
seulement en test.

**Ce que ce cas ne couvre pas** : une ligne, une seule page, un seul appel —
le scénario le plus simple que ce code puisse rencontrer. N'ont **toujours**
jamais tourné en réel :
- la **pagination sur plusieurs pages** (le curseur composite n'a jamais
  affronté un vrai paquet d'ex æquo côté serveur, seulement le
  `FakeSyncServer`) ;
- les **volumes et la latence réels** (des centaines/milliers de lignes,
  un vrai réseau) ;
- les **lignes empoisonnées** ([GAP-03], [GAP-04]) — comportement lu dans le
  code, jamais observé contre un vrai serveur ;
- la **fusion** entre deux appareils sur le même compte ([GAP-01]).

Ce qui le fermerait : un script de fumée qui pousse ~2000 lignes, vide le store
local, relance un pull complet et compare. Attention : ~2000 lignes poussées en
un upsert forment **un seul paquet d'ex æquo** (trigger `now()`), ce qui est
justement le cas que le curseur composite est censé traiter — donc c'est le bon
volume de test, pas un excès.

---

## B. Synchro cloud — résidus assumés dans le code

### GAP-03 — Une ligne dont l'horodatage serveur est illisible retente sans fin
**Sévérité : basse.** `SyncPullActor.swift` (~:150 et ~:207). Si une ligne en
tête de page a un `id` valide mais un `server_updated_at` absent ou non
parsable, elle n'est jamais abandonnée de force : le curseur ne peut pas être
posé sur une position qu'on ne sait pas lire. Choix assumé et commenté
(« mieux vaut caler que fabriquer une position »), **mais aucun test ne le
couvre**.

Pourquoi c'est laissé : le cas suppose une écriture serveur anormale (le trigger
remplit toujours la colonne). Le risque est un blocage de table, pas une perte.

Ce qui le fermerait : décider si on veut un compteur borné là aussi, ou au
minimum écrire le test qui documente le comportement actuel.

### GAP-04 — Adoption d'id `RPGState` : une ligne serveur orpheline permanente
**Sévérité : basse.** `SyncPullActor.swift:705`. Après un pull échoué suivi d'un
push réussi, un appareil réinstallé peut pousser un `RPGState` neuf alors que le
serveur en détient déjà un pour le même profil. Le pull suivant les délivre tous
les deux : l'un fusionne, l'autre déclenche la branche d'adoption d'id. Le
système **se stabilise** (vérifié : pas de boucle) au prix d'une ligne serveur
orpheline par profil touché, et d'un changement d'identifiant sur un `@Model`
déjà persisté. Aucun compteur n'est perdu (fusion par `max()`).

Ce qui le fermerait : soit accepter et documenter, soit un nettoyage serveur des
`rpg_states` orphelins.

### GAP-05 — `ISO8601DateFormatter` tronque à la milliseconde
**Sévérité : informative.** Le serveur renvoie 6 chiffres de microsecondes ;
`…22.968936+00:00` et `…22.968999+00:00` donnent le **même** `Date`. Analysé :
conséquence possible = redélivrance de la queue d'une même milliseconde, jamais
de perte, parce que le curseur est toujours posé sur une ligne réellement
présente dans la page donc strictement en avant. La branche `eq` du filtre
utilise la **chaîne verbatim**, jamais un `Date` re-sérialisé — c'est ce qui
protège.

À ne pas « corriger » sans refaire l'analyse : c'est le genre de détail qu'on
casse en croyant l'améliorer.

---

## C. Périmètre volontairement reporté

### GAP-06 — Pas d'opt-in séparé pour l'historique Sakura
**Sévérité : bloquant si le chat part un jour au serveur.** La spec place cet
opt-in au lot 4 ; il a été reporté parce que **rien ne pousse
`companion_chat_messages` aujourd'hui**. Le chat reste local, `privacy.html` le
dit explicitement, et la fonction de suppression couvre quand même la table côté
serveur.

Règle à ne pas casser : **le jour où on pousse du contenu de conversation, cet
opt-in doit exister d'abord.** C'est un consentement distinct de la sauvegarde.

### GAP-07 — La fonction Edge n'est pas redéployée automatiquement
**Sévérité : moyenne (piège silencieux).** `supabase/config.toml` fige la config
et `CLAUDE.md` documente la commande, mais il n'y a **pas de step CI** (il
faudrait un secret `SUPABASE_ACCESS_TOKEN`). Si le projet Supabase est
réinitialisé, la suppression casse en 404 pendant que `privacy.html` continue de
la promettre.

Ce qui le fermerait : un job GitHub Actions sur `master` avec le secret, calqué
sur l'exemple officiel `supabase/setup-cli`.

---

## D. Hors synchro

### GAP-08 — ~~La Watch ne produit aucun historique FSRS~~ — **entrée FAUSSE, voir GAP-17**
**Fermé le 2026-08-15 : le constat d'origine était erroné.** Il s'appuyait sur
« aucun `ReviewLog(` dans `IkeruWatch/` » — une preuve cherchée au mauvais
endroit. Par conception c'est l'**iPhone** qui écrit les journaux :
`Shared/WatchQuizReviewBatch.swift` transporte les événements et
`WatchConnectivityManager.processWatchQuizBatch` les note via
`CardRepository.gradeCard(surface: "watch")`. La chaîne complète a été retracée
et elle est vivante sur `dev`.

Leçon, la deuxième du même jour : **une absence constatée dans un fichier ne
prouve rien tant qu'on n'a pas vérifié que le mécanisme devait s'y trouver.**
(L'autre : compter ce qu'une vue affiche n'est pas compter des lignes — voir
GAP-15.)

Mais le mécanisme livré porte trois défauts, relevés en relecture adversariale
et **non corrigés** → GAP-17.

### GAP-15 — Rien ne produit jamais de tombstone : une suppression ne se propage pas
**Sévérité : haute (annulation silencieuse d'une action de l'apprenant).**
Constaté sur device le 2026-08-15, sur les vraies données.

`deletedAt` n'est **jamais** positionné par une action utilisateur. Les seules
affectations de ce champ dans tout le dépôt sont dans le *pull*
(`SyncPullActor*.swift`), qui ne fait que recopier ce que le serveur a dit.
Toutes les suppressions de l'app sont des `modelContext.delete()` durs :
profil (`ProfileViewModel:173`), entrée de vocabulaire
(`VocabularyRepository:259`), carte (`CardRepository:519`).

Une ligne supprimée disparaît donc de l'appareil pendant que le serveur la
conserve avec `deleted_at = null`. Elle ne revient pas tout de suite —
seulement parce que le curseur de pull a déjà dépassé son `server_updated_at`,
donc elle n'est plus redistribuée. **Le curseur est remis à zéro** au
changement d'identité, à la réinstallation, et à toute bascule de
l'interrupteur de sauvegarde (`CloudSyncCoordinator.setConsent` →
`cursorStore.resetAll()`). Au pull suivant, `SyncPullActor+StandaloneTables`
réinsère toute ligne serveur absente en local, sans condition — la suppression
est annulée.

⚠️ **Pas d'exhibit mesuré — une première tentative était fausse.** L'écart
apparent « 17 lignes serveur contre 2 sur l'iPhone » relevé d'abord n'en est
pas un : les 15 lignes manquantes sont des entrées kana avec
`isInDictionary = false`, et `VocabularyRepository.allEntries()` filtre sur
`isInDictionary == true` (`:248`). Elles sont présentes des deux côtés, juste
masquées de la liste. Compter ce qu'une vue affiche n'est pas compter des
lignes. Le constat ci-dessus reste établi **par lecture du code**, pas par
observation : il manque encore une démonstration de bout en bout (supprimer un
vrai mot du dictionnaire, réinitialiser le curseur, le voir revenir).

⚠️ **Le mécanisme de tombstone existe pourtant de bout en bout** —
`SyncPayloadBuilder` sérialise `deleted_at` pour les 8 tables, les règles de
fusion le gèrent, le pull l'applique, et tout ça est couvert par des tests
contre le `FakeSyncServer`. C'est un mécanisme complet dont **aucun chemin de
production ne déclenche jamais le premier maillon**. Les tests ne pouvaient pas
le voir : ils fournissent eux-mêmes les tombstones en entrée.

Ce qui le fermerait : faire écrire `deletedAt` aux sites de suppression plutôt
que de détruire la ligne, et filtrer les lignes tombstonées à la lecture. C'est
un chantier à part entière (8 types d'entités, toutes les requêtes de lecture,
une purge différée) — pas une rustine.

Non fermé faute de temps sur cette session : la démonstration de bout en bout
(couper/rallumer la sauvegarde, puis observer les 15 kana revenir) n'a pas pu
être jouée, parce que la bascule ne déclenchait aucune synchro — voir GAP-16,
qui est la raison pour laquelle le test n'a pas eu lieu.

### GAP-16 — Rallumer la sauvegarde pouvait ne rien faire, en silence
**Sévérité : moyenne. Corrigé le 2026-08-15**, entrée conservée parce que le
symptôme est instructif.

`handleCloudSyncToggleChange` appelait `syncNow()` sans `ignoringThrottle:
true`. Le throttle de 60 s existe pour brider les déclencheurs de fond
(passage au premier plan, retour du réseau) — pas une action explicite de
l'apprenant. Rallumer l'interrupteur moins d'une minute après n'importe quelle
autre tentative renvoyait donc `.skippedThrottled` et ne faisait **rien**,
pendant que la ligne d'état affichait « à jour » : une affirmation sur une
synchro qui n'a jamais tourné.

Observé sur device : consent off → on, puis aucune écriture serveur (dernière
écriture `cards`/`review_logs`/`vocabulary_entries` : la veille à 17:48).

Le chemin de restauration à l'onboarding passait déjà `ignoringThrottle: true`,
avec un commentaire expliquant exactement ce raisonnement. Un seul des deux
appelants avait été corrigé — la leçon générale : quand on documente pourquoi
un appel doit contourner une protection, vérifier **tous** les appels qui
relèvent du même argument.

### GAP-17 — Le pont Watch → iPhone perd des nano-sessions et peut noter le mauvais profil
**Sévérité : haute (perte de données + corruption inter-profils).** Trois
défauts dans du code **déjà livré sur `dev`**, trouvés en relecture
adversariale le 2026-08-15. Aucun n'est corrigé.

**1. CRITIQUE — une nano-session entière peut disparaître définitivement.**
`Ikeru/Services/WatchConnectivityManager.swift:186` appelle
`markBatchProcessed(batch.sessionId)` — écriture **synchrone** en
`UserDefaults` — *avant* la boucle de notation et ses N points de suspension.
Si iOS tue le processus (jetsam, arrêt forcé) pendant l'un de ces `await`, le
lot est marqué « traité » avec **zéro `ReviewLog` écrit**, et toute
redélivrance est rejetée. Dix révisions réelles → aucun historique, pour
toujours.

Ce qui rend le défaut notable : le commentaire des lignes 181-184 montre que
l'auteur a raisonné sur **exactement ce danger** (« marking it earlier … would
drop the batch forever ») et n'a déplacé le marquage que derrière le garde
`modelContainer`, laissant la fenêtre bien plus large des `await` sans
protection. Le commentaire décrit une intention que le code ne tient qu'au
tiers.

Correction minimale : un `Set<UUID>` en mémoire pour la déduplication des
`Task` entrelacés, et l'écriture `UserDefaults` **après** la sauvegarde du
contexte. Correction complète : persister le lot brut à la réception et
rejouer au lancement ce qui n'a pas été noté.

**2. IMPORTANT — un lot répondu sous le profil A est noté sur les cartes de B.**
`WatchQuizReviewBatch` ne porte **aucun identifiant de profil**. À la
réception, `allKanaCards()` → `activeProfileCards()` résout les caractères sur
le profil **actif au moment de la livraison**. Bascule de profil entre le quiz
et la livraison → état FSRS de B muté et `ReviewLog` fabriqués pour des
révisions que B n'a jamais faites. Aggravant : `StudySetStore.chosenGroups`
(`KanaPoolViewModel.swift:415`) lit une clé `UserDefaults` **globale**, pas par
profil — le recouvrement de caractères est donc le cas probable, pas le cas
limite. Correction : porter un `profileId` dans le lot et abandonner (ou
mettre en file) si le profil actif ne correspond pas.

**3. IMPORTANT — XP crédité pour des réponses explicitement non notées.**
`WatchConnectivityManager.swift:276` re-dérive soigneusement `correctCount` et
`totalQuestions` des événements réellement notés, mais passe
`xpEarned: batch.xpEarned` tel quel. Désélectionner un groupe kana entre le
quiz et la livraison → 0 révision notée, 0 `ReviewLog`, et **50 XP quand
même**. Le commentaire des lignes 254-268 énonce le bon principe et ne
l'applique qu'à deux champs sur trois.

### GAP-13 — « Révisions » et l'historique réel divergent, dans les deux sens
**Fermé le 2026-08-15** (PR #85, `9297c8d`→`15dc7d3`, mergée `055cc40`).
Constaté sur device le 2026-08-14 : le Tatami affichait **53 révisions**
pendant que la sauvegarde cloud remontait **74 `ReviewLog`**. Ce n'étaient pas
deux mesures du même phénomène, mais deux compteurs alimentés par des chemins
disjoints — `KanaDrillViewModel` journalisait via `gradeCard` sans jamais
toucher `RPGState.totalReviewsCompleted`, pendant que `WatchConnectivityManager`
créditait ce même compteur sans produire de `ReviewLog` (c'était [GAP-08],
depuis requalifié [GAP-17]).

**Ce qui a changé** : `CardRepository.activeProfileReviewCount()` dérive
désormais le chiffre directement des lignes `ReviewLog` du profil actif
(`deletedAt == nil`) — vérifié par lecture, c'est une lecture pure sans
cache, pas un troisième compteur qui pourrait rediverger. Les trois sites
d'affichage sont rebranchés dessus (vérifié par `grep` sur le dépôt au
2026-08-15, zéro résidu) : `HomeViewModel.advancedThresholdSignals()`,
`TatamiEligibilityRow`, et le champ « Lifetime review count » de l'export
JSON (`DataExportManager`).

**Ce qui n'a PAS disparu** : `RPGState.totalReviewsCompleted` — le champ
lui-même n'a **pas** été supprimé (la charge utile de synchro et le snapshot
de sauvegarde locale en dépendent sans changement de schéma) et reste
**incrémenté à la main à trois endroits** (`SessionRPGPersistence`, et deux
chemins dans `WatchConnectivityManager` : `processWatchResult` legacy et
`processWatchQuizBatch`, `grep totalReviewsCompleted` au 2026-08-15 confirme
les trois écrivains, zéro de plus). Ce n'est plus un défaut : le champ est
maintenant documenté comme non-autoritaire pour tout affichage
(`RPGState.totalReviewsCompleted`'s doc comment) et gardé sciemment pour un
usage plus étroit — la relance « premier terme du jour » de `HomeView`
(`evaluateFirstSessionDailyTermPrompt`), qui a besoin de sa transition
0 → >0, pas du chiffre dérivé. Le repointer sur `ReviewLog` a été envisagé et
rejeté (voir JOURNAL 2026-08-15) : ça aurait cassé la relance pour tout
apprenant ayant déjà fait du drill kana avant sa première séance.

⚠️ Effet assumé : le chiffre affiché **a augmenté** d'un coup pour les
apprenants existants (53 → ~74 dans le cas observé) et la porte Tatami s'est
rapprochée. C'est une correction, pas un cadeau, mais c'est un changement de
comportement sur une porte pédagogique.

**Ce qui reste non vérifié** : le saut 53→74 lui-même n'a jamais été rejoué
sur l'appareil qui a servi au constat original. Côté tests, la couverture
est inégale entre les trois sites d'affichage : `IkeruCore` est couvert
(159 tests verts sur le filtre `RPG|Review|Session|Tatami|Mastery`, dont 3
nouveaux pour `activeProfileReviewCount`), et **`DataExportManager` a un
test app-target exécutable en CI** (`DataExportManagerTests`, 12/12 verts) —
c'est d'ailleurs ce test qui a attrapé un vrai rouge en CI pendant la
vérification (fixture posant `totalReviewsCompleted: 999` sans `ReviewLog`,
correct pour l'ancien comportement, faux pour le nouveau) : une preuve
concrète, pas seulement théorique, que la dérivation change le résultat.
En revanche, ni `HomeViewModel.advancedThresholdSignals()` ni
`TatamiEligibilityRow` ne sont exercés par un test app-target pour ce
chemin précis : `HomeViewModelTests` existe (15 `@Test`) mais ne teste ni
`advancedThresholdSignals()` ni `activeProfileReviewCount` — et n'est de
toute façon **pas** dans le sous-ensemble `-only-testing` que la CI lance
(`.github/workflows/ci.yml`) ; `TatamiEligibilityRow` n'a aucun fichier de
test du tout. Ce n'est pas la panne SwiftData qui bloque `ProfileViewModelTests`
(18 tests, SIGTRAP pré-existant sur l'hôte de test applicatif, sans rapport
avec GAP-13) — c'est simplement une couverture qui n'existe pas.

### GAP-14 — Le schéma serveur n'est pas reproductible depuis le repo
**Sévérité : moyenne.** `supabase/migrations/` ne contient que la migration de
clé composite du 2026-08-14. Les 8 tables, leurs politiques RLS, la colonne
`server_updated_at` et ses triggers ont été appliqués directement sur le projet
vivant et n'existent **nulle part** dans le dépôt. Un projet Supabase
réinitialisé ne se reconstruit pas.

Ce qui le fermerait : `supabase db pull` pour aspirer le schéma existant dans
`supabase/migrations/`, en vérifiant que le rejeu sur une base vierge redonne
bien les 8 tables, les politiques et les triggers. À faire avant que le schéma
ne bouge encore.

### GAP-09 — Aucune cible de tests UI
**Sévérité : moyenne.** L'infrastructure de fixtures par argument de lancement
existe, mais rien ne l'exerce. Aucun parcours utilisateur n'est testé de bout en
bout.

### GAP-10 — La CI ne lance qu'un sous-ensemble filtré des tests Core
**Sévérité : moyenne, contrainte externe.** Le filtre couvre ~40 motifs de suites
sur 1015 cas `@Test`. Ce n'est **pas** du code non testé : c'est l'image
`macos-15` dont la bibliothèque Swift Testing (1501) SIGSEGV sur une suite
legacy, alors que la toolchain locale (1902) passe tout. Débloqué par un bump de
l'image, pas par du travail sur nos tests.

---

## E. Dû par l'utilisateur (ne peut pas être fait par un agent)

**Vide au 2026-08-14** — les deux entrées de cette section ont été fermées lors
de la passe device du jour. Section conservée : la prochaine livraison touchant
à l'UI ou à un flux destructif en remettra.

*Fermé* — **GAP-11, suppression de profil** : les deux cas passent sur iPhone
14 Pro. Non actif comme actif, aucun nom vide pendant l'animation, aucun crash,
retour propre sur le profil habituel. À noter pour qui rejouera ce test : créer
un profil l'**active immédiatement** (`ProfileViewModel.createProfile` pose
l'actif et émet `displayModeDidChange` — délibéré, c'est la parade à l'héritage
du mode d'affichage par un profil neuf). Tester le cas « non actif » demande
donc de rebasculer d'abord.

*Fermé* — **GAP-12, parcours de sauvegarde cloud** : voir plus haut.
