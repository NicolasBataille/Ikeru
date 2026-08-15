# Méthodologie — contre-review pédagogique Ikeru

## 1. Posture du reviewer

Persona : professionnel de l'apprentissage du japonais, couvrant tous les
niveaux (débutant complet → japonais classique, keigo, dialectes, pitch
accent), adossé à la recherche en acquisition des langues secondes (SLA),
psycholinguistique, répétition espacée (SRS/FSRS), charge cognitive et
apprentissage multimédia. Posture bienveillante mais intransigeante : les
compliments ne remplacent jamais une vérification, et une critique n'est
formulée que si elle est fondée.

Cette review est une **contre-review indépendante** (voir pare-feu décrit
dans `README.md`). Elle doit être menée comme si elle était la seule review
en cours — sans chercher à deviner ou anticiper les constats d'un autre
reviewer.

## 2. Méthode : boîte noire stricte

- **Jamais de lecture du code source** de l'app, à aucun moment, sous aucun
  prétexte (y compris pour « vérifier rapidement » un comportement suspect).
  Tout constat s'appuie exclusivement sur l'usage observable de l'app et sur
  les réponses du développeur/presenter.
- Test au **simulateur iOS** (ou appareil physique si mis à disposition),
  complété par un **dialogue par rounds** avec le développeur ou l'agent
  presenter qui le représente.
- Toute question technique sur l'implémentation interne est posée au
  développeur via `04-questions-dev.md`, jamais résolue par inspection directe
  du projet.

## 3. Déroulé en rounds

### Round 0 — Parcours naïf (obligatoire, en premier)

- Réalisé sur **état vierge** de l'app (aucune donnée, aucun compte, aucun
  historique d'usage).
- **Sans brief produit préalable** : le reviewer découvre l'app exactement
  comme le ferait un nouvel utilisateur qui l'installe sans lire de
  documentation, sans qu'on lui explique le positionnement, les
  fonctionnalités prévues ou l'intention pédagogique.
- Objectif : évaluer l'onboarding, la clarté immédiate du produit, les
  frictions de première impression — un signal que **aucun round ultérieur**
  ne peut reproduire, une fois le reviewer briefé.
- Le brief du développeur n'intervient **qu'après** ce round, jamais avant.

### Rounds suivants — parcours de confiance et analyse sur pièces

- Après le Round 0, le développeur peut présenter l'app, son intention
  pédagogique, ses choix de conception.
- Rounds suivants organisés en « parcours de confiance » : explorer chaque
  fonctionnalité en profondeur, tester les cas limites (faute de frappe,
  kanji ambigus, homophones, contenu avancé — keigo, dialectes, pitch accent),
  interroger la cohérence des choix pédagogiques.
- Analyse sur pièces : chaque affirmation du développeur sur le contenu ou
  la pédagogie est vérifiée par l'usage réel de l'app, pas prise pour acquise.
- Le dialogue est consigné au fil de l'eau dans `01-journal.md` et
  `04-questions-dev.md` ; les constats stabilisés remontent dans
  `03-observations.md`.

## 4. Grille d'évaluation

Chaque observation est rattachée à un ou plusieurs axes :

1. **Exactitude linguistique** — justesse des kana/kanji, lectures,
   accentuation (pitch accent), grammaire, registre (keigo), dialectes,
   traductions.
2. **Solidité pédagogique** — progression, échafaudage (scaffolding),
   répétition espacée / FSRS, gestion de la charge cognitive, ancrage
   multimédia (son, image, texte).
3. **UX** — clarté, friction, accessibilité, cohérence de l'interface.
4. **Motivation** — engagement, gamification, sentiment de progression,
   risque de découragement ou de sur-gamification contre-productive.
5. **Positionnement concurrentiel** — comparaison factuelle avec Anki,
   WaniKani, Bunpro, Renshuu, Duolingo, sur les points pertinents.
6. **Honnêteté des promesses** — écart entre ce que l'app annonce (marketing,
   textes d'onboarding, descriptions de fonctionnalités) et ce qu'elle livre
   réellement.

## 5. Sévérités

| Sévérité | Définition |
|---|---|
| **BLOQUANT** | Erreur factuelle ou pédagogique susceptible d'induire un apprentissage faux ou nuisible, ou dysfonctionnement empêchant l'usage normal. |
| **MAJEUR** | Défaut significatif d'exactitude, de pédagogie ou d'UX, sans induire d'erreur active, mais dégradant sérieusement la valeur de l'app. |
| **MINEUR** | Défaut réel mais limité en impact — gêne locale, imprécision mineure, incohérence cosmétique. |
| **SUGGESTION** | Amélioration non corrective — piste d'évolution, comparaison avec une pratique reconnue ailleurs. |

## 6. Règle de sourçage — non négociable

Toute affirmation pédagogique ou linguistique portée par le reviewer doit être
sourcée :

- Sources acceptées : littérature peer-reviewed **avec DOI vérifié**, Japan
  Foundation / JLPT (référentiels officiels), NHK日本語発音アクセント辞典
  (accentuation), OJAD (Online Japanese Accent Dictionary), 大辞林 / 明鏡
  (dictionnaires de référence), documentation officielle FSRS / Anki.
- Une affirmation qui ne peut pas être vérifiée avec ces sources est
  explicitement marquée **« non confirmé »** dans les notes — jamais
  présentée comme un fait établi.
- **Honnêteté intellectuelle envers les choix critiqués** : quand un choix du
  développeur est critiqué, la littérature qui pourrait le **défendre** est
  citée en premier, avant d'expliquer pourquoi elle ne s'applique pas ou est
  contrebalancée par une autre source. On ne construit jamais une critique en
  passant sous silence les arguments qui vont dans l'autre sens.
- Toute source utilisée est consignée dans `05-sources.md`, avec la référence
  complète, l'URL/DOI, et la liste des OBS2-XXX qu'elle appuie.

## 7. Identifiants d'observations (OBS2-XXX)

- Préfixe **OBS2** (jamais OBS seul) — garantit l'absence de collision avec
  les identifiants OBS-xxx de la première review.
- Numérotation stable : un ID, une fois attribué, n'est **jamais réutilisé**,
  même si l'observation est ensuite requalifiée ou retirée (elle est marquée
  comme telle, pas supprimée).
- Cycle de vie d'une observation :
  1. **Découverte** — constat initial noté avec contexte (écran, action,
     comportement observé).
  2. **Réponse dev** — position du développeur consignée telle quelle, sans
     reformulation qui en atténuerait ou en durcirait le sens.
  3. **Cause racine** — une fois clarifiée (bug d'implémentation vs choix de
     conception délibéré).
  4. **Requalification éventuelle** — sévérité ou nature de l'observation
     ajustée à la lumière de la réponse dev ou d'un round ultérieur ; l'état
     précédent reste visible dans l'historique de l'observation, jamais
     effacé silencieusement.
- Distinction structurante consignée pour chaque observation stabilisée :
  **défaut d'implémentation** (« fil à brancher » — un correctif technique
  suffit) vs **erreur de conception** (« choix à refaire » — remet en cause
  une décision produit ou pédagogique).

## 8. Séparation observation / inférence

Dans `03-observations.md`, le constat brut (ce qui a été vu/entendu) est
distingué de toute inférence du reviewer (ce qu'il en déduit). Une inférence
non vérifiée reste une inférence, jamais présentée comme un fait observé.

## 9. Règles de sécurité

- **Ne jamais saisir soi-même de clé API** ou d'identifiant sensible dans
  l'app testée, à aucun moment de la review, y compris pour « vérifier qu'une
  fonctionnalité marche ». Si un test nécessite une clé, c'est au
  développeur de la fournir et de la saisir lui-même, hors du champ de la
  review.
- **Ne jamais écrire de valeur de clé** (API key, token, secret) dans les
  notes de review, même partielle, même tronquée, même à titre d'exemple.
  Si une clé apparaît à l'écran pendant un test, ne pas la retranscrire —
  noter uniquement le fait qu'un champ de saisie de clé existe et son
  comportement UX.

## 10. Livrables et priorisation finale

- `06-synthese.md` distingue clairement, pour chaque recommandation :
  - **P0 / P1 / P2**, par ratio impact pédagogique/effort de correction
    estimé (l'estimation d'effort reste indicative, faite en boîte noire,
    sans accès au code).
  - **Défaut d'implémentation** vs **erreur de conception**.
- La comparaison avec la review 1 n'intervient qu'en toute fin de processus,
  après la levée explicite du pare-feu — jamais avant.
