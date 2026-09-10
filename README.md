# Ikeru 生ける

A Japanese learning app for French speakers, built for iPhone, with an Apple
Watch companion and a home-screen widget.

Ikeru takes a beginner from their first hiragana to the **JLPT N5** perimeter —
and stops there, deliberately. It is not a path to fluency, and it doesn't claim
to be one.

[![TestFlight](https://img.shields.io/badge/TestFlight-public%20beta-blue)](https://testflight.apple.com/join/kC7FfYxW)

---

## What it does

- **Spaced repetition** on kana, kanji and vocabulary, scheduled with **FSRS-5**
  rather than a hand-rolled interval ladder — with one deliberate deviation,
  documented in `FSRSService`: due dates always land at least a day out, and
  same-day relearning is the session layer's job instead.
- **Stroke order** — animated, and traceable, with on-device handwriting
  recognition scoring the attempt.
- **Sakura**, an AI conversation partner that adapts to what the learner has
  actually studied, with furigana over kanji and translations hidden until
  tapped.
- **Pitch accent** drills, including a haptic mode on the Watch.
- **Listening and shadowing**, on bundled audio that works with no network.
- **Local-first storage**, with optional encrypted cloud backup.

### Honest scope

The shipped content bundle is, exactly:

| | |
|---|---:|
| kanji | 90 |
| radicals | 79 |
| kana | 142 |
| vocabulary | 693 |
| grammar points | 31 |
| example sentences | 335 |
| bundled audio clips | 1259 |

Of those sentences, 96 are Ikeru's own and 239 come from Tatoeba. Of the
vocabulary, 205 words are Ikeru's own list and 488 come from the Tanos JLPT N5
list — but every English and French meaning is written for Ikeru, including for
the imported words. The split is recorded per row (`vocabulary.list_source`), so
that claim is a query rather than a promise.

The bundled audio now covers everything the app speaks: all 208 drillable kana,
all 665 distinct vocabulary readings, and all 335 example sentences — imported
ones included, which was not true before. Measured after regeneration: 1258
texts, 0 failures, nothing left falling back to on-device synthesis.

That is JLPT N5 and no further. N4 and beyond are not in the app, and the
onboarding copy says so.

Known gaps — what is untested, unverified, or knowingly deferred — are tracked
in a register kept outside this repository, one entry per gap, with severity and
what would close it. It is kept deliberately unflattering.

---

## Architecture

```
Ikeru/          iOS app target — SwiftUI views, view models
IkeruCore/      Swift package — models, services, repositories, theme
IkeruWatch/     watchOS companion, embedded in the iPhone app
IkeruWidget/    home-screen widget extension
IkeruTests/     app-target tests
```

**IkeruCore** holds everything that isn't a view, so it can be tested without a
simulator: the FSRS scheduler, the session planner, the sync engine, the AI
provider chain, the content repositories.

- **Swift 6**, strict concurrency. Actors for shared mutable state, `Sendable`
  value types across isolation boundaries.
- **SwiftData** with a versioned schema (currently V4) and tested migrations.
- **iOS 17+**, watchOS 10+, arm64, iPhone only.

### Cloud sync

Optional, off by default, and **local-first** — the app is fully functional with
it disabled. Backed by Supabase (EU region) with an **anonymous identity**: no
account, no email, a token in the device Keychain.

Every row carries `user_id` and every table has row-level security comparing it
to `auth.uid()` from the caller's own verified JWT, so the publishable key
embedded in the binary grants nothing on its own. Merge is last-writer-wins per
field with FSRS history replay, and deletions propagate as tombstones.

Schema and policies live in [`supabase/migrations/`](supabase/migrations/).

---

## Build

No secrets are needed to build or test.

```bash
# iOS app (no signing)
xcodebuild build -project Ikeru.xcodeproj -scheme Ikeru \
  -destination "generic/platform=iOS" \
  -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO

# Core package tests
cd IkeruCore && swift test --no-parallel
```

Schemes: `Ikeru`, `IkeruWatch`, `IkeruWidget`.

Two traps worth knowing before you run the tests:

- **`--no-parallel` is required** for the SwiftData suites.
- **`LegacyStoreMigrationTests` must run in its own process.** Opening a
  container with the frozen V1 snapshots poisons CoreData's process-global
  entity↔class cache for `RPGState`; every later V2 fetch in that process can
  materialise the wrong class. Neither `.serialized` nor `--no-parallel` is
  enough — the poisoning outlives the suite.

  ```bash
  cd IkeruCore && swift test --no-parallel --filter "LegacyStoreMigration"
  ```

Branch flow is two-stage: feature branches open a PR against `dev`, which CI
validates without deploying; `master` is release-only, and every push to it
spends a TestFlight build.

The wider conventions, the engineering log and the gap register are working
documents kept outside this repository — they are notes to ourselves, not part
of the app.

---

## Content and licences

| Source | Licence | Used for |
|---|---|---|
| [KanjiVG](https://kanjivg.tagaini.net/) — Ulrich Apel | CC BY-SA 3.0 | stroke-order vector paths |
| [KANJIDIC](https://www.edrdg.org/) — EDRDG | CC BY-SA 4.0 | kanji readings and meanings |
| [Tatoeba](https://tatoeba.org/) contributors | CC BY 2.0 FR | example sentences |
| [VOICEVOX](https://voicevox.hiroshiba.jp/) — 四国めたん | VOICEVOX terms | bundled pronunciation audio |
| Noto Serif JP — Google Fonts | SIL OFL 1.1 | Japanese typeface |

Vocabulary, grammar notes and radical decompositions are written for Ikeru.

Provenance here is measured, not assumed. The kanji readings were once
documented as hand-authored; a diff against KANJIDIC showed all 63 dotted kun
readings byte-identical to its okurigana convention and the on-readings
reproducing its ordering in 89 of 90 kanji, so KANJIDIC is credited. The same
diff is why **RADKFILE is not** credited — only 36 of 90 radical decompositions
match it. Crediting a source you didn't use is the same error with the sign
flipped.

Per-row provenance for sentences is stored in the content bundle, so imported
and original sets stay distinguishable.

---

## Privacy

No analytics, no tracking, no ad SDKs. Learning data stays on the device unless
cloud backup is explicitly enabled. Account deletion removes every server row
via `ON DELETE CASCADE` from the auth user.

Full policy: <https://nicolasbataille.github.io/Ikeru/privacy.html>

---

## Status

Public beta on TestFlight, not yet on the App Store. The repository is public as
a portfolio — it is a real app under active development, not a finished
artefact, and there is a register of where it isn't done, kept honestly and kept
out of this repo.
