# Tatoeba sentence corpus

The 536 imported example sentences in `Ikeru/Resources/ContentBundles/n5-content.sqlite`
come from here. The 96 that were already in the bundle are Ikeru's own and are
untouched.

The count was 317 in an earlier revision of this funnel. A review found a
matching bug in the stem model (a numeral or verb like 五つ/聞く could reduce
to a one-character stem that then matched unrelated 五-/聞-compounds), plus a
few sentences and translations wrong on inspection; both are fixed below and
the corpus was regenerated against a fresh Tatoeba snapshot, which is why the
count moved rather than staying frozen at 317 — see `blocklist.json` and the
"one kanji is not a word" note in `build-corpus.py`'s `build_known_lexicon`.

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
| blocklist | 43 684 | 5 | hand-reviewed rejections no filter below can express — see `blocklist.json` |
| script | 40 426 | 3 258 | latin letters, digits, `「」`, `〜` — the bundle teaches kanji numerals, not `1732` |
| single sentence | 39 693 | 733 | a `。？！` mid-string means two sentences or a dialogue |
| is a sentence | 39 500 | 193 | fewer than 2 hiragana ⇒ no grammar, e.g. `一、二、三、四、五。` |
| **kanji floor** | **2 510** | 36 990 | one kanji outside the bundle's 90 and the learner cannot read the line |
| length 6–18 | 2 101 | 409 | see below |
| katakana allowlist | 1 423 | 678 | proper nouns — トム alone is in 201 candidate pairs |
| topic | 1 423 | 0 | already emptied by the kanji floor (死, 殺, 戦争, 酒 are not taught kanji) |
| register | 1 380 | 43 | plain imperatives (`見ろ。`, `〜てくれ。`), `〜な` prohibitive, `〜ぞ / 〜ぜ` |
| french quality | 1 374 | 6 | digits, quotes, parentheses, no final punctuation, crude vocabulary |
| **lexical i+1** | **992** | 382 | see below |
| vocabulary anchor | 914 | 78 | no bundle word ⇒ the sentence can't be filed under anything |
| one French per Japanese | 756 | 158 | Tatoeba offers several; the oldest `fra` id wins |
| not already bundled | 750 | 6 | the same Japanese already exists among the 96 |
| near-duplicate collapse | 696 | 54 | `あの本は小さい。` and `その本は小さい。` drill the same item |
| **cap: 5 per word** | **548** | 148 | see below |
| french dedup per word | 536 | 12 | same word, same French gloss twice — see below |

### Why these thresholds

**Kanji floor (the 90 bundled kanji).** Non-negotiable, but *not sufficient*:
`きりがない` passes it and is nowhere near N5. Everything below exists because
of that.

**Length 6–18 characters.** Under 6, Tatoeba yields interjections — `はい。`,
`じゃ。`, `やあ！` — which teach no structure and are useless for shadowing or
sentence construction. Over 18, sentences start stacking clauses, proper nouns
and N3 grammar (`まるで母国語であるかのように`). The band holds 2 101 of the
2 510 sentences that clear the kanji floor, so the bound costs little.

**Lexical i+1: at most 2 unknown words, each common corpus-wide.**
A token counts as *known* when it is (a) grammatical glue, (b) a bundle word or
its kanji stem, or (c) a loanword from the reviewed katakana allowlist. A
word's stem must be at least two characters — see the block comment on
`build_known_lexicon` for why a one-kanji stem is a bug, not a feature: it
only ever survives on words that are themselves two characters long (五つ →
stem 五, 聞く → stem 聞), and those are exactly the compounds where matching a
bare kanji instead of the word means matching the wrong word. Measured on the
current vocabulary table: of 74 stems the old rule produced, 53 were a single
kanji — that is most of the class the bug touched, not an edge case. The
fixed rule keeps 21; the bundle's many two-character words (聞く, 見る, 出る,
入る, 行く, 来る, 買う…) now only match their conjugated forms through
`vocabulary_in`'s token-boundary rule, not the stem shortcut.

*Glue* is derived from the data, not hand-listed: a hiragana-only token
appearing in ≥ 0.2 % of the 248 866-sentence Japanese corpus (≥ 498 sentences)
is a particle, a copula form or an inflection fragment — that is what the head
of a frequency table over a closed class looks like. 164 types.

Two unknowns rather than one. The original argument was that the bundle held
206 words where a real N5 lexicon is roughly four times that, so against so
small a reference "one unknown" would have meant "already in the bundle", not
"i+1". **That argument expired** when the bundle reached 693 words — and the
threshold was re-measured on 2026-08-16 rather than inherited.

Sweep with `--max-unknown N --dry-run`:

| cut | retained | words anchored | grammar |
|---:|---:|---:|---:|
| 0 | 316 | 154/693 | 29/31 |
| 1 | 506 | 187/693 | 30/31 |
| **2** | **536** | **188/693** | **30/31** |

Tightening to 1 reads as almost free — 30 sentences and one word. It is not:
the 37 sentences that actually differ are `日本語を話します。`,
`わたしはテレビを見ています。`, `この本は読みやすい。`,
`いくらお金をもっていますか。` and their like. Dropping "I speak Japanese" out
of a Japanese-learning app to satisfy a threshold is the wrong trade.

What keeps the 2-unknown band honest is the filter below it: each unknown must
itself appear in ≥ 150 corpus sentences, which separates a common word a
beginner will meet again (テーブル, よろしく, どうぞ) from an idiom fragment
(`きり` 57, `いたずら` 58, `ぐあい` 2). "Two unknowns" therefore means two
*common* words, never two fragments.

It is also a tail, not the bulk: of 1 374 candidates, 512 carry no unknown and
588 carry one, so only ~7 % of the retained corpus sits at the loose end. Cut
at 0 is not a stricter i+1 — it is i+0, where no sentence teaches anything new,
and it costs a grammar point.

Every run now prints this distribution. Re-run the sweep rather than trusting
this paragraph.

**Katakana allowlist, not a name blocklist.** Blocklisting Tatoeba's cast is an
endless game. The funnel instead allowlists 65 everyday loanwords, hand-picked
from the katakana actually present in the candidate set. Alcohol and tobacco
(ビール, ワイン, アルコール, タバコ) and coarse register (バカ, ケチ, ナンパ)
are deliberately left out.

**One French per Japanese: the lowest `fra` id.** Among translations that all
pass the quality gate, the oldest is the one that has been visible — and
correctable — on Tatoeba the longest. Deterministic, and it does not require
judging French style.

**Cap of 5 sentences per vocabulary word.** The query shape this schema
supports is `SELECT japanese FROM sentences WHERE vocabulary_word = ?`
(`ContentRepository.fetchSentences`). As of 2026-08-15, no reachable
navigation path in the app actually renders what that query returns —
`VocabularyExamplesView` (the one view that would `ForEach` a capped slice of
it, via `.prefix(2)`) and its host `KanjiStudyView` are unreached from any
navigation path today (verified, see that view's own doc comment), and the
other callers of the underlying repository method (`SessionComposer`,
`LeechInterventionService`) never look at the sentences they fetch. The cap
stays anyway: it is what spreads the corpus rather than letting a dozen
high-frequency words (私, 何) collect everything, and a query with no current
caller can still get one tomorrow. Sentences are assigned rarest-word first,
so the pool covers as many distinct words as it can before the cap is hit.
**211 sentences passed every quality gate and were dropped by this cap
alone**, plus a further 10 dropped one step later for repeating another
sentence's French gloss under the same word (see the next paragraph) — none
of them are bad sentences, only surplus for the reader that exists today (or
duplicates of a card already shown). Raising `MAX_PER_VOCAB_WORD` recovers
the capped ones.

**French dedup per word.** The funnel dedupes the Japanese (stage "not already
bundled") and the token bag (stage "near-duplicate collapse"), but nothing
upstream of the cap ever compared the *French* gloss two sentences ended up
with. Tatoeba links several distinct Japanese sentences to the same
translation often enough that, once two or three of them land under the same
vocabulary word, the card reads as the same French sentence pasted three
times (新聞 had 「日本語の新聞はありますか。」 phrased three different ways in
Japanese, glossed identically each time in French). This pass runs after the
cap and does not backfill the freed slot with another candidate — a smaller,
distinct-per-card corpus rather than a same-size one.

## Coverage obtained

*(All coverage numbers below are measured against the applied bundle —
`SELECT DISTINCT vocabulary_word FROM sentences` — not against the funnel's
own internal candidate-scoring counters, which count differently: a sentence
can *contain* several bundle words while being *filed under* only one.)*

- **Vocabulary**: **236 of the 693 bundled words have at least one example**,
  combining the 96 original sentences with the 536 imported ones — measured on
  the bundle with `SELECT COUNT(DISTINCT vocabulary_word) FROM sentences`.
  `build-corpus.py --verbose` additionally reports 188/693 filed under from the
  Tatoeba side alone, and 193/693 appearing anywhere; the gap between those and
  236 is coverage Ikeru's own 96 sentences contribute.
- The remaining ~457 words have no example. The share grew, not shrank, because
  the vocabulary table tripled (205 → 693) while the corpus roughly doubled —
  covering a bigger lexicon from the same kanji-restricted Tatoeba pool is
  strictly harder. The classes that stay uncovered are the same ones as before:
  counters (`四つ`…`九つ`), weekdays other than 月曜日/金曜日, family terms
  (`兄`, `姉`, `弟`, `妹`), food (`卵`, `野菜`, `果物`, `魚`), and verbs like
  `泳ぐ`, `走る`, `言う`. No filter can conjure them; they would need
  hand-written sentences.
- **Grammar**: 30 of the 31 taught points are exercised by at least one
  imported sentence — up from 27. Only 26 (`方 (かた)`) is still missing; 21
  (`なければならない`), 24 (`つもり`) and 31 (`けど / が`) are now covered.
  These are *surface-regex* counts, not a parse — see `GRAMMAR_MARKERS`.
- **Register**: 276 of 536 imported sentences use です/ます. The rest are
  plain form, which the bundle also teaches.

## What the selection cannot do

- **It scores vocabulary, not grammar.** `もう学校へ行かせないでください。` is
  built entirely from known words and passes, but its causative is N4. Nothing
  in the funnel measures construction difficulty.
- **The segmenter is imperfect.** NLTokenizer splits `一つ` into `一` + `つ` and
  `行きます` into `行き` + `ます`. The word matcher compensates with
  token-boundary-aligned substring matching (`vocabulary_in`'s rule 1) plus
  kanji stems (rule 2, `build_known_lexicon`) — the stem rule used to accept
  a different verb sharing a one-kanji stem (`見せて` counted for `見る`,
  `聞こえる` for `聞く`); requiring a stem of at least two characters closed
  that (see `build_known_lexicon`'s block comment), at the cost of coverage
  for every two-character bundle word.
- **French↔Japanese fidelity is Tatoeba's, not verified here**, beyond the
  handful of pairings in `blocklist.json` that a human happened to notice on
  inspection. Detecting drift automatically would take a translation model;
  nothing was rewritten, per the licence — a wrong pairing is removed, never
  corrected.

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
Apple's Japanese segmenter), reads the current bundle for the kanji and
vocabulary lists, and applies `blocklist.json` before any other filter — a
sentence or pairing rejected there never reaches the funnel at all.
`apply-tatoeba-sentences.py` is idempotent in content: it deletes the rows it
previously wrote before re-inserting and then `VACUUM`s, so running it twice
leaves the bundle's `.dump` identical (measured) and its bytes identical to
within 3 — SQLite's own file-change-counter/schema-cookie/version-valid-for
header fields, which the engine bumps on every write regardless of content.

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
quality pass, and nothing in the app reads `sentences.english`. The one query
shape reading this table at all is `ContentRepository.fetchSentences`
(`SELECT japanese FROM sentences WHERE vocabulary_word = ?`), and as of
2026-08-15 no navigation path reachable in the app renders what it returns —
see the "Cap of 5 sentences per vocabulary word" note above. Imported ids
start at 10 001 so they never collide with the hand-written 1…96.
