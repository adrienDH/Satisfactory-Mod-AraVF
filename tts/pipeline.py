"""Doublage de l'IA FICSIT pour une langue (ARAVF_LANG, voir languages.py) : voix Kokoro + effets FICSIT.

  uv run python tts/pipeline.py prepare      # plan : messages, textes, bus, cinematiques
  uv run --python 3.12 --with "kokoro>=0.9.4" --with "transformers>=4.44" --with soundfile \
      python tts/pipeline.py synth           # une voix par sous-titre (reprise possible)
  uv run python tts/pipeline.py assemble     # un fichier par message + horaires des sous-titres

Entrees : corpus/ada_corpus.tsv, corpus/messages.tsv (extract/), raw/narrative (assets MSG_* du jeu),
raw/vanilla-bus.txt. Sorties : tts/voices/<langue>/plan.json, lines/*.wav, messages/*.wav.
"""
import array
import csv
import json
import os
import re
import struct
import subprocess
import sys
import time
import wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from languages import CURRENT, LANG, speakable  # noqa: E402

CORPUS = os.path.join(ROOT, "corpus", "ada_corpus.tsv")
MESSAGES = os.path.join(ROOT, "corpus", "messages.tsv")
VANILLA_BUS = os.path.join(ROOT, "raw", "vanilla-bus.txt")
NARRATIVE = os.path.join(ROOT, "raw", "narrative")             # assets MSG_* extraits du jeu
OUT = os.path.join(ROOT, "tts", "voices", LANG)
LINES = os.path.join(OUT, "lines")
MSGS = os.path.join(OUT, "messages")
PLAN = os.path.join(OUT, "plan.json")

AI_SENDERS = {"Sender_ADA", "Sender_ADA_Ficsmas", "Sender_ADA_Pelevator"}
ALIEN_SENDER = "Sender_Aliens"
DEFAULT_BUS = "main_ada_vo"
SPECIFIC_BUSES = ("vo_barks", "vo_pelevator")   # le plus precis l'emporte sur DEFAULT_BUS
PAUSE = 1.2                                     # sous-titre vide de l'asset (" ") : silence (s)
MAX_TEMPO = 1.3                                 # acceleration maximale d'une replique de cinematique
GAP = 0.35                                      # silence entre deux sous-titres d'un message (s)
SILENCE = 180                                   # seuil de fin de voix (~ -45 dBFS sur 16 bits)
RATE = 44100

# ---------------------------------------------------------------- cinematiques
# Outro : voix jouees par la cinematique (pas par un UFGMessage) ; le mod remplace en memoire l'identifiant
# Wwise de chaque evenement du jeu par celui de la voix du pack.
# (nom de l'evenement, duree anglaise en s, [(cle Narrative/Outro, debut en s), ...]) ; debuts : horaires
# des mots de la voix anglaise (transcription Whisper des sons extraits).
OUTRO_DIR = "/Game/WwiseAudio/Events/VO/ProjectAssembly_VO_Test/"
OUTRO = [
    ("Play_VO_ProjectAssemblyTest_VO_Outro_01", 3.14, [("0010", 0)]),
    ("Play_VO_ProjectAssemblyTest_VO_Outro_02", 2.27, [("0020", 0)]),
    ("Play_VO_ProjectAssemblyTest_VO_Outro_03", 2.09, [("0030", 0)]),
    ("Play_VO_ProjectAssemblyTest_VO_Outro_04", 2.38, [("0040", 0)]),
    ("Play_VO_ProjectAssemblyTest_VO_Outro_05", 1.55, [("0050", 0)]),
    ("Play_VO_ProjectAssemblyTest_VO_Outro_06", 2.60, [("0060", 0)]),
    ("Play_VO_ProjectAssemblyTest_VO_Outro_07", 1.47, [("0070", 0)]),
    ("Play_VO_ProjectAssemblyTest_VO_Outro_08", 1.53, [("0090", 0)]),
    ("Play_VO_ProjectAssemblyTest_VO_Outro_09", 1.80, [("0100", 0)]),
    ("Play_VO_ProjectAssemblyTest_VO_Outro_10", 1.32, [("0110", 0)]),
    ("Play_VO_ProjectAssemblyTest_VO_Outro_11", 3.31, [("0120", 0)]),
    ("Play_VO_ProjectAssembly_Test_VO_Outro_12", 1.37, [("0130", 0)]),
    ("Play_VO_ProjectAssemblyTest_VO_Outro_13", 10.64, [("0140", 0), ("0150", 2.0), ("0160", 3.1), ("0170", 4.1),
                                                         ("0180", 5.1), ("0190", 6.3), ("0200", 7.4), ("0210", 8.5)]),
]

# Intro (capsule) : un seul evenement du jeu joue 2 min 42 de voix ET d'ambiance dans la meme piste. Pour ne
# redistribuer aucun son du jeu, le pack joue sa voix des que l'evenement demarre, rend muette la piste anglaise
# (voix + ambiance), baisse la piste d'effets pendant chaque replique (la voix anglaise s'y entend un peu) et
# joue une ambiance de capsule recreee (intro_ambience.py).
INTRO_TRIGGER = "Play_Cinematic_DropPod"
INTRO_DURATION = 162.29
INTRO_MUTE_DB = -96.0        # piste anglaise (voix + ambiance) : muette pendant toute l'intro
INTRO_FX_DUCK_DB = -20.0     # piste d'effets : baissee pendant chaque replique
INTRO_ALIEN = {"0110"}       # cri des aliens ("V O I C I   N O T R E   C H A N T"), dit par la voix alien
INTRO_AMBIENCE = os.path.join(ROOT, "tts", "voices", "intro_ambience.wav")
INTRO = [("0010", 5.58), ("0020", 8.46), ("0030", 11.88), ("0040", 18.52), ("0050", 25.64), ("0060", 29.6),
         ("0070", 33.66), ("0080", 40.74), ("0090", 50.34), ("0100", 57.6), ("0110", 59.0), ("0120", 61.46),
         ("0130", 65.06), ("0140", 71.48), ("0150", 75.38), ("0160", 77.56), ("0170", 78.54), ("0180", 80.54),
         ("0190", 83.40), ("0200", 93.08), ("0210", 97.98), ("0220", 101.24), ("0230", 104.56), ("0240", 106.62),
         ("0250", 126.46), ("0260", 127.98), ("0270", 129.6), ("0280", 132.14), ("0290", 135.3), ("0300", 151.18),
         ("0310", 156.2)]


# ---------------------------------------------------------------- outils
def read_corpus():
    with open(CORPUS, encoding="utf-8") as f:
        return list(csv.DictReader(f, delimiter="\t", quoting=csv.QUOTE_NONE))


def wwise_id(message):
    """MSG_Tier1_Schematic_1-1 -> Tier1_Schematic_1_1 (caracteres surs pour Wwise et Unreal)."""
    return re.sub(r"[^A-Za-z0-9_]", "_", message[4:] if message.startswith("MSG_") else message)


def paths(ident, count):
    """Fichiers d'un message : une voix par sous-titre, puis le message assemble."""
    return [os.path.join(LINES, f"{ident}__{i:02d}.wav") for i in range(count)], os.path.join(MSGS, f"{ident}.wav")


def read_wav(path):
    with wave.open(path, "rb") as w:
        params = w.getparams()
        data = array.array("h", w.readframes(w.getnframes()))
    if params.nchannels != 1 or params.sampwidth != 2:
        raise ValueError(f"{path} : attendu mono 16 bits")
    return params.framerate, data


def write_wav(path, data, rate=RATE):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(data.tobytes())


def silence(seconds, rate=RATE):
    return array.array("h", bytes(int(seconds * rate) * 2))


def trim_tail(data):
    end = len(data)
    while end > 0 and abs(data[end - 1]) < SILENCE:
        end -= 1
    return data[:end]


def unspaced(text):
    """'V O I C I   N O T R E   C H A N T' -> 'Voici notre chant.'"""
    words = [w.replace(" ", "") for w in re.split(r"\s{2,}", text.strip())]
    return " ".join(words).capitalize() + "."


# ---------------------------------------------------------------- prepare
def asset_subtitles(asset):
    """Sous-titres de l'asset du jeu : {indice: (texte source, index d'import de l'interlocuteur)}.
    Chaque sous-titre (FText puis TimeStamp puis Sender) se termine par la reference a son Sender."""
    rel = asset.split(".")[0][len("/Game/FactoryGame/Narrative/"):]
    with open(os.path.join(NARRATIVE, rel + ".uasset"), "rb") as f:
        b = f.read()
    subs = {}
    for m in re.finditer(rb"/Subtitles\((\d+)\)\x00", b):
        n = struct.unpack_from("<i", b, m.end())[0]
        start, size = m.end() + 4, (n if n >= 0 else -2 * n)
        text = b[start:start + size].decode("utf-8" if n >= 0 else "utf-16-le", "replace").rstrip("\x00")
        sender = next((v for q in range(start + size, start + size + 80)
                       for v in [struct.unpack_from("<i", b, q)[0]] if -40 < v < 0 and b[q - 1] == 0), None)
        subs[int(m.group(1))] = (text, sender)
    return subs


def voices_of(asset, senders, count):
    """Qui dit chaque sous-titre : "ia" ou "alien", ou None si on ne sait pas.
    Dans un message mixte, l'import de Sender_Aliens precede celui de l'IA (verifie sur les 50 messages)."""
    if ALIEN_SENDER not in senders:
        return ["ia"] * count
    if not senders & AI_SENDERS:
        return ["alien"] * count
    subs = asset_subtitles(asset)
    if len(subs) != count or any(v is None for _, v in subs.values()):
        return None
    alien = min(v for _, v in subs.values())
    return ["alien" if subs[i][1] == alien else "ia" for i in sorted(subs)]


def cine_entries(texts):
    """Entrees du plan pour l'outro (voix remplacees) et l'intro (voix ajoutee)."""
    entries, skipped = [], {}
    cines = [("Narrative/Outro", f"{OUTRO_DIR}{name}.{name}", name, dur, keys) for name, dur, keys in OUTRO]
    cines.append(("Narrative/Intro", "", INTRO_TRIGGER, INTRO_DURATION, INTRO))
    for namespace, game_event, name, duration, keys in cines:
        ident = "Cine_" + wwise_id(re.sub(r"^Play_(VO_)?", "", name))
        lines = [texts.get((namespace, k), "") for k, _ in keys]
        if not all(t.strip() for t in lines):
            skipped[name] = "cinematique non traduite"
            continue
        intro = not game_event
        alien = [intro and k in INTRO_ALIEN for k, _ in keys]
        lines_wav, wav = paths(ident, len(lines))
        entries.append({
            "id": ident,
            "message": name,
            "asset": "",
            "cine": True,
            "vanilla_event": game_event,                      # outro : evenement du jeu dont la voix est remplacee
            "trigger": name if intro else "",                 # intro : voix jouee en plus de l'evenement du jeu
            "mute_db": INTRO_MUTE_DB if intro else 0,
            "fx_duck_db": INTRO_FX_DUCK_DB if intro else 0,
            "extras": [{"id": "Cine_Ambience", "wav": INTRO_AMBIENCE, "bus": "cinematic"}] if intro else [],
            "vanilla_duration": duration,
            "offsets": [t for _, t in keys],
            "bus": DEFAULT_BUS,
            "asset_subtitles": 0,
            "texts": lines,
            "speech": [speakable(unspaced(t) if a else t) for t, a in zip(lines, alien)],
            "voices": ["alien" if a else "ia" for a in alien],
            "lines": lines_wav,
            "wav": wav,
        })
    return entries, skipped


def prepare():
    corpus = read_corpus()
    column = CURRENT["column"]
    subs, texts = {}, {}
    for row in corpus:
        texts[(row["namespace"], row["key"])] = row[column]
        if row["sub_index"]:
            subs.setdefault(row["message"], {})[int(row["sub_index"])] = row[column]

    buses = {}
    with open(VANILLA_BUS, encoding="utf-8-sig") as f:
        for line in f:
            name, _, rest = line.strip().partition(" ")
            found = [b for b in SPECIFIC_BUSES if b in rest]
            buses[name] = found[0] if found else DEFAULT_BUS

    plan, skipped = [], {}
    with open(MESSAGES, encoding="utf-8") as f:
        for row in csv.DictReader(f, delimiter="\t", quoting=csv.QUOTE_NONE):
            name = row["message"]
            senders = set(filter(None, row["senders"].split(",")))
            translated = subs.get(name, {})
            if not translated:
                skipped[name] = "aucun sous-titre"
                continue
            unknown = senders - AI_SENDERS - {ALIEN_SENDER}
            if unknown:
                skipped[name] = "interlocuteur inconnu : " + ",".join(sorted(unknown))
                continue
            count = max(int(row["subtitles"]), len(translated))
            missing = [i for i in range(count) if i not in translated]
            # sous-titres sans traduction : seulement des pauses (" ") dans l'asset, sinon on ecarte
            if missing and any(asset_subtitles(row["asset"]).get(i, ("?",))[0].strip() for i in missing):
                skipped[name] = f"sous-titres non traduits : {missing}"
                continue
            voices = voices_of(row["asset"], senders, count)
            if voices is None:
                skipped[name] = "interlocuteurs des sous-titres illisibles"
                continue
            lines = [translated.get(i, "") for i in range(count)]
            bank = os.path.splitext(os.path.basename(row["bank"]))[0] if row["bank"] else ""
            ident = wwise_id(name)
            lines_wav, wav = paths(ident, count)
            plan.append({
                "id": ident,
                "message": name,
                "asset": row["asset"],
                "vanilla_event": row["event"],
                "bus": buses.get(bank, DEFAULT_BUS),
                "asset_subtitles": int(row["subtitles"]),
                "texts": lines,
                "speech": [speakable(t) for t in lines],
                "voices": voices,
                "lines": lines_wav,
                "wav": wav,
            })

    cines, cine_skipped = cine_entries(texts)
    plan += cines
    skipped.update(cine_skipped)
    ids = [p["id"] for p in plan]
    if len(ids) != len(set(ids)):
        sys.exit("identifiants Wwise en double")
    os.makedirs(OUT, exist_ok=True)
    with open(PLAN, "w", encoding="utf-8") as f:
        json.dump({"lang": LANG, "mod": CURRENT["mod"], "language_name": CURRENT["name"],
                   "messages": plan, "skipped": skipped}, f, ensure_ascii=False, indent=1)
    reasons = {}
    for r in skipped.values():
        key = r.split(" :")[0]
        reasons[key] = reasons.get(key, 0) + 1
    print(f"[{LANG}] {len(plan)} messages a doubler, {sum(len(p['texts']) for p in plan)} sous-titres ; ecartes : {reasons}")
    print(f"bus : { {b: sum(1 for p in plan if p['bus'] == b) for b in (DEFAULT_BUS,) + SPECIFIC_BUSES} }")


# ---------------------------------------------------------------- synth
def synth():
    """Une voix par sous-titre (Kokoro, modele charge une fois) ; reprend ou elle s'est arretee."""
    import alien_voice
    import kokoro_voice
    with open(PLAN, encoding="utf-8") as f:
        plan = json.load(f)["messages"]
    jobs = [(t, out, v) for p in plan for t, out, v in zip(p["speech"], p["lines"], p["voices"])
            if not (os.path.exists(out) and os.path.getsize(out) > 1000)]
    total = sum(len(p["lines"]) for p in plan)
    print(f"[{LANG}] {total - len(jobs)} deja generes, {len(jobs)} a generer", flush=True)
    os.makedirs(LINES, exist_ok=True)
    t0 = time.time()
    for i, (speech, out, voice) in enumerate(jobs, 1):
        if not speech:
            write_wav(out, silence(PAUSE))
        elif voice == "alien":
            alien_voice.synth(speech, out)
        else:
            kokoro_voice.synth(speech, out)
        if i % 25 == 0 or i == len(jobs):
            rate = i / (time.time() - t0)
            print(f"  {i}/{len(jobs)}  ({rate:.1f}/s, reste ~{(len(jobs) - i) / rate / 60:.0f} min)", flush=True)
    print("synthese terminee")


# ---------------------------------------------------------------- assemble
def fit_cine_line(data, rate, room):
    """Replique de cinematique : sans le silence initial, et acceleree (30 % au plus) si la parole
    depasse la place que lui laisse l'anglais (room, en s)."""
    lead = next((i for i, v in enumerate(data) if abs(v) > SILENCE), 0)
    data = data[max(0, lead - int(0.03 * rate)):]
    spoken = len(trim_tail(data)) / rate
    tempo = min(MAX_TEMPO, spoken / room) if room > 0 else 1.0
    if tempo <= 1.02:
        return data
    res = subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-f", "s16le", "-ar", str(rate), "-ac", "1", "-i", "-",
                          "-af", f"atempo={tempo:.3f}", "-f", "s16le", "-"], input=data.tobytes(),
                         capture_output=True, check=True)
    return array.array("h", res.stdout)


def merge_windows(windows, gap=0.8):
    """Fenetres [debut, fin] rapprochees (moins de gap s) fusionnees : une seule baisse de volume."""
    merged = []
    for a, b in windows:
        if merged and a - merged[-1][1] < gap:
            merged[-1][1] = b
        else:
            merged.append([a, b])
    return merged


def assemble():
    """Un fichier par message (repliques separees par GAP, ou calees sur l'anglais pour les cinematiques),
    et dans le plan les horaires des sous-titres et, pour l'intro, les fenetres de baisse des effets."""
    with open(PLAN, encoding="utf-8") as f:
        doc = json.load(f)
    os.makedirs(MSGS, exist_ok=True)
    for p in doc["messages"]:
        rate, out, stamps, spoken = None, array.array("h"), [], []
        cine = p.get("cine", False)
        for i, line in enumerate(p["lines"]):
            r, data = read_wav(line)
            if cine and p["texts"][i]:
                nxt = p["offsets"][i + 1] if i + 1 < len(p["offsets"]) else None
                room = (nxt - p["offsets"][i] - 0.15) if nxt is not None else (p["vanilla_duration"] - p["offsets"][i]) * 1.15
                data = fit_cine_line(data, r, room)
            if rate is None:
                rate = r
            elif r != rate:
                raise ValueError(f"{line} : frequence {r} au lieu de {rate}")
            if cine:
                # chaque replique au moment ou l'anglais la dit, sans chevaucher la precedente
                start = max(int(p["offsets"][i] * rate), len(out) + (int(0.1 * rate) if i else 0))
                out.extend(silence((start - len(out)) / rate, rate))
            elif i:
                out.extend(silence(GAP, rate))
            stamps.append(round(len(out) / rate, 3))
            spoken.append([round(len(out) / rate, 3), round((len(out) + len(trim_tail(data))) / rate, 3)])
            last = i == len(p["lines"]) - 1
            out.extend(data if last or not p["texts"][i] else trim_tail(data))
        write_wav(p["wav"], out, rate)
        p["timestamps"] = stamps
        p["duration"] = round(len(out) / rate, 3)
        if p.get("fx_duck_db"):
            p["fx_duck"] = merge_windows(spoken)
        if cine:
            late = [round(s - o, 2) for s, o in zip(stamps, p["offsets"])]
            if max(late) > 0.3:
                print(f"  {p['id']} : repliques en retard sur l'anglais (s) : {late}")
    with open(PLAN, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=1)
    total = sum(p["duration"] for p in doc["messages"])
    print(f"[{LANG}] {len(doc['messages'])} messages assembles, {total / 3600:.2f} h d'audio")


if __name__ == "__main__":
    commands = {"prepare": prepare, "synth": synth, "assemble": assemble}
    if len(sys.argv) != 2 or sys.argv[1] not in commands:
        sys.exit(__doc__)
    commands[sys.argv[1]]()
