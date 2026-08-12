# Échange avec un relecteur « expert apprentissage du japonais »

> Date : 2026-08-10 · Interlocuteur : instance Claude Code `reviewer`, sans accès
> au code source, testant l'app sur simulateur iOS.
> Objectif : se faire challenger sur 100 % de l'app — UI/UX, contenu,
> méthodes d'apprentissage. Bienveillant mais honnête.
> **Aucune modification de code pendant cet échange.** Ce fichier est le relevé
> des retours ; le tri et le plan d'action viendront après.

## Comment lire ce document

- **[R]** = retour du relecteur (sa voix, son verdict).
- **[C]** = contexte / intention de design que je lui ai donnée en réponse.
- **[!]** = point où sa critique tient malgré l'explication → dette réelle.
- **[≈]** = point où l'explication a levé la critique → à documenter, pas à corriger.
- **[?]** = désaccord non tranché, ou besoin d'une décision produit de Nico.

---

## Statut de l'échange

- [ ] Round 0 — mise en place, premières impressions à froid
- [ ] Round 1 — onboarding & premier contact
- [ ] Round 2 — moteur SRS / FSRS
- [ ] Round 3 — composition de session
- [ ] Round 4 — kana
- [ ] Round 5 — vocabulaire & kanji
- [ ] Round 6 — grammaire
- [ ] Round 7 — écoute, oral, accent tonique
- [ ] Round 8 — écriture & ordre des traits
- [ ] Round 9 — Sakura / IA conversationnelle
- [ ] Round 10 — motivation, RPG anti-gamification, rétention
- [ ] Round 11 — volume de contenu & échelle JLPT
- [ ] Round 12 — Watch, widgets, surfaces annexes
- [ ] Round 13 — apprenant francophone / i18n
- [ ] Round 14 — accessibilité
- [ ] Round 15 — synthèse & priorisation

---

## Notes

### Round 0 — mise en place

**Incident de départ (2026-08-10).** Le relecteur a ouvert l'app et est tombé
directement sur le **profil personnel « Nikou », déjà entamé** : pas d'onboarding,
et une trentaine de minutes d'observation faites du point de vue d'un utilisateur
avancé au lieu du débutant demandé.

Corrigé par `simctl terminate → uninstall → install` du même binaire (container de
données vierge, y compris les flags `UserDefaults` d'onboarding — plus radical que
le bouton « Wipe » des outils dev, qui ne les remet pas forcément à zéro).

**[?] Question ouverte née de l'incident** — à vérifier au relancement : une
réinstallation propre doit-elle bien ramener l'onboarding complet (prénom →
3 slides → setup IA → visite guidée) ? Si non, c'est un bug de premier ordre :
un utilisateur qui réinstalle se retrouverait sans parcours d'entrée.

**[?] Test involontaire de lisibilité de la progression.** Le relecteur a été
posé sans contexte devant un compte avancé. Question posée : a-t-il pu deviner
son niveau supposé, ce qui était « appris », ce qui restait ?

**[!] Réponse : NON.** Devant le compte avancé il n'a pas pu reconstituer où il
en était — « 9 AUJOURD'HUI » sans unité (cartes ? minutes ?), le niveau RPG
visible **uniquement sur le widget** (« Lv. 4 ») et nulle part dans l'app,
« 3/92 appris » seul signal cumulatif. Test à froid réussi… par l'échec.

**[≈] Onboarding après réinstallation : OK.** prénom → question de niveau →
3 slides → dashboard + visite guidée. Le parcours d'entrée survit bien à une
réinstallation.

---

### Round 0 — premières impressions à froid (parcours débutant complet)

Parcours joué : profil « Louis », « Je débute », défauts partout, 1re session
complète (5 voyelles + 6 revues, 3:08), mot du jour, onglet Étude.

#### Le verdict de fond

**[!] « Est-ce que l'app enseigne, ou est-ce qu'elle fait réviser ? »**
Après une session il penche pour **« elle fait réviser »**. Aucun moment
d'instruction : pas de leçon, pas de tracé, pas de mnémonique. Et surtout :

> **La première carte est un test, pas une leçon.** On demande de « toucher pour
> révéler » un caractère jamais vu, puis de s'auto-noter. **La note initiale est
> du bruit** — l'apprenant ne peut qu'échouer ou mentir.

Atténuants qu'il reconnaît lui-même : la révélation enseigne (glyphe + romaji +
audio) et « Encore » re-présente la carte en fin de session (vérifié sur あ).
Mais l'absence de phase de présentation reste **son point n°1**.

**[!] Écart promesse / périmètre.** La slide promet « de curieux à courant » ;
ce qui est livré est « de curieux à **lecteur de kana** ». À justifier ou à
retitrer. (Note : la trad FR « Un chemin de curieux à courant » est en plus un
calque cassé, déjà relevé au pass device et toujours non corrigé.)

**[!] La 1re session ne laisse aucune trace.** Après 6 revues : « かな 0/92
APPRIS », « PROCHAINE ÉTAPE 0/46 », « Tout est à jour — savoure le calme ».
Un débutant finit sa première séance avec **tous les compteurs à zéro** et un
message qui lui dit qu'il n'y a plus rien à faire. Le seuil d'« appris » n'est
jamais défini nulle part.

#### Ce qu'il a réellement appris (sa mesure, honnête)

Acquis : reconnaît (fragilement) あいうえお ; comprend l'organisation en gojūon ;
sait ce que sont dakuten et yōon **grâce aux micro-textes du sélecteur** ; sait
faire le geste SRS.
Non acquis : **prononcer** (audio = bouton optionnel), **écrire** (aucun tracé),
et **pourquoi** revoir あ demain (la mécanique SRS n'est jamais motivée).

#### Défauts précis relevés

- **[!] Groupes Dakuten (G/Z/D/B/P) et yōon (KY/SH/CH/NY/HY/MY) vides** dans le
  sélecteur — cartes sans aucun caractère. Impossible de voir le contenu avant
  de cocher.
- **[!] « 67 % RAPPEL » compte « Difficile » comme un échec** — incohérent avec
  la sémantique des boutons.
- **[!] Mot du jour non trié par niveau** : ポカヨケ servi à un débutant J0 —
  jargon industriel, en katakana, à quelqu'un qui a vu 5 hiragana. Fiche exacte
  et belle, mais la note culturelle parle de « pipelines CI » : **écrit pour des
  développeurs, pas pour l'audience d'une app de japonais**.
- **[!] Fuites i18n** : header « Explore » en anglais (device FR), widget en
  anglais (« 3 due », « Lv. 4 »).
- **[?]** Suffixe 札 des compteurs opaque.
- **[?]** Proverbe 七転八起 sans lecture ni furigana → japonais purement décoratif.
- **[!] Crash `IkeruWidget` EXC_GUARD / XPC_EXIT_REASON_FAULT** (icône + widget
  disparus brièvement de l'écran d'accueil). Les SIGABRT de l'app sont, eux, du
  SimMetalHost — infra simulateur, pas le code.

#### Ce qui est bon — à ne pas casser

- **Intervalles prévisionnels sous les 4 boutons** (1j/2j/4j/16j). Transparence
  rare hors Anki.
- **Re-queue intra-session des ratés.**
- **Les micro-textes du sélecteur (gojūon / dakuten / yōon)** — « la meilleure
  écriture didactique de l'app », exacts, concis, en vrai français.
- Les **3 modes de pratique** + tooltips Sakura en progressive disclosure à la
  2e visite ; « pratique libre compte quand même » = bonne décision.
- **Demande de notifications APRÈS un premier succès**, avec pre-prompt
  contextuel — « manuel du bon goût ».
- **La DA** : cohérente, identitaire, apaisée. Onboarding en 2 questions.

---

### Vérifications dans le code — réponses à ses 7 questions

> C'est ici que l'accès au source tranche ce que le test seul ne peut pas
> décider : **choix de design** ou **accident**.

**1. Seuil d'« APPRIS » — [!] sa critique tient, et le problème est structurel.**
`KanaProgress.from` compte les cartes `.familiar` ou mieux. Or
`MasteryLevel.from` exige **`reps >= 2` ET `stability >= 1.0` ET aucune rechute
< 2 j**. Une première session donne `reps = 1` → `.learning` → **le compteur ne
peut mathématiquement pas bouger le jour 1**. Le garde-fou est délibéré (commenté
dans le code : empêcher qu'un seul tap « Facile » promeuve une carte et gonfle
les portes de déverrouillage). **Le garde-fou est juste ; c'est la communication
qui est fausse** — il manque un palier intermédiaire « 5 en cours
d'apprentissage » entre 0 et « appris ».

**2. Audio auto au flip — non, aucun déclenchement automatique** à la révélation
dans `KanaFlashcardView`. C'est un bouton. → **[!] pour un syllabaire, apprendre
le glyphe sans le son est une amputation** ; son point tient.

**3. Dakuten / yōon vides — [!] ce n'est pas un bug d'affichage, c'est du contenu
absent.** `KanaGroup.characterTable` déclare ces groupes en **tableaux vides**,
avec un `TODO: populate dakuten (g/z/d/b/p) and yōon` en clair. Les 92 du
dénominateur = **46 hiragana + 46 katakana de base uniquement**. Donc : ~20
groupes affichés sont **définitivement vides et inapprenables**, et — plus grave —
**les micro-textes qu'il a salués comme la meilleure pédagogie de l'app décrivent
un contenu que l'app ne possède pas.** Le japonais réel est illisible sans
dakuten ni yōon : c'est un trou de couverture, pas une finition.

**4. « Difficile » compté en échec — [!] accident confirmé, pas un choix.**
Deux compteurs divergent dans le même fichier :
- `missedCardIDs` (rejeu des erreurs) : seul `.again` compte comme erreur, avec
  un commentaire explicite « a `.hard` grade means the recall was slow but
  ultimately correct » ;
- `correctCount` (qui pilote le % de rappel) : `isCorrect = grade == .good ||
  grade == .easy` → **`.hard` tombe en échec**.

L'intention écrite dans le code est « hard = réussite » ; `isCorrect` n'a pas
suivi. Son 4/6 s'explique exactement : 1 « Encore » + 1 « Difficile ».

**5. Étape « setup IA » — [!] c'est MOI qui ai eu tort, pas l'app.** Le parcours
réel est `NameEntryView → OnboardingTourView → dismiss`, sans setup IA. Mon brief
venait de la review de juillet, antérieure au passage à 3 onglets. **À retenir :
mes briefs doivent être vérifiés dans le code courant, pas dans les docs.**

**6. Ligne éditoriale du terme du jour — [!] sa critique tient.** 57 candidats.
`DailyTermCandidate` **porte bien un champ `jlptLevel`**… que `DailyTermService`
**ne consulte jamais** : la sélection ne score que sur saison / jour de semaine /
tags. Le filtrage par niveau est *possible* dans le modèle et *absent* dans
l'algorithme.

**7. Système de niveaux — [!] orphelin.** Aucune surface RPG dans l'app :
3 onglets (Explore / Practice / Settings), pas d'onglet RPG. `HomeView` porte
même le commentaire « was keyed to RPG level, **now removed** ». Le niveau
n'existe donc plus que **sur le widget**. XP, loot et niveaux tournent toujours
en arrière-plan sans destination visible. → **décision produit à prendre : ou on
réexpose, ou on retire.**

**Widget crash** — entitlements app et widget cohérents (`group.com.ikeru.shared`
des deux côtés), donc pas un décalage d'app group. `os_fault_with_payload` +
`LIBXPC / XPC_EXIT_REASON_FAULT`, **3 occurrences répétées** (00:51:01, 00:51:16,
00:51:57) en plus de la sienne à 00:41:39 → reproductible, à investiguer.

---

### Round 1 — états J+30/J+90, Tatami, katakana, et les deux propositions de fond

#### [!] OBS-013 — Le seeder fixture est inutilisable (bloquant pour toute la QA)

Sa trouvaille la plus importante côté outillage, **confirmée et pire que ce qu'il
a vu**. `TestFixtures.seedCards` :

- seed des **kanji placeholder** : `Card(front: "足", back: "reading-14", type: .kanji)` ;
- pour les cartes « maîtrisées », le recto est `"\(glyph)\(index)"` → **`人0`,
  `日1`, `目2`… ce ne sont même pas des caractères japonais valides** ;
- **aucun kana** n'est seedé → les groupes restent tous à 0 %, et le compteur
  かな X/92 reste bloqué à 0 quel que soit le slider ;
- `UserProfile(displayName: "Nico")` **en dur** → écrase le prénom saisi ;
- `reseed` appelle `wipeAll`, qui purge la clé de profil actif → **dictionnaire
  personnel vidé et flags de tutoriels remis à zéro** (d'où les tutoriels qui se
  rejouent « à J+30 »).

**Conséquence : la boucle de test J+30/J+90 ne fonctionne pas sur du contenu
réel.** À refondre (seeder de vrais kana avec un historique FSRS plausible) avant
toute réponse honnête sur la progression dans le temps.

#### [!] Aucune surface d'historique ni de statistiques

« C'est le même écran avec des chiffres plus gros. » Pas de courbe, pas de
journal de sessions, pas de « ce que je sais maintenant ». Les seules traces
cumulatives sont le % de maîtrise par groupe (enfoui dans le sélecteur) et les
barres Tatami (enfouies dans Réglages).

#### [!] Le verdict anti-burnout — sa formule est la synthèse du round

> « Tu as remplacé la pression par… rien. Ce n'est pas la thèse qui est fausse,
> c'est qu'elle n'est qu'à moitié implémentée : **tu as enlevé le fouet sans
> installer le miroir.** »

Zéro streak / zéro ligue : il valide sans réserve (cohérent avec la Self-
Determination Theory, compétence vs pression externe). Mais l'anti-burnout
**exige un substitut** : un « livret de compétence » (ce que je sais / ce qui
s'est consolidé cette semaine), pas du silence. Sans ça, la thèse prive le
débutant du seul signal qu'il pouvait avoir.

#### [!] Tatami — ne vaut pas (encore) l'attente

**Déblocage.** Il voit « Prêt » avec « Jours actifs 0/30 ». Vérifié : la règle est
`(révisions ≥ 750 ET maîtrisées ≥ 75) OU jours actifs ≥ 30` — un **OU**, avec
exclusion délibérée de tout critère de streak (cohérent avec la philosophie).
→ **La logique est juste, la présentation ment** : trois critères affichés comme
s'ils étaient cumulatifs alors que le troisième est une voie alternative.

**Contenu.** Confirmé par la liste des consommateurs de `displayMode` — **11
fichiers**, et parmi les vues d'apprentissage **seulement les deux bulles de chat
Sakura**. Zéro vue flashcard, zéro sélecteur de kana, zéro vue vocabulaire.
→ **Sur les cartes de révision, Tatami ne change strictement rien.** La promesse
d'onboarding « Kanji d'abord, traductions masquées » n'est pas tenue là où ça
compte. C'est un reskin de chrome vendu au prix de 750 révisions.

**[!] Audit linguistique des labels Tatami** — il repère 勘定 ; le code en compte
**trois douteux** (il n'a vu qu'une partie des sections) :

| Label | Section | Verdict |
|---|---|---|
| 稽古 | Practice | ✅ juste et beau |
| 表示 | Display | ✅ standard |
| 開発 | Dev tools | ✅ standard |
| 学習/練習/設定 | tab bar | ✅ idiomatiques |
| **勘定** | Account | ❌ = l'addition au restaurant → アカウント / 会員情報 |
| **倉庫** | Data & Storage | ❌ = entrepôt physique → データ / ストレージ |
| **関連** | About | ❌ = « en rapport avec » → 情報 / このアプリについて |
| 知能 | AI providers | ⚠️ poétique, non standard (人工知能 / AI) |

Son argument est décisif : **ce mode s'adresse au public qui verra l'erreur.**

#### [!] Katakana — pas de transition, juste plus de cartes

- La rangée du haut n'est pas des onglets mais des **presets de sélection**,
  scrollable et coupée au bord → « Tous »/« Effacer » invisibles sans scroll.
  Piège d'affordance (il a cru à des segments cassés pendant 5 minutes).
- **Rien sur les paires à interférence** (シ/ツ, ソ/ン) — la plaie classique.
- **Aucun pont « même son, nouvelle forme »** (か→カ) **alors que la donnée
  existe** : le romaji est identique des deux côtés.
- Aucun séquencement : un J0 peut cocher « Tous » = 92 cartes d'un coup.

Reco à coût quasi nul : cartes de **liaison** à l'introduction d'un katakana
(か grisé au-dessus de カ) + drills contrastifs sur les 4-5 paires piégeuses.

#### [★] (d) La phase de présentation manquante — sa proposition, à retenir

Honnêteté intellectuelle de sa part : il cite l'**effet de pré-test** (Kornell,
Hays & Bjork 2009 ; Potts & Shanks 2014) qui défend le flux actuel — **puis il
explique pourquoi il ne s'applique pas ici** : ces travaux portent sur du
matériel où la devinette a un ancrage sémantique. Devant あ, un débutant absolu
n'a rien à deviner ; le test est vide.

Séquence proposée pour un lot de 5 kana, **sans ajouter un seul tap** :

1. **Carte de présentation** (~15-20 s) : glyphe grand, romaji visible d'emblée,
   **audio en lecture automatique** (double codage — Paivio ; contiguïté
   multimédia — Mayer). Aucun bouton de notation : *on n'évalue pas, on rencontre*.
2. **Tracé animé une fois** — la capacité KanjiVG est déjà dans l'app (90/90 SVG).
   L'encodage moteur renforce la reconnaissance visuelle, pas seulement
   l'écriture (Naka & Naoi 1995 ; Longcamp et al. 2005).
3. **Lien discret « une astuce pour retenir ? »** — mnémonique par mots-clés
   (Atkinson 1975), optionnel pour préserver la sobriété.
4. **Premier rappel dans la même séance, 2-4 cartes plus loin** (pas en fin de
   file) : la carte devient une vraie mesure, et la première note FSRS un vrai
   signal (Landauer & Bjork 1978).

Coût : ~1 min 40 sur une séance de 5 min, **zéro tap supplémentaire** (le
planificateur entrelace déjà). Un template de carte à créer ; audio et tracé
sont déjà embarqués. → *« la modification au meilleur ratio impact/effort de
toute ma review »*.

**Et, indépendamment : l'audio doit jouer automatiquement à la révélation des
cartes de révision aussi.** Sa formule : *« 447 clips embarqués et le geste par
défaut ne les déclenche jamais. Pour un syllabaire — dont l'unique fonction est
d'encoder des SONS — un bouton optionnel, c'est un clavier optionnel sur une app
de dactylo. »*

#### [★] (e) Learning steps intra-jour — sa position

Il valide la cohérence FSRS (la position officielle est que les learning steps
classiques sont largement superflus), **mais relève deux failles propres à Ikeru** :

1. **w17/w18 sont des poids morts.** FSRS-5 les a introduits *précisément* pour
   modéliser les same-day reviews ; on les active, mais **aucun flux ne génère de
   same-day review** hors re-queue des « Encore ».
2. **Le re-queue ne protège que l'utilisateur lucide.** Le débutant type, devant
   un symbole qu'il vient de révéler, tape « Bien » (il vient de le voir !) →
   4 jours d'intervalle sur une trace de 3 secondes. Le lendemain c'est du
   **réapprentissage, pas de la révision**.

Sa position : **garder « intervalles ≥ 1 jour », mais imposer un critère de
sortie de séance** — toute carte NOUVELLE doit avoir produit **un rappel réussi
intra-séance** avant d'entrer dans le planning (successive relearning, Rawson &
Dunlosky ; l'espacement ne paie qu'après un encodage initial réussi — Cepeda et
al. 2006). Ce n'est pas un learning step chronométré à la Anki.

> **L'angle mort qu'il pointe :** « chaque matinée de débutant commence par une
> série d'échecs sur les items de la veille — c'est le contraire du calme que
> vous vendez. »

#### Divers relevés

- **[?]** « 20 exercices » en séance vs « 15 à réviser » annoncés → composition
  de file opaque, à instrumenter.
- **[!]** « Cartes maîtrisées 250/75 » affiché **sans plafond**.
- **[≈]** Libellé du gros chiffre : **non arbitraire**, il suit la composition
  réelle de la séance — `allNew` → « À APPRENDRE », `allReview` → « À RÉVISER »,
  `mixed` → « AUJOURD'HUI ». Conçu comme un « honest hero label ». Mais **aucune
  légende** → trois libellés dans le même emplacement, indéchiffrables pour
  l'utilisateur. Design juste, découvrabilité nulle.
- **[≈]** Dialogue de sortie de séance : « très bien fait ».

---

### Round 2 — portes, Sakura, planificateur

> Bibliographie vérifiée par ses soins dans `05-sources.md` (28 sources
> Dossiers A/B avec DOI résolus via CrossRef ; Dossier C : 7 confirmées,
> 3 pré-DOI recoupées, 2 explicitement « non confirmé »).
> **Auto-correction de sa part** : le « N5 ≈ 800 mots » qu'il avait utilisé au
> Round 0 vient de listes **reconstruites par la communauté** — la Japan
> Foundation ne publie plus de listes officielles depuis 2010. Ordre de grandeur
> valable, précision non.

#### [!] Le claim Tadoku est le cas d'école du chiffre qui a l'air sourcé

« ~95 % de couverture des Tadoku L0 avec 100 mots + 50 kanji » : **non
soutenable**. Les seuils de couverture pour la compréhension (Laufer 1989 : 95 % ;
Hu & Nation 2000 : 98 % ; Nation 2006) s'atteignent avec **plusieurs milliers**
de familles de mots. Aucune étude de corpus japonais ne soutient ce chiffre, et
tadoku.org **ne publie pas** de définition chiffrée du vocabulaire L0 (vérifié).

**Correctif proposé — meilleur que la citation** : on possède 96 phrases et nos
propres passages. **Calculer la couverture réelle de nos 100 premiers mots sur
NOTRE corpus, afficher ce chiffre, supprimer la référence Tadoku.** Une porte
calibrée sur son propre contenu est défendable ; drapée dans un corpus externe
non mesuré, non.

#### [!] « Swain » ×2 : habillage, sans ambiguïté

L'hypothèse de l'output (Swain 1985) attribue des **fonctions** à la production
(noticing, test d'hypothèses, réflexion métalinguistique). Elle **ne contient
aucun nombre**. Rien n'y permet de dériver « 50 mots », « 2 syllabaires » ou
« 60 % sur 30 jours ».

Idem pour « receptive-first per SLA research » : la primauté de l'input est
défendable comme **direction** (tradition VanPatten/Krashen), mais la critique
documentée de i+1 comme non-opérationnalisable (Gregg 1984, via Lichtman &
VanPatten 2021) montre justement qu'**on ne peut pas en tirer de seuils
numériques**.

> Sa position : « La politique réceptif-avant-productif est saine ; sa
> calibration actuelle est arbitraire. **L'arbitraire assumé est acceptable,
> l'arbitraire déguisé en science ne l'est pas.** »

→ Garder les seuils comme **heuristiques assumées**, retirer les noms propres.

#### [!] OBS-018 BLOQUANT — la porte N4 sur Sakura

Confirmé : N4 exigé, contenu N5 max → **fonctionnalité phare structurellement
inatteignable**. Mais son analyse va plus loin que « baisser le seuil » : **le
prompt Sakura contraint déjà le niveau JLPT**, donc la protection que la porte
prétend offrir est *déjà assurée par l'adaptation du partenaire*. La porte est
redondante avec une protection existante.

Reco : remplacer la porte binaire par un **déblocage par scénarios** — une
« première conversation » scriptée-guidée tôt (se présenter, trois échanges),
conversation libre plus tard.

#### [!] BYO-clé : « indéfendable pour la fonctionnalité phare d'une app grand public »

Sur A16 c'est « Gemini ou rien » : le routeur à 8 niveaux est de l'ingénierie que
l'utilisateur ne verra jamais. Trois options, par ordre de préférence :

1. **Dégradation gracieuse** *(recommandée)* — sans clé, Sakura fonctionne en
   **mode scripté** : dialogues arborescents pré-écrits sur le contenu N5, audio
   VOICEVOX déjà embarqué, marqueurs `[VOCAB]` fonctionnels. Le cœur pédagogique
   survit hors ligne ; la clé devient un *enhancer* « conversation libre ».
2. Repositionner Sakura en fonctionnalité avancée optionnelle — **et retirer 話
   de la promesse d'onboarding** tant que c'est le cas.
3. Statu quo assumé en bêta, avec un écran d'explication honnête.

> « L'option actuelle — la promesse au niveau 1 et la clé cachée dans Réglages →
> Fournisseurs IA — est **la pire combinaison**. »

#### [≈] Un LLM comme partenaire : « oui comme partenaire, non comme professeur »

Littérature spécifique émergente, **rien de robuste confirmé** (marqué tel quel
dans sa biblio). Raisonnement de linguiste : les LLM dérivent en registre et en
niveau sur la longueur ; leurs corrections de particules/politesse sont
majoritairement justes mais **pas fiablement** — et un débutant ne peut pas
détecter le faux positif. Le risque principal n'est pas la correction ratée,
c'est la **fluidité illusoire**.

**Nos mitigations sont les bonnes** (contrainte JLPT, `[CORRECTION]` parcimonieux,
capture `[VOCAB]` → dictionnaire : « cette boucle-là est excellente »). À garder :
corrections en style **recast** (reformuler juste, sans cours de grammaire).

#### [≈] Préférence souple vs i+1 dur : « la souplesse est le bon choix, ne cède pas »

i+1 n'a jamais été opérationnalisé numériquement en 40 ans. Contraindre durement
un LLM à 40 mots produirait du japonais artificiel aux pragmatiques déformées —
**pire pédagogiquement** que quelques mots inconnus, que le furigana + traduction
au tap rendent gérables.

#### [!] Planificateur — sa critique la plus structurelle

> « Le vrai problème n'est pas les ratios — c'est que **les quotas subordonnent
> FSRS à une esthétique de composition**. »

Test : 24 cartes dues, budget 5 min → 40 % = ~2 min de révisions → le backlog
déborde sur demain, qui déborde sur après-demain. **FSRS présuppose que les dues
sont traitées** ; un quota qui les écrête fabrique une dette de rétention
silencieuse — *une machine à burnout cachée dans une app anti-burnout*.

**Vérifié dans le code : il a raison, c'est un plafond dur.** `reviewBudget =
totalSec × 0.40`, sans logique de débordement. En mode fondation le plafond est
de 50 %, mais c'est toujours un plafond.

Reco : **les révisions dues sont prioritaires en absolu** (jusqu'au budget) ; les
quotas 30/20/10 ne s'appliquent qu'au temps restant. Si le backlog mange tout,
le dire (« aujourd'hui, on consolide ») — cohérent avec le libellé héro honnête.

#### [≈→!] Ratios par stade : le précédent existe déjà dans le code

Sa reco (3 profils : lancement / construction / croisière) est juste — et
**partiellement déjà implémentée** : le **mode fondation** (tant qu'il reste des
kana jamais vus → révisions dues + une rangée de nouveaux kana, 40/30/20/10
court-circuité) est exactement son « profil lancement ». Donc sa proposition
n'est pas une réécriture, c'est **l'extension d'un motif existant**.

Note d'honnêteté de sa part : le ratio « ~10 % de neuf » en croisière est
documenté chez Anki comme **conséquence émergente** de l'algorithme, pas comme
prescription — **ne pas le citer comme « best practice officielle »**.

#### [≈] Entrelacement : bon défaut, avec deux réserves sourcées

Pour la discrimination d'items confusables — exactement les kana — l'entrelacement
bat le blocage (Rohrer & Taylor 2007 ; Taylor & Rohrer 2010). **Mais** contre-
exemple L2 réel : Carpenter & Mueller 2013 (4 expériences), le blocage gagne sur
l'apprentissage de règles de prononciation françaises. « Toujours entrelacer »
est une surgénéralisation.

→ **Introduire en mini-bloc, réviser en entrelacé.**

**Raffinement de sa reco (e) par la biblio :** Karpicke & Roediger 2007 montre que
les steps courts *multiples* n'aident qu'à 10 minutes, pas à 2 jours → **un seul
rappel intra-séance** (critère de sortie), pas une échelle de steps à la Anki.
**Un step, pas des steps** — et c'est exactement ce que w17/w18 modélisent.

#### [!] Les durées estimées mentent à mesure que le deck mûrit

« kana 25 s » est une estimation de carte **jeune** ; une carte mûre se répond en
6-10 s. Les séances « 5 min » finiront systématiquement en avance. → recalibrer
les durées **par maturité**, sinon le budget temps ment.

---

### Vérifications bloquantes pour sa séquence (d)

**[!] Tracés kana : ILS N'EXISTENT PAS.** Le bundle ne contient qu'une table
`kanji` (90 lignes, 90/90 SVG présents — d'où le « 90/90 KanjiVG » des notes
internes). **Zéro kana** : pas de table kana, aucun caractère du bloc kana dans
la table `kanji`, aucune ressource SVG kana ailleurs.

→ **L'étape 2 de sa séquence (tracé animé) est irréalisable aujourd'hui pour les
kana.** Le moteur de rendu et le mode tracé au doigt existent et fonctionnent ;
c'est la **donnée** qui manque. KanjiVG couvre pourtant les kana en amont : c'est
un trou de pipeline de génération, pas une impossibilité.

---

### Round 3 — Watch, dictionnaire, parcours de confiance

#### [!!] OBS-024 BLOQUANT — le drill d'accent tonique enseigne deux accents faux

Vérifié contre NHK/OJAD, **et vérifié dans le code** : sur 8 mots, 6 sont exacts
(さくら[0], ともだち[0], カメラ[1], たまご[2], あたま[3], おとうと[4]) et **deux
sont faux** :

| Mot | Codé dans l'app | Vérité | Erreur |
|---|---|---|---|
| いぬ | `("いぬ", 2, 1)` → 頭高型 | **[2] 尾高型** | position d'accent fausse |
| おとこ | `("おとこ", 3, 2)` → 中高型 | **[3] 尾高型** | position d'accent fausse |

**Ce que le code révèle en plus, et qui est le vrai enseignement :** la table est
organisée en **sections commentées par patron** (`// 頭高 (atamadaka)`,
`// 中高 (nakadaka)`…), deux exemples par patron. Autrement dit **les mots ont
été choisis pour remplir une grille pédagogique, et deux 尾高 ont été enrôlés de
force dans les cases 頭高 et 中高.** La logique de classification, elle, est
correcte (`0=heiban, 1=atamadaka, 2..n-1=nakadaka, n=odaka`).
→ **La taxonomie est juste ; ce sont les données qui ont été tordues pour entrer
dedans.** C'est la même pathologie que le reste du projet, appliquée au contenu.

#### [!] OBS-025 — et l'angle mort de conception est le même que celui des données

Son observation la plus fine du round :

> « Les deux erreurs sont des 尾高 mal classés, et **尾高 est précisément le patron
> que ton affichage ne peut pas montrer** — sans particule, 尾高 et 平板 sont
> indiscernables (あたま L-H-H et ともだち L-H-H-H se terminent pareil ; la
> différence n'existe que sur あたま**が**). »

**La faille de données et la faille de conception sont dans le même angle mort.**
Correctif conjoint : afficher **mot + が** avec le point de la particule.
Accessoire : le bouton haptique n'a **aucune animation visuelle synchronisée** —
les points restent statiques pendant la vibration ; canal de feedback visuel
gratuit non utilisé.

**Verdict sur le concept lui-même — il valide :** le poignet est un canal
défendable pour l'accent (structure rythmique adaptée à l'haptique), comme
**renfort** et non comme enseignement premier (il faut avoir entendu le mot
ailleurs — d'où l'importance que l'iPhone joue enfin ses 447 clips). *« Le seul
endroit du marché où j'ai vu cette idée. »* Corriger les données + particule +
visuel synchronisé = vrai différenciateur.

#### [!] OBS-022 MAJEUR — le Kana Quiz de la Watch n'a aucun feedback correctif

Une erreur avance **sans jamais montrer la bonne réponse** — ni sur le moment, ni
au résumé. Il a répondu « yu » sur る : point rouge, question suivante, et
**る = ru ne lui sera jamais enseigné**.

> « Un quiz sans feedback correctif est un test, pas un exercice — c'est LA
> condition de toute la littérature, **y compris le pretesting** que je t'ai cité. »

**[!] OBS-023** — distracteurs aléatoires (る en Q3 et ろ en Q5 sans être posés
comme pièges l'un de l'autre : **la paire classique gâchée**) et tirage **avec
répétition** (ほ en Q8 et Q9). Toute la Watch est **en anglais** en environnement FR.

#### [≈→!] OBS-026 — le dictionnaire personnel EST l'embryon du miroir

Réponse à ma question : **ce n'est pas une liste morte**, et c'est plus avancé
qu'espéré. La fiche mot contient déjà l'état de maîtrise (初 NOUVEAU), les
compteurs FSRS (rencontres / intervalle / rechutes), la date d'ajout et un
« Historique des rencontres » structuré. **Les chips de filtre exposent l'échelle
complète New/Learning/Familiar/Mastered — exactement le vocabulaire de
progression qui manque au dashboard, et il existe déjà ici.**

> « **Un livret de compétence sans page de couverture.** »

Manque : la **surface agrégée** (compteurs par état, delta hebdomadaire,
timeline) — **sur le dashboard**, pas enfouie dans Étude.
Trois frictions : **aucune auto-complétion à l'ajout manuel** (l'app embarque
206 mots et laisse taper 水/みず/eau à la main — *« un débutant ne CONNAÎT pas la
lecture du mot qu'il veut sauver »*) ; **pas de bouton audio sur la fiche** alors
que le clip est dans le bundle ; chips et labels en anglais.

#### Parcours de confiance

- **[?] OBS-027** — « Exporter les données » ouvre une feuille **définitivement
  vide** (5 s+, pas de spinner). Possiblement un artefact share-sheet du
  simulateur → **à confirmer sur device avant de compter**.
- **[!] OBS-028 MAJEUR — aucun moyen de supprimer un profil** : ⋮ inerte, pas de
  swipe, rien. Pour une app qui accumule des mois de données d'apprentissage
  c'est un trou de confiance, et l'analogue App Store de la suppression de compte.
- **[!]** Bascule multi-profils fonctionnelle et restauration propre, mais :
  dialogue « New Profile / Name / Create » à moitié anglais, et **l'Interface
  Tatami est restée active sur un profil fraîchement créé** → réglage global ou
  fuite d'état entre profils ? **Un profil vierge ne doit pas hériter du mode
  expert.**
- **[!]** Backlog observé en vraie grandeur : **24 dus la veille → 35 le
  lendemain.** La dette de rétention silencieuse, mesurée.
- **[≈]** Le libellé « AUJOURD'HUI » confirmé correct en composition mixte (5+30).

---

## SYNTHÈSE FINALE DU RELECTEUR

### Le partage demandé : implémentation vs conception

> **~17 défauts d'implémentation pour 6 erreurs de conception.**
> « Ce projet est massivement un problème de **fils à brancher**, pas de choix à
> refaire. »

Et **plusieurs fils ont déjà leur prise posée** :

| Le fil | La prise qui existe déjà |
|---|---|
| Critère de sortie de séance | `w17`/`w18` FSRS-5 activés (poids morts) |
| Profils de séance par stade | le **mode fondation** |
| Livret de compétence | le **dictionnaire personnel** |
| Tracés kana | pipeline **KanjiVG** (couvre les kana en amont) |
| Terme du jour par niveau | champ **`jlptLevel`** déjà porté par le modèle |

**La pathologie récurrente, confirmée par six sous-systèmes indépendants :**
**l'intention écrite non implémentée**, et sa jumelle **la capacité sans sa
donnée**.

### Les 6 vraies erreurs de conception

1. Première exposition = **test sans présentation**
2. **Quotas du planificateur au-dessus des dues FSRS**
3. **Portes habillées en science**
4. **Anti-burnout sans miroir**
5. **Drill d'accent sans particule**
6. **Tatami comme récompense de volume**

> Remarque décisive : **les six ont des correctifs qui RENFORCENT l'identité du
> produit au lieu de la diluer — aucun ne demande d'ajouter un streak, une ligue
> ou un sapin de Noël.**

### Priorisation

**P0 — avant toute distribution publique** (jours, pas semaines)
- corriger 犬 / 男 ;
- peupler dakuten / yōon ;
- re-keyer la porte Sakura ;
- autoplay audio à la révélation ;
- purger les rationales pseudo-sourcées.

**P1 — le cœur**
- séquence de présentation + critère de sortie de séance ;
- dues prioritaires + profils par stade ;
- livret de compétence sur le dashboard ;
- pipeline de tracés étendu aux kana.

**P2**
- i18n, navigation, suppression de profil, seeder, particule du drill, ponts
  katakana, Tatami réel ou sans porte, RPG tranché.

### La phrase de clôture

> **« Le moteur est bon, la maison est belle ; il manque les meubles, et le
> professeur n'est pas encore entré. »**
>
> « La bonne nouvelle de cette review, c'est que faire entrer le professeur —
> présentation, feedback correctif, miroir de compétence — coûte **un ordre de
> grandeur de moins** que ce qui a déjà été construit. »

**Livrables de son côté :** 28 observations (OBS-001→028, dont **4 BLOQUANT**),
~35 sources vérifiées (`05-sources.md`), synthèse complète (`06-synthese.md`)
avec matrice implémentation/conception.

**Round 4 possible s'il est rappelé :** retest après correctifs P0, ou Sakura en
direct avec une clé Gemini fournie par Nico.

---

## Prévention — ce qui sort de la cause racine des accents

Deux mesures issues de la clôture, à traiter comme des **règles**, pas comme des
correctifs ponctuels. Elles répondent à la forme la plus grave de la pathologie :
quand « l'intention non implémentée » touche le **contenu enseigné**, l'apprenant
n'a aucun moyen de s'en défendre.

**1. Règle de process contenu.**
> Toute donnée linguistique embarquée doit être **vérifiée contre une source**
> (NHK / OJAD pour l'accent tonique), **jamais générée pour équilibrer une
> structure.**

C'est exactement ce qui a produit les deux 尾高 enrôlés de force dans les cases
頭高 et 中高 : le besoin « deux exemples par patron » a primé sur la vérité.

**2. Le test unitaire qui aurait attrapé les deux lignes.**
La logique de classification est **correcte** (`0=heiban, 1=atamadaka,
2..n-1=nakadaka, n=odaka`). Il suffit donc de **recalculer le patron depuis le
numéro d'accent et de le comparer à la section déclarée** dans la table
d'exemples. `("いぬ", 2, 1)` rangé sous `// 頭高` passerait ; `("いぬ", 2, 2)`
— la valeur correcte — échouerait immédiatement contre sa section.

→ Généralisable : **partout où une table de contenu est organisée en sections
sémantiques, un test doit vérifier que chaque entrée appartient bien à sa
section.** Le même motif protégerait les groupes kana, les niveaux JLPT du terme
du jour, et les patrons d'accent.

**3. Règle d'interface — la valeur effective, jamais la valeur stockée.**

> **Un réglage doit afficher la valeur qui est réellement en vigueur.** Sinon
> chaque dérivation silencieuse (mode d'affichage, profil, plateforme) devient un
> **mensonge d'interface**.

Deux instances du même principe ont été trouvées dans cette review, sur des
surfaces sans rapport :

| Surface | Affiché | Réalité |
|---|---|---|
| Éligibilité Tatami | « Prêt » avec « Jours actifs 0/30 » | critère en **OU**, présenté comme cumulatif |
| Furigana | « Activé » | **inopérant** en mode Tatami si l'interrupteur n'a jamais été touché |

Le second est le plus coûteux : il éteint une aide de lecture **sur la
fonctionnalité destinée aux débutants**, sans que rien à l'écran ne le signale.
Correctif de fond : afficher l'effectif, ou expliciter la dérivation (« suit le
mode d'affichage »).

**4. Passe de test dédiée aux fuites d'état.**

Sa leçon de méthode, à intégrer au protocole de test :

> Créer un profil vierge **APRÈS** avoir mis l'app dans tous ses états, puis
> vérifier **chaque réglage : effectif vs affiché**.

C'est ce qui aurait attrapé d'un coup la chaîne Tatami → fuite inter-profils →
furigana éteint. Trois observations notées comme indépendantes sur trois rounds
et trois surfaces **étaient un seul défaut d'état qui se propageait**.

---

## Note de méthode — ce qui a fait la valeur de l'échange

À conserver pour reproduire l'exercice :

- **Impressions à froid avant tout brief.** Ne pas dire la thèse produit tant que
  le relecteur n'a pas joué le parcours — sinon on ne mesure plus ce que l'app
  raconte d'elle-même, on mesure l'adhésion au discours.
- **Vérifier chaque critique dans le code, à chaque round.** C'est ce qui permet
  de trancher **choix de design vs accident** au lieu d'empiler des soupçons —
  et c'est ce qui a requalifié « bug d'affichage » en « contenu absent », puis
  « deux données fausses » en « symptôme de méthode ».
- **Corriger ses propres erreurs devant le relecteur** (mon brief inventait une
  étape « setup IA » tirée d'une doc périmée). Ça l'autorise à ne pas croire sur
  parole — il l'a fait ensuite systématiquement.
- **Réciproquement, exiger la traçabilité** : il a cité la littérature qui
  *défendait* le design actuel avant de la réfuter, s'est auto-corrigé sur un
  chiffre, et a marqué deux points « non confirmé » plutôt que de combler. C'est
  ce qui rend ses 28 observations transmissibles sans re-vérification.

**Le seul point où il s'est trompé de toute la review** — dakuten pris pour un
bug d'affichage — est précisément celui où son hypothèse était **la moins
falsifiable sans accès au code**. Bon indicateur de là où ce type de review a
besoin d'un binôme.

---

## Suite : faire relire les résultats d'un **apprenant**, pas l'app

Cette review portait sur l'app. La suite naturelle est de faire relire par le
même type d'agent **les performances réelles d'un humain** — d'où une spec
dédiée :

→ [`docs/design-specs/2026-08-10-learner-telemetry-design.md`](../design-specs/2026-08-10-learner-telemetry-design.md)

Trouvaille qui a motivé la spec, et qui n'était apparue dans aucun round :
**l'app calcule déjà la paire de confusion et la jette.**
`KanaDrillViewModel.selectedOptionCharacter` résout le kana correspondant à la
mauvaise réponse choisie, l'affiche une fraction de seconde, et ne le persiste
jamais. Pendant ce temps `LeechDetectionService` **devine** les confusions depuis
une table de kanji visuellement proches écrite à la main.

> L'app extrapole des confusions pendant qu'elle en observe de vraies et les
> efface.

C'est la même pathologie que tout le reste — la capacité sans sa donnée — mais
appliquée à l'observation de l'apprenant. Et c'est le champ le plus précieux pour
un expert : savoir qu'un apprenant confond シ/ツ vaut plus que n'importe quel taux
de réussite.

---

### Round 4 (2026-08-12) — Sakura en conditions réelles

> Clé Gemini de test fournie et saisie **par Nico** (le relecteur ne manipule pas
> de credentials). Profil N5.

**Verdict d'ensemble :** *« dans son périmètre conversationnel, Sakura est le
point pédagogiquement le plus abouti de l'app »*.

#### [≈] Ce qui marche — validé en situation

- **Corrections : 2/2, exactes et parcimonieuses.** Message piégé
  (昨日**に**映画を見ます。とても楽しい**でした**。) traité comme un bon prof :
  recast naturel dans la réponse, carte fautif-barré → corrigé attrapant **les
  deux** erreurs (〜ました *et* 〜かったです, suppression du に), règle en une
  phrase. Mélange de registre (俺+です) corrigé, abus de あなた **sagement
  ignoré** — une correction par tour, bonne parcimonie pour du N5.
- **Le niveau tient.** « Parle-moi de Kyoto » en français → 3 phrases courtes N5
  + relance conversationnelle, pas d'encyclopédie. Aucune dérive constatée.
  Sakura répond **en japonais aux entrées françaises** — bonne immersion.
- **La boucle `[VOCAB]` est complète** : 花見 proposé en pastille (ruby correct),
  définition en japonais simple (桜を見ること), tap → fiche → dictionnaire, et la
  fiche affiche « Historique des rencontres : Sakura Chat, il y a 2 min » avec
  l'extrait de contexte. **Rencontre → source → dictionnaire, de bout en bout.**
  C'est *le miroir en action*.
- Traduction masquée par défaut, révélée par phrase. Taxonomie d'erreurs correcte
  (échec réseau → message générique + Réessayer fonctionnel, pas le faux « clé
  refusée »).

#### [!] OBS-029 — un symptôme, **deux bugs distincts** (vérification code)

Il rapporte « le furigana n'est branché nulle part ». **Le code dit autre chose,
et la distinction change le correctif.**

**Bug A — les bulles : le câblage existe, c'est le RÉGLAGE qui ment.**
`ConversationBubbleView` passe bien par `KanaRubyText` (ligne 173) avec
`showFurigana: effectiveFurigana`. Mais :

```swift
// ReadingAidResolver
var effective: Bool {
    userTouched ? storedValue : (mode == .beginner)
}
```

Donc si l'utilisateur **n'a jamais touché** l'interrupteur furigana et se trouve
en **mode Tatami**, le furigana est **désactivé** — quelle que soit la valeur
stockée. Et `SettingsView` affiche `furiganaEnabled ? "On" : "Off"`, c'est-à-dire
**la valeur stockée, pas la valeur effective**.

→ **L'écran de réglages affiche « Activé » pendant que la fonctionnalité est
inactive.** Le relecteur était en Tatami (forcé au Round 1, et il a noté au
Round 3 que **Tatami avait fuité sur un profil fraîchement créé**). Les trois
observations se recoupent : ce n'est pas trois bugs, c'est une chaîne.

Correctif : afficher la valeur **effective** (ou expliciter « suit le mode
d'affichage »), + corriger la fuite de Tatami entre profils.

**Bug B — les cartes de correction : vraie absence de câblage.**
`CorrectionItemView` rend `Text(correction.original)` et
`Text(correction.corrected)` **en clair, sans jamais passer par `KanaRubyText`**.
Le format machine `漢字(かんじ)` arrive donc à l'écran avec ses parenthèses.
→ Ici sa recommandation « brancher le ruby » est **exactement** le correctif.

> À noter : `CLAUDE.md` documente « `KanaRubyText` met les furigana au-dessus des
> kanji » comme un fait acquis. Encore une **intention écrite non implémentée** —
> la dernière de la review, et sur la fonctionnalité phare.

#### [!] OBS-018 amendée — la porte N4 est **doublement** lettre morte

Confirmé dans le code : `EtudeView` ouvre `ConversationView` **sans aucune
vérification de déverrouillage**. Le fichier porte même le commentaire
« *No grid, no locked tiles* » — la refonte de l'onglet Étude a supprimé les
tuiles verrouillées.

Donc le seuil N4 est **à la fois inatteignable** (contenu N5 max) **et non
appliqué** à l'entrée principale ; il ne subsiste que dans le planificateur.

> Son ironie, qui est le vrai enseignement : **l'expérience réelle démontre que
> la porte était inutile** — Sakura à N5 avec un débutant, ça marche très bien.
> Une porte qu'on ne peut pas franchir, qu'on n'applique pas, et dont on n'avait
> pas besoin.

#### [?] OBS-030 MINEUR — finitions Sakura

- **Pas de contexte horaire dans le prompt** → こんにちは à 9 h 20, et
  re-salutation en milieu de conversation.
- **Langue des explications incohérente** (français pur vs japonais + glose).
- **Vouvoiement dans les corrections** vs tutoiement partout ailleurs.
- Label « MEANING » en anglais.
- Le **premier** échec réseau mériterait un auto-retry : *« la première
  expérience Sakura d'un débutant ne doit pas être un échec »*.

#### Reco Sakura révisée (remplace celle du Round 2)

Le mode scripté hors-ligne reste souhaitable comme dégradation sans clé, mais la
priorité absolue devient plus simple et moins chère :

1. **brancher le ruby sur les cartes de correction** (composant existant) ;
2. **corriger le mensonge du réglage furigana** (+ fuite Tatami entre profils) ;
3. ajouter **l'heure** au prompt ;
4. fixer la **langue des explications** sur celle de l'interface.

> « Avec ça, Sakura passe de *démo prometteuse* à *argument d'achat*. »
