#if IKERU_DEV_TOOLS
import Foundation
import SwiftData
import IkeruCore
import os

/// Dev-only fixture seeder that builds a deterministic profile from launch
/// arguments or from the "Outils développeur" menu in Réglages.
///
/// ## Design: simulate HISTORY, not state
///
/// Every card starts from a blank `FSRSState()` and is walked forward
/// through a plausible sequence of past, dated `ReviewLog`s — *replayed
/// through the real `FSRSService.schedule`* — instead of having
/// `stability`/`reps`/`lapses` poked in by hand. The resulting state is
/// therefore something the production scheduler could actually have
/// produced: `dueDate` always agrees with `fsrsState.stability`,
/// `MasteryLevel.from(fsrsState:)` always agrees with "due" vs.
/// "mastered", and leeches / confusion hints
/// (`LeechDetectionService.analyzeConfusion`) emerge on their own from a
/// nonzero failure rate rather than a hardcoded flag. See
/// `simulateHistory` for the mechanics: replay a grade sequence on a
/// nominal timeline first (to learn the resulting stability), then replay
/// the *same* sequence again on real calendar dates shifted so the due
/// date lands where the requested bucket needs it (overdue vs. comfortably
/// ahead).
///
/// ## Content
///
/// - **Kana**: the real 92 base characters (`KanaGroup.allBaseCharacters`),
///   never fabricated glyphs. All 92 are always seeded (idempotent with
///   what `KanaCardRepository.seedIfNeeded()` would create) so the "かな
///   X/92" counter and group percentages are never stuck at zero.
/// - **Kanji / vocabulary**: a small hand-picked set of genuine N5 words
///   and kanji (`kanjiPool` / `vocabPool` below), cross-checked against
///   `JLPTBackfillService`'s N5 list — see that pool's doc comment for why
///   this is a manual subset rather than a programmatic pull from the
///   bundle.
///
/// ## What the sliders roughly mean
///
/// The dev-tools UI (`SettingsView`) still exposes three sliders —
/// `level` (1–30), `dueCount` (0–50), `masteredCount` (0–200) — since
/// changing that UI is outside this file's perimeter. Roughly:
/// débutant = low level / low due / low mastered; kana en cours = mid
/// level with a modest due backlog; backlog = high due regardless of
/// level; avancé = high level and high mastered. `level` drives how much of
/// the 92-kana pool reads as mastered vs. learning vs. untouched
/// (`seedKana`) — from nothing mastered at `level == 1` up to only the
/// fixed 10-card learning band left unmastered at `level == 30`, so neither
/// end of the range saturates or under-shoots the persona it's supposed to
/// produce. `dueCount`/`masteredCount` drive the kanji/vocabulary overdue
/// vs. comfortably-ahead split (`seedContentCards`), capped in combination
/// to `contentPool.count` (40 real N5 items) so no word is ever seeded
/// twice. Roughly every 4th due card gets a rougher trajectory so leeches —
/// and the confusion pairs `LeechDetectionService` derives from real fronts
/// like 日/目 — show up without every due card being one.
///
/// The RPG state's `xp`/`level` are *not* the slider `level` restated —
/// they're derived from the sum of `RPGConstants.xpForGrade` over every
/// simulated `ReviewLog` this run actually produced, run through
/// `RPGConstants.levelForXP` (see `seedRPGState`), so a fixture profile's
/// displayed level always agrees with its logged review history. The
/// slider `level` only steers how much *content* gets simulated; the
/// resulting displayed level is a consequence of that, not a mirror of it.
///
/// Launch-args usage (Debug builds):
/// ```bash
/// xcrun simctl launch booted com.ikeru.app \
///   -mockProfile -mockLevel=15 -mockDue=25 -mockMastered=120
///
/// # ...or the one shape the sliders cannot express — nothing due at all:
/// xcrun simctl launch booted com.ikeru.app -mockProfile -mockNothingDue
/// ```
///
/// `-mockNothingDue` overrides the due bands entirely; see `populate`.
///
/// In-app usage (Debug + TestFlight): the `Outils développeur` section in
/// Réglages exposes the same controls (`wipeAndSeed`, `wipeAll`,
/// `grantLevelUp`).
///
/// ## Reseeding preserves identity
///
/// `wipeAndSeed` reuses the existing `UserProfile` row in place (same
/// `id`, same `displayName`) instead of deleting + recreating it with a
/// hardcoded name. That means: the typed display name is never clobbered;
/// per-profile UserDefaults keys (`OnboardingFlags`, the active-profile
/// pointer) stay keyed on the same `UserProfile.id`, so already-dismissed
/// tutorials stay dismissed; and `VocabularyEntry`/`VocabularyEncounter`
/// (the personal dictionary) are never touched by a reseed — only the
/// fixture-generated `Card`/`ReviewLog`/`RPGState`/chat/exercise-outcome
/// rows are cleared and regenerated.
///
/// The whole file is gated behind `#if IKERU_DEV_TOOLS` so the App Store
/// build, which strips the flag, cannot ship fixture code. See CLAUDE.md
/// "Removing IKERU_DEV_TOOLS" for the App Store cleanup procedure.
public enum TestFixtures {

    private static let logger = Logger(subsystem: "com.ikeru.app", category: "TestFixtures")

    /// Neutral placeholder used only when there is no existing profile (and
    /// therefore no typed display name) to preserve — i.e. the very first
    /// `-mockProfile` cold launch, or `wipeAndSeed` called with no profile
    /// yet on disk.
    private static let placeholderDisplayName = "Testeur"

    // MARK: - Entry points

    /// Seeds a fixture profile if `-mockProfile` is present and no profile exists yet.
    /// Returns `true` if a profile was created.
    @MainActor
    @discardableResult
    public static func seedIfRequested(
        context: ModelContext,
        profileVM: ProfileViewModel
    ) -> Bool {
        guard AppEnvironment.hasFlag("mockProfile") else { return false }
        guard !profileVM.hasProfile else {
            logger.info("Skipping fixture seed — profile already exists")
            return false
        }

        let level = AppEnvironment.intArg("mockLevel") ?? 5
        let dueCount = AppEnvironment.intArg("mockDue") ?? 12
        let masteredCount = AppEnvironment.intArg("mockMastered") ?? 40
        let nothingDue = AppEnvironment.hasFlag("mockNothingDue")

        logger.info(
            "Seeding fixture profile: level=\(level) due=\(dueCount) mastered=\(masteredCount) nothingDue=\(nothingDue)"
        )

        let profile = UserProfile(displayName: placeholderDisplayName)
        context.insert(profile)

        populate(
            context: context,
            profile: profile,
            level: level,
            dueCount: dueCount,
            masteredCount: masteredCount,
            nothingDue: nothingDue,
            now: Date()
        )

        do {
            try context.save()
        } catch {
            logger.error("Failed to save fixture profile: \(error.localizedDescription)")
            return false
        }

        profileVM.loadProfile()
        return true
    }

    /// Regenerates the fixture content for the *current* profile (or
    /// creates one if none exists), preserving its identity — see the
    /// type-level "Reseeding preserves identity" doc above.
    ///
    /// `nothingDue` is the same switch `-mockNothingDue` flips on the launch
    /// path — see `populate`. Exposed as a parameter (rather than read from
    /// `CommandLine` inside) so a unit test can assert on the resulting card
    /// pool without launching the app; see `TestFixturesNothingDueTests`.
    @MainActor
    /// Renvoie ce qui a été RÉELLEMENT semé (OBS2-033), ou `nil` si la
    /// sauvegarde a échoué. Les curseurs sont des consignes que le pool de
    /// contenu plafonne, et le niveau RPG n'est pas réglable — l'appelant doit
    /// donc afficher ce retour, pas ses propres valeurs d'entrée.
    @discardableResult
    public static func wipeAndSeed(
        context: ModelContext,
        profileVM: ProfileViewModel,
        level: Int,
        dueCount: Int,
        masteredCount: Int,
        nothingDue: Bool = false
    ) -> SeedSummary? {
        let now = Date()

        let profile: UserProfile
        if let existing = profileVM.currentProfile {
            profile = existing
            clearGeneratedState(context: context, profile: profile)
        } else {
            profile = UserProfile(displayName: placeholderDisplayName)
            context.insert(profile)
        }

        let summary = populate(
            context: context,
            profile: profile,
            level: level,
            dueCount: dueCount,
            masteredCount: masteredCount,
            nothingDue: nothingDue,
            now: now
        )

        do {
            try context.save()
        } catch {
            logger.error("wipeAndSeed save failed: \(error.localizedDescription)")
            return nil
        }

        profileVM.loadProfile()
        logger.info(
            """
            wipeAndSeed: demandé level=\(level) due=\(dueCount) mastered=\(masteredCount) \
            nothingDue=\(nothingDue) — obtenu due=\(summary.contentDue) \
            mastered=\(summary.contentMastered) rpgLevel=\(summary.rpgLevel)
            """
        )
        return summary
    }

    /// Deletes every UserProfile + RPGState + Card so the next launch returns
    /// to the onboarding screen. Mirrors what `-uninstall` would do without
    /// removing the build itself.
    ///
    /// Unlike `wipeAndSeed`, this is meant to be total — it is the "Wipe
    /// profile" destructive action, not a reseed — so it does clear the
    /// personal vocabulary dictionary too.
    @MainActor
    public static func wipeAll(context: ModelContext, profileVM: ProfileViewModel) {
        let entities: [any PersistentModel.Type] = [
            UserProfile.self,
            RPGState.self,
            Card.self,
            ReviewLog.self,
            CompanionChatMessage.self,
            VocabularyEncounter.self,
            VocabularyEntry.self,
            ExerciseOutcomeLog.self,
            // Added 2026-08-19 with « Apporte ton propre texte ». Omitting it
            // made "Wipe profile" a lie in the one place it matters most: the
            // learner's own pasted/photographed prose survived a total wipe
            // and reappeared in the reading journal on the next launch.
            TextImport.self,
        ]
        for entity in entities {
            do {
                try context.delete(model: entity)
            } catch {
                logger.error("wipeAll delete \(String(describing: entity)) failed: \(error.localizedDescription)")
            }
        }
        do {
            try context.save()
        } catch {
            logger.error("wipeAll save failed: \(error.localizedDescription)")
        }
        UserDefaults.standard.removeObject(forKey: ActiveProfileResolver.activeProfileIDKey)
        profileVM.loadProfile()
        logger.info("wipeAll: cleared all persisted state")
    }

    /// Bumps the active profile's XP past the next-level threshold so the Home
    /// banner / RPG screen can render the level-up state on the next refresh.
    @MainActor
    public static func grantLevelUp(context: ModelContext) {
        guard let state = ActiveProfileResolver.fetchActiveRPGState(in: context) else {
            logger.warning("grantLevelUp skipped — no active profile")
            return
        }
        let nextLevelXP = xpRequired(forLevel: state.level + 1)
        state.xp = nextLevelXP + 1
        do {
            try context.save()
            logger.info("grantLevelUp: xp set to \(state.xp), expecting level \(state.level + 1)")
        } catch {
            logger.error("grantLevelUp save failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Shared population core

    /// Seeds kana + kanji/vocabulary cards for `profile` from a simulated
    /// review history (see the type-level doc), then derives the RPG state
    /// — `xp`, `level`, `totalReviewsCompleted` — from what that simulation
    /// actually produced, instead of setting them by hand from `level`
    /// alone. This is the step that closes the loop: every `ReviewLog` row
    /// generated below contributes its real `RPGConstants.xpForGrade` to
    /// the total, and the resulting level comes from
    /// `RPGConstants.levelForXP` on that total — so a fixture profile's
    /// level is never numerically incoherent with the log history that
    /// backs it. The requested `level` still drives *content generation*
    /// (how many kana/content cards land in the mastered vs. learning vs.
    /// fresh bands) — it just no longer double as the RPG state's `level`
    /// directly.
    ///
    /// ## `nothingDue`
    ///
    /// Seeds the one profile shape no other combination of sliders can
    /// express: a learner who has **nothing left to review right now**.
    ///
    /// It needs its own switch because `dueCount` does not reach far enough.
    /// Measured 2026-08-16: `-mockDue=0` governs only `seedContentCards`,
    /// while `seedKana` seeds its own 92 characters on trajectories derived
    /// from `level` — a fixed 10-card overdue "learning" band at every level,
    /// plus never-reviewed cards (`dueDate == now`, i.e. due) for whatever the
    /// mastered band doesn't cover. Either band alone makes something due, so
    /// no `(level, due, mastered)` triple produces a quiet queue.
    ///
    /// Rather than post-processing `dueDate` — which would break this file's
    /// central invariant that every card's state is what a real replay
    /// produced — `nothingDue` routes *every* card through the existing
    /// `.upcoming` anchor: all 92 kana get the mastered trajectory (no
    /// learning band, no fresh cards) and the content pool contributes only
    /// its comfortably-ahead half (`due` forced to 0). "Everything begun,
    /// everything scheduled ahead" is a state the production scheduler
    /// genuinely produces, so `dueDate` still agrees with `fsrsState`.
    ///
    /// Consequence worth knowing before writing a test against it: with no
    /// `reps == 0` card left, `DefaultSessionPlanner.caughtUpAvailability`
    /// offers **deepen** and not **discover** — the two are mutually
    /// exclusive here, because a never-reviewed card is itself due.
    @MainActor
    private static func populate(
        context: ModelContext,
        profile: UserProfile,
        level: Int,
        dueCount: Int,
        masteredCount: Int,
        nothingDue: Bool,
        now: Date
    ) -> SeedSummary {
        var rng = SeededGenerator(seed: fixtureSeed(level: level, due: dueCount, mastered: masteredCount))

        let kanaTally = seedKana(
            context: context,
            profile: profile,
            level: level,
            nothingDue: nothingDue,
            now: now,
            rng: &rng
        )
        let contentTally = seedContentCards(
            context: context,
            profile: profile,
            due: nothingDue ? 0 : dueCount,
            mastered: masteredCount,
            nothingDue: nothingDue,
            now: now,
            rng: &rng
        )

        let totalReviews = kanaTally.reviewCount + contentTally.reviewCount
        let totalXP = kanaTally.xp + contentTally.xp

        let state = seedRPGState(profile: profile, xp: totalXP, totalReviews: totalReviews)
        context.insert(state)

        return SeedSummary(
            contentDue: contentTally.seededDue,
            contentMastered: contentTally.seededMastered,
            rpgLevel: state.level
        )
    }

    /// Ce que le semis a RÉELLEMENT produit, par opposition à ce qu'on lui a
    /// demandé (OBS2-033). Les trois curseurs sont des consignes, pas des
    /// résultats : le pool de contenu plafonne « dû » + « maîtrisé » à ses 40
    /// entrées, et le niveau RPG n'est pas réglable du tout — il se déduit de
    /// l'XP accumulée par l'historique simulé (`RPGConstants.levelForXP`).
    /// Rapporter la consigne à la place du résultat, c'est ce qui faisait
    /// annoncer « 120 mastered » à un semis qui en avait créé 20.
    public struct SeedSummary: Sendable {
        public let contentDue: Int
        public let contentMastered: Int
        public let rpgLevel: Int
    }

    /// Clears everything a reseed regenerates for `profile` — its cards
    /// (cascades to their review logs), its RPG state, its companion chat
    /// history, and its exercise-outcome logs — while explicitly leaving
    /// alone: the `UserProfile` row itself (same id, same display name) and
    /// `VocabularyEntry` / `VocabularyEncounter` (the personal dictionary,
    /// which has no per-profile scoping and must never be nuked by a dev
    /// "reseed" action).
    @MainActor
    private static func clearGeneratedState(context: ModelContext, profile: UserProfile) {
        // Named distinctly from the model properties it's compared against
        // below (`profile?.id`, `.profileId`, `.profileID`) — matches the
        // cautious naming `ProfileViewModel.deleteProfile` already uses for
        // the same `ExerciseOutcomeLog` predicate (`deletedID`), rather than
        // shadowing a property name inside a `#Predicate` closure.
        let targetProfileID = profile.id

        let cardDescriptor = FetchDescriptor<Card>(
            predicate: #Predicate<Card> { $0.profile?.id == targetProfileID }
        )
        if let cards = try? context.fetch(cardDescriptor) {
            for card in cards { context.delete(card) } // cascades ReviewLog rows
        }

        if let rpgState = profile.rpgState {
            context.delete(rpgState)
            profile.rpgState = nil
        }

        let chatDescriptor = FetchDescriptor<CompanionChatMessage>(
            predicate: #Predicate<CompanionChatMessage> { $0.profileId == targetProfileID }
        )
        if let messages = try? context.fetch(chatDescriptor) {
            for message in messages { context.delete(message) }
        }

        let outcomeDescriptor = FetchDescriptor<ExerciseOutcomeLog>(
            predicate: #Predicate<ExerciseOutcomeLog> { $0.profileID == targetProfileID }
        )
        if let outcomes = try? context.fetch(outcomeDescriptor) {
            for outcome in outcomes { context.delete(outcome) }
        }
    }

    // MARK: - RPG seeding

    /// Builds the RPG state from `xp`/`totalReviews` actually produced by
    /// the simulated review history — `level` is `RPGConstants.levelForXP(xp)`,
    /// never a value handed in separately, so it can't drift out of sync
    /// with the XP total that backs it.
    @discardableResult
    private static func seedRPGState(
        profile: UserProfile,
        xp: Int,
        totalReviews: Int
    ) -> RPGState {
        let level = RPGConstants.levelForXP(xp)

        // Reuse the state the profile already owns when there is one.
        // `UserProfile.init` always mints an `RPGState`, and displacing a
        // SAVED one by assigning the owning side (`state.profile = profile`)
        // traps the process in `SwiftData/BackingData.swift:940` — measured
        // 2026-08-16, see the GAP-10 regression test in
        // `IkeruTests/HomeViewModelTests.swift`. `clearGeneratedState` happens
        // to nil the relationship out before every current call, so this code
        // never trapped in practice; reusing the existing object removes the
        // dependency on that ordering instead of leaving a live crash one
        // refactor away, in a screen that ships to TestFlight testers.
        let state = profile.rpgState ?? RPGState()
        state.xp = xp
        state.level = level
        state.totalReviewsCompleted = totalReviews
        // No per-session log is simulated, only per-review ones, so this is
        // a rough estimate (real sessions mix kana + content and run
        // roughly this many reviews) rather than an exact count — good
        // enough to keep the counter in the right ballpark for a value
        // nothing in the UI treats as precise.
        state.totalSessionsCompleted = max(1, totalReviews / averageReviewsPerSession)

        // Attributes scaled to level
        let scaled = RPGAttribute.allPredefined.map { attr in
            guard attr.unlockLevel <= level else { return attr }
            let value = min(100, max(5, level * 5))
            return attr.withValue(value)
        }
        state.setAttributes(scaled)

        // Inverse side only. Never `state.profile = profile` — see above.
        profile.rpgState = state
        return state
    }

    /// Total XP required to reach `level`, using the *exact* production formula
    /// from RPGConstants so the seeded profile is internally consistent.
    /// Only used by `grantLevelUp`, which bumps an *existing* profile past
    /// its next threshold — the fixture seeder itself derives `level` from
    /// simulated XP instead (`seedRPGState`).
    private static func xpRequired(forLevel level: Int) -> Int {
        RPGConstants.totalXPForLevel(level)
    }

    /// Rough average reviews-per-session used only to give
    /// `totalSessionsCompleted` a plausible order of magnitude from the
    /// total simulated review count — no per-session boundary is actually
    /// simulated (see `simulateHistory`).
    private static let averageReviewsPerSession = 15

    // MARK: - Kana seeding

    /// Seeds all 92 base kana (idempotent with what
    /// `KanaCardRepository.seedIfNeeded()` would create), split into three
    /// bands driven by `level` (1–30):
    /// - the first `masteredCount` (curriculum order — vowels through W/N,
    ///   hiragana then katakana) get a long, mostly-successful review
    ///   history landing comfortably in the future ("mastered");
    /// - a fixed band of 10 more get a short, shakier history landing
    ///   overdue ("learning" / still in progress) — kept at exactly 10
    ///   across the whole level range (not just while there happens to be
    ///   room) so the "kana en cours" persona stays reachable at every
    ///   level, not just below some cutoff;
    /// - the remainder are left as freshly-seeded, never-reviewed cards
    ///   (`reps == 0`, due today) — exactly what a real first-time kana
    ///   seed produces.
    ///
    /// `masteredCount` scales from 0 at `level == 1` (a true "débutant" —
    /// nothing mastered yet) up to `allKana.count - 10` at `level == 30`
    /// (leaving the fixed learning band as the only non-mastered cards) —
    /// so the かな counter never saturates to 92/92 before the top of the
    /// level range, and a level-1 profile never reads as having already
    /// anchored kana.
    ///
    /// `nothingDue` collapses the three bands into the first one: all 92 kana
    /// take the mastered trajectory, so neither the overdue learning band nor
    /// the never-reviewed remainder can put a card in today's queue. See
    /// `populate`'s doc for why that switch exists at all — `level` alone
    /// cannot express it, because the learning band is fixed at 10 across the
    /// whole range on purpose.
    @MainActor
    private static func seedKana(
        context: ModelContext,
        profile: UserProfile,
        level: Int,
        nothingDue: Bool,
        now: Date,
        rng: inout SeededGenerator
    ) -> (reviewCount: Int, xp: Int) {
        let allKana = KanaGroup.allBaseCharacters
        let learningBandSize = nothingDue ? 0 : min(10, allKana.count)
        let maxMastered = allKana.count - learningBandSize
        let levelFraction = Double(max(1, min(level, 30)) - 1) / 29.0
        let masteredCount = nothingDue
            ? allKana.count
            : min(maxMastered, max(0, Int((Double(maxMastered) * levelFraction).rounded())))
        let learningCount = min(allKana.count - masteredCount, learningBandSize)

        var totalReviews = 0
        var totalXP = 0
        for (index, kana) in allKana.enumerated() {
            if index < masteredCount {
                let tally = makeCard(
                    front: kana.character,
                    back: kana.romaji,
                    type: .vocabulary,
                    jlptLevel: nil,
                    profile: profile,
                    context: context,
                    reviewCount: Int.random(in: 5...9, using: &rng),
                    // A lapse on the FINAL review collapses stability, and
                    // `.upcoming` can only pull the last review back to its
                    // `max(1, interval/2)` floor — so a short enough interval
                    // lands the card back inside today despite the "comfortably
                    // ahead" intent. Harmless noise in an ordinary fixture; fatal
                    // to `nothingDue`, whose entire contract is an empty queue.
                    // A spotless history is what a caught-up learner's anchored
                    // kana look like anyway.
                    failureRate: nothingDue ? 0 : Double.random(in: 0.02...0.12, using: &rng),
                    desiredRetention: 0.9,
                    anchor: .upcoming(reviewedDaysAgo: 1.0...30.0),
                    now: now,
                    rng: &rng
                )
                totalReviews += tally.reviewCount
                totalXP += tally.xp
            } else if index < masteredCount + learningCount {
                let tally = makeCard(
                    front: kana.character,
                    back: kana.romaji,
                    type: .vocabulary,
                    jlptLevel: nil,
                    profile: profile,
                    context: context,
                    reviewCount: Int.random(in: 1...3, using: &rng),
                    failureRate: Double.random(in: 0.15...0.35, using: &rng),
                    desiredRetention: 0.9,
                    anchor: .overdue(byDays: 0.0...5.0),
                    now: now,
                    rng: &rng
                )
                totalReviews += tally.reviewCount
                totalXP += tally.xp
            } else {
                makeFreshCard(
                    front: kana.character,
                    back: kana.romaji,
                    type: .vocabulary,
                    profile: profile,
                    context: context,
                    now: now
                )
            }
        }
        return (totalReviews, totalXP)
    }

    // MARK: - Kanji / vocabulary seeding

    /// Seeds up to `due` cards with an overdue history and up to `mastered`
    /// cards with a comfortably-ahead history, drawn from `contentPool`
    /// (real N5 kanji + vocabulary — see its doc comment) *without*
    /// repetition: the due bucket takes the pool's first `cappedDue` items
    /// and the mastered bucket takes the next `cappedMastered`, so no front
    /// is ever seeded twice across the two buckets. Both counts are capped
    /// to `contentPool.count` (40 items) combined — at the slider maxima
    /// (`due` 50, `mastered` 200) this means fewer cards are actually
    /// created than requested, rather than cycling the pool with a modulo
    /// and minting several duplicate cards for the same word. Roughly every
    /// 4th due card is given a rougher trajectory (higher failure rate,
    /// more reviews) so lapses cross `CardRepository.leechThreshold` and
    /// the card is flagged as a leech the same way production grading
    /// would — which in turn lets `LeechDetectionService.analyzeConfusion`
    /// surface real confusion pairs (e.g. 日/目) since the fronts are
    /// genuine kanji.
    ///
    /// `nothingDue` never reaches the due bucket — `populate` already forces
    /// `due` to 0 for that mode. It is threaded in only to zero the mastered
    /// bucket's failure rate, for the reason spelled out on `seedKana`'s
    /// mastered branch: a lapse on the last review can schedule a
    /// "comfortably ahead" card back inside today.
    @MainActor
    private static func seedContentCards(
        context: ModelContext,
        profile: UserProfile,
        due: Int,
        mastered: Int,
        nothingDue: Bool,
        now: Date,
        rng: inout SeededGenerator
    ) -> (reviewCount: Int, xp: Int, seededDue: Int, seededMastered: Int) {
        guard !contentPool.isEmpty else { return (0, 0, 0, 0) }
        let cappedDue = min(max(0, due), contentPool.count)
        let cappedMastered = min(max(0, mastered), contentPool.count - cappedDue)

        var totalReviews = 0
        var totalXP = 0

        for i in 0..<cappedDue {
            let item = contentPool[i]
            let isStrugglingTrajectory = i % 4 == 3
            let tally = makeCard(
                front: item.front,
                back: item.back,
                type: item.type,
                jlptLevel: .n5,
                profile: profile,
                context: context,
                reviewCount: isStrugglingTrajectory
                    ? Int.random(in: 3...5, using: &rng)
                    : Int.random(in: 2...4, using: &rng),
                failureRate: isStrugglingTrajectory
                    ? Double.random(in: 0.45...0.65, using: &rng)
                    : Double.random(in: 0.1...0.25, using: &rng),
                desiredRetention: 0.9,
                anchor: .overdue(byDays: 1.0...21.0),
                now: now,
                rng: &rng
            )
            totalReviews += tally.reviewCount
            totalXP += tally.xp
        }

        for i in 0..<cappedMastered {
            // Offset by `cappedDue` so the mastered bucket picks up exactly
            // where the due bucket's slice of the pool left off — no index
            // is ever drawn by both buckets.
            let item = contentPool[cappedDue + i]
            let tally = makeCard(
                front: item.front,
                back: item.back,
                type: item.type,
                jlptLevel: .n5,
                profile: profile,
                context: context,
                reviewCount: Int.random(in: 5...9, using: &rng),
                // Zeroed under `nothingDue` — same reason as `seedKana`'s
                // mastered branch: a final-review lapse can pull a
                // "comfortably ahead" card back into today's queue.
                failureRate: nothingDue ? 0 : Double.random(in: 0.02...0.1, using: &rng),
                desiredRetention: 0.9,
                anchor: .upcoming(reviewedDaysAgo: 1.0...45.0),
                now: now,
                rng: &rng
            )
            totalReviews += tally.reviewCount
            totalXP += tally.xp
        }

        return (totalReviews, totalXP, cappedDue, cappedMastered)
    }

    // MARK: - Card + history construction

    /// Creates a `Card` whose `fsrsState`, `dueDate`, `lapseCount` and
    /// `leechFlag` are every one derived from a simulated review history
    /// (see `simulateHistory`), and inserts a real `ReviewLog` per
    /// simulated event. Returns the number of review events created and the
    /// XP those events are worth under `RPGConstants.xpForGrade` — the base
    /// per-grade amount the production `ExerciseXP.award` builds on for a
    /// completed review, before its type-specific bonus (e.g. +2 for
    /// `.kanjiStudy`), session bonuses, and JLPT multiplier. Those extras
    /// are deliberately not replayed here, so the seeded total is a slight
    /// floor under what a real learner's history would have earned — good
    /// enough to make the seeded `xp`/`level` internally consistent with
    /// the logged history, without reimplementing the full award pipeline.
    @MainActor
    @discardableResult
    private static func makeCard(
        front: String,
        back: String,
        type: CardType,
        jlptLevel: JLPTLevel?,
        profile: UserProfile,
        context: ModelContext,
        reviewCount: Int,
        failureRate: Double,
        desiredRetention: Double,
        anchor: HistoryAnchor,
        now: Date,
        rng: inout SeededGenerator
    ) -> (reviewCount: Int, xp: Int) {
        let history = simulateHistory(
            reviewCount: reviewCount,
            failureRate: failureRate,
            desiredRetention: desiredRetention,
            anchor: anchor,
            now: now,
            rng: &rng
        )
        let lastReview = history.state.lastReview ?? now
        let dueDate = FSRSService.dueDate(for: history.state, desiredRetention: desiredRetention, now: lastReview)
        let intervalDays = max(1, Int(dueDate.timeIntervalSince(lastReview) / 86_400))

        let card = Card(
            front: front,
            back: back,
            type: type,
            fsrsState: history.state,
            interval: intervalDays,
            dueDate: dueDate,
            lapseCount: history.state.lapses,
            leechFlag: history.state.lapses >= CardRepository.leechThreshold,
            jlptLevel: jlptLevel
        )
        card.profile = profile
        context.insert(card)

        var xp = 0
        for event in history.logs {
            let responseTimeMs = event.grade == .again
                ? Int.random(in: 3_000...9_000, using: &rng)
                : Int.random(in: 1_000...5_000, using: &rng)
            let log = ReviewLog(
                card: card,
                grade: event.grade,
                responseTimeMs: responseTimeMs,
                timestamp: event.date
            )
            context.insert(log)
            xp += RPGConstants.xpForGrade(event.grade)
        }

        return (history.logs.count, xp)
    }

    /// Creates a never-reviewed card (`reps == 0`, due today) — exactly
    /// what a real first-time seed produces for content the learner hasn't
    /// touched yet. No `ReviewLog` rows.
    @MainActor
    private static func makeFreshCard(
        front: String,
        back: String,
        type: CardType,
        profile: UserProfile,
        context: ModelContext,
        now: Date
    ) {
        let card = Card(front: front, back: back, type: type, dueDate: now)
        card.profile = profile
        context.insert(card)
    }

    // MARK: - FSRS history simulation

    /// Where a simulated review history's *last* event should land, in
    /// real calendar time, relative to `now`.
    private enum HistoryAnchor {
        /// The resulting due date must land in the past by at least this
        /// many extra days beyond the FSRS-recommended interval — i.e. a
        /// genuinely overdue card.
        case overdue(byDays: ClosedRange<Double>)
        /// The card was last reviewed this many days ago, capped well
        /// under the FSRS-recommended interval — i.e. a card that is
        /// scheduled comfortably ahead, not due yet.
        case upcoming(reviewedDaysAgo: ClosedRange<Double>)
    }

    private struct SimulatedReviewEvent {
        let grade: Grade
        let date: Date
    }

    private struct SimulatedHistory {
        let state: FSRSState
        let logs: [SimulatedReviewEvent]
    }

    /// Generates a plausible past review history and replays it through the
    /// *real* `FSRSService.schedule`, so the resulting state is never a
    /// hand-set stability/reps pair.
    ///
    /// Two passes, because `FSRSState.lastReview` can only be set by
    /// actually calling `schedule(now:)` with that timestamp — there's no
    /// mutating setter to relabel it after the fact:
    ///
    /// 1. **Nominal pass**: replay a randomly-sampled grade sequence
    ///    starting at an arbitrary epoch, spacing each subsequent review by
    ///    FSRS's own recommended interval (with jitter). This tells us the
    ///    resulting stability/interval without committing to real dates yet.
    /// 2. **Anchor + real pass**: given `anchor`, compute what the *real*
    ///    calendar date of the last event should be (past for `.overdue`,
    ///    future-leaning for `.upcoming`), derive a constant day-shift from
    ///    the nominal timeline to that date, and replay the *same* grade
    ///    sequence with every date shifted by that constant. A pure
    ///    translation preserves every elapsed-day delta `schedule` computed
    ///    in pass 1, so the final state is numerically identical to pass 1
    ///    — just dated for real.
    private static func simulateHistory(
        reviewCount: Int,
        failureRate: Double,
        desiredRetention: Double,
        anchor: HistoryAnchor,
        now: Date,
        rng: inout SeededGenerator
    ) -> SimulatedHistory {
        let count = max(1, reviewCount)
        let epoch = Date(timeIntervalSince1970: 0)

        // Pass 1 — nominal timeline.
        var grades: [Grade] = []
        var nominalDates: [Date] = []
        var nominalState = FSRSState()
        var nominalDate = epoch
        for i in 0..<count {
            let grade = sampledGrade(failureRate: failureRate, rng: &rng)
            grades.append(grade)
            nominalDates.append(nominalDate)
            nominalState = FSRSService.schedule(state: nominalState, grade: grade, now: nominalDate)
            guard i < count - 1 else { break }
            let gap = idealIntervalDays(for: nominalState, desiredRetention: desiredRetention)
            let jitter = Double.random(in: 0.75...1.2, using: &rng)
            nominalDate = nominalDate.addingTimeInterval(max(1, gap * jitter) * 86_400)
        }

        // Anchor.
        let finalIntervalDays = idealIntervalDays(for: nominalState, desiredRetention: desiredRetention)
        let lastNominalDate = nominalDates.last ?? epoch
        let realLastReviewDate: Date
        switch anchor {
        case .overdue(let byDays):
            let overdueBy = Double.random(in: byDays, using: &rng)
            realLastReviewDate = now.addingTimeInterval(-(finalIntervalDays + overdueBy) * 86_400)
        case .upcoming(let reviewedDaysAgo):
            let cappedDaysAgo = min(Double.random(in: reviewedDaysAgo, using: &rng), max(1, finalIntervalDays * 0.5))
            realLastReviewDate = now.addingTimeInterval(-cappedDaysAgo * 86_400)
        }
        let shift = realLastReviewDate.timeIntervalSince(lastNominalDate)

        // Pass 2 — real timeline (same grade sequence, shifted dates).
        var state = FSRSState()
        var logs: [SimulatedReviewEvent] = []
        for (grade, nominal) in zip(grades, nominalDates) {
            let real = nominal.addingTimeInterval(shift)
            state = FSRSService.schedule(state: state, grade: grade, now: real)
            logs.append(SimulatedReviewEvent(grade: grade, date: real))
        }

        return SimulatedHistory(state: state, logs: logs)
    }

    /// The FSRS-recommended interval (in days) for `state`, independent of
    /// any particular reference date — `FSRSService.dueDate` always
    /// returns `now + interval`, so subtracting `now` back out isolates
    /// the interval regardless of which placeholder `now` is passed in.
    private static func idealIntervalDays(for state: FSRSState, desiredRetention: Double) -> Double {
        let reference = Date(timeIntervalSince1970: 0)
        return FSRSService.dueDate(for: state, desiredRetention: desiredRetention, now: reference)
            .timeIntervalSince(reference) / 86_400
    }

    /// Samples a `Grade` for one simulated review: `.again` with
    /// probability `failureRate`, otherwise weighted toward `.good` (a
    /// rough approximation of a real learner's grade distribution).
    private static func sampledGrade(failureRate: Double, rng: inout SeededGenerator) -> Grade {
        let clampedFailureRate = min(0.9, max(0, failureRate))
        let roll = Double.random(in: 0..<1, using: &rng)
        if roll < clampedFailureRate { return .again }
        let remaining = (roll - clampedFailureRate) / (1 - clampedFailureRate)
        if remaining < 0.15 { return .hard }
        if remaining < 0.85 { return .good }
        return .easy
    }

    // MARK: - Deterministic RNG

    /// Seeded so a given (level, due, mastered) combination always
    /// produces the exact same fixture — reproducible across simulator
    /// resets and developer machines, per the task's "états nommés et
    /// reproductibles" goal.
    private struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) {
            self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
        }

        mutating func next() -> UInt64 {
            // xorshift64*
            state ^= state >> 12
            state ^= state << 25
            state ^= state >> 27
            return state &* 0x2545_F491_4F6C_DD1D
        }
    }

    private static func fixtureSeed(level: Int, due: Int, mastered: Int) -> UInt64 {
        fnv1aHash("ikeru.fixture.v1.\(level).\(due).\(mastered)")
    }

    private static func fnv1aHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash == 0 ? 1 : hash
    }

    // MARK: - Content pools

    /// A single real kanji or vocabulary entry used to seed content cards.
    private struct ContentItem {
        let front: String
        let back: String
        let type: CardType
    }

    /// Genuine N5 kanji + vocabulary, hand-picked and cross-checked
    /// character-for-character against `JLPTBackfillService`'s
    /// `N5SeedDictionary` (IkeruCore, `Services/Progress/JLPTBackfillService.swift`)
    /// — every `front` below appears verbatim in that list. That list
    /// itself is `private` (file-scoped, different module) and the only
    /// public way to reach real bundled content is
    /// `ContentRepository`/`ContentLoadingService`, which are fully async
    /// and actor-isolated. Routing through them would require making
    /// `seedIfRequested`/`wipeAndSeed` async, which would break every
    /// existing (synchronous) call site in `IkeruApp.swift` and
    /// `SettingsView.swift` — both outside this file. So: a small,
    /// manually-verified real subset here, not a programmatic extraction
    /// from the bundle. Readings are supplied from standard Japanese (not
    /// extracted from the bundle, which doesn't carry them in the private
    /// list either) — common, unambiguous words/kanji, but worth flagging
    /// as hand-typed rather than machine-checked.
    private static let kanjiPool: [ContentItem] = [
        ContentItem(front: "人", back: "ひと", type: .kanji),
        ContentItem(front: "日", back: "ひ", type: .kanji),
        ContentItem(front: "月", back: "つき", type: .kanji),
        ContentItem(front: "火", back: "ひ", type: .kanji),
        ContentItem(front: "水", back: "みず", type: .kanji),
        ContentItem(front: "木", back: "き", type: .kanji),
        ContentItem(front: "金", back: "きん", type: .kanji),
        ContentItem(front: "土", back: "つち", type: .kanji),
        ContentItem(front: "山", back: "やま", type: .kanji),
        ContentItem(front: "川", back: "かわ", type: .kanji),
        ContentItem(front: "口", back: "くち", type: .kanji),
        ContentItem(front: "目", back: "め", type: .kanji),
        ContentItem(front: "耳", back: "みみ", type: .kanji),
        ContentItem(front: "手", back: "て", type: .kanji),
        ContentItem(front: "足", back: "あし", type: .kanji),
        ContentItem(front: "心", back: "こころ", type: .kanji),
        ContentItem(front: "本", back: "ほん", type: .kanji),
        ContentItem(front: "車", back: "くるま", type: .kanji),
        ContentItem(front: "雨", back: "あめ", type: .kanji),
        ContentItem(front: "電", back: "でん", type: .kanji),
    ]

    private static let vocabPool: [ContentItem] = [
        ContentItem(front: "日本", back: "にほん", type: .vocabulary),
        ContentItem(front: "日本語", back: "にほんご", type: .vocabulary),
        ContentItem(front: "日本人", back: "にほんじん", type: .vocabulary),
        ContentItem(front: "学校", back: "がっこう", type: .vocabulary),
        ContentItem(front: "先生", back: "せんせい", type: .vocabulary),
        ContentItem(front: "友達", back: "ともだち", type: .vocabulary),
        ContentItem(front: "天気", back: "てんき", type: .vocabulary),
        ContentItem(front: "水曜日", back: "すいようび", type: .vocabulary),
        ContentItem(front: "自転車", back: "じてんしゃ", type: .vocabulary),
        ContentItem(front: "電話", back: "でんわ", type: .vocabulary),
        ContentItem(front: "新聞", back: "しんぶん", type: .vocabulary),
        ContentItem(front: "先週", back: "せんしゅう", type: .vocabulary),
        ContentItem(front: "今週", back: "こんしゅう", type: .vocabulary),
        ContentItem(front: "来週", back: "らいしゅう", type: .vocabulary),
        ContentItem(front: "大学", back: "だいがく", type: .vocabulary),
        ContentItem(front: "病院", back: "びょういん", type: .vocabulary),
        ContentItem(front: "銀行", back: "ぎんこう", type: .vocabulary),
        ContentItem(front: "映画", back: "えいが", type: .vocabulary),
        ContentItem(front: "音楽", back: "おんがく", type: .vocabulary),
        ContentItem(front: "勉強", back: "べんきょう", type: .vocabulary),
    ]

    private static let contentPool: [ContentItem] = kanjiPool + vocabPool
}
#endif
