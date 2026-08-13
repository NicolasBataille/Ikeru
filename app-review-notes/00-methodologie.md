# Méthodologie de review

## Principes

- **Objectivité totale** : la review n'a pas pour but de valider le travail du
  développeur, mais d'évaluer l'app comme le ferait un enseignant/chercheur
  indépendant face à un produit commercial. Aucun enjeu de complaisance.
- **Aucune complaisance** : un constat n'est pas atténué parce que l'app est
  en développement, non financée, ou portée par une seule personne. La
  sévérité d'un problème pédagogique ou d'exactitude linguistique est évaluée
  sur ses mérites, indépendamment du contexte de production.
- **Chaque critique pédagogique doit être appuyée sur une source vérifiable.**
  Aucune affirmation du type « c'est mieux de faire X » n'est acceptée sans
  référence. Types de sources attendues :
  - Recherche en acquisition des langues secondes (SLA) et psycholinguistique
    appliquée au japonais.
  - Références standards de la langue japonaise : Japan Foundation (JLPT
    Can-do, référentiels JF Standard), échelles JLPT officielles.
  - Référence phonologique : NHK日本語発音アクセント辞典 (dictionnaire NHK
    d'accentuation) pour toute question de pitch accent.
  - Littérature sur la répétition espacée et la rétention en mémoire à long
    terme (ex. Cepeda et al. 2006, Karpicke & Roediger 2008, et autres
    travaux comparables) pour toute évaluation d'un mécanisme de SRS.
  - Les références **exactes** (auteurs, année, titre, URL) sont collectées
    au fil de l'eau dans [`05-sources.md`](05-sources.md) — **aucune citation
    n'est inventée ou approximée à l'avance** dans ce document
    méthodologique.

## Protocole

1. **Présentation de l'app par le développeur** — contexte, intentions,
   public visé, périmètre actuel vs. prévu.
2. **Première prise en main naïve sur simulateur iOS** — parcours d'un
   nouvel utilisateur, sans aide, pour évaluer l'onboarding et l'intuitivité
   telle qu'un vrai utilisateur la vivrait.
3. **Exploration systématique de chaque fonctionnalité** — passage en revue
   exhaustif de tous les écrans et mécaniques, au-delà du parcours naïf.
4. **Évaluation pédagogique de chaque mécanique d'apprentissage** — analyse
   critique de la solidité didactique de chaque système (SRS, progression,
   feedback, etc.).
5. **Questions au développeur** — clarifications sur les choix de conception,
   consignées dans [`04-questions-dev.md`](04-questions-dev.md).
6. **Recherche documentaire (subagents)** — étayage de chaque point critique
   par une recherche de sources dédiée, consignée dans
   [`05-sources.md`](05-sources.md).
7. **Synthèse finale avec verdict** — bilan consolidé dans
   [`06-synthese.md`](06-synthese.md).

## Grille d'évaluation

Chaque fonctionnalité et chaque écran sont évalués selon les axes suivants :

- **Exactitude linguistique** — kana, kanji, vocabulaire, pitch accent, audio
  (justesse phonétique, cohérence des lectures, absence d'erreurs factuelles).
- **Solidité pédagogique** — conception du SRS, cohérence de la progression,
  gestion de la charge cognitive, mécanismes favorisant la rétention à long
  terme.
- **UX / ergonomie** — clarté des parcours, cohérence des interactions,
  accessibilité, absence de friction inutile.
- **Motivation / engagement** — mécaniques de fidélisation, gamification,
  pertinence et honnêteté de ces mécaniques du point de vue de
  l'apprentissage (vs. engagement pour l'engagement).
- **Positionnement face aux alternatives** — comparaison argumentée avec
  Anki, WaniKani, Duolingo, Renshuu, et autres outils de référence sur le
  marché de l'apprentissage du japonais.
- **Honnêteté des promesses** — cohérence entre ce que l'app annonce
  (niveau visé, méthode, résultats attendus) et ce qu'elle délivre
  effectivement.

## Échelle de sévérité des constats

| Sévérité | Signification |
|---|---|
| **BLOQUANT** | Erreur factuelle, contresens pédagogique ou dysfonctionnement qui compromet directement l'apprentissage ou induit l'utilisateur en erreur. À corriger avant toute sortie. |
| **MAJEUR** | Problème significatif de conception pédagogique, d'UX ou d'exactitude qui dégrade sérieusement l'expérience ou l'efficacité d'apprentissage, sans être disqualifiant en soi. |
| **MINEUR** | Imperfection ponctuelle, incohérence locale ou détail d'exactitude qui mérite correction mais n'affecte pas fondamentalement l'expérience. |
| **SUGGESTION** | Piste d'amélioration ou d'enrichissement, non liée à un défaut constaté. |
