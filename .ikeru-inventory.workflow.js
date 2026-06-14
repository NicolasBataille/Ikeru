export const meta = {
  name: 'ikeru-ux-inventory',
  description: 'Map the full feature/IA surface of Ikeru with evidence (code footprint, coupling, stub/dead code, concept load) to drive a UX simplification. Read-only inspection. Workers Sonnet.',
  phases: [
    { title: 'Inventory', detail: '8 read-only agents map each subsystem with evidence', model: 'sonnet' },
  ],
}

const REPO = '/Users/batum/Projects/Ikeru'

const COMMON = [
  'You are inspecting the iOS SwiftUI app "Ikeru" (a Japanese-learning app) at ' + REPO + '. App code in Ikeru/, shared logic in IkeruCore/Sources/. This is a READ-ONLY inspection pass: DO NOT edit any file, DO NOT run git, DO NOT build. Only read, grep, and count.',
  '',
  'GOAL CONTEXT: the product owner feels the app is "too full" and too complicated to use — both the UI and the feature set. We are gathering evidence to decide what to CUT, MERGE, HIDE behind progressive disclosure, or KEEP. The stated product posture is calm and anti-gamification ("no streaks, no gems, no daily login pressure"). Your job is to map your assigned subsystem in full detail with hard evidence so a simplification plan can be built.',
  '',
  'For your assigned area, produce: every screen/feature, its purpose, its status (working / partial / stub / locked / dead), its entry points (how a user reaches it), the code files + approx LOC, whether it is COUPLED to the core learning loop (does it gate or change what/how the user learns, or is it a parallel side-system?), redundancy/overlap with other features, and how many distinct CONCEPTS a new user must understand to use it. Then give candid cut/merge/hide candidates with rationale and risk.',
  '',
  'Use concrete evidence: cite file paths, grep counts, LOC (wc -l), entry points. Be candid and specific, not diplomatic. Count things. Flag stubs (functions that only log / TODO / "added in a later task"), locked features, and dead code.',
].join('\n')

const SCHEMA = {
  type: 'object',
  properties: {
    area: { type: 'string' },
    summary: { type: 'string', description: 'Plain-language overview of what this subsystem is and how heavy it is' },
    features: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          name: { type: 'string' },
          purpose: { type: 'string' },
          status: { type: 'string', enum: ['working', 'partial', 'stub', 'locked', 'dead'] },
          entryPoints: { type: 'string' },
          files: { type: 'array', items: { type: 'string' } },
          locApprox: { type: 'number' },
          coupledToLearning: { type: 'string', description: 'tight | loose | none — and why' },
          redundancy: { type: 'string' },
        },
        required: ['name', 'purpose', 'status', 'locApprox'],
      },
    },
    conceptCount: { type: 'number', description: 'How many distinct concepts a new user must grasp to use this area' },
    complexitySignals: { type: 'array', items: { type: 'string' } },
    cutMergeHideCandidates: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          item: { type: 'string' },
          recommendation: { type: 'string', enum: ['cut', 'merge', 'hide', 'simplify', 'keep'] },
          rationale: { type: 'string' },
          risk: { type: 'string' },
          approxLocFreed: { type: 'number' },
        },
        required: ['item', 'recommendation', 'rationale'],
      },
    },
  },
  required: ['area', 'summary', 'features', 'conceptCount', 'cutMergeHideCandidates'],
}

phase('Inventory')
const areas = [
  { key: 'nav-ia', body: 'AREA: Navigation & Information Architecture. Map the top-level structure: Ikeru/Views/MainTabView.swift (all tabs and their order), Ikeru/App/NavigationCoordinator.swift, IkeruApp.swift, every fullScreenCover/sheet/navigationDestination across the app (grep), deep links / App Intents / Shortcuts (ShortcutsManager). Produce the complete map of how a user navigates: tabs -> screens -> sub-screens -> sheets. Count the total number of distinct top-level destinations and the depth. Assess whether 5 tabs is justified and which could merge. Concept count = how many navigational concepts a user juggles.' },
  { key: 'home-session', body: 'AREA: Home + the core study/session loop. Files: Ikeru/Views/Home/*, Ikeru/Views/Session/*, Ikeru/Views/Learning/CardReview/*, Ikeru/ViewModels/HomeViewModel.swift, SessionViewModel.swift, IkeruCore SessionPlanner, ProgressService, FSRSService, DailyTerm. Map the actual daily loop: what the user sees on Home, how a session is composed, the SRS grading, the summary. Identify everything on Home that is NOT the core "review/study now" action (daily proverb, XP bar, breakdown, etc.) and whether it adds value or clutter. This is the heart of the app — assess how clean the core loop is.' },
  { key: 'etude-exercises', body: 'AREA: Etude tab + ALL exercise types. Files: Ikeru/Views/Learning/Etude/*, and every exercise family under Ikeru/Views/Learning/ (Kana, Kanji, Vocabulary, Reading, Listening, Speaking, Writing, plus FillInBlank, GrammarPoint, SentenceConstruction, StrokeOrder, Handwriting, PitchAccent, Shadowing). For EACH exercise type: does it actually work end to end, is it a stub, or is it locked behind an unlock threshold (IkeruCore ExerciseUnlock)? List the unlock thresholds. Count how many exercise types are shown in the Etude grid and how many are actually usable today. This is a prime suspect for "too full" — quantify the sprawl.' },
  { key: 'rpg-gamification', body: 'AREA: the ENTIRE RPG / gamification layer — the prime suspect. Map every part: XP, levels, ranks (dan/段), the Rang tab (RPGProfileView), lootboxes (LootBoxService, LootBoxChallengeView mini-games, LootBoxOpenView), distinctions/achievements (hanko), attributes (RPGAttribute: Reading/Writing/Listening/Speaking + Culture/Intuition), inventory & cosmetics (EquipmentService, themes), level-up & loot-reveal celebrations, EnsoRankView, RPGRankCrest. Files across Ikeru/Views/RPG/*, IkeruCore RPG models + services (RPGService, RPGConstants, LootBoxService, LootDropService, EquipmentService, MasteryEventDetector). CRITICAL QUESTION: does any of this GATE or change actual learning, or is it a parallel reward theatre bolted on top? Does XP/level unlock real content or just cosmetics? Quantify total LOC of the whole gamification layer. The product posture is explicitly anti-gamification — assess how much of this contradicts that and could be removed wholesale.' },
  { key: 'ai-companion', body: 'AREA: AI / Companion. Files: Ikeru/Views/Learning/Conversation/* (Chat tab, CompanionTabView, ConversationView, CompanionChatSheet, bubbles, inline kanji/quiz/mnemonic), Ikeru/ViewModels/Learning/ConversationViewModel.swift, CompanionChatViewModel, IkeruCore AIRouterService + AIProviders/* + ConversationService. Map: how central is the AI? What does it require to work (API keys, on-device FoundationModels)? What is the DEFAULT experience (offline / no provider configured)? How many entry points (Chat tab, floating button, topic seeds)? Is the Chat tab earning its place as a top-level tab if it is offline by default for most users? Assess whether AI should be a primary tab, a secondary feature, or demoted.' },
  { key: 'settings-modes', body: 'AREA: Settings + cross-cutting config concepts. Files: Ikeru/Views/Settings/* (now with sub-pages), Ikeru/Views/Shared/Theme/DisplayMode* + DisplayModeEnvironment, IkeruCore DisplayMode, DisplayModeAdvancedThresholdMonitor, DisplayModePreferenceRepository, backup (CloudBackupManager/BackupService), pre-warm (PreWarmFactory/Notifier), RigJobs. Count every distinct user-facing setting and every CONCEPT a setting introduces (e.g. "Tatami vs Beginner display mode", "FSRS retention target", "rig jobs", "pre-warm"). The display-mode duality (beginner/tatami) and its threshold monitor are suspects for unnecessary conceptual load. Identify settings that most users will never touch and that could be removed or auto-defaulted.' },
  { key: 'data-content', body: 'AREA: Data model & content — to identify the REAL core the app is built around. Files: IkeruCore/Sources/Models/*, Repositories/*, ContentSeedService, ContentLoadingService, and the SwiftData @Model types in the app. What entities exist (cards, vocab, kanji, kana, progress, RPG state, conversations, etc.)? Which are core to learning vs. supporting the side-systems? How much content ships (counts)? This frames what the app MUST keep vs. what is accretion. Also note any data the app stores only to feed gamification.' },
  { key: 'metrics-dead', body: 'AREA: Cross-cutting metrics & dead/stub code (quantify "fullness"). Compute: LOC per top-level feature area (Home, Session, Etude+exercises, RPG/gamification, Conversation/AI, Settings, shared Theme) using find + wc -l on the relevant directories. Count: number of view files per area, number of Core services, number of @Model types, number of user-facing settings, number of exercise types, number of tabs. Find dead/stub code across the app: grep for "added in a later task", "TODO", "FIXME", "Demo" types used in production, functions that only log, unreferenced views (grep for struct names with zero external call sites — spot check the suspicious ones). Produce a ranked table of where the bulk of the code/complexity lives, so we know what cutting would actually simplify.' },
]

const results = await parallel(areas.map(function (a) {
  return function () {
    return agent(COMMON + '\n\n' + a.body, { label: 'inv:' + a.key, phase: 'Inventory', model: 'sonnet', schema: a.key === 'metrics-dead' ? undefined : SCHEMA })
      .then(function (r) { return { key: a.key, data: r } })
  }
}))

return { areas: results.filter(Boolean) }
