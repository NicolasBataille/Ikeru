# Claude Code — conventions Ikeru

Petit guide pour rester aligné avec le flow du repo.

## Journal de bord : toujours tracer ce qu'on a fait (`JOURNAL.md`)

**À chaque session de travail sur l'app, ajouter une entrée en haut de
[`JOURNAL.md`](JOURNAL.md)** — avant de clore la session, pas « plus tard ».

Git dit *ce qui a changé*. Le journal dit *ce qu'on a essayé, ce qu'on a
vérifié, et pourquoi on a tranché comme ça*. Quatre rubriques :

- **Fait** — les changements livrés, avec le SHA du commit.
- **Testé** — ce qui a été vérifié et **comment** (device / simulateur / CI /
  test unitaire), et surtout ce qui n'a **pas** pu l'être, avec la raison. Une
  vérification manquante qu'on croit faite est pire que pas de vérification.
- **Écarté** — les pistes explorées puis abandonnées, avec le pourquoi. C'est la
  rubrique la plus utile : elle évite de refaire deux fois la même impasse.
- **Ouvert** — ce qui reste en suspens et ce qui le débloque.

Ne pas recopier le contenu des commits : renvoyer au SHA, et garder ici le
raisonnement, les mesures chiffrées et les décisions. Un bug qui a coûté cher à
diagnostiquer mérite que ses fausses pistes soient écrites noir sur blanc.

## Branches : par défaut, partir de `dev`, pas de `master`

Le repo utilise un flow à deux étages :

```
feature/*  →  PR  →  dev      (CI valide, AUCUN deploy)
dev        →  PR  →  master   (CI + TestFlight deploy)
```

- **Toute nouvelle branche** doit partir de `dev` (`git checkout dev && git pull && git checkout -b feature/X`).
- **Toute PR de feature** cible `dev` (`gh pr create --base dev`).
- **`master` est réservé aux releases** : on n'y push directement jamais. On y arrive via une PR `dev → master` quand l'utilisateur dit explicitement « release » / « déploie » / « ship ».
- Chaque push à `master` brûle un build TestFlight (12 min de CI + 10 min de processing Apple), donc on ne fait pas ça pour rien.

## Build & tests

- `cd IkeruCore && swift test --no-parallel` fait tourner **toute** la suite Core (1250 tests / 174 suites verts au 2026-08-15). `--no-parallel` reste requis pour les suites SwiftData.
  > Cette ligne disait « le full `swift test` SIGSEGV sur des suites legacy ».
  > **C'était faux sur les deux points** : jamais de SIGSEGV (sortie 1), et rien
  > de legacy — c'était `LocalGPUProviderTests`, qui construisait un vrai
  > `NWBrowser` Bonjour via l'argument par défaut de `LocalGPUProvider()`.
  > Corrigé (voir GAP-10). Ne pas réintroduire d'allowlist `--filter` : la CI
  > utilise désormais une **denylist**, pour que toute suite nouvelle tourne par
  > défaut au lieu d'être exclue en silence. ⚠️ `LegacyStoreMigrationTests` (le round-trip V1→V2) doit tourner dans **son propre process** : `swift test --no-parallel --filter "LegacyStoreMigration"` séparément — ouvrir un container avec les snapshots V1 figés empoisonne le cache global entité↔classe de CoreData pour `RPGState`, et tout fetch V2 ultérieur dans le même process peut matérialiser la mauvaise classe (« Failed to cast model … »). Ni `.serialized` ni `--no-parallel` ne suffisent (l'empoisonnement survit à la fin de la suite). Le filtre CI principal ne matche volontairement pas ce nom.
- `xcodebuild build -project Ikeru.xcodeproj -scheme Ikeru -destination "generic/platform=iOS" -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO` pour valider la compile iOS sans signing.
- Schemes : `Ikeru` (app), `IkeruWatch` (watchOS), `IkeruWidget` (widget extension).
- watchOS est restreint : pas de `Vision` ni `AVAudioUnitTimePitch` — wrap les imports/usages dans `#if canImport(Vision)` ou `#if !os(watchOS)`.

## Localisation (gotcha SwiftUI)

Les strings vivent dans `Ikeru/Localization/Localizable.xcstrings` (catalogue avec FR + EN).

- `Text("Mon texte")` avec un **littéral** → init `LocalizedStringKey` → lookup auto dans le catalogue ✅
- `Text(someString)` où `someString: String` → init `verbatim:` → **PAS** de lookup ❌

Pour les modèles qui exposent du texte (`struct Page { let title: String }`), typer `title` en `LocalizedStringKey` (compatible avec les littéraux grâce à `ExpressibleByStringLiteral`). Pour les strings runtime assignées à un `@State`, utiliser `String(localized: "...")` au site d'assignation. Voir PR #13 pour le pattern canonique.

> **`String(localized:)` dans IkeruCore résout le MAUVAIS bundle** et ignore l'override `AppLocale` (le `\.locale` injecté à `MainTabView`). Pour du texte runtime venant de Core, stocker la **clé** du catalogue et rendre via `Text(LocalizedStringKey(key))` dans la couche vue (app target) — pas dans Core.

## Sakura / IA (Gemini)

Sakura (partenaire de conversation) passe par `AIRouterService` → chaîne de fallback de providers. Sur un iPhone A16 (14 Pro) le modèle on-device d'Apple n'existe pas, donc **Gemini est le seul provider utilisable** : clé absente/refusée = Sakura échoue.

- **Modèle** : `gemini-2.5-flash` (constante `GeminiProvider.model`). L'ancien `gemini-2.0-flash` a un quota free-tier de **0** sur certains projets Google → `429 RESOURCE_EXHAUSTED, limit: 0`. Bumper la constante quand le modèle est retiré.
- **Clé** : Réglages → IA → Gemini (Keychain, `KeychainKeys.geminiAPIKey`). Les clés Google AI Studio existent désormais au format **`AQ.…`** autant que `AIzaSy…` — **les deux sont valides**, ne pas rejeter une clé `AQ.`.
- **Erreurs** : clé refusée (`400 API_KEY_INVALID` / 401 / 403) → `AIError.invalidKey` → « Votre clé IA a été refusée » (au lieu d'un générique « Sakura n'a pas pu répondre »). Triage : `curl -H "x-goog-api-key: <clé>" .../v1beta/models/<modèle>:generateContent`.
- **Contexte vocabulaire** : le VM passe les mots « connus » (dictionnaire, plafonné à 40) au prompt système comme préférence **souple** — Sakura les réutilise seulement si c'est naturel, jamais de force.
- **Rendu chat** : `KanaRubyText` met les furigana (hiragana) au-dessus des kanji uniquement (pas de romaji sur chaque kana) ; la traduction est masquée par défaut et révélée au tap, en ligne dimmée **sous** chaque phrase.

## Audio bundlé (prononciation offline)

Clips pré-générés et embarqués dans `Ikeru/Resources/Audio/` (un `.m4a` par chaîne, nommé `SHA-256(texte).hex[:16]`). `AudioService.playTTS` joue le clip bundlé via `BundledAudioLocator`, sinon fallback synthèse on-device. Zéro setup, zéro réseau.

- Régénérer : `scripts/generate-audio.py` (idempotent). Voix **VOICEVOX** speaker 2 (四国めたん), moteur libre lancé via Apple `container` (Docker ne démarre pas headless) — voir la memory `reference-bundled-audio`. Créditer VOICEVOX dans `AttributionView`.
- Textes : 92 kana + readings vocabulaire + phrases (depuis `n5-content.sqlite`) + readings des « termes du jour » (parsés depuis `DailyTermCatalog.swift`).
- La clé Swift (`BundledAudioLocator`) et la clé Python doivent rester **identiques**.
- `Audio/` est une **folder reference** dans le pbxproj (`lastKnownFileType = folder`) → nouveaux clips inclus sans édition pbxproj.

## Sauvegarde cloud Supabase

Projet `aiayzlarixlogcoyswna`, **région UE**, palier gratuit. Identité **anonyme**
(pas de compte) : `AnonymousIdentityManager` fait un `POST /auth/v1/signup` à
corps vide et garde le jeton dans le Trousseau de l'appareil.

- **La clé publiable est publique par nature** — elle est committée dans
  `SyncJSON.swift` et embarquée dans le binaire. Elle ne donne rien seule : les
  8 tables ont RLS, chaque ligne porte `user_id = auth.uid()`. Vérifié en réel
  le 2026-08-13 : un second utilisateur anonyme ne voit ni ne modifie les lignes
  du premier. Ne jamais committer la clé **`service_role`**, elle est d'une autre
  nature.
- **Curseur de pull** : chaque table porte `server_updated_at` avec un trigger
  `BEFORE INSERT OR UPDATE`. C'est l'horloge du **serveur** — ne jamais paginer
  sur `updated_at` (horloge client, fausse sur un téléphone mal réglé).
- **Suppression** : les 8 tables sont en `ON DELETE CASCADE` vers `auth.users`,
  donc supprimer l'utilisateur auth efface tout, y compris une table ajoutée
  plus tard.

### Fonction Edge : à redéployer à la main

`supabase/functions/delete-account` **n'est pas redéployée automatiquement** —
pas de step CI (il faudrait un secret `SUPABASE_ACCESS_TOKEN`). Après toute
modification du fichier, ou si le projet Supabase est réinitialisé :

```bash
supabase functions deploy delete-account --project-ref aiayzlarixlogcoyswna
```

Ne pas l'oublier : `docs/privacy.html` **promet** la suppression des données
serveur. Si la fonction est absente, le bouton renvoie 404 pendant que la
politique de confidentialité affirme le contraire — la page est servie par
GitHub Pages dès le merge sur `master`. `supabase/config.toml` fige la config
(`verify_jwt = true`) pour que le redéploiement reproduise l'existant.

Vérifier après déploiement : sans en-tête `Authorization` → 401, jeton bidon →
401, `GET` → 405, appel authentifié → 200 avec le compte de lignes par table.

### Mise en pause du palier gratuit

Un projet gratuit est **mis en pause après ~7 jours sans requête**.
`.github/workflows/supabase-keepalive.yml` le ping tous les jours. L'app étant
local-d'abord, une pause n'est jamais une perte de données — mais elle casse la
sauvegarde en silence. Si ce job passe au rouge, le projet est probablement déjà
en pause : il faut le restaurer depuis le dashboard.

## Pipeline CI

Workflow : `.github/workflows/ci.yml`.

Sur `master` et `dev` : SwiftLint → build (iOS / Watch / Widget en parallèle) → tests (filtered green subset Core + KanaDrillViewModelTests) → device-build sanity check → **[master uniquement]** deploy TestFlight via `xcrun altool`.

Particularités :
- Le test step **pick dynamiquement** le dernier simulateur iPhone dispo (`xcrun simctl list devices available`). Ne pas hardcoder `iPhone N` — l'image macos-15 bump périodiquement.
- `xcrun altool` exit 0 même en cas d'échec d'upload → le step grep `UPLOAD FAILED|Failed to upload|ERROR ITMS-` dans la sortie et force `exit 1`.

## TestFlight setup (one-time, déjà fait)

- 6 GitHub secrets : `ASC_API_KEY_{ID,BASE64}`, `ASC_ISSUER_ID`, `IOS_DIST_CERT_P12_{BASE64,PASSWORD}`, `APPLE_TEAM_ID`.
- Public link External Testing : `https://testflight.apple.com/join/kC7FfYxW`.
- Privacy policy : `https://nicolasbataille.github.io/Ikeru/privacy.html` (servi via GitHub Pages depuis `/docs/`).
- Beta Review : seulement la 1ère fois par version majeure ; les builds suivants se distribuent auto au groupe Public Beta dès qu'ils sortent du processing Apple (sauf changement permissions/capabilities).

## Sécurité (repo public)

Le repo est **public pour le portfolio**. Ne jamais committer :
- `.p8` / `.p12` / certs de distribution
- Tokens, mots de passe, clés API
- Données personnelles autres que les références déjà publiques (email contact, nom team)

Tous les secrets sensibles sont gérés via GitHub Actions secrets.

## Outils développeur en TestFlight (`IKERU_DEV_TOOLS`)

La section « Outils dev » dans Réglages (sliders fixture profile + boutons Wipe / Lootbox / Level-up / Clear cache / Build info) ainsi que le code TestFixtures sont gatés par le flag de compilation `IKERU_DEV_TOOLS`.

Ce flag est activé dans **Debug ET Release** (cf. `SWIFT_ACTIVE_COMPILATION_CONDITIONS` dans `Ikeru.xcodeproj/project.pbxproj` lignes ~1687 et Release config Project Ikeru) — donc visible dans les builds TestFlight le temps des tests.

### Removing `IKERU_DEV_TOOLS` avant App Store

Avant la première submission App Store, retirer le flag du Release config du projet :

1. Ouvrir `Ikeru.xcodeproj/project.pbxproj` dans un éditeur texte
2. Localiser la config Release du PBXProject « Ikeru » (id `7D6595C8356D9F7F7E05434C`)
3. Supprimer la ligne `SWIFT_ACTIVE_COMPILATION_CONDITIONS = IKERU_DEV_TOOLS;`
4. Optionnel : aussi dans la config Debug PBXProject (id `A45A6F037871A5F44542F639`) ramener `SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;` (au lieu de `"DEBUG IKERU_DEV_TOOLS"`)
5. Rebuild : la section disparaît, le code `TestFixtures` est exclu du binaire

Vérifier ensuite avec `grep -rn "IKERU_DEV_TOOLS" Ikeru.xcodeproj/project.pbxproj` qui doit retourner zero match avant submit App Store.

Le code Swift gardant les `#if IKERU_DEV_TOOLS` reste en place — il est juste exclu à la compilation. Pratique pour réintroduire le menu plus tard si besoin (juste re-add le flag).

## App targets

- iPhone uniquement (`TARGETED_DEVICE_FAMILY = "1"`) — pas d'iPad pour l'instant. Si support iPad un jour, prévoir les 4 orientations dans `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad`.
- Architecture arm64, iOS 17.0+ minimum, watchOS 10+ pour la Watch app.
- Team ID Apple : `N84YXYF2NZ` (payant, ne pas confondre avec le team perso gratuit `SY88W6CB3G`).

## Watch app (companion embarquée)

`IkeruWatch` (cible watchOS single-target moderne, `WKApplication`) est **embarquée dans l'app iPhone** comme companion — plus une app standalone. Elle s'installe donc via l'app Watch de l'iPhone (« Apps disponibles ») et part avec les builds TestFlight, sans sideload manuel ni Developer Mode.

- Câblage pbxproj (calqué sur l'embed du widget) : phase `PBXCopyFilesBuildPhase` « Embed Watch Content » (`dstSubfolderSpec = 16`, `dstPath = "$(CONTENTS_FOLDER_PATH)/Watch"`) sur la cible `Ikeru`, + `PBXBuildFile` (IkeruWatch.app, `RemoveHeadersOnCopy`) + `PBXTargetDependency`. Résultat : `Ikeru.app/Watch/IkeruWatch.app` (vérifié par `ValidateEmbeddedBinary`).
- Linkage : `INFOPLIST_KEY_WKCompanionAppBundleIdentifier = com.ikeru.app` (config IkeruWatch). Bundle id watch : `com.ikeru.app.watch` (doit être préfixé par l'app hôte).
- Signature CI : pipeline en **automatique** (`-allowProvisioningUpdates` + clé API ASC) → `com.ikeru.app.watch` provisionné tout seul au 1er archive qui l'embarque (surveiller cette 1ère release).
- Contenu : deux nano-sessions (quiz kana hiragana, drill d'accent tonique haptique) + une complication (données encore en dur, TODO App Group `UserDefaults`).
