# Ikeru — TODO

> **The authoritative backlog now lives in the July 2026 review docs:**
>
> - [`docs/reviews/2026-07-08-project-review.md`](docs/reviews/2026-07-08-project-review.md) — full findings
> - [`docs/reviews/2026-07-08-remediation-plan.md`](docs/reviews/2026-07-08-remediation-plan.md) — phased plan (Phases 0–9)
>
> This file is only a pointer plus the highest-risk open debt. Six TestFlight builds
> have shipped (releases #16–#21); the old "first build / integration wiring" checklist
> is obsolete and has been removed.

## Top open debt (verified 2026-07-14)

- [ ] **Learner telemetry for expert review** — spec written, not implemented:
  [`docs/design-specs/2026-08-10-learner-telemetry-design.md`](docs/design-specs/2026-08-10-learner-telemetry-design.md).
  Journaliser ce que fait l'apprenant pour faire relire ses résultats par un agent expert
  (cadence hebdo vs ponctuelle **non tranchée**). Lot 1 = `answeredValue`/`exerciseType`/`surface`
  sur `ReviewLog` → rend les **paires de confusion** observables (aujourd'hui calculées puis
  jetées). Prérequis : réparer le seeder fixture (§10).
- [ ] **Cloud sync (Supabase free tier)** — spec written, not implemented:
  [`docs/design-specs/2026-08-10-cloud-sync-design.md`](docs/design-specs/2026-08-10-cloud-sync-design.md).
  Comptes + avancement distant + resync, **local-d'abord** (l'app doit rester utilisable
  hors-ligne). 4 entités sur 11 sont append-only ⇒ sans conflit ; `ReviewLog` fait autorité
  sur `Card`. Prérequis bloquants : suppression de profil (obligation App Store dès qu'il y a
  login) + `IkeruSchemaV3` (tombstones). Sert aussi de **banc de fixtures** pour les tests
  utilisateur (§11).
- [ ] **Fixture seeder is unusable** — seeds placeholder cards (`人0`, `日1`), zero kana,
  hardcodes the display name, wipes the personal dictionary and resets tutorial flags.
  Blocks all J+30/J+90 QA and the telemetry spec above. Found in the 2026-08 expert review
  (OBS-013). Fix règle : **générer un historique `ReviewLog` sur du contenu réel et laisser
  FSRS dériver l'état**, au lieu de poser `stability`/`reps` à la main.
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
