# Tatoeba sentence corpus

The 317 imported example sentences in `Ikeru/Resources/ContentBundles/n5-content.sqlite`
come from here. The 96 that were already in the bundle are Ikeru's own and are
untouched.

## Provenance and licence

| | |
|---|---|
| Source | [Tatoeba](https://tatoeba.org) per-language exports |
| Files | `jpn_sentences.tsv`, `fra_sentences.tsv`, `jpn-fra_links.tsv` |
| Snapshot | downloaded 2026-08-15 |
| Licence | **CC BY 2.0 FR** — attribution required, commercial use allowed |

> "These files are released under CC BY 2.0 FR." — <https://tatoeba.org/en/downloads>

Attribution is rendered in-app by `Ikeru/Views/Settings/AttributionView.swift`
(Réglages → Attribution), in French and English.

**No Tatoeba audio is imported, and none may be.** Tatoeba's audio is licensed
separately, per contributor: "If the license field is empty, you may not reuse
the audio outside the Tatoeba project." Pronunciation in Ikeru comes from the
app's own VOICEVOX pipeline (`scripts/generate-audio.py`). The imported
sentences have **no bundled clip yet** — `AudioService.playTTS` falls back to
on-device synthesis for them until `generate-audio.py` is re-run.

Nothing from **JMdict** is imported. That is a different licence question with
a different answer — see `scripts/content-fr/README.md`.

## What was imported, and what was not

Every Japanese sentence and every French translation is reproduced **verbatim**.
Two purely typographic normalisations are applied to the French, both to match
the 96 sentences already in the bundle (`normalise_french` in `build-corpus.py`):
curly apostrophe → straight, and a plain space before `? ! ; :`. No word is
added, removed, reordered or rephrased.

## The funnel

Run `build-corpus.py --verbose` to reproduce these counts.

| stage | kept | dropped | why |
|---|---:|---:|---|
| jpn↔fra pairs | 43 689 | — | every linked pair in the exports |
| script | 40 431 | 3 258 | latin letters, digits, `「」`, `〜` — the bundle teaches kanji numerals, not `1732` |
| single sentence | 39 698 | 733 | a `。？！` mid-string means two sentences or a dialogue |
| is a sentence | 39 505 | 193 | fewer than 2 hiragana ⇒ no grammar, e.g. `一、二、三、四、五。` |
| **kanji floor** | **2 515** | 36 990 | one kanji outside the bundle's 90 and the learner cannot read the line |
| length 6–18 | 2 106 | 409 | see below |
| katakana allowlist | 1 428 | 678 | proper nouns — トム alone is in 201 candidate pairs |
| topic | 1 428 | 0 | already emptied by the kanji floor (死, 殺, 戦争, 酒 are not taught kanji) |
| register | 1 392 | 36 | plain imperatives (`見ろ。`), `〜な` prohibitive, `〜ぞ / 〜ぜ` |
| french quality | 1 386 | 6 | digits, quotes, parentheses, no final punctuation, crude vocabulary |
| **lexical i+1** | **1 010** | 376 | see below |
| vocabulary anchor | 826 | 184 | no bundle word ⇒ no production reader would ever serve it |
| one French per Japanese | 686 | 140 | Tatoeba offers several; the oldest `fra` id wins |
| not already bundled | 680 | 6 | the same Japanese already exists among the 96 |
| near-duplicate collapse | 638 | 42 | `あの本は小さい。` and `その本は小さい。` drill the same item |
| **cap: 5 per word** | **317** | 321 | see below |

### Why these thresholds

**Kanji floor (the 90 bundled kanji).** Non-negotiable, but *not sufficient*:
`きりがない` passes it and is nowhere near N5. Everything below exists because
of that.

**Length 6–18 characters.** Under 6, Tatoeba yields interjections — `はい。`,
`じゃ。`, `やあ！` — which teach no structure and are useless for shadowing or
sentence construction. Over 18, sentences start stacking clauses, proper nouns
and N3 grammar (`まるで母国語であるかのように`). The band holds 2 106 of the
2 515 sentences that clear the kanji floor, so the bound costs little.

**Lexical i+1: at most 2 unknown words, each common corpus-wide.**
A token counts as *known* when it is (a) grammatical glue, (b) a bundle word or
its kanji stem, or (c) a loanword from the reviewed katakana allowlist.

*Glue* is derived from the data, not hand-listed: a hiragana-only token
appearing in ≥ 0.2 % of the 248 866-sentence Japanese corpus (≥ 498 sentences)
is a particle, a copula form or an inflection fragment — that is what the head
of a frequency table over a closed class looks like. 164 types.

Two unknowns rather than one, because the bundle holds 206 words where a real
N5 lexicon is roughly four times that; against so small a reference, "one
unknown" would mean "already in the bundle", not "i+1". Each unknown must
itself appear in ≥ 150 corpus sentences, which is what separates a common word
a beginner will meet again (テーブル, よろしく, どうぞ) from an idiom fragment
(`きり` 57, `いたずら` 58, `ぐあい` 2).

**Katakana allowlist, not a name blocklist.** Blocklisting Tatoeba's cast is an
endless game. The funnel instead allowlists ~66 everyday loanwords, hand-picked
from the katakana actually present in the candidate set. Alcohol and tobacco
(ビール, ワイン, アルコール, タバコ) and coarse register (バカ, ケチ, ナンパ)
are deliberately left out.

**One French per Japanese: the lowest `fra` id.** Among translations that all
pass the quality gate, the oldest is the one that has been visible — and
correctable — on Tatoeba the longest. Deterministic, and it does not require
judging French style.

**Cap of 5 sentences per vocabulary word.** The one production reader is
`SELECT japanese FROM sentences WHERE vocabulary_word = ?`, and both views that
render the result `ForEach` it whole. Uncapped, 私 or 何 would flood the card.
The cap is also what spreads the corpus: sentences are assigned rarest-word
first, so 86 distinct words gain examples instead of a dozen collecting
everything. **321 sentences passed every quality gate and were dropped by this
cap alone** — they are not bad sentences, only surplus for the reader that
exists today. Raising `MAX_PER_VOCAB_WORD` recovers them.

## Coverage obtained

- **Vocabulary**: 86 of the 206 bundled words gained imported examples. Combined
  with the original 96 sentences, **126 of 206 words now have at least one
  example**, up from 96.
- The 80 words with none are largely absent from short kanji-restricted Tatoeba
  sentences: counters (`六つ`…`九つ`), weekdays other than 月曜日/金曜日, family
  terms (`兄`, `姉`, `弟`, `妹`), food (`魚`, `野菜`, `果物`, `卵`), and verbs like
  `泳ぐ`, `走る`. No filter can conjure them; they would need hand-written
  sentences.
- **Grammar**: 28 of the 31 taught points are exercised by at least one imported
  sentence. Missing: 21 (`なければならない`), 26 (`方 (かた)`), 31 (`けど / が`).
  These are *surface-regex* counts, not a parse — see `GRAMMAR_MARKERS`.
- **Register**: 223 of 317 use です/ます. The rest are plain form, which the
  bundle also teaches.

## What the selection cannot do

- **It scores vocabulary, not grammar.** `もう学校へ行かせないでください。` is
  built entirely from known words and passes, but its causative is N4. Nothing
  in the funnel measures construction difficulty.
- **The segmenter is imperfect.** NLTokenizer splits `一つ` into `一` + `つ` and
  `行きます` into `行き` + `ます`. The word matcher compensates with
  token-boundary-aligned substring matching plus kanji stems, which still
  accepts a different verb sharing a stem kanji — `見せて` counts for `見る`.
- **French↔Japanese fidelity is Tatoeba's, not verified here.** A few pairs
  drift (`分かりますか。` ↔ "Pouvez-vous répondre à cela ?"). Detecting that
  automatically would take a translation model; nothing was rewritten, per the
  licence.

## Regenerating

The committed `sentences.json` is the source of truth; regeneration is only
needed to refresh against a newer Tatoeba snapshot.

```bash
mkdir -p /tmp/tatoeba && cd /tmp/tatoeba
for f in jpn/jpn_sentences fra/fra_sentences jpn/jpn-fra_links; do
  curl -sSLO "https://downloads.tatoeba.org/exports/per_language/$f.tsv.bz2"
done
bunzip2 -kf *.bz2

cd -                                                    # back to the repo root
python3 scripts/tatoeba/build-corpus.py --exports /tmp/tatoeba --verbose
python3 scripts/apply-tatoeba-sentences.py
```

`build-corpus.py` needs `swiftc` (it compiles `tokenize-japanese.swift` to reach
Apple's Japanese segmenter) and reads the current bundle for the kanji and
vocabulary lists. `apply-tatoeba-sentences.py` is idempotent: it deletes the
rows it previously wrote before re-inserting, so running it twice leaves the
bundle identical.

Rebuilding the whole bundle from scratch runs in this order:

```bash
python3 scripts/generate_content_bundles.py    # 96 original sentences
python3 scripts/apply-content-fr.py            # French for those 96
python3 scripts/apply-tatoeba-sentences.py     # this corpus
```

## Schema

`apply-tatoeba-sentences.py` adds three columns to `sentences`:

| column | ikeru rows | tatoeba rows |
|---|---|---|
| `source` | `'ikeru'` | `'tatoeba'` |
| `tatoeba_ja_id` | NULL | Tatoeba sentence id |
| `tatoeba_fr_id` | NULL | Tatoeba translation id |

`english` is left **NULL** on imported rows. The English side of a Tatoeba
sentence is a separate link that would need its own join, deduplication and
quality pass, and nothing in the app reads `sentences.english` — the only
production reader of this table selects `japanese` alone. Imported ids start at
10 001 so they never collide with the hand-written 1…96.
