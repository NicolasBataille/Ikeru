import Foundation

/// A candidate term that can be picked as the "term of the day".
///
/// Curated to favour terms that feel like a small discovery: cultural
/// concepts (mono no aware, ikigai), aesthetic ideas (wabi-sabi, kintsugi),
/// industrial/process vocabulary that has crossed into English (kaizen,
/// poka-yoke), and evocative everyday words (komorebi, natsukashii).
///
/// The catalog deliberately skips first-week vocabulary like こんにちは or
/// ありがとう — those don't feel like a discovery anymore.
public struct DailyTermCandidate: Sendable, Hashable {

    /// The word as written in Japanese (kanji / katakana / kana mix).
    public let word: String

    /// Hiragana or katakana reading of the word.
    public let reading: String

    /// Romaji-ish pronunciation hint.
    public let pronunciation: String

    /// Short English meaning.
    public let meaning: String

    /// Short, evocative caption shown alongside the term.
    public let flavour: String

    /// JLPT level estimate (many of these sit outside JLPT entirely).
    public let jlptLevel: JLPTLevel?

    /// Tags used by the date-aware picker (season, weekday, mood…).
    public let tags: [String]

    public init(
        word: String,
        reading: String,
        pronunciation: String,
        meaning: String,
        flavour: String,
        jlptLevel: JLPTLevel? = nil,
        tags: [String] = []
    ) {
        self.word = word
        self.reading = reading
        self.pronunciation = pronunciation
        self.meaning = meaning
        self.flavour = flavour
        self.jlptLevel = jlptLevel
        self.tags = tags
    }
}

/// Built-in catalog used when no external content source is provided.
public enum DailyTermCatalog {

    public static let all: [DailyTermCandidate] = [

        // MARK: Industrial / process culture (Toyota Way & friends)

        DailyTermCandidate(
            word: "ポカヨケ",
            reading: "ぽかよけ",
            pronunciation: "po-ka-yo-ke",
            meaning: "mistake-proofing — a design that makes errors hard to commit",
            flavour: "the principle of making the wrong thing impossible — invented on Toyota factory floors, now everywhere from CI pipelines to Lego instructions",
            jlptLevel: nil,
            tags: ["industrial", "design", "monday", "tuesday", "thursday", "any"]
        ),
        DailyTermCandidate(
            word: "改善",
            reading: "かいぜん",
            pronunciation: "kai-zen",
            meaning: "continuous improvement, in tiny steps",
            flavour: "not 'change' — improvement, every day, by a millimetre. Toyota turned this into a manufacturing religion",
            jlptLevel: .n3,
            tags: ["industrial", "monday", "any"]
        ),
        DailyTermCandidate(
            word: "見える化",
            reading: "みえるか",
            pronunciation: "mi-e-ru-ka",
            meaning: "making something visible (a process, a metric, a problem)",
            flavour: "the management instinct of dragging hidden things onto a wall so the whole team can see them",
            jlptLevel: nil,
            tags: ["industrial", "monday", "any"]
        ),
        DailyTermCandidate(
            word: "現地現物",
            reading: "げんちげんぶつ",
            pronunciation: "gen-chi-gen-bu-tsu",
            meaning: "go and see for yourself, on the spot",
            flavour: "don't trust the report — go to the floor, the dataset, the actual customer. The Toyota mantra against guessing",
            jlptLevel: nil,
            tags: ["industrial", "monday", "tuesday", "any"]
        ),
        DailyTermCandidate(
            word: "守破離",
            reading: "しゅはり",
            pronunciation: "shu-ha-ri",
            meaning: "three stages of mastery: keep, break, leave",
            flavour: "first you obey the form, then you break it, then you leave it behind. A rhythm borrowed from martial arts and used everywhere from tea ceremony to software craft",
            jlptLevel: nil,
            tags: ["aesthetic", "any", "monday"]
        ),

        // MARK: Aesthetic / philosophical

        DailyTermCandidate(
            word: "侘び寂び",
            reading: "わびさび",
            pronunciation: "wa-bi-sa-bi",
            meaning: "beauty in imperfection and impermanence",
            flavour: "the quiet aesthetic Ikeru is named after — beauty in the worn, the asymmetric, the unfinished",
            jlptLevel: .n1,
            tags: ["aesthetic", "any"]
        ),
        DailyTermCandidate(
            word: "幽玄",
            reading: "ゆうげん",
            pronunciation: "yu-u-gen",
            meaning: "deep, mysterious beauty that resists explanation",
            flavour: "the part of a thing that keeps something hidden — what beauty becomes when it refuses to be named",
            jlptLevel: .n1,
            tags: ["aesthetic", "evening", "any"]
        ),
        DailyTermCandidate(
            word: "物の哀れ",
            reading: "もののあわれ",
            pronunciation: "mo-no-no-a-wa-re",
            meaning: "the bittersweet awareness of impermanence",
            flavour: "the gentle pang of knowing nothing lasts — the soul of a thousand years of Japanese poetry, condensed into four characters",
            jlptLevel: nil,
            tags: ["aesthetic", "autumn", "evening", "any"]
        ),
        DailyTermCandidate(
            word: "無常",
            reading: "むじょう",
            pronunciation: "mu-jo-u",
            meaning: "impermanence",
            flavour: "the Buddhist observation behind every cherry blossom poem — nothing stays, including this feeling",
            jlptLevel: nil,
            tags: ["aesthetic", "autumn", "any"]
        ),
        DailyTermCandidate(
            word: "金継ぎ",
            reading: "きんつぎ",
            pronunciation: "kin-tsu-gi",
            meaning: "the art of repairing pottery with gold lacquer",
            flavour: "broken things, mended in gold — the seam is treated as part of the object's story, not a flaw to hide",
            jlptLevel: .n1,
            tags: ["aesthetic", "any"]
        ),
        DailyTermCandidate(
            word: "間",
            reading: "ま",
            pronunciation: "ma",
            meaning: "the meaningful empty space between things",
            flavour: "the silence between two notes, the pause between two sentences — a single character for everything that isn't there",
            jlptLevel: nil,
            tags: ["aesthetic", "any"]
        ),
        DailyTermCandidate(
            word: "残心",
            reading: "ざんしん",
            pronunciation: "zan-shin",
            meaning: "the lingering awareness after an action",
            flavour: "from kendo and archery — the moment after the cut, the breath after the arrow has flown. The follow-through that finishes the gesture",
            jlptLevel: nil,
            tags: ["aesthetic", "any", "evening"]
        ),

        // MARK: Concepts of self / society

        DailyTermCandidate(
            word: "生き甲斐",
            reading: "いきがい",
            pronunciation: "i-ki-gai",
            meaning: "a reason for being — what makes mornings worth getting up for",
            flavour: "not 'purpose' — softer, smaller. The reason the morning is worth the effort. Often confused with the four-circle Venn diagram, which Japanese people don't actually recognise",
            jlptLevel: nil,
            tags: ["self", "morning", "any"]
        ),
        DailyTermCandidate(
            word: "本音",
            reading: "ほんね",
            pronunciation: "hon-ne",
            meaning: "what one really thinks",
            flavour: "the half of every Japanese conversation that doesn't get said aloud — the true opinion behind the polite one",
            jlptLevel: nil,
            tags: ["self", "society", "any"]
        ),
        DailyTermCandidate(
            word: "建前",
            reading: "たてまえ",
            pronunciation: "ta-te-ma-e",
            meaning: "the public-facing version of one's opinion",
            flavour: "the polite mask that lets a meeting end on time. The other half of honne — and Japan has been talking about the gap between the two for centuries",
            jlptLevel: nil,
            tags: ["self", "society", "any"]
        ),
        DailyTermCandidate(
            word: "甘え",
            reading: "あまえ",
            pronunciation: "a-ma-e",
            meaning: "the comfort of leaning on someone's goodwill",
            flavour: "the small, very Japanese verb for letting yourself be a little spoiled by someone you trust — Doi Takeo wrote a whole book trying to translate it",
            jlptLevel: nil,
            tags: ["self", "any"]
        ),
        DailyTermCandidate(
            word: "遠慮",
            reading: "えんりょ",
            pronunciation: "en-ryo",
            meaning: "restraint out of consideration for others",
            flavour: "saying 'no thank you' to the last piece of cake. The very Japanese habit of holding back so others have room",
            jlptLevel: .n3,
            tags: ["self", "society", "any"]
        ),
        DailyTermCandidate(
            word: "義理",
            reading: "ぎり",
            pronunciation: "gi-ri",
            meaning: "social obligation, sense of duty",
            flavour: "the chocolate you give a coworker on Valentine's Day — affection isn't the point, the gesture is. A whole social grammar in two characters",
            jlptLevel: .n2,
            tags: ["society", "any"]
        ),
        DailyTermCandidate(
            word: "縁",
            reading: "えん",
            pronunciation: "en",
            meaning: "the unseen thread that ties people, places, and chance encounters",
            flavour: "the word the language reaches for when 'fate' is too strong and 'coincidence' is too weak",
            jlptLevel: nil,
            tags: ["society", "any"]
        ),
        DailyTermCandidate(
            word: "一期一会",
            reading: "いちごいちえ",
            pronunciation: "i-chi-go-i-chi-e",
            meaning: "this moment will not happen again — treat it as such",
            flavour: "tea ceremony's deepest principle, distilled into four characters. A reminder, every day, that this exact gathering won't repeat",
            jlptLevel: nil,
            tags: ["aesthetic", "any", "weekend"]
        ),
        DailyTermCandidate(
            word: "切磋琢磨",
            reading: "せっさたくま",
            pronunciation: "ses-sa-ta-ku-ma",
            meaning: "polishing each other through friendly rivalry",
            flavour: "the kind of competition where you both get sharper. Originally about cutting and polishing stone — applied now to teammates and lifelong rivals",
            jlptLevel: nil,
            tags: ["self", "any"]
        ),
        DailyTermCandidate(
            word: "一所懸命",
            reading: "いっしょけんめい",
            pronunciation: "is-sho-ken-mei",
            meaning: "with everything you have, on this single spot",
            flavour: "literally 'one place, life and death' — from samurai who defended a single stretch of land. Used today for any task you're giving your whole attention to",
            jlptLevel: .n3,
            tags: ["self", "monday", "any"]
        ),

        // MARK: Atmospheric / poetic everyday

        DailyTermCandidate(
            word: "木漏れ日",
            reading: "こもれび",
            pronunciation: "ko-mo-re-bi",
            meaning: "sunlight filtering through leaves",
            flavour: "the dappled light that falls through trees — Japanese has an entire word for it",
            jlptLevel: .n1,
            tags: ["nature", "morning", "spring", "summer"]
        ),
        DailyTermCandidate(
            word: "気配",
            reading: "けはい",
            pronunciation: "ke-hai",
            meaning: "a sign or presence felt before it's seen",
            flavour: "the sense that someone has just walked into the room without you turning around. The vocabulary of intuition",
            jlptLevel: nil,
            tags: ["aesthetic", "evening", "any"]
        ),
        DailyTermCandidate(
            word: "風物詩",
            reading: "ふうぶつし",
            pronunciation: "fuu-bu-tsu-shi",
            meaning: "the small things that signal a particular season",
            flavour: "the first cicada in July, the first scarf in October — the seasonal cues a culture keeps a list of",
            jlptLevel: nil,
            tags: ["aesthetic", "any", "spring", "summer", "autumn", "winter"]
        ),
        DailyTermCandidate(
            word: "懐かしい",
            reading: "なつかしい",
            pronunciation: "na-tsu-ka-shi-i",
            meaning: "warmly nostalgic; fondly familiar",
            flavour: "not the wistful kind of nostalgia — the warm kind. The smile a memory pulls out of you",
            jlptLevel: .n3,
            tags: ["mood", "any", "evening"]
        ),
        DailyTermCandidate(
            word: "切ない",
            reading: "せつない",
            pronunciation: "se-tsu-na-i",
            meaning: "bittersweet, painfully tender",
            flavour: "the small, sweet ache of caring about something you can't quite hold onto",
            jlptLevel: .n2,
            tags: ["mood", "evening", "autumn"]
        ),
        DailyTermCandidate(
            word: "縁側",
            reading: "えんがわ",
            pronunciation: "en-ga-wa",
            meaning: "the wooden veranda along a traditional Japanese house",
            flavour: "the in-between strip of wood between house and garden — neither fully inside nor outside. A favourite place for cats and grandparents",
            jlptLevel: nil,
            tags: ["aesthetic", "weekend", "spring", "summer"]
        ),
        DailyTermCandidate(
            word: "森林浴",
            reading: "しんりんよく",
            pronunciation: "shin-rin-yo-ku",
            meaning: "forest bathing — being in a forest just to be in it",
            flavour: "a Japanese-coined prescription for stress: walk into a forest and stay there for a while. No phone, no goal",
            jlptLevel: .n1,
            tags: ["nature", "weekend", "spring", "summer", "autumn"]
        ),
        DailyTermCandidate(
            word: "積ん読",
            reading: "つんどく",
            pronunciation: "tsun-doku",
            meaning: "buying books and letting them pile up unread",
            flavour: "the very specific joy and shame of buying books faster than you can read them. Older than the internet — and the internet has only made it worse",
            jlptLevel: .n1,
            tags: ["aesthetic", "weekend", "any"]
        ),
        DailyTermCandidate(
            word: "隙間時間",
            reading: "すきまじかん",
            pronunciation: "su-ki-ma-ji-kan",
            meaning: "the small slivers of time between tasks",
            flavour: "the five minutes before a meeting, the wait for a kettle. A whole word for the time most cultures don't even count",
            jlptLevel: nil,
            tags: ["self", "monday", "tuesday", "wednesday", "thursday", "friday", "any"]
        ),
        DailyTermCandidate(
            word: "口寂しい",
            reading: "くちさびしい",
            pronunciation: "ku-chi-sa-bi-shi-i",
            meaning: "wanting to eat or chew something out of restlessness, not hunger",
            flavour: "literally 'mouth-lonely' — the urge to nibble that has nothing to do with being hungry. Every snack drawer's secret name",
            jlptLevel: nil,
            tags: ["mood", "evening", "any"]
        ),
        DailyTermCandidate(
            word: "目の保養",
            reading: "めのほよう",
            pronunciation: "me-no-ho-yo-u",
            meaning: "a feast for the eyes",
            flavour: "literally 'eye nourishment' — the small recovery you get from looking at something beautiful for no reason",
            jlptLevel: nil,
            tags: ["aesthetic", "weekend", "any"]
        ),

        // MARK: Specific cultural rituals

        DailyTermCandidate(
            word: "花見",
            reading: "はなみ",
            pronunciation: "ha-na-mi",
            meaning: "cherry blossom viewing",
            flavour: "the ritual of slowing down for a week each spring just to sit under blooming sakura — picnic optional, attendance compulsory",
            jlptLevel: .n5,
            tags: ["spring", "march", "april", "weekend"]
        ),
        DailyTermCandidate(
            word: "月見",
            reading: "つきみ",
            pronunciation: "tsu-ki-mi",
            meaning: "moon viewing",
            flavour: "the autumn pastime of going outside on purpose to look at the moon. There's even a moon-viewing dango for it",
            jlptLevel: .n3,
            tags: ["autumn", "september", "october", "evening"]
        ),
        DailyTermCandidate(
            word: "雪見",
            reading: "ゆきみ",
            pronunciation: "yu-ki-mi",
            meaning: "snow viewing",
            flavour: "third of the trio (with hanami and tsukimi). The deliberate act of looking at falling snow, ideally with a warm drink in hand",
            jlptLevel: nil,
            tags: ["winter", "december", "january", "february"]
        ),
        DailyTermCandidate(
            word: "紅葉狩り",
            reading: "もみじがり",
            pronunciation: "mo-mi-ji-ga-ri",
            meaning: "leaf-hunting — going to look at autumn foliage",
            flavour: "literally 'maple hunting' — though nothing is hunted. The autumn answer to hanami: chase the colour before it falls",
            jlptLevel: nil,
            tags: ["autumn", "october", "november", "weekend"]
        ),
        DailyTermCandidate(
            word: "炬燵",
            reading: "こたつ",
            pronunciation: "ko-ta-tsu",
            meaning: "low table with a heater and a quilt over it",
            flavour: "the gravitational well of Japanese winter — once your legs are under the blanket, you do not get up",
            jlptLevel: .n2,
            tags: ["winter", "december", "january", "february"]
        ),
        DailyTermCandidate(
            word: "初詣",
            reading: "はつもうで",
            pronunciation: "hatsu-mou-de",
            meaning: "the year's first visit to a shrine",
            flavour: "the first shrine visit of the new year — half tradition, half excuse to get some fresh air on January 1st",
            jlptLevel: nil,
            tags: ["winter", "january"]
        ),
        DailyTermCandidate(
            word: "五月病",
            reading: "ごがつびょう",
            pronunciation: "go-gatsu-byou",
            meaning: "May sickness — the post-holiday slump",
            flavour: "the Japanese name for the May funk that hits new students and employees after Golden Week. Diagnosed culturally, cured by routine",
            jlptLevel: nil,
            tags: ["spring", "may", "monday"]
        ),

        // MARK: Verbs and expressions worth noticing

        DailyTermCandidate(
            word: "頑張る",
            reading: "がんばる",
            pronunciation: "gan-ba-ru",
            meaning: "to persist, to do one's best",
            flavour: "the verb the language uses for both 'good luck' and 'hang in there'. Hard to translate cleanly because it's also a value",
            jlptLevel: .n5,
            tags: ["self", "monday", "any"]
        ),
        DailyTermCandidate(
            word: "お疲れ様",
            reading: "おつかれさま",
            pronunciation: "o-tsu-ka-re-sa-ma",
            meaning: "expression that recognises someone's effort",
            flavour: "the word coworkers say to each other at the end of a shift — there's no English equivalent, but everyone wishes there were",
            jlptLevel: .n4,
            tags: ["expression", "evening", "friday", "any"]
        ),
        DailyTermCandidate(
            word: "仕方ない",
            reading: "しかたない",
            pronunciation: "shi-ka-ta-nai",
            meaning: "it can't be helped",
            flavour: "the most-used three syllables in any Japanese week — half acceptance, half philosophy. Translates badly because the shrug is the meaning",
            jlptLevel: .n3,
            tags: ["expression", "any"]
        ),
        DailyTermCandidate(
            word: "面倒くさい",
            reading: "めんどくさい",
            pronunciation: "men-do-ku-sai",
            meaning: "what a pain; can't be bothered",
            flavour: "the word every Japanese person has muttered at a Monday morning email. Endlessly applicable",
            jlptLevel: .n3,
            tags: ["mood", "monday", "any"]
        ),
        DailyTermCandidate(
            word: "微妙",
            reading: "びみょう",
            pronunciation: "bi-myou",
            meaning: "subtle; iffy; hard to call",
            flavour: "the polite word for 'not great, not terrible' — used to describe everything from a film to a piece of fish that's been in the fridge too long",
            jlptLevel: .n3,
            tags: ["mood", "any"]
        ),
        DailyTermCandidate(
            word: "言霊",
            reading: "ことだま",
            pronunciation: "ko-to-da-ma",
            meaning: "the spirit, or power, that lives in words",
            flavour: "the old Japanese belief that what you say shapes what happens — which is why some words are still avoided at weddings",
            jlptLevel: nil,
            tags: ["aesthetic", "any"]
        ),
        DailyTermCandidate(
            word: "真面目",
            reading: "まじめ",
            pronunciation: "ma-ji-me",
            meaning: "earnest, diligent, taking things seriously",
            flavour: "high praise in a Japanese workplace — the quiet, reliable virtue of doing the job properly",
            jlptLevel: .n3,
            tags: ["self", "monday", "any"]
        ),
        DailyTermCandidate(
            word: "馬鹿正直",
            reading: "ばかしょうじき",
            pronunciation: "ba-ka-shou-ji-ki",
            meaning: "honest to a fault",
            flavour: "literally 'idiotically honest' — the kind of person who tells the truth even when it would be wiser to stay quiet. Said with affection more often than not",
            jlptLevel: nil,
            tags: ["self", "any"]
        ),
        DailyTermCandidate(
            word: "起承転結",
            reading: "きしょうてんけつ",
            pronunciation: "ki-shou-ten-ketsu",
            meaning: "four-act narrative structure: intro, develop, twist, resolve",
            flavour: "the Japanese counterpart to the three-act structure — but with a twist instead of a climax. A different shape for telling stories",
            jlptLevel: nil,
            tags: ["aesthetic", "any"]
        )
    ]
}
