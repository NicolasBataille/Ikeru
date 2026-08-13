# Découverte de l'application

## Présentation par le développeur

Cadre posé par le dev-relais (session « presenter ») :

- App **non sortie**, ciblant en priorité un apprenant **francophone** ;
  interface bilingue FR/EN suivant la langue configurée sur le device.
- **iPhone uniquement**, portrait, **dark mode forcé**.
- Des outils dev sont cachés dans Réglages (sliders de profil fixture,
  boutons Wipe / Lootbox / Level-up / Clear cache, Build info) permettant
  d'explorer des états avancés (J+30, J+90) sans avoir à les atteindre par le
  jeu normal.
- Le compagnon IA « Sakura » nécessite une clé Gemini, qui n'a pas été
  fournie pour cette session — cette fonctionnalité sera donc traitée en
  discussion avec le développeur plutôt qu'en test direct.
- Limites connues du simulateur signalées à l'avance : micro et
  reconnaissance vocale capricieux, pas de VoiceOver disponible.
- La thèse produit (l'angle défendu par le développeur sur ce que l'app
  apporte) est volontairement gardée secrète jusqu'après le Round 0, afin de
  recueillir des impressions à froid non biaisées.

## Aperçu accidentel d'un profil avancé (« Nikou », ~J+N)

**Observation séparée du parcours débutant** — issue du faux départ du
premier lancement (voir [`01-journal.md`](01-journal.md), 00:35), avant que
le dev-relais ne réinstalle l'app pour repartir sur un profil vierge. Les
éléments ci-dessous documentent un état avancé du produit, pas le parcours
naïf d'un nouvel utilisateur.

**Dashboard** : salutation こんばんは suivie du prénom, date affichée
« 8月10日・月 », carte proverbe du jour 七転八起 (« Tombe sept fois,
relève-toi huit »), gros chiffre « 9 AUJOURD'HUI » (unité non précisée —
cartes dues ? minutes de pratique ?), CTA 稽古を始める・COMMENCER,
compteur « かな 3/92 APPRIS », carte « NOUVEAU TERME DU JOUR » avec rappel
du terme de la veille (縁側, « véranda en bois le long d'une maison
japonaise »), compteurs NOUVEAUX 3 / RÉVISION 6 / APPROX. 2m, et ligne
« PROCHAINE ÉTAPE 3/46 Apprends les hiragana ».

**Réglages** : toggles Rappels et Bilan hebdomadaire, Terme du jour programmé
à 09:00, Furigana Activé, réglage « Objectif de rétention 95% » (la valeur
par défaut sur un profil neuf est 90%) avec le sous-texte « Plus élevé
signifie une meilleure mémorisation, mais plus de révisions quotidiennes »,
toggle « Interface Tatami » (off, sous-texte « Conçu pour les apprenants à
l'aise avec le japonais ») accompagné d'une « Progression Tatami : Révisions
14/750, Cartes maîtrisées 3/75, Jours actifs 1/30 » (nature exacte de ces
seuils de déblocage non identifiée), section Compte (Profil, Ajouter un
profil = gestion multi-profils, Exporter les données, Langue réglée sur
Auto·Français), section Fournisseurs IA, section Cache & préchauffage
(0/500 MB), Version 1.0.0 (1), lien « Revoir la visite guidée », Crédits,
et section Outils dev présente.

**Widget écran d'accueil** : affiche « Ikeru — 3 due — Lv. 4 », en
**anglais** alors que le device est configuré en français (bug i18n, voir
OBS-005). Un système de niveaux (« Lv. 4 ») existe donc dans l'app, mais
n'était visible nulle part dans le dashboard in-app observé.

## Première prise en main (parcours naïf, profil vierge « Louis »)

Chronologie du Round 0, rejoué sur container vierge après réinstallation
(00:44–00:56, voir [`01-journal.md`](01-journal.md)) :

1. **Écran prénom** : logo kanji stylisé (visuellement proche de 中, à
   confirmer avec le développeur), titre « TON CHEMIN COMMENCE », sous-titre
   « Comment veux-tu être appelé(e) ? », champ « Ton prénom », bouton
   続ける・CONTINUER (désactivé tant que le champ est vide). Registre : le
   tutoiement est utilisé, avec écriture inclusive (« appelé(e) »).

2. **« As-tu déjà étudié le japonais ? »** : deux choix — 初 « Je débute —
   Kana, romaji et aides à la lecture activés. La voie douce. » vs. 畳
   « J'en connais déjà — Kanji d'abord, traductions masquées. Modifiable
   dans les Réglages. » (ce second choix est relié à l'« Interface Tatami »
   vue dans les Réglages du profil avancé). Choix fait pour ce parcours :
   « Je débute ».

3. **Trois slides de présentation** (navigation par swipe), chacune associée
   à un kanji :
   - 道 *michi* — « Ton voyage — Un chemin de curieux à courant — Maîtrise
     les kana, kanji, la grammaire et la conversation »
   - 友 *tomo* — « Ton compagnon — [le] compagnon IA s'adapte à toi »
   - 始 *hajime* — « Commencer — Tu commenceras par les hiragana »
   Romaji affiché sous chaque kanji.

4. **Note** : l'étape « configuration IA » annoncée en amont par le
   dev-relais n'est **pas** apparue dans ce parcours (voir Q7 dans
   [`04-questions-dev.md`](04-questions-dev.md)).

5. **Visite guidée « Sakura »** (~7 étapes, skippable via « Passer ») :
   intro (« Enchantée, je suis Sakura ! … te faire visiter en 30
   secondes »), L'accueil 家, Commencer à pratiquer 稽古 (explique le CTA du
   dashboard et mentionne « 46 sons de base »), Explorer 学 (présente
   l'onglet Étude : kana, vocabulaire enregistré, Sakura comme partenaire de
   conversation), Les réglages 設 (avec l'astuce qu'on peut relancer la
   visite depuis Réglages), étape finale « À toi de jouer ! 行 » avec la
   phrase « 頑張って (ganbatte) veut dire bon courage » (romaji correct ;
   coupure de mot en fin de ligne, 頑/張って, à noter comme détail de mise
   en page).

6. **Dashboard vierge** : carte « Aujourd'hui » avec le même proverbe
   七転八起 (sans lecture ni explication associée), un seul CTA
   仮名を選ぶ・CHOISIR MES KANA, compteur « かな 0/92 APPRIS ».

7. **Sélecteur de kana** : trois segments — Hiragana (base) / Hiragana
   (complet) / Katakana. Pour la base : « SYLLABAIRE FLUIDE / Hiragana /
   Base (gojūon) : Les 46 sons de base dans la table classique : cinq
   voyelles, puis des rangées consonne + voyelle ». Groupes organisés par
   rangée (Voyelles あいうえお pré-cochées, puis K, S, T, N, H, M, Y, R,
   W/N), chaque kana affiché avec son romaji et un indicateur « Maîtrise :
   0% ». Bouton « Tout sélectionner » par section. Footer : « 5 caractères
   sélectionnés » + bouton « Commencer ces kana ». Sections suivantes :
   - « Dakuten (voisées) », avec explication : « ゛voise la consonne (か ka
     → が ga), ゜transforme le h en p (は ha → ぱ pa) ».
   - « Combinés (yōon) », avec explication : « Un kana consonne + petit
     ゃ・ゅ・ょ fusionnent en une seule syllabe : き + ゃ = きゃ kya ».
   Les explications linguistiques de ces deux sections sont exactes et bien
   rédigées.

8. **Tutoriel de geste** (sur la 1re carte) : swipe dans les 4 directions =
   Facile (haut) / À revoir (gauche) / Bien (droite) / Difficile (bas), avec
   la précision « les quatre mêmes boutons sont aussi en bas de l'écran » ;
   consigne « TOUCHE LA CARTE POUR RÉVÉLER ».

9. **Session SRS** : recto = kana seul + bouton audio (pas d'autoplay
   constaté au flip de la carte — à confirmer, l'audio n'étant pas
   vérifiable de façon fiable au simulateur). Un tap révèle le romaji.
   Quatre boutons de réponse : 再 ENCORE (1j) / 難 DIFFICILE (2j) / 良 BIEN
   (4j) / 易 FACILE (16j), avec intervalles prévisionnels affichés
   directement sous chaque bouton (vraisemblablement des stabilités
   initiales FSRS ~0.4 / 1.2 / 3.1 / 15.7 jours arrondies à l'entier — voir
   Q5). Réponses données pendant la session : あ → Encore, い → Bien, う →
   Difficile, え → Bien, お → Facile. あ a bien été re-présentée en fin de
   session (re-queue intra-session fonctionnelle) et a été regradée Bien.

10. **Résumé de séance** : titre « 稽古終わり » (« Séance terminée »),
    proverbe 七転び八起き, statistiques « 6 CARTES / 67% RAPPEL / 3:08
    TEMPS », détail « NOUVEAUX 5 札 / À REVOIR 1 札 », boutons
    続ける・CONTINUER et « REVOIR LES ERREURS ». Le calcul du 67% :
    4 réponses réussies sur 6 au sens strict — la réponse « Difficile » est
    donc comptée comme un échec, alors qu'en sémantique SRS classique
    (Hard) elle constitue une réussite (voir OBS-004).

11. **Retour au dashboard** : message « Tout est à jour — savoure le
    calme », mais les compteurs « かな 0/92 APPRIS » et « PROCHAINE ÉTAPE
    0/46 » restent inchangés malgré la session venant d'être complétée (voir
    OBS-003). Une demande contextuelle « Essayer le mot du jour ? »
    (boutons Plus tard / Activer) déclenche ensuite le prompt système iOS de
    demande d'autorisation de notifications — bonne pratique de pre-prompt.

12. **Terme du jour** : ポカヨケ, lecture ぽかよけ (vérifiée correcte au
    zoom, incluant le handakuten), romaji po-ka-yo-ke, définition
    « détrompeur — un design qui rend les erreurs difficiles à commettre »,
    avec une note culturelle mentionnant Toyota, les « pipelines CI » et les
    notices Lego. Le bouton « Ajouter au dictionnaire » devient « Ajouté au
    dictionnaire » après tap, et le compteur Vocabulaire de l'onglet Étude
    passe à 1. Lien « Termes passés » disponible.

13. **Onglet Étude** : trois cartes — Kana (0/92), Vocabulaire (1, sous-titre
    « Tes mots enregistrés »), Parler avec Sakura (sous-titre « Partenaire
    de conversation IA »). Le header de l'écran, « Explore », est affiché en
    **anglais** alors que le device est en français (voir OBS-005). Lors
    d'une 2e visite de l'écran kana, un tooltip Sakura présente « Trois
    façons de pratiquer » : Réviser (« cartes dues aujourd'hui, celles que
    ta mémoire s'apprête à lâcher »), Pratique libre (« toute ta sélection,
    sans pression. Tes réponses comptent quand même pour le planning »),
    Points faibles (« cible d'abord tes kana les moins maîtrisés »), avec
    trois boutons correspondants À réviser / Pratique libre / Points
    faibles. Ce tooltip n'apparaissant qu'à la 2e visite illustre un
    mécanisme de *progressive disclosure*.

## Round 1 : états simulés, Tatami, katakana

Exploration menée 01:10–01:30 (voir [`01-journal.md`](01-journal.md)) via les
outils dev, pour évaluer l'app à des états avancés (J+30/J+90) sans avoir à
les atteindre par le jeu normal.

**Developer Tools** (Réglages → Outils dev → Developer Tools, écran en
anglais) : sliders Seed fixture profile (bornes Level 30 / Due 50 / Mastered
200 ; ne persistent pas entre visites), boutons Wipe profile, Force
level-up, Clear asset cache, Build info. Deux seeds appliqués avec succès
(confirmation « ✓ Seeded » affichée) : « lvl 4, 15 due, 40 mastered » puis
« lvl 30, 50 due, 200 mastered ». Limites majeures découvertes (voir
OBS-013) : cartes kanji placeholder générées (recto 足, verso
« reading-14 »), écrase le prénom du profil (Louis → Nico), vide le
dictionnaire de vocabulaire (le mot ajouté au Round 0 a disparu), remet les
flags de tutoriels à zéro (tutoriel de geste + tooltips Sakura re-affichés),
remet « Jours actifs » à 0, et ne touche PAS aux kana (tous les groupes
restent à Maîtrise 0%).

**Dashboard après seed** : après « J+30 » (lvl 4/15 due/40 mastered), le gros
chiffre affiche « 15 À RÉVISER » — le libellé du chiffre principal est donc
dynamique/incohérent : « À réviser » ici, contre « AUJOURD'HUI » sur le
profil avancé « Nikou » vu au faux départ. Détail : NOUVEAUX 0 / RÉVISION 15
/ APPROX 3m, かな 0/92 APPRIS inchangé, PROCHAINE ÉTAPE 0/46 inchangé. Après
le seed max (lvl 30/50 due/200 mastered) : « 24 À RÉVISER », APPROX 6m.

**Session « à réviser » après seed** : file mélangeant des kanji placeholder
(足 → « reading-14 », intervalles mûrs Encore 1j / Difficile 3j / Bien 7j /
Facile 20j — preuve que les intervalles FSRS croissent bien avec
l'historique simulé) et de vraies cartes kana issues du Round 0 (あ → a,
intervalles jeunes 1j/2j/4j/16j). Dialogue de sortie : « Quitter cette
séance ? Tu as terminé 1 de 20 exercices » (20, alors que le dashboard
annonçait 15 « à réviser »). Résumé après sortie : « 1 CARTES / 100% RAPPEL
/ 1:51 », « À REVOIR 1 札 ».

**Écran « Cache & préchauffage »** (Réglages → Données & stockage) : Cache de
ressources 0/500 MB, Préchauffage audio Activé, Notifications de
préchauffage Désactivé, bouton Préchauffer maintenant, section « Tâches du
rig » (libellé jargon).

**Écran Crédits** : KanjiVG (CC BY-SA 3.0), décrit comme « tracés vectoriels
utilisés dans les animations d'ordre des traits et les exercices de
calligraphie » — donc des données de tracé sont déjà embarquées et
créditées, sans surface observée pour l'instant dans le parcours testé ;
Noto Serif JP (SIL OFL 1.1) ; VOICEVOX 四国めたん (audio pré-généré offline,
crédit requis).

**Interface Tatami activée** : tab bar réduite à des kanji seuls (学習 / 練習
/ 設定), titres de sections préfixés en kanji (本日・AUJOURD'HUI,
表示・AFFICHAGE, 勘定・COMPTE, 知能・FOURNISSEURS IA), sous-texte « Pour
revenir au mode débutant, désactive ici ». Mais le reste de l'interface
demeure entièrement en français, les romaji restent affichés sous les kana
du sélecteur, et les traductions ne sont pas masquées (le proverbe traduit
reste affiché) — contradiction avec la promesse d'onboarding « Kanji
d'abord, traductions masquées » (voir OBS-015). Le dashboard Tatami est
quasi identique au dashboard normal.

**Vocabulaire (onglet Étude)** : écran vide après seed (« Aucun mot pour le
moment — Les mots enregistrés en discutant avec Sakura apparaissent ici —
tu peux aussi en ajouter un toi-même », bouton « Ajouter un mot »), bouton
retour présent sur cet écran (contraste avec OBS-012).

## Round 2 : matériel fourni par le dev (non testé — architecture)

Matériel d'architecture transmis par le dev-relais (pas d'exploration in-app,
extraits de code et tableaux fournis directement) — voir questions posées en
retour par le dev dans [`04-questions-dev.md`](04-questions-dev.md) et
constats correspondants dans [`03-observations.md`](03-observations.md)
(OBS-018, OBS-019, OBS-020).

**Portes de déverrouillage — les 12 types d'exercices et leurs seuils**,
tels que fournis :

| Type d'exercice | Seuil de déverrouillage | Justification citée |
|---|---|---|
| kanaStudy | ouvert | « receptive-first per SLA research » |
| kanjiStudy | ouvert | « receptive-first per SLA research » |
| vocabularyStudy | ouvert | « receptive-first per SLA research » |
| listeningSubtitled | ouvert | « receptive-first per SLA research » |
| fillInBlank | 50 vocab familier+ | — |
| grammarExercise | 46 hiragana maîtrisés | — |
| sentenceConstruction | 5 points de grammaire | — |
| readingPassage | 100 vocab + 50 kanji | « ~95 % coverage of Tadoku L0 » |
| writingPractice | 2 syllabaires + 50 vocab | « Swain » |
| listeningUnsubtitled | ≥ 60 % de rappel sur les 30 dernières révisions | — |
| speakingPractice | ≥ 60 % de rappel sur 30 jours | « Swain » |
| sakuraConversation | JLPT N4 (300 vocab + 30 points de grammaire) | — |

3 types restent en placeholder (grammaire, texte à trous, passage de
lecture) — admis par le dev dès le brief initial. Aucune des « justifications
citées » n'a de référence primaire ni de lien dans le code (constantes nues,
commentaire de texte libre) — voir OBS-019.

**Architecture Sakura (chat IA)** : routeur à 8 niveaux de fallback — Apple
on-device (iOS 26+) → Gemini → Groq → OpenRouter → Cerebras → GitHub Models
(gratuits) → Claude (payant) → GPU local. Sur un iPhone A16 (pas de modèle
Apple on-device disponible), Gemini est en pratique le seul fournisseur
utilisable : la fonctionnalité phare exige que l'utilisateur apporte sa
propre clé API (voir OBS-020). Prompt système : partenaire de conversation
amical, contrainte de niveau JLPT, furigana au format machine 漢字(かんじ),
marqueurs [CORRECTION]/[VOCAB] alimentant le dictionnaire personnel,
vocabulaire déjà connu (plafonné à 40 mots) injecté comme préférence souple
(pas de contrainte stricte).

**Planificateur de séance** : répartition 40 % révisions FSRS dues / 30 %
compétence la plus faible / 20 % variété rotative / 10 % contenu neuf,
entrelacés par round-robin pondéré lissé (corrigé depuis une version
antérieure en 4 blocs contigus par compétence). Durées estimées par item :
kana 25 s, kanji 60 s, vocabulaire 30 s, écoute 60 s, lecture 120 s,
conversation 180 s ; la séance se remplit jusqu'au budget de temps choisi
par l'utilisateur.

## Round 3 : app Watch

Exploration menée 08:25–08:40 (voir [`01-journal.md`](01-journal.md)), sur
simulateur Apple Watch Series 11 (46mm), à partir d'un build autonome fourni
par le dev (synchronisation avec l'iPhone non testable dans cette
configuration — attendu, pas un défaut constaté).

**Kana Quiz** : QCM de reconnaissance kana→romaji, 4 choix, 10 questions,
points de progression en tête d'écran (vert = juste, rouge = faux), écran
final « 9/10 Nice work! » avec bouton « Again ». Format bien adapté au
poignet (gros boutons, lecture rapide). Une réponse fausse observée (る
répondue « yu ») fait avancer directement à la question suivante **sans
jamais montrer la bonne réponse** — ni pendant, ni au résumé (voir OBS-022).

**Pitch Accent** : 8 mots, un par écran, chacun affichant l'étiquette du
patron d'accent (中高型 / 平板型 / 尾高型 / 頭高型), le mot en kana, une
rangée de points de mores (or = mora haute, gris = mora basse), un bouton
haptique et un bouton suivant. Mots observés dans l'ordre : たまご 中高
L-H-L, ともだち 平板 L-H-H-H, あたま 尾高 L-H-H, カメラ 頭高 H-L-L, いぬ
頭高 H-L ⚠️, おとうと 尾高 L-H-H-H, おとこ 中高 L-H-L ⚠️, さくら 平板
L-H-H. Le bouton haptique déclenche une vibration mais **aucune animation
visuelle synchronisée** sur les points de mores (voir OBS-025). Les mots
sont affichés isolés, sans particule, ce qui rend 尾高 et 平板
indiscernables à l'écran (voir OBS-025) — et deux des huit mots affichent un
patron qui ne correspond pas à l'accent standard de Tokyo attendu (voir
OBS-024, vérification OJAD/NHK en Mission 1).

**Dictionnaire personnel** (côté iPhone, testé à 08:36, pour compléter
l'inventaire OBS-011/OBS-026) : ajout manuel d'un mot via un formulaire
Mot / Lecture / Sens, sans aucune auto-complétion depuis les données
embarquées (206 mots du corpus). Liste des mots avec tri « Mastery »,
recherche, chips d'état affichées en **anglais** (All / New / Learning /
Familiar / Mastered), ligne « Réviser les mots dus », badge 初 par mot,
compteur en forme d'œil (encounters). Fiche mot détaillée : panneau
MAÎTRISE (初 NOUVEAU / 0 ENCOUNTERS / 0j INTERVAL / 0 LAPSES — libellés
partiellement en anglais), date d'ajout, section « Historique des
rencontres » (vide, prête à logger), bouton « Retirer du dictionnaire ».
Aucun bouton audio sur la fiche mot alors que les lectures de vocabulaire
sont dans le bundle audio embarqué. Compteur « 1 mots » non accordé.

## Round 4 : Sakura en conversation réelle

Exploration menée 09:15–13:50 (voir [`01-journal.md`](01-journal.md)), clé de
test fournie par le dev (le reviewer n'a saisi aucun credential — règle de
sécurité de la review), profil Nico (N5).

**Écran Fournisseurs IA** : « IA sur l'appareil (Apple FoundationModels — pas
de clé, pas de réseau, pas de quota) » en tête, puis section « Recommandé »
avec une carte Gemini (Google AI Studio · Free tier, champ « Colle ta clé
API », bouton Enregistrer, lien « Obtenir une clé gratuite »), puis
« Avancé > ». Bonne conception : un chemin recommandé unique, pas de choix
paralysant entre 8 providers. Clé non ré-affichée après enregistrement,
bouton Supprimer présent.

**Écran d'accueil conversation** : « Rencontre Sakura », badge N5 (header +
intro), 3 amorces proposées en **français**, champ « Écris en japonais… »,
bouton micro.

**Échange 1** (amorce « Bonjour ! Comment ça va ? ») : réponse en ~3 s, 3
phrases N5 (こんにちは！私は元気です。あなたも元気ですか？), traduction
masquée par défaut et révélée par phrase en ligne dimmée sous chaque phrase
(conforme au design annoncé). Notes : こんにちは servi à 9h20 du matin (pas
de contexte horaire dans le prompt) ; **aucun furigana ruby** dans la bulle
malgré « Furigana : Activé » dans les réglages.

**Échange 2** (« 昨日に映画を見ます。とても楽しいでした。 ») : réponse avec
recast correct (昨日映画を見ましたか) accompagnée d'une carte de correction
(texte fautif barré → version corrigée) attrapant LES DEUX erreurs à la fois
(temps du verbe, 〜ました attendu, ET adjectif, 〜かったです attendu, plus la
suppression du に fautif) avec une règle concise en français. Mais la carte
de correction affiche le format machine brut 昨日(きのう)映画(えいが)…
au lieu d'un rendu ruby.

**Échange 3** (« 俺はフランス人です。あなたの趣味は何ですか？ ») : premier
envoi tombé en échec réseau (voir journal), retry réussi. Correction de
registre 俺→私 avec explication bilingue (« 私 est une façon plus polie de
dire je ») ; l'abus de あなた dans le même message n'est sagement pas
corrigé (une seule correction par tour — parcimonie confirmée). Explication
cette fois donnée en japonais+français, alors que l'échange 2 était en
français pur (incohérence de langue d'une carte à l'autre).

**Échange 4** (« Parle-moi de Kyoto ! » envoyé en français) : PAS de dérive
de niveau — réponse en 3 phrases courtes N5 (有名な場所, きれいな寺や庭…)
avec relance conversationnelle (京都に行ったことがありますか, seul point
frôlant le N4). Sakura répond en japonais à une entrée française : bonne
immersion, le garde-fou de niveau tient sous la pression d'une question
ouverte.

**Échange 5** (« Apprends-moi un mot ») : Sakura propose 花見 dans une
pastille [VOCAB] dédiée, où le furigana はなみ EST correctement rendu en
ruby cette fois — le composant fonctionne donc, il n'est simplement pas
branché sur les bulles ni sur les cartes de correction. Tap sur la pastille
→ fiche mot (花見 / はなみ / « regarder les fleurs (de cerisier) », label
« MEANING » en anglais) → bouton « Ajouter au dictionnaire » → le mot
apparaît dans l'onglet Vocabulaire avec compteur de rencontres = 1, et la
fiche affiche « Historique des rencontres : Sakura Chat, il y a 2 min,
extrait du contexte » — la boucle rencontre → source → dictionnaire
fonctionne de bout en bout.

## Inventaire des fonctionnalités

Inventaire v1, établi d'après ce qui a été observé au Round 0 — à compléter
aux rounds suivants :

- Onboarding personnalisé (prénom, niveau déclaré).
- Visite guidée rejouable depuis les Réglages.
- SRS de type FSRS pour les kana (hiragana base/complet, katakana, dakuten,
  yōon), avec 3 modes de pratique (À réviser / Pratique libre / Points
  faibles).
- Mot du jour, avec notifications programmables.
- Dictionnaire personnel de vocabulaire (mots ajoutés manuellement depuis le
  terme du jour, au minimum).
- Chat IA « Sakura » (non testé cette session, clé Gemini requise).
- Gestion multi-profils.
- Export de données.
- Interface Tatami (mode avancé déblocable, masquant traductions/romaji).
- Widget écran d'accueil.
- App Watch (mentionnée dans la doc du projet côté dev, non testée cette
  session).
- Réglage d'objectif de rétention (défaut 90%, observé à 95% sur le profil
  avancé).
- Cache & préchauffage (gestion de l'espace de stockage audio/données).
- Système de niveaux/XP (« Lv. 4 » vu sur le widget, sans équivalent visible
  in-app au dashboard observé).
- Outils dev (sliders fixture, Wipe, Lootbox, Level-up, Clear cache, Build
  info).
