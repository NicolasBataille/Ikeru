import Foundation
import os

/// Concrete `SessionPlanner`. Structurally deterministic from inputs;
/// content selection within each segment is randomised (`randomElement()`)
/// from the available card pool, so the *shape* of the plan is stable
/// per-day but specific exercise content varies. No I/O.
///
/// Home composition picks one of three stage profiles per session
/// (2026-08-13 device pass, review OBS "Planificateur"):
///   - **lancement** (`composeFoundation`) — while any chosen kana is still
///     unseen: due reviews + one curriculum row of new kana. Pre-existing;
///     unchanged by this pass. Reviews here are capped at 50 % of the
///     session budget (`totalSec / 2`), NOT an absolute priority like the
///     other two stages below — see the `- Note:` on `composeFoundation`.
///   - **construction** (`composeConstruction`) — the 40/30/20/10 segment
///     skeleton (skill-balance booster / variety tile / new-content drip),
///     now with due reviews as an ABSOLUTE priority: `pickReviews` is given
///     the *entire* session budget, not a 40 % slice, and the 30/20/10
///     quotas are applied to whatever budget is left over once dues are
///     scheduled (see `composeConstruction`). A backlog that exceeds the
///     session budget consumes all of it — the session is honestly "mostly
///     review" rather than silently deferring the backlog. (Previously
///     `reviewBudget = totalSec * 0.40` was a hard ceiling with no
///     overflow logic — 24 due cards in a 5-minute budget served ~2
///     minutes of review and pushed the rest to tomorrow, compounding.)
///   - **croisière** (`composeCruising`) — once most of the started deck is
///     FSRS-mature (`isCruisingStage`): due reviews first, then a small
///     new-content trickle (reusing `homeNewContentFraction`), no
///     skill-balance booster or variety tile. See `isCruisingStage` for the
///     (assumed, unsourced) trigger heuristic.
/// In all three profiles, segments are built independently (each keeps its
/// own internal order — e.g. review stays most-overdue-first) and merged
/// via a single deterministic interleave (`interleave(streams:)`), so a
/// session reads as a mix of kinds rather than contiguous blocks.
///
/// Review-item duration budgeting is also modulated by card maturity
/// (`reviewDurationSeconds`): a `.srsReview` on a well-established
/// (high-stability) card is budgeted for less time than one still being
/// learned, because a mature card really is answered faster. Every other
/// exercise kind keeps its flat `ExerciseItem.estimatedDurationSeconds`.
///
/// Étude/Study composition is round-robin across the user's selected
/// types, intersected with the unlocked set, ordered by pedagogical
/// receptive→productive. It does not go through `pickReviews`, so review
/// duration modulation does not apply there.
public struct DefaultSessionPlanner: SessionPlanner {

    /// Interleave weight for the review stream, and (in `composeConstruction`)
    /// the nominal ceiling `pickReviews` would otherwise cap the review wave
    /// at — but `composeConstruction` now calls `pickReviews` with the
    /// *entire* remaining session budget instead of `totalSec * 0.40`, so
    /// this constant no longer bounds how much time reviews can actually
    /// consume. Kept for the interleave-scheduling ratio.
    public static let homeReviewFraction: Double = 0.40
    /// Target share of TOTAL session time for the skill-balance booster in
    /// `composeConstruction` — applied to whatever budget remains after due
    /// reviews are scheduled (`min(totalSec * fraction, remainingSec)`), not
    /// to the full session unconditionally.
    public static let homeSkillBalanceBoosterFraction: Double = 0.30
    /// Target share of TOTAL session time for the variety tile in
    /// `composeConstruction` — same remainder-capped treatment as the
    /// skill-balance booster above.
    public static let homeVarietyTileFraction: Double = 0.20
    /// Target share of TOTAL session time for the new-content drip in
    /// `composeConstruction` (remainder-capped, see above) — and also the
    /// fraction `composeCruising` reuses for its own new-content trickle.
    public static let homeNewContentFraction: Double = 0.10

    /// Cruising-stage trigger — see `isCruisingStage`. ASSUMED heuristic
    /// (like the 40/30/20/10 split itself): the review that recommended a
    /// "croisière" profile gave no numeric trigger condition, so this
    /// threshold — the fraction of started cards that must be
    /// `.mastered`/`.anchored` — is an implementation choice, not a sourced
    /// figure. Revisit if it fires too early/late against real usage.
    public static let cruisingMasteryThreshold: Double = 0.6
    /// Minimum number of started (`reps > 0`) cards before cruising can
    /// trigger at all — guards against a handful of quickly-mastered kana,
    /// right after foundation mode ends, flipping the whole session into
    /// cruising while the rest of the deck (vocab, kanji) is still `.new`.
    public static let cruisingMinStartedCards: Int = 20

    /// New kana introduced per foundation session — one gojūon row.
    public static let foundationRowSize = 5

    /// Exercise types whose content the app never TEACHES anywhere yet: they
    /// quiz raw N5 content-DB entries (words, sentences) with no connection to
    /// what the learner has actually met — guessing, not learning. Excluded
    /// from the HOME booster/variety pools until the vocab-dictionary feature
    /// provides a real "already encountered" source (owner decision,
    /// 2026-07-19 device pass). Étude custom sessions keep every type — there
    /// the learner opts in explicitly.
    public static let untaughtContentTypes: Set<ExerciseType> = [
        .listeningSubtitled, .listeningUnsubtitled,
        .speakingPractice, .sakuraConversation,
        .vocabularyStudy, .sentenceConstruction
    ]

    public init() {}

    public func compose(inputs: SessionPlannerInputs) async -> SessionPlan {
        let plan: SessionPlan
        switch inputs.source {
        case .homeRecommendation:
            plan = composeHome(inputs: inputs)
        case .studyCustom(let types, let levels):
            plan = composeStudy(inputs: inputs, types: types, levels: levels)
        case .caughtUp(let offer):
            plan = composeCaughtUp(inputs: inputs, offer: offer)
        }
        Logger.learningLoop.info(
            "session.composed source=\(String(describing: inputs.source), privacy: .public) duration=\(inputs.durationMinutes)"
        )
        return plan
    }

    // MARK: - Caught up (nothing due)

    /// Maximum cards in a caught-up session, whichever offer was chosen.
    ///
    /// A learner here has *already* finished their reviews for the day. This
    /// is extra, opted-into work, so the cap is deliberately below a normal
    /// session's: the point is a satisfying short round, not a second
    /// full session that turns "caught up" into a treadmill. Ten is a
    /// judgement call, not a measurement — revisit against real usage.
    public static let caughtUpSessionCap = 10

    /// Composes the session a learner asked for when nothing was due.
    ///
    /// Returns an EMPTY plan when the chosen pool is empty (every card
    /// mastered and nothing left to discover). That is not a failure to
    /// paper over: `SessionComposer` turns an empty plan into `nil`, and the
    /// caller keeps showing the proposal instead of opening a blank session.
    /// The offer's availability is computed up front by
    /// `caughtUpAvailability(cards:)` so the UI never offers a button that
    /// cannot produce anything.
    private func composeCaughtUp(
        inputs: SessionPlannerInputs,
        offer: SessionPlannerInputs.CaughtUpOffer
    ) -> SessionPlan {
        let totalSec = inputs.durationMinutes * 60
        let exercises: [ExerciseItem]
        switch offer {
        case .deepen:
            exercises = composeDeepen(cards: inputs.availableCards, secondsBudget: totalSec)
        case .discover:
            exercises = composeDiscover(cards: inputs.availableCards, secondsBudget: totalSec)
        }
        return finalize(exercises: exercises)
    }

    /// "Approfondir": started cards that are NOT yet due, weakest first.
    ///
    /// Ordering is by ascending retrievability — the card closest to being
    /// forgotten comes first. Sorting by due date instead would surface the
    /// cards the scheduler is already most confident about, which is the
    /// opposite of "push further on what you know". Retrievability is the
    /// scheduler's own estimate, so this reuses the model rather than
    /// inventing a second notion of "weak".
    ///
    /// Cards already due are excluded on purpose: if any existed, the learner
    /// would not be on this screen, and including them would let a caught-up
    /// session silently become the normal one.
    private func composeDeepen(
        cards: [CardDTO],
        secondsBudget: Int,
        now: Date = Date()
    ) -> [ExerciseItem] {
        let started: [CardDTO] = cards.filter { $0.fsrsState.reps > 0 && $0.dueDate > now }
        var scored: [(card: CardDTO, retrievability: Double)] = []
        scored.reserveCapacity(started.count)
        for card in started {
            scored.append((card, FSRSService.retrievability(for: card.fsrsState, now: now)))
        }
        scored.sort { lhs, rhs in
            if lhs.retrievability != rhs.retrievability {
                return lhs.retrievability < rhs.retrievability
            }
            return lhs.card.front < rhs.card.front
        }

        return takeWithinBudget(scored.map(\.card), secondsBudget: secondsBudget)
    }

    /// "Découvrir": cards never reviewed, in curriculum order.
    ///
    /// Reuses `pickNewContent`'s ordering rule (kana curriculum first, then
    /// alphabetical) so discovery introduces content in the same sequence the
    /// normal drip would — a learner who discovers ahead is not put on a
    /// different track from one who waits.
    ///
    /// The "announced as new" half of the owner's decision is NOT implemented
    /// here: `NewCardPresentationScheduler` already inserts an ungraded
    /// presentation phase before every `reps == 0` card, and `SessionComposer`
    /// applies it to every plan. Reimplementing it here would give new cards
    /// two different introductions depending on how the session started.
    private func composeDiscover(cards: [CardDTO], secondsBudget: Int) -> [ExerciseItem] {
        let candidates = cards
            .filter { $0.fsrsState.reps == 0 }
            .sorted { lhs, rhs in
                let li = Self.kanaCurriculumIndex[lhs.front] ?? Int.max
                let ri = Self.kanaCurriculumIndex[rhs.front] ?? Int.max
                return li != ri ? li < ri : lhs.front < rhs.front
            }

        return takeWithinBudget(candidates, secondsBudget: secondsBudget)
    }

    /// Fills from an already-ordered list until the time budget or the
    /// caught-up cap runs out, whichever comes first.
    private func takeWithinBudget(_ ordered: [CardDTO], secondsBudget: Int) -> [ExerciseItem] {
        var items: [ExerciseItem] = []
        var spent = 0
        for card in ordered {
            if items.count >= Self.caughtUpSessionCap { break }
            let duration = Self.reviewDurationSeconds(for: card)
            if spent + duration > secondsBudget { break }
            items.append(.srsReview(card))
            spent += duration
        }
        return items
    }

    /// Which caught-up offers can actually produce a session, given the pool.
    ///
    /// Exposed so the Home proposal can hide an offer instead of showing a
    /// button that does nothing — a silent no-op on tap is the defect this
    /// whole change exists to remove, and it would be ironic to reintroduce
    /// it one layer up.
    public static func caughtUpAvailability(
        cards: [CardDTO],
        now: Date = Date()
    ) -> Set<SessionPlannerInputs.CaughtUpOffer> {
        var offers: Set<SessionPlannerInputs.CaughtUpOffer> = []
        if cards.contains(where: { $0.fsrsState.reps > 0 && $0.dueDate > now }) {
            offers.insert(.deepen)
        }
        if cards.contains(where: { $0.fsrsState.reps == 0 }) {
            offers.insert(.discover)
        }
        return offers
    }

    // MARK: - Home

    private func composeHome(inputs: SessionPlannerInputs) -> SessionPlan {
        let totalSec = inputs.durationMinutes * 60

        // Foundation mode (owner decision, 2026-07-19 device pass): while the
        // learner's chosen study set still contains kana they have never
        // begun, they are building the syllabary — and the 40/30/20/10 mix is
        // wrong twice over: the booster/variety pools schedule listening /
        // speaking / vocab-recall drills about words they've never met, and
        // the single-card drip would stretch 46 kana over 46 days. Until
        // every chosen kana is begun, the session is honest and compact: the
        // due reviews + one curriculum row of new kana. (A first cut gated
        // this on a begun-card count — it expired after two sessions with
        // half the chosen set still unseen; the unseen-kana predicate IS the
        // definition of the foundation phase.)
        let unseenKana = inputs.availableCards.filter { $0.fsrsState.reps == 0 && $0.isKana }
        if !unseenKana.isEmpty {
            return composeFoundation(inputs: inputs, unseenKana: unseenKana, totalSec: totalSec)
        }

        if isCruisingStage(cards: inputs.availableCards) {
            return composeCruising(inputs: inputs, totalSec: totalSec)
        }

        return composeConstruction(inputs: inputs, totalSec: totalSec)
    }

    /// "Construction" profile: the 40/30/20/10 segment skeleton, but due
    /// reviews are an ABSOLUTE priority, not a 40 %-capped slice.
    ///
    /// `pickReviews` is handed the full session budget (`totalSec`), so a
    /// backlog can consume the whole session if it has to — FSRS presupposes
    /// dues get processed, and a quota that silently defers them just moves
    /// the (growing) backlog to tomorrow. The skill-balance booster, variety
    /// tile, and new-content drip then split whatever budget is actually
    /// left, each capped at `min(totalSec * itsFraction, remainingSec)` —
    /// so on a light-backlog day the mix still reads close to the original
    /// 40/30/20/10, and on a heavy-backlog day it gracefully degrades toward
    /// "all review" (and the Home hero label already reads that honestly:
    /// `HomeViewModel.TodayKind` picks `.allReview` whenever the composed
    /// plan's new-card count is 0, which is exactly what happens here when
    /// there's no budget left for `pickNewContent`).
    private func composeConstruction(inputs: SessionPlannerInputs, totalSec: Int) -> SessionPlan {
        // Segment 1: Review wave — priority, uncapped by the 40 % nominal
        // share (see `homeReviewFraction`'s doc comment).
        let reviewItems = pickReviews(from: inputs.availableCards, secondsBudget: totalSec)
        let reviewSpent = reviewItems.reduce(0) { $0 + Self.effectiveDurationSeconds(for: $1) }
        var remainingSec = max(0, totalSec - reviewSpent)

        // Segment 2: Skill-balance booster — quota applies to what's LEFT.
        let skillBoosterBudget = min(Int(Double(totalSec) * Self.homeSkillBalanceBoosterFraction), remainingSec)
        let lowestSkill = lowestSkill(in: inputs.profile.skillBalances)
        let boosterPool = VarietyPoolResolver.effectivePool(
            for: inputs.profile.jlptLevel,
            unlockedTypes: inputs.unlockedTypes
        ).subtracting(Self.untaughtContentTypes)
        let boosterItems = fillSegment(
            forSkill: lowestSkill,
            inPool: boosterPool,
            secondsBudget: skillBoosterBudget,
            availableCards: inputs.availableCards
        )
        remainingSec = max(0, remainingSec - boosterItems.reduce(0) { $0 + Self.effectiveDurationSeconds(for: $1) })

        // Segment 3: Variety tile — different skill from booster, quota also
        // applies to what's left after review + booster.
        let varietyBudget = min(Int(Double(totalSec) * Self.homeVarietyTileFraction), remainingSec)
        let varietyPool = boosterPool.filter { $0.skill != lowestSkill }
        let varietyItems = fillRotating(
            inPool: varietyPool,
            secondsBudget: varietyBudget,
            day: dayOfYear(),
            availableCards: inputs.availableCards
        )
        remainingSec = max(0, remainingSec - varietyItems.reduce(0) { $0 + Self.effectiveDurationSeconds(for: $1) })

        // Segment 4: New content drip — whatever's left, capped at 10 % of
        // total. Zero when the backlog (or booster/variety) ate the budget —
        // the session is then honestly all-review, not silently short one
        // new card.
        let newContentBudget = min(Int(Double(totalSec) * Self.homeNewContentFraction), remainingSec)
        let newItems: [ExerciseItem] = pickNewContent(
            secondsBudget: newContentBudget,
            availableCards: inputs.availableCards
        ).map { [$0] } ?? []

        // Merge the four segment streams into one interleaved order,
        // proportional to their 40/30/20/10 weights, instead of four
        // contiguous blocks. Same exercise SET and per-segment counts as
        // before — only the cross-segment ORDER changes.
        let exercises = interleave(streams: [
            (items: reviewItems, weight: Self.homeReviewFraction),
            (items: boosterItems, weight: Self.homeSkillBalanceBoosterFraction),
            (items: varietyItems, weight: Self.homeVarietyTileFraction),
            (items: newItems, weight: Self.homeNewContentFraction)
        ])

        return finalize(exercises: exercises)
    }

    /// "Croisière" (cruising) profile: due reviews first (same absolute
    /// priority as `composeConstruction`), then a small new-content trickle
    /// with whatever budget remains — no skill-balance booster, no variety
    /// tile. Triggered by `isCruisingStage` once most of the started deck is
    /// FSRS-mature: at that point the learner is maintaining a deck they've
    /// largely learned, not actively building skill balance across
    /// exercise kinds, so forcing booster/variety content stops making
    /// sense — reviews plus a steady trickle of new material is enough.
    ///
    /// The ~10 % new-content share reuses `homeNewContentFraction`. NOTE ON
    /// HONESTY: a "new cards should be ~10 % of a mature deck's daily load"
    /// ratio is documented (e.g. by Anki) as an EMERGENT consequence of how
    /// a spaced-repetition scheduler behaves under steady-state review load
    /// — not a prescribed best practice — so this reuse is "a reasonable
    /// trickle we're borrowing the number for", not a citation.
    private func composeCruising(inputs: SessionPlannerInputs, totalSec: Int) -> SessionPlan {
        let reviewItems = pickReviews(from: inputs.availableCards, secondsBudget: totalSec)
        let reviewSpent = reviewItems.reduce(0) { $0 + Self.effectiveDurationSeconds(for: $1) }
        let remainingSec = max(0, totalSec - reviewSpent)

        let newContentBudget = min(Int(Double(totalSec) * Self.homeNewContentFraction), remainingSec)
        let newItems: [ExerciseItem] = pickNewContent(
            secondsBudget: newContentBudget,
            availableCards: inputs.availableCards
        ).map { [$0] } ?? []

        let exercises = interleave(streams: [
            (items: reviewItems, weight: 1 - Self.homeNewContentFraction),
            (items: newItems, weight: Self.homeNewContentFraction)
        ])
        Logger.learningLoop.info(
            "session.cruisingMode reviews=\(reviewItems.count) newDrip=\(newItems.count)"
        )
        return finalize(exercises: exercises)
    }

    /// Whether the learner has moved from "construction" into "croisière":
    /// most of the deck they've actually started is FSRS-mature. See the
    /// `cruisingMasteryThreshold` / `cruisingMinStartedCards` doc comments
    /// for why these particular numbers and why the minimum-sample guard
    /// exists. Only considers cards with `reps > 0` — cards never
    /// attempted (fresh vocab/kanji queued behind the kana foundation, say)
    /// don't count against "mature", by design: this reads maturity of what
    /// the learner has engaged with, not the whole catalogue.
    ///
    /// ### Le cas limite que ce commentaire signalait, et qui est désormais traité
    ///
    /// Ce texte disait : « KNOWN EDGE CASE (flagged, not solved here): a
    /// learner who has mastered every kana but is sitting on a large unseen
    /// vocabulary/kanji queue can classify as cruising — because kana
    /// dominate their `reps > 0` set — and lose the skill-balance booster /
    /// variety tile ». C'était exact, et c'est ce que la contre-review a
    /// mesuré de l'extérieur (OBS2-023) : les kana, majoritaires, décidaient
    /// du régime pour tout le monde, et emportaient avec eux les seuls
    /// segments qui font apparaître les autres types d'exercices.
    ///
    /// La croisière se décide maintenant **par groupe pédagogique** et non sur
    /// l'ensemble : un seul groupe encore en construction suffit à retenir
    /// toute la séance en construction, donc à conserver le booster et la
    /// tuile de variété.
    ///
    /// Deux précautions, chacune apprise d'un défaut réel :
    ///
    /// - **Le regroupement n'est PAS `card.type`.** Le semeur de production
    ///   émet TOUTES les cartes kana avec `CardType.vocabulary` — même cause
    ///   que OBS2-034 — donc grouper sur le type remettrait kana et
    ///   vocabulaire dans le même seau, et le défaut survivrait au correctif.
    ///   `card.isKana` compare au catalogue des 208 caractères.
    /// - **Un groupe marginal ne décide de rien.** Trois cartes de kanji
    ///   traînant dans un deck ne doivent pas retenir indéfiniment un
    ///   apprenant en construction : un groupe ne pèse qu'à partir de
    ///   `cruisingMinStartedCards` cartes, le même seuil de significativité
    ///   que la règle globale.
    ///
    /// Si aucun groupe n'atteint ce seuil (deck petit et très éparpillé), on
    /// retombe sur la règle globale d'origine plutôt que de renvoyer un `false`
    /// arbitraire.
    ///
    /// Ne considère toujours que les cartes `reps > 0` pour juger la maturité —
    /// on lit ce que l'apprenant a engagé, pas le catalogue. Mais un groupe
    /// entier jamais commencé est désormais un signal de CONSTRUCTION, ce qui
    /// est précisément ce qui manquait.
    private func isCruisingStage(cards: [CardDTO]) -> Bool {
        let started = cards.filter { $0.fsrsState.reps > 0 }
        guard started.count >= Self.cruisingMinStartedCards else { return false }

        let buckets = Dictionary(grouping: cards) { card -> CruisingBucket in
            card.isKana ? .kana : .other(card.type)
        }

        var significantBuckets = 0
        for (_, bucketCards) in buckets {
            guard bucketCards.count >= Self.cruisingMinStartedCards else { continue }
            significantBuckets += 1

            let bucketStarted = bucketCards.filter { $0.fsrsState.reps > 0 }
            // Un groupe significatif jamais (ou à peine) commencé : l'apprenant
            // construit encore, quelle que soit la maturité des autres.
            guard bucketStarted.count >= Self.cruisingMinStartedCards else { return false }

            guard Self.isMature(bucketStarted) else { return false }
        }

        guard significantBuckets > 0 else { return Self.isMature(started) }
        return true
    }

    /// Clé de regroupement pédagogique. `.kana` est séparé de `.other` parce
    /// que `CardType` ne distingue pas les kana du vocabulaire — voir
    /// `isCruisingStage`.
    private enum CruisingBucket: Hashable {
        case kana
        case other(CardType)
    }

    /// Part de cartes ayant atteint `.mastered` ou `.anchored`, comparée au
    /// seuil de croisière. Extrait pour que la règle par groupe et la règle
    /// globale de repli ne puissent pas diverger.
    private static func isMature(_ startedCards: [CardDTO]) -> Bool {
        guard !startedCards.isEmpty else { return false }
        let matureCount = startedCards.filter {
            $0.masteryLevel == .mastered || $0.masteryLevel == .anchored
        }.count
        return Double(matureCount) / Double(startedCards.count) >= cruisingMasteryThreshold
    }

    /// Foundation session: due reviews (kana already begun) interleaved with
    /// one curriculum-ordered row of new kana (up to `foundationRowSize`).
    /// The row is introduced regardless of the proportional new-content
    /// budget — a foundation session is intentionally compact, and rows of
    /// five are how the syllabary is actually learned. No booster, no
    /// variety: nothing here draws on content the learner hasn't met.
    ///
    /// - Note: Unlike `composeConstruction` and `composeCruising` — where due
    ///   reviews get the *entire* session budget before anything else is
    ///   scheduled — foundation keeps a hard 50 % ceiling on the review
    ///   budget (`totalSec / 2` below). "Due reviews are an absolute
    ///   priority" is therefore true for construction/cruising but NOT for
    ///   foundation: here a large kana backlog is deliberately capped so a
    ///   beginner still sees new kana every session rather than a review-only
    ///   grind. Defendable (see rationale above), but undocumented until now
    ///   — flagged by remediation item #45(e). Not changed by this comment.
    private func composeFoundation(
        inputs: SessionPlannerInputs,
        unseenKana: [CardDTO],
        totalSec: Int
    ) -> SessionPlan {
        // 50 % ceiling, not an absolute priority — see the `- Note:` above
        // composeFoundation. Contrast with composeConstruction/composeCruising,
        // which hand pickReviews the entire remaining budget.
        let reviewItems = pickReviews(
            from: inputs.availableCards,
            secondsBudget: totalSec / 2
        )
        let introItems = unseenKana
            .enumerated()
            .sorted { lhs, rhs in
                let li = Self.kanaCurriculumIndex[lhs.element.front] ?? Int.max
                let ri = Self.kanaCurriculumIndex[rhs.element.front] ?? Int.max
                if li != ri { return li < ri }
                // Stable, deterministic order for kana outside the base
                // curriculum (dakuten): input order, then front.
                if lhs.element.front != rhs.element.front { return lhs.element.front < rhs.element.front }
                return lhs.offset < rhs.offset
            }
            .prefix(Self.foundationRowSize)
            .map { ExerciseItem.srsReview($0.element) }
        let exercises = interleave(streams: [
            (items: reviewItems, weight: 0.5),
            (items: Array(introItems), weight: 0.5)
        ])
        Logger.learningLoop.info(
            "session.foundationMode reviews=\(reviewItems.count) introduced=\(introItems.count)"
        )
        return finalize(exercises: exercises)
    }

    /// Deterministically interleaves multiple ordered streams proportional to
    /// their weights, using the "smooth weighted round-robin" scheduling
    /// algorithm (as used by nginx's upstream load balancer): every tick, each
    /// stream's credit accrues by its own weight; the stream with the highest
    /// credit is drained by exactly one item and its credit is reduced by the
    /// total weight. Ties break by stream order (first-declared wins), which
    /// keeps the result a pure function of the inputs — no randomness, so
    /// identical inputs always produce an identical merge.
    ///
    /// Each stream's own internal order is preserved: items are always popped
    /// front-to-back, never reordered within a stream (e.g. the review
    /// stream's most-overdue-first ordering from `pickReviews` survives).
    /// A stream that runs dry (or was empty) is simply skipped for the rest
    /// of the merge — its remaining weight is not redistributed, matching
    /// standard smooth-WRR behaviour.
    private func interleave(streams: [(items: [ExerciseItem], weight: Double)]) -> [ExerciseItem] {
        var queues = streams.map(\.items)
        let weights = streams.map(\.weight)
        let totalWeight = weights.reduce(0, +)
        let totalItems = queues.reduce(0) { $0 + $1.count }
        guard totalWeight > 0, totalItems > 0 else { return queues.flatMap { $0 } }

        var currentWeights = [Double](repeating: 0, count: streams.count)
        var result: [ExerciseItem] = []
        result.reserveCapacity(totalItems)

        while result.count < totalItems {
            var bestIndex: Int?
            for index in queues.indices where !queues[index].isEmpty {
                currentWeights[index] += weights[index]
                if bestIndex == nil || currentWeights[index] > currentWeights[bestIndex!] {
                    bestIndex = index
                }
            }
            guard let selected = bestIndex else { break }
            result.append(queues[selected].removeFirst())
            currentWeights[selected] -= totalWeight
        }
        return result
    }

    // MARK: - Study custom

    private func composeStudy(
        inputs: SessionPlannerInputs,
        types: Set<ExerciseType>,
        levels: Set<JLPTLevel>
    ) -> SessionPlan {
        let candidate = types.intersection(inputs.unlockedTypes)
        let totalSec = inputs.durationMinutes * 60
        var exercises: [ExerciseItem] = []
        var spent = 0

        let ordered = candidate.sorted {
            $0.skill.pedagogicalOrder < $1.skill.pedagogicalOrder
        }
        guard !ordered.isEmpty else { return finalize(exercises: []) }
        var idx = 0
        var safety = 0
        while spent < totalSec, safety < 100 {
            let type = ordered[idx % ordered.count]
            guard let item = synthesise(type: type, availableCards: inputs.availableCards) else {
                idx += 1
                safety += 1
                continue
            }
            if spent + item.estimatedDurationSeconds > totalSec, !exercises.isEmpty { break }
            exercises.append(item)
            spent += item.estimatedDurationSeconds
            idx += 1
            safety += 1
        }
        // `levels` reserved for future content-pool filtering; not yet
        // wired because content packs aren't tagged by JLPT yet.
        // `levels` is reserved for future content-pool filtering; not yet
        // wired because content packs aren't tagged by JLPT yet. Surface
        // this loud-and-clear in logs so callers know their filter was a no-op.
        if !levels.isEmpty {
            let names = levels.map(\.rawValue).joined(separator: ",")
            Logger.learningLoop.info("studyCustom: jlptLevels filtering not yet implemented — ignoring \(names, privacy: .public)")
        }
        _ = levels
        return finalize(exercises: exercises)
    }

    // MARK: - Helpers

    /// Fills a budget by appending SRS reviews until the next would overflow.
    /// Only cards whose `dueDate <= now` AND that the learner has actually
    /// begun (`reps > 0`) enter the review wave. The `reps > 0` gate is what
    /// keeps never-started characters — e.g. the full katakana set that gets
    /// materialised as immediately-due cards the moment the kana grid is
    /// opened — out of "Practice", which is meant to *review* what you've
    /// started. Brand-new characters reach the session only through the
    /// curriculum-ordered new-content drip (`pickNewContent`), never as reviews.
    /// (`dueDate <= now` alone previously re-served a just-graded card; the
    /// reps gate additionally stops the unlearned-katakana leak.)
    ///
    /// Budget consumption per card uses `reviewDurationSeconds`, not the flat
    /// `ExerciseItem.estimatedDurationSeconds` — a well-established card is
    /// budgeted for less time than one still being learned, so a
    /// mature-heavy backlog fits more reviews into the same budget than a
    /// young-heavy one would.
    private func pickReviews(from cards: [CardDTO], secondsBudget: Int, now: Date = Date()) -> [ExerciseItem] {
        // Most-overdue first: sort the eligible cards by dueDate ascending
        // (stable tiebreak on input order) so budget truncation always keeps
        // the most urgent reviews when not everything fits.
        let ordered = cards
            .filter { $0.dueDate <= now && $0.fsrsState.reps > 0 }
            .enumerated()
            .sorted { lhs, rhs in
                lhs.element.dueDate != rhs.element.dueDate
                    ? lhs.element.dueDate < rhs.element.dueDate
                    : lhs.offset < rhs.offset
            }
            .map(\.element)
        var items: [ExerciseItem] = []
        var spent = 0
        for card in ordered {
            let duration = Self.reviewDurationSeconds(for: card)
            if spent + duration > secondsBudget { break }
            items.append(.srsReview(card))
            spent += duration
        }
        return items
    }

    /// Per-mastery multiplier applied to the flat `.srsReview` baseline
    /// (`ExerciseItem.estimatedDurationSeconds`, currently 15 s) when
    /// budgeting review segments. ASSUMED heuristic — not measured against
    /// this app's actual per-card response times — reflecting the general
    /// observation (raised in the 2026-08-10 pedagogy review) that a
    /// well-established card is answered in a fraction of the time a
    /// still-learning card takes, so a flat per-type estimate makes a
    /// mature-heavy session's time budget run out early. `.new`/`.learning`
    /// cards keep the full baseline; the multiplier only shrinks once a card
    /// has actually built FSRS stability (`.familiar` and above).
    private static func reviewDurationMultiplier(for level: MasteryLevel) -> Double {
        switch level {
        case .new, .learning: return 1.0
        case .familiar: return 0.8
        case .mastered: return 0.6
        case .anchored: return 0.4
        }
    }

    /// Maturity-modulated budget cost, in seconds, of reviewing `card`. See
    /// `reviewDurationMultiplier`.
    private static func reviewDurationSeconds(for card: CardDTO) -> Int {
        let base = Double(ExerciseItem.srsReview(card).estimatedDurationSeconds)
        let multiplier = reviewDurationMultiplier(for: card.masteryLevel)
        return max(1, Int((base * multiplier).rounded()))
    }

    /// Budget cost, in seconds, of scheduling `item` — the maturity-modulated
    /// `reviewDurationSeconds` for `.srsReview`, the flat
    /// `ExerciseItem.estimatedDurationSeconds` for every other kind (their
    /// duration doesn't depend on a backing card's FSRS state the way a
    /// review's does). Used both while filling segments and when `finalize`
    /// reports the plan's total estimated duration, so the reported time
    /// reflects what was actually budgeted rather than re-summing flat
    /// per-type constants.
    private static func effectiveDurationSeconds(for item: ExerciseItem) -> Int {
        if case .srsReview(let card) = item {
            return reviewDurationSeconds(for: card)
        }
        return item.estimatedDurationSeconds
    }

    /// Fills a segment with exercises targeting `skill`, drawn from `pool`.
    /// Picks the shortest-fitting candidate first, then repeats it until
    /// the budget is exhausted (round-robin across all candidates that fit).
    private func fillSegment(
        forSkill skill: SkillType,
        inPool pool: Set<ExerciseType>,
        secondsBudget: Int,
        availableCards: [CardDTO]
    ) -> [ExerciseItem] {
        let candidates = pool
            .filter { $0.skill == skill }
            .sorted { $0.estimatedDurationSeconds < $1.estimatedDurationSeconds }
        guard !candidates.isEmpty else { return [] }

        var items: [ExerciseItem] = []
        var spent = 0
        var idx = 0
        var safety = 0
        while spent < secondsBudget, safety < 100 {
            let type = candidates[idx % candidates.count]
            guard let item = synthesise(type: type, availableCards: availableCards) else {
                idx += 1
                safety += 1
                continue
            }
            if spent + item.estimatedDurationSeconds > secondsBudget { break }
            items.append(item)
            spent += item.estimatedDurationSeconds
            idx += 1
            safety += 1
        }
        return items
    }

    /// Fills the variety segment by rotating through the pool. Day index
    /// chooses the starting point so the variety tile shifts day-by-day.
    private func fillRotating(
        inPool pool: Set<ExerciseType>,
        secondsBudget: Int,
        day: Int,
        availableCards: [CardDTO]
    ) -> [ExerciseItem] {
        guard !pool.isEmpty else { return [] }
        let sorted = pool.sorted { $0.rawValue < $1.rawValue }
        var items: [ExerciseItem] = []
        var spent = 0
        var idx = 0
        var safety = 0
        while spent < secondsBudget, safety < 100 {
            let type = sorted[(day + idx) % sorted.count]
            guard let item = synthesise(type: type, availableCards: availableCards) else {
                idx += 1
                safety += 1
                continue
            }
            if spent + item.estimatedDurationSeconds > secondsBudget { break }
            items.append(item)
            spent += item.estimatedDurationSeconds
            idx += 1
            safety += 1
        }
        return items
    }

    /// Curriculum index for every base kana (hiragana あいうえお… first, then
    /// katakana), built once from the canonical group order. Used to introduce
    /// new characters in pedagogical order rather than whatever order
    /// `allCards()` happens to return — so day one always teaches あ, and
    /// hiragana is always offered before katakana.
    private static let kanaCurriculumIndex: [String: Int] = {
        var map: [String: Int] = [:]
        for (index, kana) in KanaGroup.allBaseCharacters.enumerated() {
            map[kana.character] = index
        }
        return map
    }()

    /// Picks the single "new" (never-reviewed) card to drip into the session.
    /// Candidates are ordered by the kana curriculum so the introduction order
    /// is stable and pedagogical (hiragana before katakana); non-kana new
    /// content sorts after all kana. Without this ordering the drip grabbed an
    /// arbitrary unseen card from `allCards()` ordering — which could be a
    /// katakana the learner never chose.
    private func pickNewContent(secondsBudget: Int, availableCards: [CardDTO]) -> ExerciseItem? {
        let unseen = availableCards.filter { $0.fsrsState.reps == 0 }
        guard !unseen.isEmpty else { return nil }
        let ordered = unseen.sorted { lhs, rhs in
            let li = Self.kanaCurriculumIndex[lhs.front] ?? Int.max
            let ri = Self.kanaCurriculumIndex[rhs.front] ?? Int.max
            if li != ri { return li < ri }
            return lhs.front < rhs.front
        }
        guard let card = ordered.first else { return nil }
        let exercise = ExerciseItem.srsReview(card)
        return Self.effectiveDurationSeconds(for: exercise) <= secondsBudget ? exercise : nil
    }

    /// Maps an `ExerciseType` to a concrete `ExerciseItem` payload.
    ///
    /// Returns `nil` when the type requires a real backing card that isn't
    /// available (kanji study / writing practice with no kanji card in the
    /// pool): we never fabricate a card, because a synthetic card can't be
    /// honestly FSRS-graded. Callers skip `nil` results. Content-backed kinds
    /// that don't have a real content source yet (reading passages, listening,
    /// etc.) still use a placeholder UUID so the planner can return a
    /// structurally valid plan; those are filtered by `finalize` until wired.
    private func synthesise(type: ExerciseType, availableCards: [CardDTO]) -> ExerciseItem? {
        switch type {
        case .kanjiStudy:
            let kanjiCards = availableCards.filter { $0.type == .kanji }
            guard let card = kanjiCards.randomElement() else { return nil }
            return .kanjiStudy(card)
        case .kanaStudy:
            // Kana is NOT an SRS `Card`: it lives in the separate KanaCharacter /
            // KanaData model, drilled by the standalone KanaDrillViewModel. There
            // is therefore no `CardDTO` to back a kana study exercise, no
            // `.kanaStudy` case on `ExerciseItem`, and no single-kana in-session
            // drill unit. Synthesise nothing rather than fabricating a wrong-type
            // kanji drill from a kanji card (the prior bug: `.kanaStudy` shared
            // this branch with `.kanjiStudy` and returned `.kanjiStudy(card)`,
            // showing a kanji handwriting drill for a kana request). A real
            // kana-in-mixed-session unit — a dedicated `ExerciseItem` case + view
            // sourcing KanaCharacters — is future work for the Compose/Étude sheet.
            return nil
        case .vocabularyStudy:
            return .vocabularyStudy(UUID())
        case .listeningSubtitled, .listeningUnsubtitled:
            return .listeningExercise(UUID())
        case .fillInBlank:
            return .fillInBlank(UUID())
        case .grammarExercise:
            return .grammarExercise(UUID())
        case .sentenceConstruction:
            return .sentenceConstruction(UUID())
        case .readingPassage:
            return .readingPassage(UUID())
        case .writingPractice:
            let kanjiCards = availableCards.filter { $0.type == .kanji }
            guard let card = kanjiCards.randomElement() else { return nil }
            return .writingPractice(card)
        case .speakingPractice, .sakuraConversation:
            return .speakingExercise(UUID())
        }
    }

    /// Whether an exercise kind is "live" — i.e. backed by a real, wired
    /// in-session drill view that can present and honestly grade it. Used by
    /// `finalize` as an allowlist so the planner never schedules a placeholder.
    ///
    /// Exhaustive on `ExerciseItem` on purpose: adding a new kind forces an
    /// explicit live/filtered decision here rather than silently defaulting.
    ///
    ///   LIVE (wired drill views):
    ///     Tier 1:
    ///       .srsReview            — SRS flashcard deck
    ///       .kanjiStudy           — HandwritingExerciseView, writes a real FSRS grade
    ///       .writingPractice      — HandwritingExerciseView, writes a real FSRS grade
    ///       .sentenceConstruction — SentenceConstructionView, XP-only
    ///     Tier 2 (XP-only drills):
    ///       .listeningExercise    — ListeningExerciseView (word/meaning subtypes)
    ///       .speakingExercise     — ShadowingExerciseView
    ///       .vocabularyStudy      — VocabularyRecallView (multiple-choice recall)
    ///
    ///   STILL FILTERED (no wired view / no real content source yet):
    ///     Tier 3 (deferred):  .fillInBlank, .readingPassage, .grammarExercise
    ///     (listening PASSAGE comprehension also stays out — no passages table.)
    ///
    /// NOTE (`.vocabularyStudy` XP-only): vocabulary has NO backing SwiftData
    /// `Card` (it lives only in the read-only content DB), so its completion is
    /// XP-only — it never writes an FSRS grade or `ReviewLog`. See
    /// `SessionViewModel.completeCurrentExercise`, where only the card-backed
    /// kinds (`.kanjiStudy`, `.writingPractice`) reach `gradeCard`. FSRS
    /// scheduling for vocabulary is deferred until the vocab-dictionary feature
    /// makes vocab cards gradeable.
    static func isLive(_ item: ExerciseItem) -> Bool {
        switch item {
        case .srsReview, .kanjiStudy, .writingPractice, .sentenceConstruction,
             .listeningExercise, .speakingExercise, .vocabularyStudy:
            return true
        case .fillInBlank, .readingPassage, .grammarExercise:
            return false
        }
    }

    private func lowestSkill(in balances: [SkillType: Double]) -> SkillType {
        let sorted = SkillType.allCases.sorted { (balances[$0] ?? 0) < (balances[$1] ?? 0) }
        return sorted.first ?? .reading
    }

    private func dayOfYear(now: Date = Date()) -> Int {
        Calendar(identifier: .gregorian).ordinality(of: .day, in: .year, for: now) ?? 0
    }

    private func finalize(exercises rawExercises: [ExerciseItem]) -> SessionPlan {
        // Allowlist of exercise kinds that have a real, fully-wired in-session
        // drill view TODAY. Everything else still renders a placeholder, so the
        // planner filters it out rather than scheduling something the UI cannot
        // honestly present or grade. This replaces the previous SRS-only filter.
        let exercises = rawExercises.filter { Self.isLive($0) }
        // Maturity-modulated total (`effectiveDurationSeconds`), not a flat
        // re-sum of `estimatedDurationSeconds` — see that helper's doc
        // comment. KNOWN GAP: two app-layer call sites re-derive their own
        // "session length" independently from the flat per-type constant
        // instead of reading `estimatedDurationMinutes` off the plan
        // (`SessionViewModel.swift` and `SessionComposer.swift`'s adaptive
        // preview) — those are outside this file's remit and still read as
        // if every review took the flat baseline.
        let secs = exercises.reduce(0) { $0 + Self.effectiveDurationSeconds(for: $1) }
        var breakdown: [SkillType: Int] = [:]
        for ex in exercises { breakdown[ex.skill, default: 0] += 1 }
        return SessionPlan(
            exercises: exercises,
            estimatedDurationMinutes: max(0, secs / 60),
            exerciseBreakdown: breakdown
        )
    }
}
