# Synchronisation cloud — comptes, avancement, et mode hors-ligne

> Date : 2026-08-10 · Statut : **spec, non implémentée**
> Cible : instance **Supabase** gratuite (Postgres + Auth + RLS).
> Contrainte produit : **l'app doit rester pleinement utilisable hors-ligne.**

## 1. Objectif et non-objectifs

**Objectif.** Sortir l'avancement de l'apprenant du seul appareil : gérer des
comptes, stocker la progression côté serveur, et **resynchroniser à la
reconnexion** — sans jamais bloquer l'usage hors-ligne.

**Non-objectifs**, explicitement hors périmètre :

- pas de temps réel / collaboratif (aucun besoin, coût de complexité élevé) ;
- pas de contenu utilisateur partagé entre apprenants ;
- pas de migration du contenu pédagogique (les bundles restent embarqués) ;
- **pas de dépendance réseau pour apprendre**. Si le serveur est mort, l'app est
  strictement aussi bonne qu'aujourd'hui.

## 2. Le principe non négociable : local d'abord

> **SwiftData reste la source de vérité pour l'écriture et la lecture. Le cloud
> est un miroir réconcilié en arrière-plan.**

Concrètement : aucune vue n'attend le réseau, aucune notation de carte ne part
d'un appel HTTP, aucun écran de chargement bloquant. La synchro est une tâche de
fond qui peut échouer en silence et réessayer.

Ce n'est pas une préférence d'architecture, c'est la thèse produit : une app de
révision quotidienne qui exige du réseau perd sa fiabilité — et le calme qu'elle
vend avec.

## 3. Le cadeau architectural : la plupart des données ne peuvent pas entrer en conflit

Le schéma compte **11 entités** (`IkeruSchemaV2`). Classées par nature de synchro :

| Entité | Nature | Politique |
|---|---|---|
| `ReviewLog` | **append-only, immuable** | insertion idempotente — *sans conflit possible* |
| `ExerciseOutcomeLog` | **append-only** | idem |
| `VocabularyEncounter` | **append-only** | idem |
| `CompanionChatMessage` | **append-only** | idem, mais **opt-in séparé** (§7) |
| `Card` | état mutable | LWW + **réparable depuis `ReviewLog`** |
| `VocabularyEntry` | état mutable | LWW par champ |
| `UserProfile` | état mutable | LWW |
| `RPGState` | compteurs monotones | merge par `max()` |
| `MnemonicCache` | cache régénérable | **ne pas synchroniser** (ou best-effort) |
| `AssetManifest` | cache local d'appareil | **jamais** |
| `DailyTerm` | déterministe par jour | synchroniser seulement `usedWords` (anti-répétition) |

**Quatre entités sur onze sont append-only** — donc conflict-free par
construction. Et la cinquième, `Card`, porte un état **dérivable** de son
historique : en cas de divergence irréconciliable, `ReviewLog` fait autorité et
l'état FSRS peut être recalculé.

Deuxième cadeau : **toutes les entités ont déjà une clé primaire `UUID` générée
côté client**. L'upsert est donc naturellement idempotent — rejouer un push deux
fois est sans effet. C'est la propriété qui rend une synchro simple viable.

## 4. Identité : anonyme d'abord, compte ensuite

L'onboarding actuel est à **zéro friction** : un prénom, deux questions, on
apprend. Imposer un login détruirait la meilleure propriété du produit.

**Décision :** `signInAnonymously()` de Supabase Auth **au premier lancement**.
L'appareil obtient une identité serveur immédiatement, la synchro fonctionne, et
l'apprenant ne voit rien.

**Lier un vrai compte devient une action opt-in**, proposée *au moment où elle a
du sens* — « garder ta progression si tu changes de téléphone », pas à
l'installation. Supabase permet de promouvoir une session anonyme en compte
permanent **sans perdre l'`user_id`** : aucune migration de données à ce moment-là.

Méthodes : **Sign in with Apple** (obligatoire dès qu'on propose un autre login
tiers) + e-mail magic link. Pas de mot de passe à gérer.

**Multi-profils :** l'app a déjà des profils locaux multiples. Ils deviennent des
lignes `profiles` sous un même `user_id`. Un compte peut porter plusieurs
apprenants (utile : usage familial), et la bascule reste locale.

## 5. Mécanique de synchro

### 5.1 Ce qu'il faut ajouter au schéma → `IkeruSchemaV3`

Sur chaque entité synchronisée :

- `updatedAt: Date` — horloge de modification locale ;
- `deletedAt: Date?` — **tombstone**. Sans ça, une suppression ne peut pas se
  propager : l'appareil B ré-enverrait éternellement la ligne que A a effacée ;
- `syncedAt: Date?` — dernier push confirmé, sert au calcul du delta.

→ Nouvelle version de schéma + `MigrationStage` légère. Le repo a déjà une V1→V2
qui fonctionne : le motif est connu, mais **lire d'abord l'avertissement en tête
de `IkeruSchema.swift`** (les types figés ne se modifient jamais ; on ajoute une
version).

### 5.2 La boucle

**Push** — lignes locales où `updatedAt > syncedAt`, par lots, en `upsert` sur
l'`id`.
**Pull** — lignes serveur où `updated_at > cursor`, `cursor` étant un
**horodatage serveur**, jamais l'horloge de l'appareil (dérive garantie sinon).
**Merge** — selon le tableau du §3.
**Déclencheurs** — retour au premier plan, fin de séance, retour du réseau. Avec
throttle : la fin de séance est le seul moment qui justifie un push immédiat.

### 5.3 Conflits : les règles qui comptent vraiment

**Règle 1 — un cloud vide n'écrase JAMAIS un local peuplé.**
C'est le sinistre classique de toute synchro naïve : l'apprenant se connecte, le
serveur répond « 0 carte », et six mois de mémoire disparaissent. Le premier
`pull` sur un compte vide doit être traité comme un **seed depuis le local**, pas
comme une vérité.

**Règle 2 — `ReviewLog` fait autorité sur `Card`.**
Si deux appareils ont noté la même carte hors-ligne, on ne choisit pas un
gagnant : on **fusionne les deux journaux** et on rejoue l'état FSRS. C'est
possible parce que `FSRSService` est composé de fonctions pures à horloge
injectable — propriété déjà présente, ici payante.

**Règle 3 — les compteurs monotones se fusionnent par `max()`**, jamais par LWW
(sinon un appareil en retard fait *reculer* l'XP).

**Règle 4 — la suppression gagne toujours** sur une modification concurrente.

### 5.4 Ce qui ne part jamais

- **Les clés API** (Gemini, Claude…) : Keychain, appareil, point final.
- Les clips audio et le cache d'assets (régénérables, volumineux).
- Les bundles de contenu (statiques, versionnés avec l'app).
- Les enregistrements vocaux de shadowing (locaux et éphémères).

## 6. Sécurité — RLS ou rien

**La `anon key` de Supabase n'est pas un secret** : elle est conçue pour être
publique et sera visible dans un repo public. **Sa sécurité repose entièrement
sur les Row Level Security policies.** Sans RLS, elle donne un accès total.

Donc, comme condition de mise en service :

- **RLS activée sur toutes les tables**, sans exception, avec une policy du type
  `auth.uid() = user_id` en lecture comme en écriture ;
- **la `service_role key` ne doit jamais approcher le binaire** — CI et scripts
  d'admin uniquement, via secrets GitHub ;
- un test automatisé qui **vérifie qu'une table sans RLS fait échouer la CI** :
  c'est le genre d'oubli qui ne se voit jamais à l'œil ;
- pas de PII au-delà du strict nécessaire : `displayName` est un prénom choisi,
  pas une identité.

## 7. Confidentialité et conformité — bloquant

Ajouter des comptes et un serveur **change la nature du produit** au regard de
l'App Store et du RGPD. Rien ne se livre avant que ces points soient traités :

- **Suppression de compte in-app obligatoire** (App Store 5.1.1(v)) dès qu'il y a
  login. Or la review du 2026-08-10 a établi qu'**il n'existe aujourd'hui aucun
  moyen de supprimer un profil** (OBS-028) — ce trou passe de « dette de
  confiance » à **blocage réglementaire**.
- **`privacy.html` et `PrivacyInfo.xcprivacy` mis à jour AVANT la livraison.** La
  politique actuelle décrit une app qui ne stocke rien à distance. Ce projet a
  déjà dû corriger une politique qui contredisait les flux réels ; ne pas
  recommencer.
- **L'historique de conversation Sakura est du texte libre écrit par
  l'utilisateur.** Il ne part au serveur que sur **opt-in distinct** du reste.
- Export et suppression complets doivent rester possibles (l'export local existe
  déjà — il devient la brique « portabilité »).
- Hébergement : choisir une **région UE** à la création du projet. Ce n'est pas
  modifiable après.

## 8. Réalités du palier gratuit — à savoir avant de s'engager

| | Limite | Impact |
|---|---|---|
| Base | 500 Mo | large : `ReviewLog` est le moteur de croissance, ~100 o/ligne, ~50 révisions/jour ⇒ **~2 Mo par apprenant et par an** |
| Auth | 50 000 MAU | sans objet à cette échelle |
| **Inactivité** | **projet mis en pause après ~7 jours sans requête** | ⚠️ **le vrai risque** |

**La mise en pause est le point à traiter honnêtement.** Pour une app perso ou
portfolio à usage irrégulier, le projet peut se retrouver en pause et faire
échouer toute synchro. Deux conséquences :

1. c'est **exactement pourquoi le local-d'abord n'est pas négociable** — un
   projet en pause doit être un non-événement pour l'apprenant ;
2. prévoir un ping de maintien en vie (cron GitHub Actions déjà disponible) et
   surtout **une UI qui ne dramatise pas** l'échec de synchro : un état « pas
   encore synchronisé », jamais une erreur bloquante.

Coût : **0 €**, conforme à la contrainte « aucune API payante ».

## 9. Et l'iCloud existant ?

`CloudBackupManager` existe mais est **désactivé à la compilation**
(`iCloudEnabled = false`), et les entitlements CloudKit sont commentés dans
`Ikeru.entitlements`. La review de juillet avait relevé que ses écrans
dead-endaient (depuis gatés).

**Décision recommandée : Supabase remplace cette voie.** Ne pas maintenir deux
systèmes de synchro concurrents — c'est la meilleure façon de fabriquer des
divergences indébogables. Soit on retire `CloudBackupManager`, soit il reste
dormant et non exposé, mais il ne revit pas.

## 10. Découpage

**Lot 0 — prérequis** *(à faire même si la synchro est repoussée)*
Suppression de profil (OBS-028) ; `IkeruSchemaV3` avec `updatedAt` / `deletedAt`
/ `syncedAt` ; réparation du seeder fixture (sans apprenant synthétique crédible,
la synchro est intestable).

**Lot 1 — sauvegarde à sens unique**
Auth anonyme + push seul. Aucun pull, donc **aucun risque de perte de données** :
le pire cas est un serveur en retard. C'est la moitié de la valeur (ne plus
perdre sa progression) pour une fraction du risque.

**Lot 2 — pull et fusion**
Curseur serveur, tombstones, les 4 règles du §5.3, rejeu FSRS depuis `ReviewLog`.
**Le lot dangereux** : il ne se livre qu'avec des tests de divergence
(deux appareils hors-ligne, notes concurrentes, suppression concurrente).

**Lot 3 — comptes réels**
Sign in with Apple + magic link, promotion de la session anonyme, écran
« synchronisé / en attente / hors-ligne », multi-appareils.

**Lot 4 — conformité**
Suppression de compte serveur, mise à jour `privacy.html` + `PrivacyInfo`,
opt-in séparé pour l'historique Sakura.

**Lot 1-bis — états de test** *(cf. §11, se greffe dès que le pull existe)*
Générateur d'historique `ReviewLog` sur contenu réel + bibliothèque d'états
nommés + garde-fous compte de test. **À faire tôt** : c'est ce qui rend tous les
autres lots testables, et ça débloque la QA des états J+30/J+90.

> Les lots 0 et 1 livrent l'essentiel du bénéfice. **Ne pas commencer par le
> lot 2.**

## 11. Fabriquer des états d'apprenant pour les tests — la deuxième raison de faire ça

C'est un bénéfice à part entière, et il répond à un blocage **avéré** : la review
du 2026-08-10 s'est arrêtée net sur les états J+30/J+90 parce que le seeder
fixture local est inutilisable (OBS-013 — cartes de recto `人0`, `日1`, aucun
kana, prénom écrasé, dictionnaire vidé, tutoriels réinitialisés).

Avec un état serveur, **fabriquer un apprenant devient une opération de données,
plus une opération de code** : on pousse l'état voulu, l'appareil le tire, et le
testeur — humain ou agent — se retrouve exactement où on veut.

### 11.1 Une bibliothèque d'états nommés

Des profils de test versionnés côté serveur, applicables à un compte de test :

| État | Ce qu'il permet de tester |
|---|---|
| `j0-vierge` | onboarding, première séance, première exposition |
| `j7-kana-en-cours` | mode fondation, progression partielle, mixte nouveau/révision |
| `j30-backlog` | la dette de rétention (24 dus → 35), le plafond de 40 % |
| `en-difficulté` | leeches, confusions récurrentes, intervention |
| `n5-complet` | portes de déverrouillage, éligibilité Tatami, seuils atteints |
| `pré-tatami` | l'état juste sous le seuil, pour voir la bascule |

### 11.2 La règle qui rend ces fixtures crédibles

> **Générer l'historique, pas l'état.**

C'est la leçon directe de l'échec du seeder actuel : il pose arbitrairement
`stability = 1, reps = 2` sur des cartes bidon, ce qui produit un apprenant
**incohérent** — d'où le compteur かな bloqué à 0 quels que soient les sliders.

À la place : **fabriquer une suite de `ReviewLog` plausible sur du contenu réel**,
puis laisser FSRS dériver l'état. C'est exactement la règle 2 du §5.3, réutilisée
à l'envers. Bénéfices :

- l'état est **forcément cohérent** avec le moteur, puisqu'il en sort ;
- les paires de confusion et les leeches apparaissent **naturellement** si on
  scripte les erreurs — donc les fonctionnalités qui en dépendent deviennent
  testables ;
- le même générateur alimente le [paquet de review d'apprenant](2026-08-10-learner-telemetry-design.md),
  ce qui permet de **valider la télémétrie sans attendre des mois de données
  réelles**.

### 11.3 Garde-fous

- Les fixtures vivent dans un **projet Supabase distinct** (ou, a minima, un flag
  serveur `is_test_account` protégé par RLS). **Aucun chemin de code ne doit
  pouvoir écraser les données d'un compte réel** — c'est la version distante du
  sinistre « cloud vide écrase le local » (§5.3, règle 1), en pire.
- L'application d'une fixture est gatée par `IKERU_DEV_TOOLS`, comme les outils
  dev actuels — et disparaît du binaire App Store avec le flag.
- L'opération est **journalisée** : savoir quel état a été appliqué et quand,
  sinon on se retrouve à déboguer un apprenant fantôme.

### 11.4 Ce que ça change pour les reviews

Le relecteur expert n'a pas pu répondre à « est-ce que ça se répare tout seul à
J+30 ? » — il a dû répondre structurellement, faute d'état crédible. Avec cette
brique, on lui livre **un compte de test dans l'état exact** qu'on veut faire
relire, et la question redevient empirique.

C'est aussi ce qui rend possible un **Round 4 de retest après correctifs** : on
rejoue les mêmes états avant/après.

## 12. Effets de bord favorables

- **Le paquet de review d'apprenant** ([spec télémétrie](2026-08-10-learner-telemetry-design.md))
  devient générable **côté serveur** : plus besoin que l'appareil produise et
  partage un dossier. La synchro et la télémétrie partagent le même modèle de
  données ; concevoir `IkeruSchemaV3` en tenant compte des deux évite une
  seconde migration.
- La **restauration après réinstallation** devient triviale — et répond à la
  question ouverte du Round 0 de la review (un utilisateur qui réinstalle perd
  tout aujourd'hui).
- Un **historique multi-appareils** rend enfin mesurable la rétention réelle vs
  cible, sur des semaines.

## 12. La question à trancher avant de coder

**Qui est l'utilisateur de cette fonctionnalité ?**

- Si c'est **Nico seul + quelques bêta-testeurs** : le lot 1 suffit
  probablement pour toujours. Sauvegarde et restauration, sans comptes.
- Si c'est **une app publique à venir** : alors le lot 4 (conformité) n'est pas
  une finition, c'est un prérequis de publication, et la suppression de compte
  doit être conçue dès le lot 0.

La réponse change le découpage, pas l'architecture. Le local-d'abord, les
tombstones et le RLS sont justes dans les deux cas.
