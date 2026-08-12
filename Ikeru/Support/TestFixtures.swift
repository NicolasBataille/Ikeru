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
/// level; avancé = high level and high mastered. `level` alone drives how
/// much of the 92-kana pool reads as mastered vs. learning vs. untouched
/// (`seedKana`); `dueCount`/`masteredCount` drive the kanji/vocabulary
/// overdue vs. comfortably-ahead split (`seedContentCards`). Roughly every
/// 4th due card gets a rougher trajectory so leeches — and the confusion
/// pairs `LeechDetectionService` derives from real fronts like 日/目 —
/// show up without every due card being one.
///
/// Launch-args usage (Debug builds):
/// ```bash
/// xcrun simctl launch booted com.ikeru.app \
///   -mockProfile -mockLevel=15 -mockDue=25 -mockMastered=120
/// ```
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

        logger.info("Seeding fixture profile: level=\(level) due=\(dueCount) mastered=\(masteredCount)")

        let profile = UserProfile(displayName: placeholderDisplayName)
        context.insert(profile)

        populate(
            context: context,
            profile: profile,
            level: level,
            dueCount: dueCount,
            masteredCount: masteredCount,
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
    @MainActor
    public static func wipeAndSeed(
        context: ModelContext,
        profileVM: ProfileViewModel,
        level: Int,
        dueCount: Int,
        masteredCount: Int
    ) {
        let now = Date()

        let profile: UserProfile
        if let existing = profileVM.currentProfile {
            profile = existing
            clearGeneratedState(context: context, profile: profile)
        } else {
            profile = UserProfile(displayName: placeholderDisplayName)
            context.insert(profile)
        }

        populate(
            context: context,
            profile: profile,
            level: level,
            dueCount: dueCount,
            masteredCount: masteredCount,
            now: now
        )

        do {
            try context.save()
        } catch {
            logger.error("wipeAndSeed save failed: \(error.localizedDescription)")
            return
        }

        profileVM.loadProfile()
        logger.info("wipeAndSeed: level=\(level) due=\(dueCount) mastered=\(masteredCount)")
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

    /// Seeds RPG state + kana + kanji/vocabulary cards for `profile`, all
    /// derived from a simulated review history (see the type-level doc).
    /// `totalReviewsCompleted` is set to the *actual* number of ReviewLog
    /// rows generated, not an arbitrary `level`-derived formula, so the RPG
    /// counters stay consistent with what the review-history simulation
    /// actually produced.
    @MainActor
    private static func populate(
        context: ModelContext,
        profile: UserProfile,
        level: Int,
        dueCount: Int,
        masteredCount: Int,
        now: Date
    ) {
        let state = seedRPGState(profile: profile, level: level)
        context.insert(state)

        var rng = SeededGenerator(seed: fixtureSeed(level: level, due: dueCount, mastered: masteredCount))
        var totalReviews = 0
        totalReviews += seedKana(context: context, profile: profile, level: level, now: now, rng: &rng)
        totalReviews += seedContentCards(
            context: context,
            profile: profile,
            due: dueCount,
            mastered: masteredCount,
            now: now,
            rng: &rng
        )
        state.totalReviewsCompleted = totalReviews
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

    @discardableResult
    private static func seedRPGState(
        profile: UserProfile,
        level: Int
    ) -> RPGState {
        let xpForLevel = xpRequired(forLevel: level)
        let xpForNext = xpRequired(forLevel: level + 1)
        let midXP = xpForLevel + (xpForNext - xpForLevel) / 2

        let state = RPGState(xp: midXP, level: level, totalReviewsCompleted: 0)
        state.totalSessionsCompleted = max(1, level / 2)

        // Attributes scaled to level
        let scaled = RPGAttribute.allPredefined.map { attr in
            guard attr.unlockLevel <= level else { return attr }
            let value = min(100, max(5, level * 5))
            return attr.withValue(value)
        }
        state.setAttributes(scaled)

        state.profile = profile
        profile.rpgState = state
        return state
    }

    /// Total XP required to reach `level`, using the *exact* production formula
    /// from RPGConstants so the seeded profile is internally consistent.
    private static func xpRequired(forLevel level: Int) -> Int {
        RPGConstants.totalXPForLevel(level)
    }

    // MARK: - Kana seeding

    /// Seeds all 92 base kana (idempotent with what
    /// `KanaCardRepository.seedIfNeeded()` would create), split into three
    /// bands driven by `level`:
    /// - the first `masteredCount` (curriculum order — vowels through W/N,
    ///   hiragana then katakana) get a long, mostly-successful review
    ///   history landing comfortably in the future ("mastered");
    /// - the next up-to-10 get a short, shakier history landing overdue
    ///   ("learning" / still in progress);
    /// - the remainder are left as freshly-seeded, never-reviewed cards
    ///   (`reps == 0`, due today) — exactly what a real first-time kana
    ///   seed produces.
    @MainActor
    private static func seedKana(
        context: ModelContext,
        profile: UserProfile,
        level: Int,
        now: Date,
        rng: inout SeededGenerator
    ) -> Int {
        let allKana = KanaGroup.allBaseCharacters
        let masteredCount = min(
            allKana.count,
            max(0, Int((Double(allKana.count) * Double(level) / 12.0).rounded()))
        )
        let learningCount = min(allKana.count - masteredCount, 10)

        var totalReviews = 0
        for (index, kana) in allKana.enumerated() {
            if index < masteredCount {
                totalReviews += makeCard(
                    front: kana.character,
                    back: kana.romaji,
                    type: .vocabulary,
                    jlptLevel: nil,
                    profile: profile,
                    context: context,
                    reviewCount: Int.random(in: 5...9, using: &rng),
                    failureRate: Double.random(in: 0.02...0.12, using: &rng),
                    desiredRetention: 0.9,
                    anchor: .upcoming(reviewedDaysAgo: 1.0...30.0),
                    now: now,
                    rng: &rng
                )
            } else if index < masteredCount + learningCount {
                totalReviews += makeCard(
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
        return totalReviews
    }

    // MARK: - Kanji / vocabulary seeding

    /// Seeds `due` cards with an overdue history and `mastered` cards with
    /// a comfortably-ahead history, cycling through `contentPool` (real N5
    /// kanji + vocabulary — see its doc comment). Roughly every 4th due
    /// card is given a rougher trajectory (higher failure rate, more
    /// reviews) so lapses cross `CardRepository.leechThreshold` and the
    /// card is flagged as a leech the same way production grading would —
    /// which in turn lets `LeechDetectionService.analyzeConfusion` surface
    /// real confusion pairs (e.g. 日/目) since the fronts are genuine kanji.
    @MainActor
    private static func seedContentCards(
        context: ModelContext,
        profile: UserProfile,
        due: Int,
        mastered: Int,
        now: Date,
        rng: inout SeededGenerator
    ) -> Int {
        guard !contentPool.isEmpty else { return 0 }
        let due = max(0, due)
        let mastered = max(0, mastered)

        var totalReviews = 0

        for i in 0..<due {
            let item = contentPool[i % contentPool.count]
            let isStrugglingTrajectory = i % 4 == 3
            totalReviews += makeCard(
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
        }

        for i in 0..<mastered {
            // Offset by `due` so the mastered bucket starts further along
            // the pool rotation — less exact overlap with the due bucket's
            // picks when both are small.
            let item = contentPool[(i + due) % contentPool.count]
            totalReviews += makeCard(
                front: item.front,
                back: item.back,
                type: item.type,
                jlptLevel: .n5,
                profile: profile,
                context: context,
                reviewCount: Int.random(in: 5...9, using: &rng),
                failureRate: Double.random(in: 0.02...0.1, using: &rng),
                desiredRetention: 0.9,
                anchor: .upcoming(reviewedDaysAgo: 1.0...45.0),
                now: now,
                rng: &rng
            )
        }

        return totalReviews
    }

    // MARK: - Card + history construction

    /// Creates a `Card` whose `fsrsState`, `dueDate`, `lapseCount` and
    /// `leechFlag` are every one derived from a simulated review history
    /// (see `simulateHistory`), and inserts a real `ReviewLog` per
    /// simulated event. Returns the number of review events created.
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
    ) -> Int {
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
        }

        return history.logs.count
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
