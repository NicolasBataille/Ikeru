# Traductions françaises du contenu N5

Ces quatre fichiers portent la version **française** du contenu pédagogique
embarqué dans `Ikeru/Resources/ContentBundles/n5-content.sqlite`.

| Fichier            | Entrées | Colonnes SQLite écrites                          |
| ------------------ | ------: | ------------------------------------------------ |
| `vocabulary.json`  |     693 | `vocabulary.meaning_fr`                           |
| `sentences.json`   |      96 | `sentences.french`                                |
| `grammar.json`     |      31 | `grammar_points.title_fr`, `explanation_fr`, `examples_fr` |
| `kanji.json`       |      90 | `kanji.meanings_fr`                               |

## Pourquoi on traduit nous-mêmes (et pourquoi il ne faut PAS « simplifier » en important JMdict)

La page de licence de l'EDRDG précise que, pour **JMdict**, seuls « les
composants japonais et anglais » sont couverts par sa licence : « les
équivalents dans d'autres langues, p. ex. allemand, **français**, néerlandais,
sont couverts par un copyright distinct détenu par les compilateurs de ce
matériel ». Le statut juridique des gloses **françaises** est donc **non
résolu** — et ce dépôt est **public**.

Les textes anglais d'Ikeru, eux, ont été **rédigés à la main pour l'app**
(c'est ce qu'affirme `AttributionView.swift`, et ça reste vrai). Ces fichiers
sont la **traduction de notre propre texte anglais**, en s'appuyant sur le
japonais comme source de vérité — aucune glose tierce, d'aucun dictionnaire ni
d'aucune base de vocabulaire japonais-français, n'y a été copiée ni consultée.

**Conséquence pratique : ne jamais remplacer ce travail par un import
automatique de gloses françaises tierces.** Ça réintroduirait exactement le
problème de licence que ces fichiers existent pour éviter.

Le même raisonnement a été appliqué à l'anglais le 2026-08-16, quand le
vocabulaire est passé de 205 à 693 mots. La **liste** vient de Tanos (CC BY),
mais son paquet contenait aussi une colonne de gloses anglaises, et on ne l'a
pas importée : le site ne dit nulle part d'où elles viennent. Voir
`scripts/tanos/README.md`. Donc les 488 gloses anglaises ajoutées sont, comme
les françaises, écrites pour Ikeru.

## Clé : `word`, pas `id`

`vocabulary.json` est indexé sur le **mot**. Il l'était sur l'`id` jusqu'au
2026-08-16, et c'était un piège : les id sont attribués par énumération dans
`generate_content_bundles.py`, donc insérer 488 mots les décalait tous — le
français serait parti sur les mauvais mots **sans une seule erreur**. Les
autres fichiers restent sur `id`, leurs tables ne bougeant pas.

## Appliquer au bundle

```bash
python3 scripts/apply-content-fr.py            # écrit dans le bundle
python3 scripts/apply-content-fr.py --dry-run  # valide tout, puis annule
```

Le script est **idempotent** (les colonnes ne sont ajoutées que si elles
manquent) et **échoue bruyamment** : une entrée JSON qui ne correspond à
aucune ligne, ou une ligne du bundle laissée sans traduction, interrompt le
run avec un statut non nul. Un trou silencieux dans le contenu serait invisible
jusqu'à l'écran de l'apprenant.

## Régénérer / modifier

Il n'y a **pas** de génération automatique : ces fichiers sont écrits et relus
à la main. Pour corriger une entrée, éditer le JSON puis rejouer le script —
le bundle est réécrit sur place, sans migration.

Conventions de rédaction, tenues sur les quatre fichiers :

- **Le japonais ne se traduit jamais** — il reste caractère pour caractère.
- **Les explications tutoient** l'apprenant (comme le reste de l'app,
  cf. `Ikeru/Localization/Localizable.xcstrings`) ; **les phrases d'exemple
  vouvoient**, parce qu'elles reflètent le registre poli du japonais source
  (です / ます / ください).
- Terminologie grammaticale française établie : « particule », « forme polie »,
  « forme du dictionnaire », « adjectif en -i » / « en -na », « thème » /
  « sujet ». Les termes japonais courants (kanji, kana, hiragana, katakana,
  furigana) restent invariables au pluriel.
- Typographie : apostrophes droites et guillemets « français », alignés sur le
  catalogue de l'app.

## Ce qui n'est PAS traduit

- `radicals.meaning` — visible via `radicalsForKanji`, mais aucun fichier de
  traduction n'existe pour cette table ; elle reste en anglais.
- `sentences.french` est peuplée mais **n'a pas encore de lecteur** :
  `ContentRepository` ne sert que le japonais des phrases, et rien dans l'app
  ne lit `sentences.english` non plus aujourd'hui.

Pour tout ce qui manque, `ContentRepository` sert **l'anglais** ligne par ligne
plutôt qu'un champ vide (voir `ContentLanguage` et les tests
`ContentRepositoryLanguageTests`).
