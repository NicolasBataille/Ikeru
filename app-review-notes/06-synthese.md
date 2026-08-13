# Synthèse finale — Review Ikeru (2026-08-10)

## Verdict global

Ikeru est une coquille d'une qualité rare — direction artistique cohérente, ton juste, microcopie honnête, moteur FSRS-5 réel, planificateur pensé — construite autour d'un déficit de contenu et de feedback. La quasi-totalité des défauts relevés sont des défauts d'implémentation (« fils à brancher ») et non des erreurs de conception ; mais trois choix de conception sont, eux, à refaire. La pathologie récurrente du projet, constatée indépendamment sur six sous-systèmes, est double : (1) l'intention écrite non implémentée (le commentaire ou la doc promet — « reading aids minimal », « portes citant la recherche SLA », micro-textes dakuten — et le code ne livre pas) ; (2) la capacité sans sa donnée (moteur de tracé sans tracés kana, w17/w18 sans flux same-day, champ jlptLevel jamais consulté, XP/loot sans surface, 447 clips audio sans déclenchement). Le moteur est bon, la maison est belle ; il manque les meubles et le professeur n'est pas encore entré.

Sur la promesse (« de curieux à courant », 4 compétences 読書聴話) : en l'état, l'app livre « de curieux à lecteur des 92 kana de base, avec un vocabulaire N5 partiel ». La promesse doit être recadrée ou le contenu rattrapé avant distribution publique.

Addendum Round 4 (2026-08-12) : Sakura testée en conditions réelles avec une clé de test. Le cœur conversationnel est le point pédagogiquement le plus abouti de l'app — corrections exactes et parcimonieuses (recast + carte + règle), niveau N5 tenu, boucle [VOCAB]→dictionnaire complète avec traçabilité des rencontres. Deux réserves : le rendu furigana n'est pas branché sur les bulles/corrections (OBS-029) — bloquant pour la cible débutante — et la porte N4 s'avère doublement lettre morte (inatteignable ET non appliquée à l'entrée Étude). Ceci renforce la conclusion générale : la valeur est construite, elle attend ses branchements.

## Défauts d'implémentation (fils à brancher)

| # | Constat | Sévérité | Réf |
|---|---|---|---|
| 1 | Dakuten/yōon : groupes déclarés vides (TODO dans le code), micro-textes qui décrivent un contenu inexistant ; le japonais réel est illisible sans | BLOQUANT | OBS-001 |
| 2 | Drill d'accent Watch : 2 mots sur 8 avec patron erroné (犬, 男 — confirmés par NHK/OJAD) | BLOQUANT | OBS-024 |
| 3 | Porte Sakura : N4 exigé, contenu N5 max — la fonctionnalité phare est inatteignable | BLOQUANT | OBS-018 |
| 4 | Audio : aucun autoplay au flip des cartes (447 clips VOICEVOX embarqués dormants) | MAJEUR | OBS-002 |
| 5 | Tracés kana absents du bundle (moteur KanjiVG fonctionnel, 90/90 kanji, 0 kana — trou de pipeline) | MAJEUR | — |
| 6 | Tatami cosmétique : displayMode consommé par aucune vue d'apprentissage ; 3 labels kanji sur 8 faux (勘定/倉庫/関連) | MAJEUR | OBS-015 |
| 7 | Navigation : écrans sans sortie (Entraînement aux kana, Cache & préchauffage) | MAJEUR | OBS-012 |
| 8 | Widget : crash EXC_GUARD reproductible (4 occurrences) | MAJEUR | OBS-008 |
| 9 | Suppression de profil inexistante côté utilisateur | MAJEUR | OBS-028 |
| 10 | Export de données : feuille vide (à confirmer sur device) | MAJEUR ? | OBS-027 |
| 11 | Quiz kana Watch : aucun feedback correctif sur erreur | MAJEUR | OBS-022 |
| 12 | Outillage : seeder inutilisable pour simuler J+30 réel (cartes 人0/日1, purge du profil actif) | MAJEUR (outillage) | OBS-013 |
| 13 | « 67 % rappel » compte Difficile comme échec (accident confirmé, l'intention écrite dit l'inverse) | MINEUR | OBS-004 |
| 14 | jlptLevel jamais consulté par le terme du jour | MINEUR | OBS-006 |
| 15 | i18n : fuites anglaises étendues (header Explore, widget, app Watch entière, chips du dictionnaire, ENCOUNTERS/INTERVAL/LAPSES, dialogue New Profile, « 1 mots », « Tâches du rig ») | MINEUR (périmètre large) | OBS-005, OBS-026, OBS-028 |
| 16 | Complication Watch : données en dur | MINEUR | — |
| 17 | Distracteurs Watch aléatoires + tirage avec répétition | MINEUR | OBS-023 |
| 18 | Sakura : rendu furigana absent des bulles et brut dans les corrections (composant ruby fonctionnel mais non branché) ; finitions conversation (contexte horaire, langue des explications, auto-retry) | MAJEUR | OBS-029, OBS-030 |

## Erreurs de conception (choix à refaire)

1. **Première exposition = test** (OBS-002). Un débutant absolu rencontre chaque kana en mode « touche pour révéler » et doit s'auto-noter sur un item jamais enseigné. La note FSRS initiale est du bruit (le garde-fou .familiar du code en est l'aveu), et l'affect (« échouer d'abord ») contredit la thèse anti-burnout. → Séquence de présentation : glyphe + romaji + audio automatique (double codage), tracé animé une fois (dès que les tracés kana existent), mnémonique optionnel, puis UN premier rappel 2-4 cartes plus loin dans la même séance comme critère de sortie (« un step, pas des steps » — compatible avec la position FSRS, utilise les w17/w18 aujourd'hui morts). Coût : un template + une règle de file ; zéro tap de plus.
2. **Quotas du planificateur au-dessus de FSRS** (OBS-021). reviewBudget = 40 % du temps, plafond dur sans débordement : le backlog déborde silencieusement (constaté : 24 dus → 35 le lendemain). Une dette de rétention cachée dans une app anti-burnout. → Dues prioritaires en absolu, quotas sur le temps restant ; profils par stade (le « mode fondation » du code prouve que le motif est déjà admis — il manque construction et croisière).
3. **Portes habillées en science** (OBS-019). « Swain », « ~95 % Tadoku L0 », « SLA research » : aucune de ces références ne soutient les nombres affichés (vérifié, Dossier C des sources). L'arbitraire assumé est acceptable ; l'arbitraire déguisé en science ne l'est pas. → Assumer les seuils comme heuristiques instrumentées ; mesurer la couverture réelle sur le corpus embarqué ; re-keyer la porte Sakura sur ce que la conversation demande (le prompt contraint déjà le JLPT).
4. **Anti-burnout sans miroir** (OBS-003, OBS-011). Retirer le streak sans installer de substitut laisse zéro boucle de feedback : compteurs à 0 après la première session, « savoure le calme » à J0, aucune surface d'historique. → Le livret de compétence : la donnée existe déjà dans le dictionnaire (états New/Learning/Familiar/Mastered, rencontres, FSRS par mot — OBS-026) ; il manque la surface agrégée sur le dashboard (compteurs par état + delta hebdomadaire + palier « en cours d'apprentissage » visible dès J0).
5. **Drill d'accent sans particule** (OBS-025). 尾高 et 平板 sont indiscernables sur un mot isolé — le drill étiquette une distinction qu'il ne peut pas montrer, et les 2 erreurs de données sont précisément des 尾高 mal classés. → Afficher mot + が avec le point de particule ; animer les points en synchronisation avec l'haptique.
6. **Tatami comme récompense de volume** (OBS-014, OBS-015). 750 révisions/75 cartes/30 jours (dont un critère affiché non vérifié) pour un reskin de labels. → Soit le mode change réellement le régime linguistique de l'interface (romaji off, traductions au tap), soit il ne mérite pas une porte. Et trancher le système XP/niveaux orphelin (OBS-010) : réexposer ou retirer du binaire.

## Points forts (à ne pas casser)

Direction artistique et identité (noir/or, zéro gamification criarde) ; transparence des intervalles FSRS sous les boutons ; re-queue intra-session des « Encore » ; micro-textes pédagogiques du sélecteur (gojūon/dakuten/yōon) — exacts et remarquablement rédigés ; 3 modes de pratique (dues / libre-compté / points faibles) avec progressive disclosure ; libellé héro « honnête » (à doter d'une légende) ; demande de notifications contextuelle après premier succès ; dialogue de sortie de séance ; boucle [VOCAB] Sakura → dictionnaire ; préférence vocabulaire souple (ne pas durcir vers un i+1 chiffré) ; multi-profils avec restauration propre ; mode fondation du planificateur ; moteur FSRS-5 réel (intervalles croissant correctement avec la maturité) ; VOICEVOX et KanjiVG embarqués et crédités ; le concept du drill haptique d'accent (original, défendable une fois les données corrigées et la particule affichée).

## Recommandations priorisées (impact/effort)

**P0 — avant toute distribution publique** : (1) corriger 犬/男 (deux lignes de données) ; (2) peupler dakuten/yōon (le pipeline et l'UI existent) ; (3) re-keyer la porte Sakura ; (4) autoplay audio au flip ; (5) purger les rationales pseudo-sourcées des docs.
**P1 — le cœur pédagogique** : (6) séquence de présentation + critère de sortie de séance (utilise w17/w18) ; (7) dues prioritaires + profils par stade dans le planificateur ; (8) livret de compétence sur le dashboard (agréger dictionnaire + états kana, palier « en cours d'apprentissage » visible à J0) ; (9) étendre le pipeline de tracés aux kana.
**P2 — finitions structurantes** : (10) sweep i18n complet (Watch, widget, chips, dialogues) ; (11) sorties de navigation manquantes ; (12) suppression de profil + vérifier l'export sur device ; (13) refondre le seeder (vrais kana avec historique FSRS réaliste) ; (14) drill d'accent : particule + synchronisation visuelle ; (15) katakana : ponts か→カ et drills contrastifs シ/ツ・ソ/ン ; (16) Tatami : régime linguistique réel ou suppression de la porte ; (17) trancher le RPG orphelin avant App Store ; (18) feedback correctif dans le quiz Watch ; (19) corriger le crash widget.

## Note méthodologique

Review menée exclusivement sur simulateur (iPhone 17 Pro iOS 26.4 + Apple Watch Series 11) et par échange avec le développeur-relais, sans lecture du code source par le reviewer. Limites : audio et haptique non vérifiables au simulateur ; Sakura non testée en direct (clé API requise) ; états J+30/J+90 non testables sur contenu réel (seeder défaillant, OBS-013) ; micro/VoiceOver hors périmètre. Chaque affirmation pédagogique ou linguistique est adossée à 05-sources.md (Dossiers A, B, C — ~35 sources vérifiées, DOI résolus). Deux constats initialement suspectés se sont révélés être des artefacts d'environnement (crashs SimMetalHost, saisie AZERTY) et ont été écartés — voir 01-journal.md.
