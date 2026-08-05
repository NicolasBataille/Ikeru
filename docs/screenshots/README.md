# Ikeru — Screenshot Inventory

Captures réalisées via mobai MCP sur iPhone réel (iPhone de Nikou,
iOS 26.4.2). Profil "Nikou", 第1段 (rank 1, 0 reviews avant capture).
Branche : `design/wabi-refinements`.

## Captures par flow

### Launch / Onboarding (3/7 — partiel)

| # | Fichier | Description |
|---|---------|-------------|
| 01 | `01-launch-animation.png` | Animation de lancement (fade-in logo) |
| 01b | `01b-launch-logo-ikeru.png` | Logo Ikeru avant onboarding |
| 02 | `02-name-entry-fr.png` | OnboardingTour — saisie du nom (FR) |

**Manquent** : `OnboardingTour` pages 1/2/3 (Your Journey / Your Companion /
Begin), `AISetupView`. Bloqué car profil déjà créé sur l'iPhone — il faudrait
soit reset l'iPhone, soit recapturer sur simulateur avec fixtures
(`-mockProfile -mockDue=20 -mockLevel=1` + uninstall préalable).

### Onglets principaux (mode beginner — défaut)

| # | Fichier | Description |
|---|---------|-------------|
| 10 | `10-home-fr.png` | Accueil — proverbe du jour + CTA "Commencer" |
| 10b | `10-home-real-device.png` | Variante Accueil sur l'iPhone réel |
| 11 | `11-chat-companion.png` | Parler — Sakura + sujets suggérés |
| 12 | `12-etude-practice-ground.png` | Étude — 「稽古場 Practice ground」grid |
| 13 | `13-rang-rpg-profile.png` | Rang — XP, distinctions, prochain grade |
| 14 | `14-reglages-settings.png` | Réglages — préférences |

### Onglets principaux (mode Tatami — `Interface Tatami = Activé`)

Tabbar passe de `Chat / Étude / Accueil / Rang / Réglages` à
`対話 / 辞書 / 稽古 / 段位 / 設定`. Headers de section en kanji
(稽古 · PRATIQUE, 表示 · DISPLAY, 記憶 · ALGORITHME DE MÉMOIRE…).

| # | Fichier | Description |
|---|---------|-------------|
| 15 | `15-settings-tatami.png` | Réglages — headers Tatami |
| 16 | `16-home-tatami.png` | Accueil — proverbe 一心不乱 + 第1段 |
| 17 | `17-etude-tatami.png` | Étude — grid Kana / Kanji / Vocabulaire / Écoute |
| 18 | `18-rang-tatami.png` | Rang — 第一段 NOVICE, 又/財/力 stats |
| 19 | `19-chat-tatami.png` | Parler — Sakura、ta senseï |
| 20b | `20-etude-tatami-scrolled.png` | Étude scrollée — types verrouillés + 編成 CTA |

### Session active (Kana drill)

| # | Fichier | Description |
|---|---------|-------------|
| 20 | `20-active-session-kana-flashcard.png` | Flashcard face cachée |
| 21 | `21-card-review-revealed-grades.png` | Carte révélée + boutons 再/難/良/易 |
| 22 | `22-session-quit-confirm.png` | Modal de confirmation "Quitter la session ?" |
| 23 | `23-session-summary.png` | Récap session — XP gagnés + détail |

### Overlays / sheets

| # | Fichier | Description |
|---|---------|-------------|
| 14b | `14-companion-chat-sheet.png` | Sheet Sakura Compagnon d'étude (bouton flottant) |
| 21b | `21-compose-session-sheet.png` | Sheet 編成 Composer une session — état initial |
| 22b | `22-compose-session-selected.png` | Sheet 編成 — Kana / N5 / 15 min, CTA actif |

## Inventaire vs spec (Spec A — Learning Loop)

Couverts :
- ✅ Étude « 稽古場 Practice ground » grid (4 unlocked + tiles verrouillées)
- ✅ Sheet « 編成 Composer une session » avec types / niveaux JLPT / durée
- ✅ Mode Tatami complet (5 onglets + variantes)
- ✅ Session drill complète (carte → grades → quit modal → summary)
- ✅ Sakura Compagnon overlay

Manquants (bloqués par état progression) :
- ⛔ Détails Réglages — Objectif quotidien, Son, FSRS, Rétention, Intervalle
  max (toutes les rows sont `[disabled]` au rang 1)
- ⛔ Sheets RPG — Lootbox open, Item detail, Level-up, Achievements
- ⛔ Pool selector Kana (`KanaPoolSelectorView`) — Quiz Kana
- ⛔ Drills par type — Vocabulaire / Kanji / Reading / Speaking / Writing /
  Listening
- ⛔ Onboarding complet (3 tour pages + AISetupView)

Pour capturer les manquants, prochaines étapes possibles :
1. Build DEBUG sur simulator avec `xcrun simctl launch booted com.ikeru.app
   -mockProfile -mockLevel=15 -mockDue=20 -mockMastered=120 -mockLootboxes=3 -mockInventory=8`
2. Driver via XCUITest target dédié (contourne la restriction Tahoe sur
   clics synthétiques) **OU** Pro tier mobai (autorise 2+ devices simultanés)
3. Naviguer sur chaque écran restant, capturer via `xcrun simctl io booted screenshot`

## Bugs détectés

### `BUG-1` — Composer Kana N5 → écran noir permanent

**Repro** : Tatami activé → Étude (辞書) → scroll bas → `編成 Composer une
session` → sélectionner « Kana » → laisser N5 / 15 min → COMPOSER.

**Résultat** : Sheet se ferme, écran complètement noir, aucun élément
accessible dans l'UI tree, plus aucune interaction possible (force-quit manuel
requis pour sortir).

**Suspect** : `SessionViewModel` / `SessionPlanner` ne gère pas le cas
« composer demande Kana N5 mais aucune carte Kana N5 n'est due » — au lieu
d'un état vide / message, retourne une view crash silencieux.

**Repro reliable** : oui (état rank 1 / 0 reviews).

**Fichiers à inspecter** :
- `Ikeru/ViewModels/SessionViewModel.swift` — startComposedSession ou équivalent
- `IkeruCore/Sources/Services/SessionPlanner.swift` — gestion empty pool
- `Ikeru/Views/Session/SessionView.swift` — fallback empty state

## Méthode

- Device : iPhone de Nikou (iPhone 15 Pro), iOS 26.4.2
- Bridge : mobai MCP daemon @ 127.0.0.1:8787
- Commande screenshot : `mcp__mobai__save_screenshot` (full-res PNG)
- Navigation : `mcp__mobai__execute_dsl` avec `action: tap` + predicates
  (`text_contains`, `type`)
- Date de capture : 2026-05-14
