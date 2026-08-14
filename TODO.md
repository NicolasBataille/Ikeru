# Ikeru — TODO

> **The authoritative backlog now lives in the July 2026 review docs:**
>
> - [`docs/reviews/2026-07-08-project-review.md`](docs/reviews/2026-07-08-project-review.md) — full findings
> - [`docs/reviews/2026-07-08-remediation-plan.md`](docs/reviews/2026-07-08-remediation-plan.md) — phased plan (Phases 0–9)
>
> This file is only a pointer plus the highest-risk open debt. Six TestFlight builds
> have shipped (releases #16–#21); the old "first build / integration wiring" checklist
> is obsolete and has been removed.

> **Ce qui n'est pas testé ou pas couvert vit dans
> [`docs/known-gaps.md`](docs/known-gaps.md)** — un registre `GAP-nn` prêt à être
> confié à un agent. Ce fichier-ci porte le backlog *produit* (quoi construire) ;
> l'autre porte les trous de *vérification* (ce qu'on ne sait pas encore).

## Top open debt (verified 2026-07-14)

- [ ] **Learner telemetry for expert review** — spec written, not implemented:
  [`docs/design-specs/2026-08-10-learner-telemetry-design.md`](docs/design-specs/2026-08-10-learner-telemetry-design.md).
  Journaliser ce que fait l'apprenant pour faire relire ses résultats par un agent expert
  (cadence hebdo vs ponctuelle **non tranchée**). Lot 1 = `answeredValue`/`exerciseType`/`surface`
  sur `ReviewLog` → rend les **paires de confusion** observables (aujourd'hui calculées puis
  jetées). Prérequis : réparer le seeder fixture (§10).
- [~] **Cloud sync (Supabase free tier)** — spec :
  [`docs/design-specs/2026-08-10-cloud-sync-design.md`](docs/design-specs/2026-08-10-cloud-sync-design.md).
  **Lots 0, 1 et 4 livrés** (schéma V4 + tombstones, sauvegarde push-only sur identité
  anonyme, conformité : `privacy.html` + `PrivacyInfo` + suppression serveur + interrupteur
  dégaté). **Lot 2 en cours** (pull + fusion : les 4 règles du §5.3, rejeu FSRS, tests de
  divergence). **Lot 3 à faire** (Sign in with Apple — tranché le 2026-08-14).
  ⚠️ Pour le lot 3 : la promotion anonyme→compte passe par `linkIdentityWithIdToken`, **pas**
  `signInWithIdToken` (le second crée un autre utilisateur et orpheline l'historique poussé),
  et demande deux réglages dashboard : « Client IDs » = `com.ikeru.app` + **Manual linking**.
  Sert aussi de **banc de fixtures** pour les tests utilisateur (§11).
- [ ] **IA sans clé : accès OpenRouter fourni par l'app** — idée 2026-08-14, non planifiée.
  Aujourd'hui Sakura est inutilisable tant que l'apprenant n'a pas collé sa propre clé Gemini,
  ce qui est une falaise à l'entrée. Objectif : un accès par défaut fourni de notre côté, la
  clé personnelle restant une **option** (pas une suppression).
  Trois contraintes à intégrer **avant** de concevoir, pas après :
  1. **Une clé partagée ne peut pas être embarquée.** Le repo est public, et de toute façon
     toute clé dans un binaire iOS s'extrait. Donc ce n'est pas « mettre une clé par défaut »
     mais **écrire un proxy** : la clé vit côté serveur, l'app appelle le proxy. La brique
     existe déjà — `supabase/functions/delete-account` est le patron exact (vérifier le JWT de
     l'appelant, puis agir avec un secret privilégié).
  2. **Le coût devient le nôtre, et l'abus aussi.** Un proxy fait converger l'usage de tout le
     monde sur un seul compte, alors que les identités anonymes sont gratuites et illimitées à
     créer — quelqu'un peut en fabriquer des milliers. Il faut une limite par utilisateur, donc
     une identité **durable**, ce que l'anonyme-par-appareil n'est pas (réinstallation = nouvelle
     identité). **C'est un argument pour faire le lot 3 avant ce chantier**, pas après.
  3. **Ça change notre posture vis-à-vis des données.** La politique actuelle dit que le texte
     part chez *le fournisseur choisi par l'utilisateur avec sa propre clé*. Avec un proxy,
     **nous** devenons l'intermédiaire pour du contenu de conversation. `privacy.html` et
     `PrivacyInfo.xcprivacy` seraient à remettre à jour — même classe de problème que le lot 4,
     et c'est celle qui mord en silence.
  À trancher au moment de planifier : les modèles gratuits d'OpenRouter sont limités et
  changent ; un usage réel demanderait des crédits payants, ce qui touche la contrainte
  « aucune API payante ».
- [x] ~~**Fixture seeder is unusable**~~ — corrigé (OBS-013). `TestFixtures.swift` génère
  désormais un historique `ReviewLog` sur du contenu réel et laisse FSRS dériver l'état, au
  lieu de poser `stability`/`reps` à la main ; les cartes bouche-trou (`人0`, `日1`) ont
  disparu. Débloque la QA J+30/J+90 et la télémétrie ci-dessus.
- [ ] **No UI-test target** — launch-argument fixture infrastructure exists but nothing
  exercises it. Add a minimal XCUITest smoke suite (remediation 8.7).
- [ ] **Content expansion** — N5 bundle has 206 vocab items / 31 grammar points / 96 sentences
  vs the ~800 / ~80 / ~300 targets; no N4+ bundle yet (remediation 4.5).
- [ ] **CI test coverage still partial** — `.github/workflows/ci.yml`'s `--filter` allowlist now
  covers ~40 suite-name patterns out of 1,015 total `@Test` cases in `IkeruCore`, materially more
  than the original ~12% quarantine (exact pass-rate not re-measured here — verify with `swift
  test` locally). The remaining gap is a documented **toolchain constraint**, not untested code: the
  macOS-15 runner's Swift Testing library (1501) SIGSEGVs mid-run on a legacy suite that never
  reproduces on newer toolchains (local Swift 6.3.3 / library 1902 runs the full suite clean).
  Un-filtering fully is blocked on the runner image, not on our tests — revisit once macos-15
  bumps its Xcode/Swift Testing version (remediation 8.1).

Everything else (bugs, SRS correctness, pedagogy wiring, AI honesty, platform features,
product decisions) is tracked in the remediation plan above — update status there, not here.

## Recently completed (since 2026-07-08)

The five items originally listed here as open have shipped:

- **SwiftData migration safety** (8.2) — `VersionedSchema` V1/V2 + `SchemaMigrationPlan` in
  `IkeruCore/Sources/Models/Schema/IkeruSchema.swift` (#24, `9f908f6`).
- **Dynamic Type** (5.1) — app-wide relative text styles + accessibility overflow fixes
  (`4ea2925`, `365cf0b`, `7793181`).
- **CI test coverage** — widened well past the original ~12% quarantine (see above); the
  toolchain SIGSEGV blocking full coverage is now documented in `ci.yml` itself.
- Also landed this window: FSRS-5 scheduling + `desiredRetention` (3.9, `45e3305`), session
  segment interleaving (3.2, `79406ea`), real `skillBalances`/grammar into `LearnerSnapshot`
  (4.3, `03b44e6`), exercise outcomes feeding FSRS grades (4.4, `2cb31d3`), i18n-lint CI gate
  (5.10, `b3b3768`), iCloud-backup UI gating + LocalGPU wiring (2.5/2.11, `41b06c7`), AI router
  rate-limit cooldown + `Retry-After` parsing (6.2, `8e4239b`), mnemonic reading validation
  (6.7, `9d4e252`).

Trust-surface items (`docs/privacy.html`, `AttributionView`, `PrivacyInfo.xcprivacy` — remediation
1.1–1.3) were fixed in this same pass; see those files' history for details.
