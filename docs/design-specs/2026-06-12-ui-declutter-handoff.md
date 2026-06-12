# UI Declutter & UX Pass — Handoff

**Date :** 2026-06-12
**Branche :** `claude/app-screen-design-viz-kvs1a5` (partie de `origin/dev` @ `5368fa9`)
**Statut :** ⚠️ Code écrit et poussé, **JAMAIS COMPILÉ** — la session a tourné dans un conteneur Linux sans toolchain Swift/Xcode. Première étape sur Mac : builder.

---

## 1. Demande d'origine

> « Améliorer l'UI et l'UX, rendre l'app vraiment bien et facilement utilisable, je la trouve **trop chargée** actuellement. »

Le travail découle d'une review complète de la DA (direction artistique Tatami) faite en amont dans la même session : specs lues (`docs/design-specs/2026-04-29-tatami-direction.md`, `2026-05-02-density-modes-design.md`, `docs/design-review/CLAUDE_DESIGN_BRIEF.md`) + audit du code de tous les écrans.

### Constats de la review qui ont motivé les changements

1. **Home surchargé** : carte STREAK affichant « 0 days » en dur (placeholder jamais câblé, contraire à la posture produit anti-streak), compteur LEARNED redondant avec Étude/RPG, ~120 lignes de code mort (`primaryAction`, `rankTitle`, etc.).
2. **Fracture DA n°1 — Conversation** : landing Companion en Tatami pur, mais bulles de chat en `RoundedRectangle` glass pré-Tatami, et **3 traitements d'avatar Sakura différents** (carré sumi 桜 / cercle さ 44pt / cercle さ 32pt).
3. **Résidus pré-Tatami** : `ikeruCard` arrondi dans AISettings, overlay de pause, toast de loot, etc.
4. **Données malhonnêtes** : achievements RPG avec des seuils fantaisistes (七 = level ≥ 2, 極 = level ≥ 10).
5. **Lisibilité** : texte à 8-9pt, jauges de progression de 1pt de haut, gris fantôme `#7A7770` (paperGhost, contraste ~4.4:1) utilisé pour du texte porteur de sens.

---

## 2. Ce qui a été fait (5 commits)

### `8a65167` — refactor(home): declutter
- `Ikeru/Views/Home/HomeView.swift` : suppression de `statsRow` (tuiles LEARNED + STREAK) et de son call site. Home = topbar + hero proverbe + daily term + session breakdown + quiet state.
- Code mort purgé : `primaryAction(_:)`, `sessionDurationEstimate(_:)`, `rankLabel`, `rankTitle`, `timeOfDayGreeting()` (la version JP, utilisée, est conservée).

### `12c4de9` — fix(rpg,settings): achievements honnêtes + row Tatami standard
- `Ikeru/Views/RPG/RPGProfileView.swift` : seuils des hanko dérivés des seuls signaux que `RPGProfileViewModel` expose (`totalReviews`, `level`) :
  初 = reviews ≥ 1 · 七 = reviews ≥ 7 · 百 = reviews ≥ 100 · 千 = reviews ≥ 1000 · 極 = level ≥ 25 (tier « Master »).
- `Ikeru/Views/Settings/DisplayModeToggleRow.swift` : remise au gabarit `rowChrome` standard (kanji 畳 13pt serif paperGhost + label 13pt + `TatamiToggle` + hairline), aide réduite à une ligne caption. `SettingsView.swift` : retrait du double padding d'embed.

### `e31ee66` — refactor(conversation): unification Tatami
- `ChatBubbleView.swift` + `ConversationBubbleView.swift` : bulles en rectangles nets + `sumiCorners` (companion = encre `#1A1A22` ~78% + coins goldDim ; user = teinte or + coins or). Comportement/paddings inchangés.
- `CompanionAvatarView.swift` (flottant 44pt) + `CompanionChatSheet.swift` (header 32pt) : avatar canonique **carré sumi + 桜 serif or** partout (le PhaseAnimator de respiration et le badge sont conservés).
- `CompanionTabView.swift` : bannière no-AI alignée Tatami.
- `InlineQuizView.swift` / `InlineMnemonicView.swift` : coins alignés.

### `1b856fe` — refactor(theme): résidus pré-Tatami
- `AISettingsView.swift` : 3× `.ikeruCard(.standard)` → `.tatamiRoom(.standard)`.
- `ActiveSessionView.swift` : overlay pause + empty state `.ikeruCard(.elevated)` → `.tatamiRoom(.glass)`.
- `CardReviewView.swift` : feedback overlay arrondi → rectangle + sumi.
- `LootDropView.swift` : toast arrondi → rectangle + sumi (couleur rarity sur les coins), ombre composite simplifiée en noir.
- `LootBoxChallengeView.swift` : card + barre de progression → vocabulaire Tatami.

### `9cb931a` — style(readability): planchers typo, jauges visibles, dé-ghosting
Trois règles appliquées chirurgicalement (swaps mono-token uniquement) :
1. **Plancher 10pt** : plus aucun texte user-facing sous 10pt (furigana du rang RPG, labels kicker/breakdown 8-9pt → 10pt, tracking réduit si besoin).
2. **Jauges 1pt → 2pt** : rails d'XP (Home, RPG, Summary) et progression de session. Les rails fusuma décoratifs et les dividers de rows restent à 1pt — c'est voulu.
3. **paperGhost réservé au chrome décoratif** : traductions de proverbes, « X XP to next rank », hints de déblocage Étude, description de Sakura, gloss des topics, aide settings → `ikeruTextSecondary` (#B8B5B0). Les eyebrows kanji, suffixes 札/分/%, dates JP, labels uppercase trackés restent ghost.

---

## 3. Consignes appliquées (à respecter pour la suite)

- **Vocabulaire Tatami obligatoire** sur toute surface carte : 0px de radius, `tatamiRoom` / `sumiCorners` / `FusumaRail`, jamais de `RoundedRectangle` sur du chrome de carte. Réf : `docs/design-specs/2026-04-29-tatami-direction.md`.
- **Vermillon `#C73E33` = hanko uniquement**, une fois par écran max. Pas de nouvelles couleurs hors `TatamiTokens` / `Color.ikeru*` / `IkeruTheme`.
- **Aucun changement de comportement/ViewModel** : tout ce pass est du chrome visuel + suppression de code mort. Seule exception : les seuils d'achievements (lecture de signaux VM existants, pas de modif du VM).
- **Localisation (gotcha CLAUDE.md)** : `Text("littéral")` → lookup catalogue ; `Text(variable)` → verbatim. Aucune nouvelle string user-facing n'a été ajoutée ; aucune entrée xcstrings nécessaire.
- **Posture produit** : anti-gamification sur les surfaces d'étude (« no streaks, no gems, no daily login pressure ») — d'où la suppression de la carte STREAK.

---

## 4. Reprise sur Mac — checklist

```bash
git fetch origin claude/app-screen-design-viz-kvs1a5
git checkout claude/app-screen-design-viz-kvs1a5

# 1. Compile iOS (AUCUNE des modifs n'a été compilée)
xcodebuild build -project Ikeru.xcodeproj -scheme Ikeru \
  -destination "generic/platform=iOS" -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO

# 2. Tests Core (subset vert, cf. CLAUDE.md)
cd IkeruCore && swift test --filter "<voir le --filter du workflow CI>"
```

**QA visuelle au simulateur** (les points à vérifier, dans l'ordre de risque) :
1. **Conversation** : bulles lisibles dans un vrai fil (contraste user vs companion), avatar 桜 carré net à 44pt ET 32pt, pas de clipping du PhaseAnimator.
2. **Home** : le retrait de la rangée stats ne laisse pas de trou bizarre entre daily-term et breakdown ; spacing `lg` cohérent.
3. **Overlays de session** (pause, empty) : `.tatamiRoom(.glass)` rend bien en overlay flottant centré — c'est le remplacement le plus risqué visuellement (tatamiRoom force `maxWidth: .infinity`).
4. **Settings → Display** : la row Interface Tatami s'aligne avec les rows voisines, caption d'aide sur une ligne.
5. **RPG** : hanko achievements cohérents avec un profil réel (compte neuf = tout en pointillés sauf rien).
6. **Lisibilité** : labels 10pt OK sur petit écran, jauges XP 2pt visibles, textes dé-ghostés pas trop clairs sur le marbre.

**CI** : ne tourne que sur push `dev`/`master` ou PR vers `dev`/`master` → ouvrir une **PR `claude/app-screen-design-viz-kvs1a5` → `dev`** pour déclencher lint + builds + tests.

---

## 5. Backlog restant (issu de la review DA, non traité dans ce pass)

Par ordre de priorité recommandé :

1. **Doctrine des reward screens** : `LevelUpView` / `LootRevealView` sont du pur « gamification theatre » (particules, glow, LEVEL UP!) en contradiction avec le brief « no gamification theatre ». À trancher : assumer et documenter, ou re-designer en célébration kintsugi/wabi-sabi.
2. **Unifier `ChatBubbleView` et `ConversationBubbleView`** en un seul composant paramétré (deux implémentations stylées séparément = divergence garantie ; ce pass les a alignées visuellement mais pas fusionnées).
3. **Topics suggérés du Companion** : 4 topics hard-codés (`CompanionTabView` ~l.335) — câbler sur de vraies données ou assumer une liste curatée.
4. **Dynamic Type** : tout est en `.system(size:)` fixe. Plan partiel à minima (les surfaces de lecture longue d'abord).
5. **Settings long** (7 sections sur un scroll) : envisager un regroupement ou des sous-pages.
6. **Archiver `docs/design-review/`** (brief + 15 screenshots pré-Tatami) ou les marquer « historical » — ils décrivent une app qui n'existe plus.
7. Mineur : seuil de suggestion Tatami utilise « streak ≥ 21 jours » (`DisplayModeAdvancedThresholdMonitor`) alors que le produit est anti-streak.

---

## 6. Méthode de visualisation sans simulateur (réutilisable)

Pour « voir » un écran depuis un environnement sans Xcode : réplique HTML/CSS construite depuis le code SwiftUI (tokens exacts de `IkeruTheme`/`TatamiTokens`, vrai PNG marbre du repo, Noto Serif JP via Google Fonts), rendue avec Playwright/Chromium en 393×852 @3x. Fidélité ~90-95%. Les fichiers de la session vivaient dans `/tmp/ikeru-viz/` (non versionnés) ; le pattern est trivial à recréer au besoin.
