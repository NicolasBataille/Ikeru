# Claude Code — conventions Ikeru

Petit guide pour rester aligné avec le flow du repo.

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

- `cd IkeruCore && swift test --filter "..."` pour les suites Core (le full `swift test` SIGSEGV sur des suites legacy, voir le `--filter` du workflow pour le subset vert).
- `xcodebuild build -project Ikeru.xcodeproj -scheme Ikeru -destination "generic/platform=iOS" -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO` pour valider la compile iOS sans signing.
- Schemes : `Ikeru` (app), `IkeruWatch` (watchOS), `IkeruWidget` (widget extension).
- watchOS est restreint : pas de `Vision` ni `AVAudioUnitTimePitch` — wrap les imports/usages dans `#if canImport(Vision)` ou `#if !os(watchOS)`.

## Localisation (gotcha SwiftUI)

Les strings vivent dans `Ikeru/Localization/Localizable.xcstrings` (catalogue avec FR + EN).

- `Text("Mon texte")` avec un **littéral** → init `LocalizedStringKey` → lookup auto dans le catalogue ✅
- `Text(someString)` où `someString: String` → init `verbatim:` → **PAS** de lookup ❌

Pour les modèles qui exposent du texte (`struct Page { let title: String }`), typer `title` en `LocalizedStringKey` (compatible avec les littéraux grâce à `ExpressibleByStringLiteral`). Pour les strings runtime assignées à un `@State`, utiliser `String(localized: "...")` au site d'assignation. Voir PR #13 pour le pattern canonique.

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

## App targets

- iPhone uniquement (`TARGETED_DEVICE_FAMILY = "1"`) — pas d'iPad pour l'instant. Si support iPad un jour, prévoir les 4 orientations dans `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad`.
- Architecture arm64, iOS 17.0+ minimum, watchOS 10+ pour la Watch app.
- Team ID Apple : `N84YXYF2NZ` (payant, ne pas confondre avec le team perso gratuit `SY88W6CB3G`).
