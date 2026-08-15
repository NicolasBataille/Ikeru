# Contre-review pédagogique — Ikeru (dossier 2)

**Statut : en attente du signal de démarrage.**

Ce dossier contient les notes d'une **seconde review pédagogique indépendante** de
l'app iOS Ikeru (apprentissage du japonais), menée par un reviewer expert
distinct du premier.

## Protocole de contre-review en aveugle

Il existe un dossier `app-review-notes/` à la racine du repo, produit par une
première review menée par un autre expert. Ce dossier-ci (`app-review-notes-2/`)
est le produit d'une **seconde review, en aveugle total** vis-à-vis de la
première :

- Le reviewer 2 n'a **pas lu** et **ne lira pas** `app-review-notes/` avant la
  fin de son propre travail.
- Le reviewer 2 sait seulement que ce dossier existe — rien de son contenu.
- L'objectif est d'obtenir deux jugements experts **indépendants** sur la même
  app, puis de comparer leur convergence/divergence. C'est cette comparaison,
  faite en toute fin de processus, qui constitue la valeur ajoutée du
  protocole global (un seul avis expert est faillible ; deux avis
  indépendants qui convergent sont un signal fort, deux avis qui divergent
  identifient les zones d'incertitude réelle).
- La comparaison avec la review 1 n'a lieu **qu'après la levée du pare-feu**,
  une fois cette review 2 achevée et figée. Voir `06-synthese.md`, dernière
  section.

## Pare-feu d'indépendance

Deux règles absolues, valables jusqu'à la fin de la review :

1. **Jamais de lecture du code source de l'app** — review en boîte noire
   stricte, uniquement via le simulateur iOS / l'appareil et le dialogue avec
   le développeur.
2. **Jamais de lecture de `app-review-notes/`** (ni de tout résumé, extrait ou
   paraphrase qui en proviendrait) avant la fin complète de cette review 2 et
   la rédaction figée de `06-synthese.md`.

Toute violation de ces deux règles invalide l'indépendance de la contre-review
et doit être consignée immédiatement dans `01-journal.md`.

## Index des fichiers

| Fichier | Rôle |
|---|---|
| `README.md` | Ce fichier — index et statut du dossier |
| `00-methodologie.md` | Protocole complet : rounds, grille d'évaluation, sévérités, règle de sourçage, règles de sécurité |
| `01-journal.md` | Journal daté de la session, entrées les plus récentes en tête |
| `02-decouverte-app.md` | Parcours naïf Round 0, brief du dev, inventaire des fonctionnalités |
| `03-observations.md` | Tableau des observations (OBS2-XXX) |
| `04-questions-dev.md` | Questions posées au développeur/presenter |
| `05-sources.md` | Bibliographie vérifiée, avec lien vers les OBS2 qu'elle appuie |
| `06-synthese.md` | Verdict global, priorisation P0/P1/P2, comparaison finale avec la review 1 |

## Prochaine étape

En attente du **signal de démarrage** de l'utilisateur, ainsi que du **nom de
l'agent interlocuteur** côté développeur (voir `01-journal.md`). Rien ne doit
être écrit dans `02-decouverte-app.md` ni `03-observations.md` avant ce
signal.
