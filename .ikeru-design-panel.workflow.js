export const meta = {
  name: 'ikeru-beginner-first-design',
  description: 'Beginner-first redesign panel: 4 diverse product/UX lenses each propose a concrete new IA + motivation model + exercise/AI decisions, then a synthesis into one plan. Read-only reasoning. Workers Sonnet.',
  phases: [
    { title: 'Panel', detail: '4 independent design proposals from distinct lenses', model: 'sonnet' },
    { title: 'Synthesize', detail: 'Merge into one unified beginner-first plan', model: 'sonnet' },
  ],
}

const REPO = '/Users/batum/Projects/Ikeru'

const BRIEF = [
  'PROJECT: Ikeru, an iOS SwiftUI Japanese-learning app (' + REPO + '). Visual art direction is "Tatami" (calm sumi-ink + gold, wabi-sabi, 0px radius). Product posture is explicitly CALM and ANTI-GAMIFICATION: "no streaks, no gems, no daily login pressure".',
  '',
  'THE PROBLEM (from the product owner): the app feels "too full" and too complicated. It was meant to serve BOTH new and experienced Japanese learners at once, and that mix produced something bad. NEW DIRECTIVE: design it BEGINNER-FIRST, then make it compatible with experienced users WITHOUT losing what is good for beginners and WITHOUT a parallel second mode that doubles the surface.',
  '',
  'GROUND TRUTH FROM A FULL CODE INVENTORY (this is what the app ACTUALLY is, vs what it pretends to be):',
  '- CONTENT: only N5 (beginner) content ships (one static SQLite bundle). N4-N1 code paths exist but no content. So the app only HAS beginner content.',
  '- WHAT ACTUALLY WORKS END-TO-END: SRS flashcard review (FSRS-5, solid) and a kana drill chain (built, polished, but currently UNWIRED into navigation). That is essentially it.',
  '- FAKE BREADTH: the session router has 12 exercise types; 9 of them render an identical PLACEHOLDER (icon + "Complete" button that auto-grades Good). The Etude tab shows an 11-tile grid where ~9 tiles lead to that placeholder.',
  '- ORPHANED-BUT-BUILT: full exercise chains for kana, vocabulary (dictionary+drill), kanji study, reading, listening, speaking (mic+pitch), writing (handwriting+stroke order) EXIST as code but are NOT reachable from any tab (~6,000+ LOC of unwired views).',
  '- GAMIFICATION (~3,600-4,650 LOC, ~31 files): XP, levels called dan/段, ranks, lootboxes opened via timed quiz mini-games, random loot drops (5%/review + pity timer) during review, an 8-attribute RPG sheet (values 0-100 never read by anything), inventory + cosmetic themes/titles, streak bonuses (5-day/30-day, never even shown), level-up + loot-reveal celebrations. NONE of it gates or changes what the user learns. It is a parallel reward theatre that contradicts the anti-gamification posture. It occupies a full top-level tab ("Rang").',
  '- AI COMPANION (~6,000 LOC, 33 files, the largest subsystem): a top-level "Companion" tab (Sakura AI chat) PLUS a separate floating avatar that opens a SECOND, redundant chat (keyword-stub responses, no real AI). Requires an API key or on-device model; OFFLINE BY DEFAULT for all new installs. 8 provider integrations.',
  '- NAVIGATION: 5 tabs (Companion, Etude/Study, Home, Rang/RPG, Settings); the middle 3 are a horizontal swipe pager, the outer 2 are tap-only (inconsistent). A dead NavigationCoordinator. ~2,200 LOC of fully dead/unreachable views. Onboarding is an 8-step tour introducing all 5 tabs.',
  '- SETTINGS: 8 sections, 20+ rows, several DEAD (Sound, Daily goal "12 cards", Terms, Support all no-ops), an FSRS "memory algorithm" stub page (read-only technical jargon), a beginner-vs-tatami DISPLAY MODE toggle + a threshold monitor + a suggestion card that only appears after 750 reviews (i.e. never for a beginner), dev-only rig/pre-warm tooling, iCloud sync disabled in code, multi-profile.',
  '- THE CORE LOOP that works: Home shows due-card count + one CTA -> immersive SRS session with swipe grading (再/難/良/易) -> calm summary. This is good and should be protected.',
].join('\n')

const QUESTIONS = [
  'Answer these concretely (propose, do not hedge):',
  '1. NEW INFORMATION ARCHITECTURE: exactly what tabs/screens should exist for a beginner-first app? (Name them. Fewer is better. Justify each.) What happens to Companion tab, Rang tab, Etude grid, the floating avatar?',
  '2. MOTIVATION / PROGRESS for a beginner that fits the calm, anti-gamification, wabi-sabi posture: what REPLACES XP/levels/ranks/lootboxes? Should we keep ANY sense of progression, and in what form (e.g. honest mastery counts, a quiet "garden/path that fills", JLPT readiness)? Be specific about what the user sees.',
  '3. EXPERIENCED USERS AS A LAYER (not a parallel mode): how do we let someone who already knows some Japanese skip ahead and get density/speed/power-features, WITHOUT a second UI skin and without bloating the beginner experience? Consider: an onboarding placement question, progressive disclosure as competence grows, a single density preference, where power features (AI, dictionary, custom sessions) live.',
  '4. THE ORPHANED EXERCISES: only SRS review + kana drill truly work. For each family (kana, vocab dictionary+drill, kanji study, reading, listening, speaking, writing) say WIRE-NOW / HIDE-UNTIL-REAL / CUT, with reasoning grounded in beginner value and maintenance cost. What is the honest minimal set of practice the app should offer today?',
  '5. THE AI COMPANION: keep as a primary tab, demote to an optional feature, or cut? If kept, how (single surface, where it lives, how it handles being offline by default)?',
  '6. WHAT TO CUT WHOLESALE vs KEEP. Be willing to remove thousands of LOC. Name the big cuts.',
].join('\n')

const SCHEMA = {
  type: 'object',
  properties: {
    oneLineVision: { type: 'string' },
    newIA: { type: 'string', description: 'Concrete tab/screen structure' },
    motivationModel: { type: 'string' },
    experiencedLayer: { type: 'string' },
    exerciseDecision: { type: 'string', description: 'wire/hide/cut per family + the honest minimal set' },
    aiDecision: { type: 'string' },
    cutWholesale: { type: 'array', items: { type: 'string' } },
    keepProtect: { type: 'array', items: { type: 'string' } },
    onboarding: { type: 'string' },
    risks: { type: 'string' },
  },
  required: ['oneLineVision', 'newIA', 'motivationModel', 'experiencedLayer', 'exerciseDecision', 'aiDecision', 'cutWholesale'],
}

phase('Panel')
const lenses = [
  { key: 'beginner-zero', lens: 'LENS: the absolute-beginner advocate. Design for someone who knows ZERO Japanese opening the app for the first time. Optimize the first 2 weeks: kana first, then the most common N5 vocab/kanji via SRS, with reading aids on. Ruthlessly minimize choices and concepts on screen. The ideal is "open app -> it tells me the ONE thing to do now -> I do it." Argue for the smallest possible IA and the gentlest possible onboarding.' },
  { key: 'wabi-sabi', lens: 'LENS: the calm/wabi-sabi product philosopher. Your obsession is the anti-gamification posture and emotional tone. Decide what (if anything) replaces XP/ranks/lootboxes so a beginner still feels growth and gentle accomplishment WITHOUT dopamine mechanics. Define what "progress" looks and feels like in a wabi-sabi app (honest, quiet, earned). Be specific and opinionated about killing the reward theatre and what a dignified replacement is.' },
  { key: 'experienced-layer', lens: 'LENS: the architect of progressive depth. Your job is to make sure experienced learners are NOT abandoned, but served as a LAYER on top of the beginner-first base — never a parallel mode. Design the mechanism: the onboarding placement question, how density/aids reduce as competence grows, where power features (AI companion, vocabulary dictionary, custom session composition, faster reviews, skipping kana) live and how they are revealed. The constraint: zero added complexity for the beginner who never touches them.' },
  { key: 'ruthless-editor', lens: 'LENS: the ruthless scope editor. Given that only N5 content ships and only SRS review + kana drill actually work, define the HONEST minimal app that could ship today and be excellent. Be aggressive: name every subsystem to delete (with LOC), every screen to remove, every concept to drop. Distinguish "cut now" from "hide until real". Your north star: an app that does a few things excellently beats one that pretends to do twenty.' },
]

const proposals = await parallel(lenses.map(function (l) {
  return function () {
    return agent(BRIEF + '\n\n' + l.lens + '\n\n' + QUESTIONS, { label: 'design:' + l.key, phase: 'Panel', model: 'sonnet', schema: SCHEMA })
      .then(function (r) { return { key: l.key, p: r } })
  }
}))
const ok = proposals.filter(Boolean)
log('Panel: ' + ok.length + '/4 proposals')

phase('Synthesize')
const synthBody = [
  BRIEF,
  '',
  'Four senior designers independently produced beginner-first redesign proposals (distinct lenses: absolute-beginner advocate, wabi-sabi philosopher, progressive-depth architect, ruthless editor). Their proposals (JSON):',
  JSON.stringify(ok.map(function (x) { return { lens: x.key, proposal: x.p }; }), null, 2),
  '',
  'YOUR JOB: synthesize ONE unified, decisive beginner-first plan. Where they disagree, make the call and say why. Produce:',
  '1. The one-line product vision.',
  '2. The final IA (exact tabs/screens, beginner default).',
  '3. The motivation/progress model (what replaces gamification; what the user actually sees).',
  '4. The experienced-user layer (onboarding placement + progressive disclosure mechanism; concrete).',
  '5. The exercise decision per family (wire-now / hide / cut) and the honest minimal practice set for v1.',
  '6. The AI decision.',
  '7. THE CUT LIST: everything to delete or gate, grouped, with rough LOC, ordered by safety (pure dead-code first, then gamification, then structural).',
  '8. A PHASED IMPLEMENTATION PLAN: Phase 0 (safe dead-code removal), Phase 1 (cut gamification theatre), Phase 2 (IA collapse + tabs), Phase 3 (beginner-first onboarding + experienced layer), Phase 4 (wire the real exercises that are worth wiring). Each phase: what changes, rough risk, what stays green.',
  'Be concrete and decisive. This plan will be executed.',
].join('\n')

const synthesis = await agent(synthBody, { label: 'synthesis', phase: 'Synthesize', model: 'sonnet' })

return { proposals: ok, synthesis: synthesis }
