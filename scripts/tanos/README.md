# Liste de vocabulaire N5 — source Tanos

Ce dossier contient **une liste de mots**, et rien d'autre : quels mots figurent
au programme du JLPT N5, et comment ils se lisent.

| Fichier | Rôle |
| --- | --- |
| `build-vocab-list.py` | Télécharge le paquet Anki de tanos.co.uk et en extrait la liste |
| `n5-word-list.json` | Le résultat : 662 mots, forme écrite + lecture en hiragana |

```bash
python3 scripts/tanos/build-vocab-list.py            # retélécharge et régénère
python3 scripts/tanos/build-vocab-list.py --deck FICHIER   # depuis une copie locale
```

## Ce qu'on prend, et ce qu'on ne prend pas

**Pris** : le mot et sa lecture. Ce sont des faits — sur le JLPT d'un côté, sur
la langue japonaise de l'autre.

**PAS pris : les traductions anglaises.** Le paquet en contient (champ d'ordinal
1) ; le script ne lit jamais cet ordinal, et il **vérifie** la disposition des
champs avant d'extraire quoi que ce soit, pour qu'un paquet ré-uploadé avec des
champs réordonnés ne fasse pas entrer de l'anglais dans la colonne des lectures.

La licence du site est pourtant permissive : « Everything on this site (that I'm
not selling), is licenced under Creative Commons "BY" » (relevé le 2026-08-16).
Mais **le site ne dit nulle part d'où viennent ses gloses anglaises**, et elles
sont plausiblement dérivées d'EDICT/JMdict — auquel cas le CC BY n'était pas
celui de Waller à accorder sur cette couche-là. Les lectures de kanji du bundle
sont déjà dérivées de KANJIDIC, et on l'a découvert **après** que l'app ait
affiché le contraire à l'écran (cf. `AttributionView.swift`). Importer une
colonne de gloses à la provenance invérifiable dans un dépôt **public**
referait la même erreur, avec une chaîne de licence pire.

Donc Ikeru écrit ses propres gloses anglaises pour ces 483 mots, exactement
comme `scripts/content-fr/` le fait déjà pour le français. Le résultat vit dans
`scripts/content/vocabulary.json`.

C'est vérifiable, pas juste affirmé : la colonne `vocabulary.list_source` du
bundle porte `tanos` ou `ikeru` **par ligne**.

```sql
SELECT list_source, COUNT(*) FROM vocabulary GROUP BY 1;
-- ikeru|205   tanos|483
```

## Attribution

CC BY demande le crédit, et le site demande un lien. Les deux sont dans
`AttributionView` (carte « Tanos JLPT lists », lien vers la page de partage).

## `n5-word-list.json` n'est PAS la source de vérité du bundle

Ce fichier est le **relevé fidèle** de ce que dit Tanos, corrections de lecture
comprises. Le vocabulaire réellement expédié vit dans
`scripts/content/vocabulary.json`, qui est *curé* : c'est là que les décisions
d'Ikeru sont prises, et elles ne remontent pas ici.

La plus visible : **11 lignes de la source joignent deux formes écrites par une
barre oblique** (`丸い/円い`, `伯母さん/叔母さん`, `キロ/キログラム`, `いい/よい`…).
Comme recto de carte, `いい/よい` n'est pas un mot. Elles sont devenues 16
entrées dans le fichier curé, une décision par ligne :

- `川/河` et `いい/よい` → seule la variante entre (`河`, `よい`) : `川` et `いい`
  étaient déjà dans la liste d'Ikeru.
- `じゃ/じゃあ`, `そうして/そして`, `ラジカセ / ラジオカセット` → une seule forme,
  celle qu'un apprenant rencontre ; la contraction et la variante rare sautent.
- `キロ` apparaît dans **deux** lignes source (kg et km) : une seule entrée, dont
  la glose dit l'ambiguïté au lieu de trancher au hasard, plus `キログラム` et
  `キロメートル` séparément.
- `伯母さん/叔母さん`, `伯父/叔父`, `初め/始め`, `丸い/円い` → deux entrées, parce
  que le choix du kanji porte une vraie distinction.

Refaire tourner `build-vocab-list.py` **ne rejoue pas** ces décisions : il
réécrit le relevé, pas le fichier curé.

## Défauts de la source, corrigés ici

- **`左` est donné pour `はだり`** — le mot se lit `ひだり`. Corrigé par
  `_READING_CORRECTIONS`. Trouvé en diffant les 179 mots qui recoupent les
  entrées écrites à la main d'Ikeru : c'est la **seule** raison pour laquelle il
  a été vu. Ne pas en déduire que les 483 autres sont propres — la passe de
  vérification des gloses relit chaque lecture pour cette raison.
- **163 entrées sans lecture**, toutes en kana seul (101 hiragana, 62 katakana).
  La lecture est dérivée : un mot en hiragana se lit lui-même, un mot en
  katakana est translittéré (`パン` → `ぱん`, convention déjà en place dans le
  bundle). Aucun mot portant un kanji n'est sans lecture — le script *échoue* si
  ça change, plutôt que de deviner.
- **9 entrées à lectures multiples** séparées par `、` (`木` → `き、もく`). La
  première devient la lecture principale, les autres sont conservées dans
  `alternate_readings` au lieu d'être jetées.
