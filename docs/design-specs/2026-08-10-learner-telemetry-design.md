# Journal d'apprentissage exportable — pour review par un agent expert

> Date : 2026-08-10 · Statut : **spec, non implémentée**
> Origine : [review pédagogique du 2026-08-10](../reviews/2026-08-10-expert-japonais-echange.md)
> et `app-review-notes/06-synthese.md`.

## 1. Le besoin

Faire relire **les résultats réels d'un apprenant** par un agent expert de
l'apprentissage du japonais — comme la review du 2026-08-10, mais portant sur
*les performances d'un humain* au lieu de l'app elle-même.

Cadence **non tranchée** : hebdomadaire automatique, ou ponctuelle à la demande.
La spec doit rendre les deux possibles sans rien réécrire (cf. §7).

**Le test de conception :** un agent qui reçoit le paquet doit pouvoir répondre à
« *cet apprenant progresse-t-il correctement, et qu'est-ce qui cloche dans sa
pratique ?* » **sans poser de question de suivi**. Tout ce qui l'obligerait à
demander une précision est un champ manquant.

## 2. Ce qui existe déjà — la prise est posée

L'export de données produit **déjà** un paquet pensé pour l'analyse machine :

| Fichier | Contenu |
|---|---|
| `cards.json` / `cards.csv` | état FSRS par carte (stability, difficulty, reps, lapses, due) |
| `reviews.json` | historique des révisions |
| `outcomes.json` | résultats d'exercices non-SRS (skill, accuracy, timestamp) |
| `rpg.json` | niveau / XP (scopé au profil) |
| `context.json` | **schéma auto-descriptif du modèle de données** |

`context.json` est la pièce maîtresse et elle est déjà là : elle décrit les
champs en langage naturel (« `reps` — Number of successful reviews (0 = new
card) »). **Un agent peut donc comprendre le paquet sans documentation externe.**

→ Cette spec **n'invente pas un système** : elle complète un format existant et
lui ajoute un mode de restitution. Même motif que les autres « prises posées »
relevées en review.

## 3. Ce qui manque, par ordre de valeur pour l'agent

### 3.1 [P0] Les paires de confusion — le manque le plus coûteux

**Aujourd'hui l'app calcule la confusion, l'affiche une fraction de seconde, et
la jette.** `KanaDrillViewModel.selectedOptionCharacter` résout le kana
correspondant à la mauvaise réponse choisie (pour le feedback « le caractère pour
*ru* est る ») — et n'est **jamais persisté**. `ReviewLog` ne stocke que
`(timestamp, card, grade, responseTimeMs)` : on sait que l'apprenant a raté シ,
jamais qu'il l'a confondu avec ツ.

Pire : `LeechDetectionService.ConfusionPattern` **devine** les confusions depuis
une table de kanji visuellement proches, écrite à la main. **L'app extrapole des
confusions pendant qu'elle en observe de vraies et les efface.**

Pour un expert, savoir qu'un apprenant confond **シ/ツ, ソ/ン, る/ろ** vaut plus
que n'importe quel taux de réussite : c'est ce qui distingue « il travaille mal »
de « il bute sur les paires à interférence, ce qui est normal et se traite ».

→ **Ajouter `answeredValue` (et `answeredItem`) à `ReviewLog`.** Champ optionnel :
nul pour un flashcard auto-évalué, renseigné pour tout format à choix.

### 3.2 [P0] La provenance de chaque révision

`ReviewLog` ne dit pas **d'où** vient la note : flashcard auto-évalué, QCM,
drill du pool, séance Home, ou quiz de la Watch. Or la sémantique de la note
change radicalement selon le format — un « Bien » auto-déclaré n'est pas un QCM
réussi.

→ Ajouter `exerciseType` et `surface` (`iphone.session` / `iphone.drill` /
`watch`).

### 3.3 [P0] Le contrat sémantique des notes

L'agent doit savoir ce que valent les 4 boutons — et notamment que **« Difficile »
est une réussite au sens SRS** (aujourd'hui compté en échec dans le % de rappel :
c'est un bug relevé en review, mais l'ambiguïté doit être levée *dans le paquet*
indépendamment du correctif).

→ Étendre `context.json` d'un bloc `grade_semantics` explicite.

### 3.4 [P1] L'accent tonique, par mot

`PitchAccentTracker` persiste en `UserDefaults` des **agrégats par patron**
uniquement : pas de mot, pas d'horodatage, pas d'export. Un expert ne peut donc
pas voir que l'apprenant échoue systématiquement sur les 尾高 — le diagnostic le
plus utile possible sur cette compétence.

→ Journaliser `(word, expectedPattern, answeredPattern, timestamp, surface)` et
l'exporter en `pitch.json`.

### 3.5 [P1] Le détail des exercices productifs

`outcomes.json` ne contient qu'un `accuracy: Double`. Pour le shadowing et
l'écriture, la **nature** de l'erreur est tout : quels mores ont dérapé, quels
traits ont manqué. Les services les calculent déjà (diff LCS, distance de tracé)
puis réduisent à un scalaire.

→ Conserver un champ `detail` (JSON libre, borné en taille) par outcome.

### 3.6 [P1] Le profil d'apprenant et l'écart au modèle

Le paquet doit s'ouvrir sur **qui est cet apprenant** : niveau déclaré à
l'onboarding, set de kana choisi, `desiredRetention` réglée, jours actifs,
ancienneté, langue d'interface.

Et surtout, l'unique métrique qui juge le moteur lui-même :

> **rétention réelle observée vs `desiredRetention` cible.**

Si la cible est 90 % et le réel 72 %, le planning est trop agressif ou les notes
sont mal calibrées — et **c'est invisible partout aujourd'hui**.

→ `learner.json`.

### 3.7 [P2] Le contexte de séance

Durée budgétée vs réelle, abandons et à quel exercice, heure de la journée,
composition planifiée vs jouée. C'est ce qui permet de distinguer « il n'apprend
pas » de « il fait ses séances à 23 h 40 en 90 secondes ».

→ `sessions.json`.

## 4. Le paquet de review

Un dossier `learner-review-<ISO8601>/`, sur-ensemble de l'export actuel :

```
learner.json      # profil, cible de rétention, rétention réelle, fenêtre couverte
reviews.json      # + answeredValue, exerciseType, surface
confusions.json   # agrégat dérivé : paires, occurrences, tendance
pitch.json        # accent tonique par mot
outcomes.json     # + detail
sessions.json     # contexte de séance
cards.json        # état FSRS (inchangé)
context.json      # schéma auto-descriptif — ÉTENDU aux nouveaux fichiers
brief.md          # ← nouveau, voir §5
```

`confusions.json` est **dérivé**, pas stocké : il s'agrège depuis `reviews.json`
au moment de l'export. Rien de neuf à persister au-delà de `answeredValue`.

## 5. `brief.md` — la pièce qui fait la différence

Un fichier en langage naturel, généré, qui **dit à l'agent ce qu'on attend de
lui**. Sans ça, chaque review repart de zéro et les résultats ne sont pas
comparables d'une semaine à l'autre.

Il contient : la fenêtre couverte, ce que l'app enseigne réellement aujourd'hui
(**y compris ses trous connus** — sans quoi l'agent signalera « aucun dakuten
travaillé » comme un défaut de l'apprenant), les questions posées, et le format
de réponse attendu.

> **Règle d'honnêteté :** le brief doit déclarer les limites de l'app. La review
> du 2026-08-10 a montré qu'un brief inexact fait perdre un round entier — cf.
> l'étape « setup IA » qui n'existait pas.

Questions par défaut :
1. Cet apprenant progresse-t-il à un rythme sain pour son ancienneté ?
2. Quelles confusions récurrentes, et lesquelles sont normales vs à traiter ?
3. La rétention réelle est-elle cohérente avec la cible ? Si non, sur-révision ou
   sous-révision ?
4. Quelles compétences sont en retard, et est-ce dû à l'apprenant ou à ce que
   l'app ne propose pas ?
5. Trois actions concrètes pour la semaine à venir.

## 6. Confidentialité — bloquant, non négociable

Ce paquet décrit **le comportement d'apprentissage d'une personne**. L'envoyer à
un agent est une transmission à un tiers.

- **Opt-in explicite**, désactivé par défaut. Jamais d'envoi silencieux.
- **Écran de consentement** nommant le destinataire réel (fournisseur LLM), avec
  la possibilité de **lire le paquet avant envoi**.
- **Pas d'envoi automatique** tant que la cadence n'est pas tranchée (§7) : la
  V1 est *export local + partage manuel*.
- Mettre à jour `docs/privacy.html` **et** `PrivacyInfo.xcprivacy` **avant** que
  la fonctionnalité existe, pas après.
- Aucun texte libre de l'utilisateur dans le paquet (les `contextSnippet` des
  rencontres de vocabulaire peuvent contenir des phrases écrites par lui) sauf
  opt-in séparé.

> Contexte : la politique de confidentialité a déjà été mise en conformité une
> fois après avoir contredit les flux réels. Ne pas refaire l'erreur dans l'autre
> sens.

## 7. Cadence — les deux options, sans choisir maintenant

La spec est conçue pour que le choix reste ouvert :

| | Hebdomadaire | Ponctuel |
|---|---|---|
| Déclencheur | tâche en arrière-plan, jour fixe | bouton « Faire relire ma progression » |
| Fenêtre | 7 jours glissants | depuis la dernière review, ou tout |
| Risque | transforme le calme en reporting périodique — **contraire à la thèse anti-burnout** | l'apprenant ne le fait jamais |

**Recommandation :** commencer **ponctuel**, et n'introduire l'hebdomadaire que
si l'usage montre qu'on le demande. Un rapport hebdomadaire non sollicité est un
streak déguisé — exactement ce que le produit refuse.

Dans les deux cas, la génération du paquet est **identique** : seul le
déclencheur et la fenêtre changent.

## 8. Ce qu'on ne journalise PAS

Cadrage explicite, pour que ça ne dérive pas en télémétrie de surveillance :

- pas de frappe au clavier, pas de parcours de navigation, pas de heatmap ;
- pas d'audio ni d'image (les enregistrements de shadowing restent locaux et
  éphémères) ;
- pas d'identifiant d'appareil, pas de géolocalisation, pas d'IP ;
- pas d'analytics tiers — **le paquet est le seul artefact, et il est lisible
  par son propriétaire**.

Tout ce qui est journalisé doit avoir un **destinataire pédagogique nommé**. Si
on ne sait pas quelle question du §5 un champ sert à répondre, on ne le
journalise pas.

## 9. Découpage

**Lot 1 — rendre les données dicibles** (aucune UI)
`answeredValue` + `exerciseType` + `surface` sur `ReviewLog` (migration de
schéma : nouvelle version + étape légère) ; `confusions.json` dérivé ;
`grade_semantics` dans `context.json`.
*Livre déjà la valeur principale : les paires de confusion deviennent
observables.*

**Lot 2 — le paquet**
`learner.json` (dont rétention réelle vs cible), `brief.md` généré, extension de
`context.json`, dossier `learner-review-*`.

**Lot 3 — les compétences fines**
`pitch.json` (sortir `PitchAccentTracker` de `UserDefaults`), `detail` sur les
outcomes, `sessions.json`.

**Lot 4 — la boucle**
Écran de consentement, bouton « Faire relire ma progression », mise à jour des
surfaces de confidentialité. *Décider la cadence ici, pas avant.*

## 10. Dépendance à corriger d'abord

Le **seeder fixture est inutilisable** (recto `人0`, `日1`, aucun kana, prénom
écrasé, dictionnaire vidé). Impossible de fabriquer un apprenant synthétique
crédible pour tester le paquet — donc impossible de valider cette fonctionnalité
autrement qu'en attendant des semaines de données réelles.

→ **Réparer le seeder est un prérequis**, pas une tâche parallèle.
