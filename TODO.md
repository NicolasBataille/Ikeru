# Ikeru — TODO

> **The authoritative backlog now lives in the July 2026 review docs:**
>
> - [`docs/reviews/2026-07-08-project-review.md`](docs/reviews/2026-07-08-project-review.md) — full findings
> - [`docs/reviews/2026-07-08-remediation-plan.md`](docs/reviews/2026-07-08-remediation-plan.md) — phased plan (Phases 0–9)
>
> This file is only a pointer plus the highest-risk open debt. Six TestFlight builds
> have shipped (releases #16–#21); the old "first build / integration wiring" checklist
> is obsolete and has been removed.

## Top open debt (verified 2026-07-08)

- [ ] **SwiftData migration safety** — no `VersionedSchema` / `SchemaMigrationPlan` despite
  `@Model` schema drift already shipped to TestFlight users (`RPGState`, `ProfileSettings`
  field additions). Lightweight migration has held so far, but any non-additive change is a
  **data-loss risk** for existing installs. Highest-priority engineering item.
- [ ] **CI test quarantine** — only ~12% of ~1,150 tests run in CI because of the `--filter`
  allowlist (`.github/workflows/ci.yml` ~line 120). Legacy `KanaCardRepository` /
  `PlannerService` suites SIGSEGV under `swift test`. Fix the crashes, then widen the filter.
- [ ] **No UI-test target** — launch-argument fixture infrastructure exists but nothing
  exercises it. Add a minimal XCUITest smoke suite.
- [ ] **Dynamic Type absent** — ~380 fixed font sizes across the app; no scaling support.
- [ ] **Content expansion** — N5 bundle has 206 vocab items vs ~800 target; no N4+ bundles yet.

Everything else (bugs, SRS correctness, pedagogy wiring, AI honesty, platform features,
product decisions) is tracked in the remediation plan above — update status there, not here.
