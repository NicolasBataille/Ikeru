"""
Pre-generate Japanese pronunciation clips and bundle them under
Ikeru/Resources/Audio/ — one .m4a per unique spoken string, named by the first
16 hex chars of SHA-256(text). The app resolves clips with the identical hash
(IkeruCore/Sources/Services/Audio/BundledAudioLocator.swift), so playback is
fully offline with zero user setup; missing clips fall back to on-device synth.

Voice: VOICEVOX (free, redistribution-clean with character credit), speaker 2
(Shikoku Metan, Normal) — clear and neutral. Run the engine locally with no
Docker Desktop, via Apple's native container runtime (macOS 26+):

    brew install container
    container system start                       # accept the kernel install
    container run -d --name voicevox --arch amd64 \\
        docker.io/voicevox/voicevox_engine:cpu-ubuntu20.04-latest
    container ls                                 # note the container IP
    echo <container-ip> > /tmp/voicevox_ip.txt
    python3 scripts/generate-audio.py            # idempotent; skips existing

Run this same command again whenever this file changes (e.g. new kana added
to KanaGroup.swift, or new vocab/sentences in the content bundle) — already
generated clips are skipped, so only the new texts get synthesized.

Texts: all 208 drillable kana (92 base + 50 dakuten + 66 yōon, hiragana +
katakana — see IkeruCore/Sources/Models/Kana/KanaGroup.swift's `characterTable`,
the source of truth this list is matched against) + every N5 vocabulary
reading + every example sentence from Ikeru/Resources/ContentBundles/
n5-content.sqlite, PLUS every "term of the day" reading parsed straight from
IkeruCore's DailyTermCatalog.swift (so the set stays in lock-step with the
catalog) (~560 clips, ~10 MB).
"""
import hashlib, os, re, sqlite3, subprocess, tempfile, urllib.parse, urllib.request

IP = open("/tmp/voicevox_ip.txt").read().strip()
BASE = f"http://{IP}:50021"
SPEAKER = 2  # 四国めたん ノーマル — clear, neutral
OUT = "Ikeru/Resources/Audio"
os.makedirs(OUT, exist_ok=True)

# Base kana (92): unchanged since the pipeline's first version.
HIRAGANA = "あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをん"
KATAKANA = "アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲン"

# Dakuten (voiced) kana (50): single code points, safe to iterate char-by-char
# like the base sets above.
HIRAGANA_DAKUTEN = "がぎぐげございずぜぞだぢづでどばびぶべぼぱぴぷぺぽ"
KATAKANA_DAKUTEN = "ガギグゲゴザジズゼゾダヂヅデドバビブベボパピプペポ"

# Yōon (combined digraphs, e.g. きゃ) (66): each entry is TWO code points, so
# these are lists of complete strings, never a string to iterate char-by-char
# — doing so would split each digraph into two orphan kana with no clip.
HIRAGANA_YOON = [
    "きゃ", "きゅ", "きょ", "しゃ", "しゅ", "しょ", "ちゃ", "ちゅ", "ちょ",
    "にゃ", "にゅ", "にょ", "ひゃ", "ひゅ", "ひょ", "みゃ", "みゅ", "みょ",
    "りゃ", "りゅ", "りょ", "ぎゃ", "ぎゅ", "ぎょ", "じゃ", "じゅ", "じょ",
    "びゃ", "びゅ", "びょ", "ぴゃ", "ぴゅ", "ぴょ",
]
KATAKANA_YOON = [
    "キャ", "キュ", "キョ", "シャ", "シュ", "ショ", "チャ", "チュ", "チョ",
    "ニャ", "ニュ", "ニョ", "ヒャ", "ヒュ", "ヒョ", "ミャ", "ミュ", "ミョ",
    "リャ", "リュ", "リョ", "ギャ", "ギュ", "ギョ", "ジャ", "ジュ", "ジョ",
    "ビャ", "ビュ", "ビョ", "ピャ", "ピュ", "ピョ",
]

def key_for(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]

DAILY_TERM_CATALOG = "IkeruCore/Sources/Models/DailyTerm/DailyTermCatalog.swift"

def collect_daily_term_readings():
    """The 🔊 button on the term-of-the-day reveal speaks `term.reading`.
    Parse the readings straight from the Swift catalog so this list never
    drifts from what the app actually pronounces. Matches `reading: "..."`."""
    try:
        src = open(DAILY_TERM_CATALOG, encoding="utf-8").read()
    except FileNotFoundError:
        print(f"WARN: {DAILY_TERM_CATALOG} not found — skipping daily terms", flush=True)
        return []
    return [m.strip() for m in re.findall(r'reading:\s*"([^"]+)"', src) if m.strip()]

def collect_texts():
    texts = []
    for ch in HIRAGANA + KATAKANA + HIRAGANA_DAKUTEN + KATAKANA_DAKUTEN:
        texts.append(ch)
    texts.extend(HIRAGANA_YOON)
    texts.extend(KATAKANA_YOON)
    con = sqlite3.connect("Ikeru/Resources/ContentBundles/n5-content.sqlite")
    for (r,) in con.execute("SELECT DISTINCT reading FROM vocabulary WHERE reading IS NOT NULL AND TRIM(reading)!=''"):
        texts.append(r.strip())
    for (s,) in con.execute("SELECT DISTINCT japanese FROM sentences WHERE japanese IS NOT NULL AND TRIM(japanese)!=''"):
        texts.append(s.strip())
    con.close()
    texts.extend(collect_daily_term_readings())
    # de-dup, preserve order
    seen, uniq = set(), []
    for t in texts:
        if t not in seen:
            seen.add(t); uniq.append(t)
    return uniq

def synth(text):
    q = urllib.parse.urlencode({"text": text, "speaker": SPEAKER})
    req = urllib.request.Request(f"{BASE}/audio_query?{q}", method="POST")
    with urllib.request.urlopen(req, timeout=60) as r:
        query = r.read()
    req2 = urllib.request.Request(f"{BASE}/synthesis?speaker={SPEAKER}", data=query,
                                  headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req2, timeout=120) as r:
        return r.read()  # WAV bytes

def main():
    texts = collect_texts()
    print(f"to generate: {len(texts)} unique texts (speaker={SPEAKER})", flush=True)
    done = skipped = failed = 0
    for i, t in enumerate(texts):
        k = key_for(t)
        out_m4a = os.path.join(OUT, f"{k}.m4a")
        if os.path.exists(out_m4a):
            skipped += 1; continue
        try:
            wav = synth(t)
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tf:
                tf.write(wav); wav_path = tf.name
            subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", wav_path, out_m4a],
                           check=True, capture_output=True)
            os.unlink(wav_path)
            done += 1
        except Exception as e:
            failed += 1
            print(f"FAIL [{i}] {t!r}: {e}", flush=True)
        if (i + 1) % 25 == 0:
            print(f"  ...{i+1}/{len(texts)} (new={done} skip={skipped} fail={failed})", flush=True)
    print(f"DONE: generated={done} skipped={skipped} failed={failed} totaltexts={len(texts)}", flush=True)
    # size
    sz = sum(os.path.getsize(os.path.join(OUT,f)) for f in os.listdir(OUT) if f.endswith('.m4a'))
    print(f"audio dir: {len([f for f in os.listdir(OUT) if f.endswith('.m4a')])} files, {sz/1e6:.1f} MB", flush=True)

main()
