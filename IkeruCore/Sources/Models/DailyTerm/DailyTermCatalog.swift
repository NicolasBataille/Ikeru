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

    /// French translation of the meaning. Falls back to `meaning` when nil.
    public let meaningFR: String?

    /// Short, evocative caption shown alongside the term.
    public let flavour: String

    /// French translation of the flavour caption. Falls back to `flavour` when nil.
    public let flavourFR: String?

    /// JLPT level estimate (many of these sit outside JLPT entirely).
    public let jlptLevel: JLPTLevel?

    /// Tags used by the date-aware picker (season, weekday, mood…).
    public let tags: [String]

    public init(
        word: String,
        reading: String,
        pronunciation: String,
        meaning: String,
        meaningFR: String? = nil,
        flavour: String,
        flavourFR: String? = nil,
        jlptLevel: JLPTLevel? = nil,
        tags: [String] = []
    ) {
        self.word = word
        self.reading = reading
        self.pronunciation = pronunciation
        self.meaning = meaning
        self.meaningFR = meaningFR
        self.flavour = flavour
        self.flavourFR = flavourFR
        self.jlptLevel = jlptLevel
        self.tags = tags
    }

    /// Returns the French meaning when the locale is French and a translation
    /// exists, otherwise falls back to the English meaning.
    public func localizedMeaning(for locale: Locale) -> String {
        if locale.language.languageCode?.identifier == "fr", let fr = meaningFR {
            return fr
        }
        return meaning
    }

    /// Returns the French flavour when the locale is French and a translation
    /// exists, otherwise falls back to the English flavour.
    public func localizedFlavour(for locale: Locale) -> String {
        if locale.language.languageCode?.identifier == "fr", let fr = flavourFR {
            return fr
        }
        return flavour
    }
}

/// Built-in catalog used when no external content source is provided.
public enum DailyTermCatalog {

    /// O(1) lookup of a candidate by its Japanese word. Lets the service
    /// resolve persisted `DailyTerm` rows back to their localized
    /// meaning/flavour at render time instead of trusting frozen DB columns.
    public static let byWord: [String: DailyTermCandidate] = {
        Dictionary(uniqueKeysWithValues: all.map { ($0.word, $0) })
    }()

    public static let all: [DailyTermCandidate] = [

        // MARK: Industrial / process culture (Toyota Way & friends)

        DailyTermCandidate(
            word: "ポカヨケ",
            reading: "ぽかよけ",
            pronunciation: "po-ka-yo-ke",
            meaning: "mistake-proofing — a design that makes errors hard to commit",
            meaningFR: "détrompeur — un design qui rend les erreurs difficiles à commettre",
            flavour: "the principle of making the wrong thing impossible — invented on Toyota factory floors, now everywhere from CI pipelines to Lego instructions",
            flavourFR: "le principe de rendre la mauvaise action impossible — inventé sur les chaînes Toyota, aujourd'hui partout, des pipelines CI aux notices Lego",
            jlptLevel: nil,
            tags: ["industrial", "design", "monday", "tuesday", "thursday", "any"]
        ),
        DailyTermCandidate(
            word: "改善",
            reading: "かいぜん",
            pronunciation: "kai-zen",
            meaning: "continuous improvement, in tiny steps",
            meaningFR: "amélioration continue, par petits pas",
            flavour: "not 'change' — improvement, every day, by a millimetre. Toyota turned this into a manufacturing religion",
            flavourFR: "pas 'changement' — amélioration, chaque jour, d'un millimètre. Toyota en a fait une religion industrielle",
            jlptLevel: .n3,
            tags: ["industrial", "monday", "any"]
        ),
        DailyTermCandidate(
            word: "見える化",
            reading: "みえるか",
            pronunciation: "mi-e-ru-ka",
            meaning: "making something visible (a process, a metric, a problem)",
            meaningFR: "rendre visible (un processus, une métrique, un problème)",
            flavour: "the management instinct of dragging hidden things onto a wall so the whole team can see them",
            flavourFR: "l'instinct managérial qui consiste à afficher les choses cachées sur un mur, pour que toute l'équipe les voie",
            jlptLevel: nil,
            tags: ["industrial", "monday", "any"]
        ),
        DailyTermCandidate(
            word: "現地現物",
            reading: "げんちげんぶつ",
            pronunciation: "gen-chi-gen-bu-tsu",
            meaning: "go and see for yourself, on the spot",
            meaningFR: "aller voir par soi-même, sur place",
            flavour: "don't trust the report — go to the floor, the dataset, the actual customer. The Toyota mantra against guessing",
            flavourFR: "ne te fie pas au rapport — va sur le terrain, dans les données, voir le client. Le mantra Toyota contre la spéculation",
            jlptLevel: nil,
            tags: ["industrial", "monday", "tuesday", "any"]
        ),
        DailyTermCandidate(
            word: "守破離",
            reading: "しゅはり",
            pronunciation: "shu-ha-ri",
            meaning: "three stages of mastery: keep, break, leave",
            meaningFR: "trois étapes de la maîtrise : suivre, briser, quitter",
            flavour: "first you obey the form, then you break it, then you leave it behind. A rhythm borrowed from martial arts and used everywhere from tea ceremony to software craft",
            flavourFR: "d'abord on obéit à la forme, puis on la brise, puis on la laisse derrière soi. Un rythme emprunté aux arts martiaux, appliqué de la cérémonie du thé jusqu'au logiciel",
            jlptLevel: nil,
            tags: ["aesthetic", "any", "monday"]
        ),

        // MARK: Aesthetic / philosophical

        DailyTermCandidate(
            word: "侘び寂び",
            reading: "わびさび",
            pronunciation: "wa-bi-sa-bi",
            meaning: "beauty in imperfection and impermanence",
            meaningFR: "la beauté dans l'imperfection et l'impermanence",
            flavour: "the quiet aesthetic Ikeru is named after — beauty in the worn, the asymmetric, the unfinished",
            flavourFR: "l'esthétique tranquille qui a donné son nom à Ikeru — la beauté de l'usé, de l'asymétrique, de l'inachevé",
            jlptLevel: .n1,
            tags: ["aesthetic", "any"]
        ),
        DailyTermCandidate(
            word: "幽玄",
            reading: "ゆうげん",
            pronunciation: "yu-u-gen",
            meaning: "deep, mysterious beauty that resists explanation",
            meaningFR: "beauté profonde et mystérieuse, qui résiste à l'explication",
            flavour: "the part of a thing that keeps something hidden — what beauty becomes when it refuses to be named",
            flavourFR: "la part d'une chose qui garde quelque chose de caché — ce que devient la beauté lorsqu'elle refuse d'être nommée",
            jlptLevel: .n1,
            tags: ["aesthetic", "evening", "any"]
        ),
        DailyTermCandidate(
            word: "物の哀れ",
            reading: "もののあわれ",
            pronunciation: "mo-no-no-a-wa-re",
            meaning: "the bittersweet awareness of impermanence",
            meaningFR: "la conscience douce-amère de l'impermanence",
            flavour: "the gentle pang of knowing nothing lasts — the soul of a thousand years of Japanese poetry, condensed into four characters",
            flavourFR: "le pincement doux de savoir que rien ne dure — l'âme de mille ans de poésie japonaise, condensée en quatre caractères",
            jlptLevel: nil,
            tags: ["aesthetic", "autumn", "evening", "any"]
        ),
        DailyTermCandidate(
            word: "無常",
            reading: "むじょう",
            pronunciation: "mu-jo-u",
            meaning: "impermanence",
            meaningFR: "impermanence",
            flavour: "the Buddhist observation behind every cherry blossom poem — nothing stays, including this feeling",
            flavourFR: "l'observation bouddhiste derrière chaque poème de fleurs de cerisier — rien ne reste, y compris ce sentiment",
            jlptLevel: nil,
            tags: ["aesthetic", "autumn", "any"]
        ),
        DailyTermCandidate(
            word: "金継ぎ",
            reading: "きんつぎ",
            pronunciation: "ki-n-tsu-gi",
            meaning: "the art of repairing pottery with gold lacquer",
            meaningFR: "l'art de réparer la céramique avec une laque d'or",
            flavour: "broken things, mended in gold — the seam is treated as part of the object's story, not a flaw to hide",
            flavourFR: "les choses cassées, recousues d'or — la couture est traitée comme une partie de l'histoire de l'objet, pas comme un défaut à cacher",
            jlptLevel: .n1,
            tags: ["aesthetic", "any"]
        ),
        DailyTermCandidate(
            word: "間",
            reading: "ま",
            pronunciation: "ma",
            meaning: "the meaningful empty space between things",
            meaningFR: "l'espace vide et signifiant entre les choses",
            flavour: "the silence between two notes, the pause between two sentences — a single character for everything that isn't there",
            flavourFR: "le silence entre deux notes, la pause entre deux phrases — un seul caractère pour tout ce qui n'est pas là",
            jlptLevel: nil,
            tags: ["aesthetic", "any"]
        ),
        DailyTermCandidate(
            word: "残心",
            reading: "ざんしん",
            pronunciation: "zan-shin",
            meaning: "the lingering awareness after an action",
            meaningFR: "la conscience qui persiste après l'action",
            flavour: "from kendo and archery — the moment after the cut, the breath after the arrow has flown. The follow-through that finishes the gesture",
            flavourFR: "du kendo et du tir à l'arc — l'instant après la coupe, le souffle après que la flèche a quitté l'arc. Le prolongement qui achève le geste",
            jlptLevel: nil,
            tags: ["aesthetic", "any", "evening"]
        ),

        // MARK: Concepts of self / society

        DailyTermCandidate(
            word: "生き甲斐",
            reading: "いきがい",
            pronunciation: "i-ki-gai",
            meaning: "a reason for being — what makes mornings worth getting up for",
            meaningFR: "une raison d'être — ce qui rend les matins dignes d'être levés",
            flavour: "not 'purpose' — softer, smaller. The reason the morning is worth the effort. Often confused with the four-circle Venn diagram, which Japanese people don't actually recognise",
            flavourFR: "pas 'mission' — plus doux, plus petit. La raison qui rend le matin digne de l'effort. Souvent confondu avec le diagramme de Venn à quatre cercles, que les Japonais ne reconnaissent pas vraiment",
            jlptLevel: nil,
            tags: ["self", "morning", "any"]
        ),
        DailyTermCandidate(
            word: "本音",
            reading: "ほんね",
            pronunciation: "hon-ne",
            meaning: "what one really thinks",
            meaningFR: "ce que l'on pense vraiment",
            flavour: "the half of every Japanese conversation that doesn't get said aloud — the true opinion behind the polite one",
            flavourFR: "la moitié de chaque conversation japonaise qui ne se dit pas à voix haute — la vraie opinion derrière la polie",
            jlptLevel: nil,
            tags: ["self", "society", "any"]
        ),
        DailyTermCandidate(
            word: "建前",
            reading: "たてまえ",
            pronunciation: "ta-te-ma-e",
            meaning: "the public-facing version of one's opinion",
            meaningFR: "la version publique de son opinion",
            flavour: "the polite mask that lets a meeting end on time. The other half of honne — and Japan has been talking about the gap between the two for centuries",
            flavourFR: "le masque poli qui permet à une réunion de se terminer à l'heure. L'autre moitié du honne — et le Japon parle de l'écart entre les deux depuis des siècles",
            jlptLevel: nil,
            tags: ["self", "society", "any"]
        ),
        DailyTermCandidate(
            word: "甘え",
            reading: "あまえ",
            pronunciation: "a-ma-e",
            meaning: "the comfort of leaning on someone's goodwill",
            meaningFR: "le confort de se reposer sur la bienveillance de quelqu'un",
            flavour: "the small, very Japanese verb for letting yourself be a little spoiled by someone you trust — Doi Takeo wrote a whole book trying to translate it",
            flavourFR: "le petit verbe très japonais pour se laisser un peu chouchouter par quelqu'un de confiance — Doi Takeo a écrit un livre entier pour le traduire",
            jlptLevel: nil,
            tags: ["self", "any"]
        ),
        DailyTermCandidate(
            word: "遠慮",
            reading: "えんりょ",
            pronunciation: "en-ryo",
            meaning: "restraint out of consideration for others",
            meaningFR: "retenue par égard pour les autres",
            flavour: "saying 'no thank you' to the last piece of cake. The very Japanese habit of holding back so others have room",
            flavourFR: "dire 'non merci' à la dernière part de gâteau. L'habitude très japonaise de se retenir pour laisser de la place aux autres",
            jlptLevel: .n3,
            tags: ["self", "society", "any"]
        ),
        DailyTermCandidate(
            word: "義理",
            reading: "ぎり",
            pronunciation: "gi-ri",
            meaning: "social obligation, sense of duty",
            meaningFR: "obligation sociale, sens du devoir",
            flavour: "the chocolate you give a coworker on Valentine's Day — affection isn't the point, the gesture is. A whole social grammar in two characters",
            flavourFR: "le chocolat qu'on offre à un collègue le 14 février — l'affection n'est pas le sujet, c'est le geste. Une grammaire sociale entière en deux caractères",
            jlptLevel: .n2,
            tags: ["society", "any"]
        ),
        DailyTermCandidate(
            word: "縁",
            reading: "えん",
            pronunciation: "en",
            meaning: "the unseen thread that ties people, places, and chance encounters",
            meaningFR: "le fil invisible qui lie les gens, les lieux et les rencontres fortuites",
            flavour: "the word the language reaches for when 'fate' is too strong and 'coincidence' is too weak",
            flavourFR: "le mot que la langue attrape quand 'destin' est trop fort et 'coïncidence' trop faible",
            jlptLevel: nil,
            tags: ["society", "any"]
        ),
        DailyTermCandidate(
            word: "一期一会",
            reading: "いちごいちえ",
            pronunciation: "i-chi-go-i-chi-e",
            meaning: "this moment will not happen again — treat it as such",
            meaningFR: "cet instant ne se reproduira pas — traite-le comme tel",
            flavour: "tea ceremony's deepest principle, distilled into four characters. A reminder, every day, that this exact gathering won't repeat",
            flavourFR: "le principe le plus profond de la cérémonie du thé, distillé en quatre caractères. Un rappel, chaque jour, que cette rencontre précise ne se reproduira pas",
            jlptLevel: nil,
            tags: ["aesthetic", "any", "weekend"]
        ),
        DailyTermCandidate(
            word: "切磋琢磨",
            reading: "せっさたくま",
            pronunciation: "ses-sa-ta-ku-ma",
            meaning: "polishing each other through friendly rivalry",
            meaningFR: "se polir mutuellement par une rivalité amicale",
            flavour: "the kind of competition where you both get sharper. Originally about cutting and polishing stone — applied now to teammates and lifelong rivals",
            flavourFR: "le genre de compétition où chacun s'aiguise. À l'origine pour la taille et le polissage de la pierre — appliqué aujourd'hui aux coéquipiers et aux rivaux de toujours",
            jlptLevel: nil,
            tags: ["self", "any"]
        ),
        DailyTermCandidate(
            word: "一所懸命",
            reading: "いっしょけんめい",
            pronunciation: "is-sho-ken-mei",
            meaning: "with everything you have, on this single spot",
            meaningFR: "avec tout ce que tu as, sur ce seul endroit",
            flavour: "literally 'one place, life and death' — from samurai who defended a single stretch of land. Used today for any task you're giving your whole attention to",
            flavourFR: "littéralement 'un seul endroit, vie ou mort' — des samouraïs qui défendaient une seule parcelle. Utilisé aujourd'hui pour toute tâche à laquelle on donne toute son attention",
            jlptLevel: .n3,
            tags: ["self", "monday", "any"]
        ),

        // MARK: Atmospheric / poetic everyday

        DailyTermCandidate(
            word: "木漏れ日",
            reading: "こもれび",
            pronunciation: "ko-mo-re-bi",
            meaning: "sunlight filtering through leaves",
            meaningFR: "lumière du soleil filtrant à travers les feuilles",
            flavour: "the dappled light that falls through trees — Japanese has an entire word for it",
            flavourFR: "la lumière mouchetée qui tombe à travers les arbres — le japonais a un mot entier pour ça",
            jlptLevel: .n1,
            tags: ["nature", "morning", "spring", "summer"]
        ),
        DailyTermCandidate(
            word: "気配",
            reading: "けはい",
            pronunciation: "ke-hai",
            meaning: "a sign or presence felt before it's seen",
            meaningFR: "un signe ou une présence ressentie avant d'être vue",
            flavour: "the sense that someone has just walked into the room without you turning around. The vocabulary of intuition",
            flavourFR: "la sensation que quelqu'un vient d'entrer dans la pièce sans qu'on ait à se retourner. Le vocabulaire de l'intuition",
            jlptLevel: nil,
            tags: ["aesthetic", "evening", "any"]
        ),
        DailyTermCandidate(
            word: "風物詩",
            reading: "ふうぶつし",
            pronunciation: "fu-u-bu-tsu-shi",
            meaning: "the small things that signal a particular season",
            meaningFR: "les petites choses qui annoncent une saison",
            flavour: "the first cicada in July, the first scarf in October — the seasonal cues a culture keeps a list of",
            flavourFR: "la première cigale en juillet, la première écharpe en octobre — les indices saisonniers qu'une culture garde en liste",
            jlptLevel: nil,
            tags: ["aesthetic", "any", "spring", "summer", "autumn", "winter"]
        ),
        DailyTermCandidate(
            word: "懐かしい",
            reading: "なつかしい",
            pronunciation: "na-tsu-ka-shi-i",
            meaning: "warmly nostalgic; fondly familiar",
            meaningFR: "chaleureusement nostalgique ; familier avec tendresse",
            flavour: "not the wistful kind of nostalgia — the warm kind. The smile a memory pulls out of you",
            flavourFR: "pas la nostalgie mélancolique — la chaleureuse. Le sourire qu'un souvenir te tire",
            jlptLevel: .n3,
            tags: ["mood", "any", "evening"]
        ),
        DailyTermCandidate(
            word: "切ない",
            reading: "せつない",
            pronunciation: "se-tsu-na-i",
            meaning: "bittersweet, painfully tender",
            meaningFR: "doux-amer, douloureusement tendre",
            flavour: "the small, sweet ache of caring about something you can't quite hold onto",
            flavourFR: "la petite douleur douce de tenir à quelque chose qu'on ne peut pas tout à fait garder",
            jlptLevel: .n2,
            tags: ["mood", "evening", "autumn"]
        ),
        DailyTermCandidate(
            word: "縁側",
            reading: "えんがわ",
            pronunciation: "en-ga-wa",
            meaning: "the wooden veranda along a traditional Japanese house",
            meaningFR: "la véranda en bois le long d'une maison japonaise traditionnelle",
            flavour: "the in-between strip of wood between house and garden — neither fully inside nor outside. A favourite place for cats and grandparents",
            flavourFR: "la bande de bois entre la maison et le jardin — ni vraiment dedans, ni vraiment dehors. Un endroit préféré des chats et des grands-parents",
            jlptLevel: nil,
            tags: ["aesthetic", "weekend", "spring", "summer"]
        ),
        DailyTermCandidate(
            word: "森林浴",
            reading: "しんりんよく",
            pronunciation: "shi-n-ri-n-yo-ku",
            meaning: "forest bathing — being in a forest just to be in it",
            meaningFR: "bain de forêt — être dans une forêt juste pour y être",
            flavour: "a Japanese-coined prescription for stress: walk into a forest and stay there for a while. No phone, no goal",
            flavourFR: "une prescription antistress inventée au Japon : entrer dans une forêt et y rester un moment. Pas de téléphone, pas d'objectif",
            jlptLevel: .n1,
            tags: ["nature", "weekend", "spring", "summer", "autumn"]
        ),
        DailyTermCandidate(
            word: "積ん読",
            reading: "つんどく",
            pronunciation: "tsu-n-do-ku",
            meaning: "buying books and letting them pile up unread",
            meaningFR: "acheter des livres et les laisser s'empiler sans les lire",
            flavour: "the very specific joy and shame of buying books faster than you can read them. Older than the internet — and the internet has only made it worse",
            flavourFR: "la joie et la honte très spécifiques d'acheter des livres plus vite qu'on ne peut les lire. Plus ancien qu'internet — et internet n'a rien arrangé",
            jlptLevel: .n1,
            tags: ["aesthetic", "weekend", "any"]
        ),
        DailyTermCandidate(
            word: "隙間時間",
            reading: "すきまじかん",
            pronunciation: "su-ki-ma-ji-kan",
            meaning: "the small slivers of time between tasks",
            meaningFR: "les petits intervalles de temps entre les tâches",
            flavour: "the five minutes before a meeting, the wait for a kettle. A whole word for the time most cultures don't even count",
            flavourFR: "les cinq minutes avant une réunion, l'attente de la bouilloire. Un mot entier pour le temps que la plupart des cultures ne comptent même pas",
            jlptLevel: nil,
            tags: ["self", "monday", "tuesday", "wednesday", "thursday", "friday", "any"]
        ),
        DailyTermCandidate(
            word: "口寂しい",
            reading: "くちさびしい",
            pronunciation: "ku-chi-sa-bi-shi-i",
            meaning: "wanting to eat or chew something out of restlessness, not hunger",
            meaningFR: "vouloir manger ou mâcher par agitation, pas par faim",
            flavour: "literally 'mouth-lonely' — the urge to nibble that has nothing to do with being hungry. Every snack drawer's secret name",
            flavourFR: "littéralement 'bouche-solitaire' — l'envie de grignoter qui n'a rien à voir avec la faim. Le nom secret de tout tiroir à goûter",
            jlptLevel: nil,
            tags: ["mood", "evening", "any"]
        ),
        DailyTermCandidate(
            word: "目の保養",
            reading: "めのほよう",
            pronunciation: "me-no-ho-yo-u",
            meaning: "a feast for the eyes",
            meaningFR: "un régal pour les yeux",
            flavour: "literally 'eye nourishment' — the small recovery you get from looking at something beautiful for no reason",
            flavourFR: "littéralement 'nourriture des yeux' — la petite récupération qu'on tire de regarder quelque chose de beau sans raison",
            jlptLevel: nil,
            tags: ["aesthetic", "weekend", "any"]
        ),

        // MARK: Specific cultural rituals

        DailyTermCandidate(
            word: "月見",
            reading: "つきみ",
            pronunciation: "tsu-ki-mi",
            meaning: "moon viewing",
            meaningFR: "contemplation de la lune",
            flavour: "the autumn pastime of going outside on purpose to look at the moon. There's even a moon-viewing dango for it",
            flavourFR: "le passe-temps d'automne qui consiste à sortir exprès pour regarder la lune. Il existe même un dango spécial pour ça",
            jlptLevel: .n3,
            tags: ["autumn", "september", "october", "evening"]
        ),
        DailyTermCandidate(
            word: "雪見",
            reading: "ゆきみ",
            pronunciation: "yu-ki-mi",
            meaning: "snow viewing",
            meaningFR: "contemplation de la neige",
            flavour: "third of the trio (with hanami and tsukimi). The deliberate act of looking at falling snow, ideally with a warm drink in hand",
            flavourFR: "le troisième du trio (avec hanami et tsukimi). L'acte délibéré de regarder la neige tomber, idéalement avec une boisson chaude à la main",
            jlptLevel: nil,
            tags: ["winter", "december", "january", "february"]
        ),
        DailyTermCandidate(
            word: "紅葉狩り",
            reading: "もみじがり",
            pronunciation: "mo-mi-ji-ga-ri",
            meaning: "leaf-hunting — going to look at autumn foliage",
            meaningFR: "chasse aux feuilles — aller observer les couleurs d'automne",
            flavour: "literally 'maple hunting' — though nothing is hunted. The autumn answer to hanami: chase the colour before it falls",
            flavourFR: "littéralement 'chasse à l'érable' — bien que rien ne soit chassé. La réponse automnale au hanami : chasser la couleur avant qu'elle ne tombe",
            jlptLevel: nil,
            tags: ["autumn", "october", "november", "weekend"]
        ),
        DailyTermCandidate(
            word: "こたつ",
            reading: "こたつ",
            pronunciation: "ko-ta-tsu",
            meaning: "low table with a heater and a quilt over it",
            meaningFR: "table basse avec un chauffage et une couverture par-dessus",
            flavour: "the gravitational well of Japanese winter — once your legs are under the blanket, you do not get up",
            flavourFR: "le puits gravitationnel de l'hiver japonais — une fois les jambes sous la couverture, on ne se relève pas",
            jlptLevel: .n2,
            tags: ["winter", "december", "january", "february"]
        ),
        DailyTermCandidate(
            word: "初詣",
            reading: "はつもうで",
            pronunciation: "ha-tsu-mo-u-de",
            meaning: "the year's first visit to a shrine",
            meaningFR: "la première visite au sanctuaire de l'année",
            flavour: "the first shrine visit of the new year — half tradition, half excuse to get some fresh air on January 1st",
            flavourFR: "la première visite au sanctuaire du nouvel an — moitié tradition, moitié prétexte pour prendre l'air le 1er janvier",
            jlptLevel: nil,
            tags: ["winter", "january"]
        ),
        DailyTermCandidate(
            word: "桜前線",
            reading: "さくらぜんせん",
            pronunciation: "sa-ku-ra-zen-sen",
            meaning: "the cherry-blossom front",
            meaningFR: "le front des cerisiers en fleur",
            flavour: "the imaginary weather front along which sakura bloom — covered on the news every spring like an actual storm system",
            flavourFR: "le front météo imaginaire le long duquel les sakura fleurissent — couvert aux infos chaque printemps comme une vraie dépression",
            jlptLevel: nil,
            tags: ["spring", "march", "april"]
        ),
        DailyTermCandidate(
            word: "五月病",
            reading: "ごがつびょう",
            pronunciation: "go-gatsu-byou",
            meaning: "May sickness — the post-holiday slump",
            meaningFR: "le mal de mai — la déprime post-vacances",
            flavour: "the Japanese name for the May funk that hits new students and employees after Golden Week. Diagnosed culturally, cured by routine",
            flavourFR: "le nom japonais du blues de mai qui frappe les nouveaux étudiants et employés après la Golden Week. Diagnostiqué culturellement, guéri par la routine",
            jlptLevel: nil,
            tags: ["spring", "may", "monday"]
        ),

        // MARK: Verbs and expressions worth noticing

        DailyTermCandidate(
            word: "お疲れ様",
            reading: "おつかれさま",
            pronunciation: "o-tsu-ka-re-sa-ma",
            meaning: "expression that recognises someone's effort",
            meaningFR: "expression qui reconnaît l'effort de quelqu'un",
            flavour: "the word coworkers say to each other at the end of a shift — there's no English equivalent, but everyone wishes there were",
            flavourFR: "le mot que se disent les collègues en fin de journée — pas d'équivalent en français, mais tout le monde aimerait qu'il en existe un",
            jlptLevel: .n4,
            tags: ["expression", "evening", "friday", "any"]
        ),
        DailyTermCandidate(
            word: "仕方ない",
            reading: "しかたない",
            pronunciation: "shi-ka-ta-nai",
            meaning: "it can't be helped",
            meaningFR: "on n'y peut rien",
            flavour: "the most-used three syllables in any Japanese week — half acceptance, half philosophy. Translates badly because the shrug is the meaning",
            flavourFR: "les trois syllabes les plus utilisées d'une semaine japonaise — moitié acceptation, moitié philosophie. Mal traduisible parce que c'est le haussement d'épaules qui fait le sens",
            jlptLevel: .n3,
            tags: ["expression", "any"]
        ),
        DailyTermCandidate(
            word: "面倒くさい",
            reading: "めんどうくさい",
            pronunciation: "men-do-u-ku-sa-i",
            meaning: "what a pain; can't be bothered",
            meaningFR: "quelle plaie ; pas envie de se prendre la tête",
            flavour: "the word every Japanese person has muttered at a Monday morning email. Endlessly applicable (often contracted to めんどくさい in speech)",
            flavourFR: "le mot que chaque Japonais a marmonné devant un mail du lundi matin. Applicable à l'infini (souvent contracté en めんどくさい à l'oral)",
            jlptLevel: .n3,
            tags: ["mood", "monday", "any"]
        ),
        DailyTermCandidate(
            word: "微妙",
            reading: "びみょう",
            pronunciation: "bi-myou",
            meaning: "subtle; iffy; hard to call",
            meaningFR: "subtil ; mitigé ; difficile à trancher",
            flavour: "the polite word for 'not great, not terrible' — used to describe everything from a film to a piece of fish that's been in the fridge too long",
            flavourFR: "le mot poli pour 'ni génial, ni catastrophique' — utilisé pour qualifier autant un film qu'un poisson resté trop longtemps au frigo",
            jlptLevel: .n3,
            tags: ["mood", "any"]
        ),
        DailyTermCandidate(
            word: "言霊",
            reading: "ことだま",
            pronunciation: "ko-to-da-ma",
            meaning: "the spirit, or power, that lives in words",
            meaningFR: "l'esprit, ou le pouvoir, qui vit dans les mots",
            flavour: "the old Japanese belief that what you say shapes what happens — which is why some words are still avoided at weddings",
            flavourFR: "la vieille croyance japonaise selon laquelle ce qu'on dit façonne ce qui arrive — c'est pourquoi certains mots sont encore évités aux mariages",
            jlptLevel: nil,
            tags: ["aesthetic", "any"]
        ),
        DailyTermCandidate(
            word: "真面目",
            reading: "まじめ",
            pronunciation: "ma-ji-me",
            meaning: "earnest, diligent, taking things seriously",
            meaningFR: "sérieux, appliqué, qui prend les choses au sérieux",
            flavour: "high praise in a Japanese workplace — the quiet, reliable virtue of doing the job properly",
            flavourFR: "un grand compliment dans un bureau japonais — la vertu calme et fiable de faire le boulot proprement",
            jlptLevel: .n3,
            tags: ["self", "monday", "any"]
        ),
        DailyTermCandidate(
            word: "馬鹿正直",
            reading: "ばかしょうじき",
            pronunciation: "ba-ka-shou-ji-ki",
            meaning: "honest to a fault",
            meaningFR: "honnête jusqu'à l'excès",
            flavour: "literally 'idiotically honest' — the kind of person who tells the truth even when it would be wiser to stay quiet. Said with affection more often than not",
            flavourFR: "littéralement 'bêtement honnête' — le genre de personne qui dit la vérité même quand il vaudrait mieux se taire. Dit avec affection le plus souvent",
            jlptLevel: nil,
            tags: ["self", "any"]
        ),
        DailyTermCandidate(
            word: "起承転結",
            reading: "きしょうてんけつ",
            pronunciation: "ki-sho-u-ten-ke-tsu",
            meaning: "four-act narrative structure: intro, develop, twist, resolve",
            meaningFR: "structure narrative en quatre temps : intro, développement, retournement, résolution",
            flavour: "the Japanese counterpart to the three-act structure — but with a twist instead of a climax. A different shape for telling stories",
            flavourFR: "l'équivalent japonais de la structure en trois actes — mais avec un retournement à la place du climax. Une autre forme pour raconter une histoire",
            jlptLevel: nil,
            tags: ["aesthetic", "any"]
        ),

        // MARK: Social grammar — niche but discoverable

        DailyTermCandidate(
            word: "空気を読む",
            reading: "くうきをよむ",
            pronunciation: "ku-u-ki-wo-yo-mu",
            meaning: "to read the air — to sense the unspoken mood of a room",
            meaningFR: "lire l'air — sentir l'ambiance non dite d'une pièce",
            flavour: "the social skill the language treats as a literacy. To not read the air is `KY` — a real, used insult",
            flavourFR: "la compétence sociale que la langue traite comme une alphabétisation. Ne pas lire l'air, c'est être `KY` — une vraie insulte, utilisée",
            jlptLevel: nil,
            tags: ["society", "any"]
        ),
        DailyTermCandidate(
            word: "根回し",
            reading: "ねまわし",
            pronunciation: "ne-ma-wa-shi",
            meaning: "preparing the ground — informal consensus-building before a meeting",
            meaningFR: "préparer le terrain — construire un consensus informel avant la réunion",
            flavour: "literally 'going around the roots'. The art of having every important conversation *before* the official meeting, so the meeting itself is the easy part",
            flavourFR: "littéralement 'faire le tour des racines'. L'art d'avoir toutes les conversations importantes *avant* la réunion officielle, pour que la réunion elle-même soit la partie facile",
            jlptLevel: nil,
            tags: ["society", "industrial", "monday", "tuesday"]
        ),
        DailyTermCandidate(
            word: "本末転倒",
            reading: "ほんまつてんとう",
            pronunciation: "hon-ma-tsu-ten-to-u",
            meaning: "putting the trivial before the essential",
            meaningFR: "mettre l'accessoire avant l'essentiel",
            flavour: "literally 'root and tip, upside down'. The four-character verdict on any project that polished the wrong thing",
            flavourFR: "littéralement 'racine et pointe, à l'envers'. Le verdict en quatre caractères de tout projet qui a peaufiné la mauvaise chose",
            jlptLevel: nil,
            tags: ["self", "industrial", "any"]
        ),
        DailyTermCandidate(
            word: "井の中の蛙",
            reading: "いのなかのかわず",
            pronunciation: "i-no-na-ka-no-ka-wa-zu",
            meaning: "a frog in a well — someone with a narrow worldview",
            meaningFR: "une grenouille au fond d'un puits — quelqu'un à la vision du monde étroite",
            flavour: "from a Zhuangzi parable — the frog at the bottom of a well thinks the patch of sky overhead is the whole sky. A gentle warning to anyone confident in a small pond",
            flavourFR: "d'une parabole de Zhuangzi — la grenouille au fond du puits croit que la parcelle de ciel au-dessus est le ciel entier. Un doux avertissement à quiconque se sent à l'aise dans une petite mare",
            jlptLevel: nil,
            tags: ["aesthetic", "any"]
        ),

        // MARK: Modern phenomena

        DailyTermCandidate(
            word: "走馬灯",
            reading: "そうまとう",
            pronunciation: "so-u-ma-to-u",
            meaning: "a revolving lantern; figuratively, life flashing before one's eyes",
            meaningFR: "une lanterne tournante ; au figuré, la vie qui défile devant les yeux",
            flavour: "named after a paper lantern with rotating cut-outs. The word the language reaches for when memories suddenly cycle past, fast and lit from within",
            flavourFR: "tiré d'une lanterne en papier aux découpes tournantes. Le mot que la langue attrape quand les souvenirs défilent soudain, rapides et éclairés de l'intérieur",
            jlptLevel: nil,
            tags: ["aesthetic", "evening", "autumn", "any"]
        ),
        DailyTermCandidate(
            word: "終活",
            reading: "しゅうかつ",
            pronunciation: "shu-u-ka-tsu",
            meaning: "preparing in advance for the end of one's life",
            meaningFR: "préparer à l'avance la fin de sa vie",
            flavour: "a word coined in the 2000s — the practical version of putting affairs in order. Funeral plans, will, possessions sorted while you're still here",
            flavourFR: "un mot inventé dans les années 2000 — la version pratique de mettre ses affaires en ordre. Funérailles prévues, testament, biens triés tant qu'on est encore là",
            jlptLevel: nil,
            tags: ["self", "any"]
        ),
        DailyTermCandidate(
            word: "わざわざ",
            reading: "わざわざ",
            pronunciation: "wa-za-wa-za",
            meaning: "going out of one's way to do something",
            meaningFR: "se donner la peine de faire quelque chose",
            flavour: "the adverb that thanks someone for the effort *and* gently scolds them for it at the same time. A whole feeling, packaged in four mora",
            flavourFR: "l'adverbe qui remercie quelqu'un pour l'effort *et* le gronde gentiment en même temps. Un sentiment entier, emballé en quatre mores",
            jlptLevel: .n3,
            tags: ["expression", "any"]
        ),
        DailyTermCandidate(
            word: "一目惚れ",
            reading: "ひとめぼれ",
            pronunciation: "hi-to-me-bo-re",
            meaning: "love at first sight",
            meaningFR: "coup de foudre",
            flavour: "literally 'one-look infatuation'. Used as comfortably for a person as for a notebook in a stationery shop",
            flavourFR: "littéralement 'engouement d'un seul regard'. Aussi à l'aise pour une personne que pour un carnet en papeterie",
            jlptLevel: nil,
            tags: ["mood", "any"]
        ),
        DailyTermCandidate(
            word: "物寂しい",
            reading: "ものさびしい",
            pronunciation: "mo-no-sa-bi-shi-i",
            meaning: "vaguely, atmospherically lonely",
            meaningFR: "vaguement, atmosphériquement solitaire",
            flavour: "the loneliness of a place rather than a person — an empty platform, a closed shop in October. Distinct from plain `さびしい`",
            flavourFR: "la solitude d'un lieu plutôt que d'une personne — un quai désert, une boutique fermée en octobre. Distinct du simple `さびしい`",
            jlptLevel: nil,
            tags: ["mood", "autumn", "evening"]
        )
    ]
}
