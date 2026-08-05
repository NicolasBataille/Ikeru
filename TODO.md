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
