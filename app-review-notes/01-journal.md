# Journal de la review

Journal chronologique des sessions de travail. Les entrées les plus récentes
sont ajoutées en haut.

---

## 2026-08-12

**14:00** — Clôture définitive — causes racines Round 4. Le dev-relais
confirme et affine : OBS-029 = deux bugs (réglage furigana menteur lié à la
fuite Tatami — chaîne reconstituée sur 3 rounds/3 surfaces — et cartes de
correction sans passage par le composant ruby) ; porte N4 confirmée non
appliquée (refonte "no locked tiles"). Reco Sakura ré-ordonnée : (1) ruby sur
cartes de correction, (2) réparer réglage furigana + fuite Tatami
inter-profils, (3) heure dans le prompt, (4) langue des explications. Le
presenter transmet à Nico : 30 observations, 4 bloquants, ratio 17/6
implémentation/conception — « un produit à brancher, pas à repenser ». Round
5 éventuel (retest post-P0) facilité à terme par une spec de synchro cloud
incluant une bibliothèque d'états d'apprenant nommés (bancs de fixtures).
Review close.

**09:15–13:50** — Round 4 — test Sakura en direct (clé Gemini de test).
Clé de test fournie par le dev, validée au préalable par curl (HTTP 200,
gemini-2.5-flash). Conformément à la règle de sécurité de la review, le
reviewer ne saisit aucun credential : c'est le dev qui a saisi la clé dans
l'app (écran Fournisseurs IA). Stockage vérifié en Keychain sans
ré-affichage de la clé (indicateur vert + bouton Supprimer seulement).
Conversation complète testée sur le profil Nico (N5) : amorce en français,
message avec erreurs de grammaire combinées (昨日に + mauvais temps),
message avec erreur de registre (俺+です), question ouverte en français
(test de dérive de niveau), demande explicite de mot ([VOCAB]). Un échec
réseau survenu en cours de test (« Sakura n'a pas pu répondre » + bouton
Réessayer, retry réussi ensuite) — message générique conforme à la
taxonomie d'erreurs, pas le message « clé refusée » attendu en cas de clé
invalide. Constat d'accès notable : la conversation Sakura s'ouvre depuis
l'onglet Étude SANS que la porte N4 ne bloque quoi que ce soit — la porte ne
semble s'appliquer qu'au planificateur de séance, pas à l'entrée directe
(nuance apportée à OBS-018). Détail du parcours dans
[`02-decouverte-app.md`](02-decouverte-app.md), nouveaux constats
OBS-029/OBS-030 dans [`03-observations.md`](03-observations.md), synthèse
amendée dans [`06-synthese.md`](06-synthese.md).

---

## 2026-08-10

**19:25** — Clôture de la review. Le dev-relais confirme et clôt : cause
racine des accents faux identifiée (contenu plié pour remplir une grille
« 2 exemples par patron » — la version la plus grave de la pathologie
récurrente « intention correcte, exécution qui ne suit pas », car appliquée
au contenu enseigné). La synthèse (partage 17 implémentation / 6 conception,
« prises déjà posées », correctifs qui renforcent l'identité
anti-gamification) est transmise à Nico. Relevé côté dev (vérifications
code) : `docs/reviews/2026-08-10-expert-japonais-echange.md`. Bilan
méthodologique acté par les deux parties : 1 seule erreur d'analyse du
reviewer sur la soirée (dakuten pris pour un bug d'affichage alors que
contenu absent). Round 4 possible (retest post-P0 + Sakura avec clé) — à la
décision de Nico. Review close.

**19:05–19:20** — Round 3 (suite) — dictionnaire, confiance, verdict
accents. Vérification linguistique OJAD/Wiktionary-NHK terminée : les 2
erreurs d'accent du drill Watch sont CONFIRMÉES (犬 = [2] 尾高型, app affiche
頭高型 ; 男 = [3] 尾高型, app affiche 中高型) ; les 6 autres mots sont exacts ;
OBS-024 reclassée BLOQUANT confirmé. Tests confiance : export vide
(OBS-027), pas de suppression de profil (OBS-028), multi-profils
fonctionnel avec restauration correcte. Synthèse finale rédigée dans
[`06-synthese.md`](06-synthese.md) — review terrain terminée.

**08:25–08:40** — Round 3 — test de l'app Watch. App Watch testée sur
simulateur Apple Watch Series 11 (46mm), build autonome fourni par le dev
(sync iPhone non testable — attendu). Deux nano-sessions testées
intégralement : Kana Quiz (10 QCM) et Pitch Accent (8 mots). Interface
entièrement en **anglais** (Kana Quiz / Pitch Accent / Nice work! / Again)
sur environnement FR — même défaut i18n que le widget. Détails dans
[`02-decouverte-app.md`](02-decouverte-app.md), constats OBS-022 à OBS-025
dans [`03-observations.md`](03-observations.md).

**02:00** — Analyse Round 2 livrée au dev. Verdicts d'expert transmis sur les
portes de déverrouillage et l'architecture Sakura/planificateur :
- Claim Tadoku (« 100 mots + 50 kanji ≈ 95 % de couverture L0 ») : NON
  soutenable — les seuils de couverture 95/98 % exigent des milliers de
  familles de mots (Laufer 1989, Hu & Nation 2000, Nation 2006) ; tadoku.org
  ne publie pas de définition chiffrée du L0. Correctif proposé : mesurer la
  couverture réelle sur le corpus embarqué de l'app et citer ce chiffre.
- « Swain » comme justification de seuils numériques : habillage —
  l'hypothèse de l'output n'énonce aucun nombre. Reco : assumer les seuils
  comme heuristiques produit instrumentées, retirer les noms propres.
- Politique réceptif-avant-productif : défendable comme direction,
  calibration arbitraire (i+1 non opérationnalisable — Gregg 1984 via
  Lichtman & VanPatten 2021).
- Porte Sakura : reco = déblocage par scénarios (première conversation
  guidée tôt), le prompt contraint déjà le niveau JLPT donc la porte N4
  protège contre un risque déjà mitigé.
- BYO-clé API : indéfendable pour une fonctionnalité phare grand public ;
  reco n°1 = mode scripté offline (dialogues arborescents N5 + audio
  VOICEVOX embarqué) avec la clé comme enhancer.
- LLM correcteur : partenaire oui, professeur non ; garder corrections en
  recast ; risque principal = fluidité illusoire ; littérature émergente,
  rien de robuste (marqué en biblio).
- Préférence vocabulaire souple : bon choix, ne pas durcir vers i+1 chiffré.
- Planificateur : défaut structurel = les quotas écrêtent les révisions
  dues FSRS (dette de rétention silencieuse) ; reco : dues prioritaires en
  absolu, quotas sur le reste ; profils par stade (lancement/construction/
  croisière) ; ratio 10:1 chez Anki = conséquence émergente, pas
  prescription ; entrelacement bon défaut pour la discrimination kana
  (Rohrer & Taylor 2007) avec contre-exemple L2 honnête (Carpenter &
  Mueller 2013) → introduire en mini-bloc, réviser en entrelacé ; durées
  estimées à recalibrer par maturité de carte.
- Raffinement de la reco (e) du Round 1 suite biblio : « un step, pas des
  steps » (Karpicke & Roediger 2007 : steps multiples utiles seulement à
  ~10 min ; Rawson & Dunlosky : critère d'1 rappel réussi).
- Correction auto-appliquée : « N5 ≈ 800 mots » = listes communautaires (JF
  ne publie plus depuis 2010).
- Prochaine étape (Round 3) : confirmation tracés kana, test des exercices
  non-placeholder (écoute sous-titrée), app Watch, puis synthèse finale.

**01:45** — Réponses Round 1 du dev reçues : Tatami confirmé cosmétique par
le code (11 consommateurs de displayMode, aucune vue d'apprentissage sauf
bulles Sakura ; 3 labels kanji sur 8 faux), libellé héro = design
intentionnel, seeder confirmé condamné (recto 人0/日1…), tracés KanjiVG 90/90
vérifiés pour kanji (kana à confirmer), w17/w18 = moitié de chaîne
(implémentés, jamais alimentés). Round 2 reçu (matériel d'architecture) : 12
portes sans citation dans le code (aveu du dev), Sakura structurellement
inatteignable (porte N4, contenu N5) → OBS-018 BLOQUANT, routeur IA 8
niveaux (Gemini seul en pratique sur A16), planificateur 40/30/20/10
entrelacé. Analyse expert en cours ; vérification du claim Tadoku déléguée
au documentaliste (Dossier C).

**01:10–01:30** — Round 1 — tests J+30/J+90, Tatami, katakana. Outils dev
explorés en détail (Réglages → Outils dev → Developer Tools, écran en
anglais) : sliders Seed fixture profile (bornes Level 30 / Due 50 / Mastered
200 ; ne persistent pas d'une visite à l'autre), boutons Wipe profile, Force
level-up, Clear asset cache, Build info. Deux seeds appliqués avec succès
(confirmation « ✓ Seeded ») : « lvl 4, 15 due, 40 mastered » puis « lvl 30,
50 due, 200 mastered ». Le fixture s'est révélé fortement limitant pour
évaluer un état avancé réaliste (OBS-013) : cartes kanji placeholder (recto
足, verso « reading-14 »), écrase le prénom du profil (Louis → Nico), vide
le dictionnaire de vocabulaire (le mot ajouté au Round 0 disparaît), remet à
zéro les flags de tutoriels (tutoriel de geste + tooltips Sakura
re-déclenchés) et « Jours actifs », et ne touche PAS aux kana (tous les
groupes restent à Maîtrise 0%). Interface Tatami déverrouillée après le seed
max (« Progression Tatami : Prêt », Révisions 750/750, Cartes maîtrisées
250/75, Jours actifs 0/30 — le critère jours actifs affiché n'est donc pas
exigé par le déblocage réel) ; toggle activé et exploré (OBS-015). Katakana
atteints via la rangée de presets du sélecteur kana (Hiragana — base /
Hiragana — complet / Katakana — base / Katakana — complet / Tous / Effacer,
scrollable horizontalement) ; groupes présents avec caractères + romaji
(S/T/N/H/M/Y/R/W-N vus), aucun traitement de la transition hiragana→katakana
constaté (OBS-017). Navigation : deux écrans confirmés sans bouton retour ni
geste de sortie (« Entraînement aux kana » et « Cache & préchauffage », voir
OBS-012) — à distinguer des taps perdus après scroll, récurrents mais
imputés au pilotage desktop (environnement, pas bug de l'app).

**01:05** — Réponses du dev-relais reçues (vérifiées par lui dans le code
source) : 6 de nos 7 questions correspondent à des dettes réelles. Faits
marquants : (1) dakuten/yōon = contenu absent avec TODO, pas bug d'affichage
→ OBS-001 reclassée BLOQUANT ; (2) "appris" structurellement immobile le jour
1 (garde-fou juste, communication manquante) ; (3) 67% = accident confirmé ;
(4) pas d'audio auto (447 clips VOICEVOX embarqués inexploités au flip) ; (5)
pas de learning steps intra-jour (FSRS-5, intervalles ≥ 1j) — notre avis
d'expert demandé ; (6) terme du jour : jlptLevel jamais consulté ; (7)
XP/niveaux orphelins (OBS-010). Brief produit reçu : thèse « app unique 4
compétences, FSRS-5, planificateur adaptatif 40/30/20/10, 12 types
d'exercices à déverrouillage progressif, philosophie anti-burnout (zéro
streak, zéro ligue, jour de repos qui retire le CTA) ». Faiblesses admises
par le dev (ne pas re-prouver) : contenu limité (206 mots, 31 points de
grammaire, 90 kanji, 96 phrases vs ~800 mots pour un N5), 3 types
d'exercices en placeholder (grammaire, texte à trous, passage de lecture).
Round 1 lancé : J+30/J+90 via fixtures, Tatami, katakana, conception de la
phase de présentation manquante, verdict sur l'absence de learning steps.
Piège connu : bouton Level-up inobservable ; plafond kana réel = 92.

**00:35** — Préparation de l'environnement de test. L'outil `idb` n'étant pas
disponible, le pilotage du simulateur se fait via computer-use (clics dans la
fenêtre Simulator) complété par des captures `simctl`. Simulateur utilisé :
iPhone 17 Pro (iOS 26.4), device configuré en `fr_FR`.

Incidents d'environnement rencontrés (à ne **pas** confondre avec des bugs de
l'app) :
- Rendu du simulateur gelé à un moment, causé par un crash `SimMetalHost` côté
  macOS — l'app a reçu un `SIGABRT` avec le message « Connection to
  SimMetalHost lost » (infrastructure Metal du simulateur, pas l'app).
- Saisie clavier hardware inopérante par moments (clavier AZERTY : la frappe
  de « Camille » produisait « Q ») — contourné en copiant le texte dans le
  presse-papiers puis en collant avec Cmd+V.
- À part, un crash **IkeruWidget** de type `EXC_GUARD`
  (`XPC_EXIT_REASON_FAULT`) observé à 00:41:39 — celui-ci concerne
  possiblement l'app elle-même (le widget) et est à signaler au développeur
  (voir OBS-008).

Faux départ : le tout premier lancement est tombé directement sur le profil
personnel avancé du développeur (« Nikou », 3/92 kana appris, niveau 4) au
lieu d'un profil vierge. Le dev-relais a désinstallé puis réinstallé l'app
pour repartir sur un container vide, et le Round 0 a été rejoué intégralement
depuis zéro. Les observations faites sur ce profil avancé, avant la remise à
zéro, sont conservées et étiquetées séparément de celles du parcours
débutant (voir [`02-decouverte-app.md`](02-decouverte-app.md)).

**00:44–00:56** — Round 0 complet exécuté en persona « débutant absolu »
(profil « Louis ») : onboarding → visite guidée → sélection des kana → 1re
session SRS (6 cartes, 3:08) → résumé de séance → mot du jour → exploration
de l'onglet Étude. Détail du parcours dans
[`02-decouverte-app.md`](02-decouverte-app.md), constats correspondants dans
[`03-observations.md`](03-observations.md).

---

Initialisation du dossier de notes. En attente de la présentation de
l'application par le développeur. Aucun test effectué à ce stade.
