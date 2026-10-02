"""Voix de l'IA FICSIT avec Kokoro (modele Apache 2.0), pour la langue de travail (ARAVF_LANG, voir languages.py).

Chaine : Kokoro (voix de la langue) -> decalage de hauteur (tts/kokoro_pitch*.json) -> effets "FICSIT"
(egalisation, modulation en anneau discrete, reflet aigu, echo court), comme ADA dans le jeu.

  uv run --python 3.12 --with "kokoro>=0.9.4" --with "transformers>=4.44" --with soundfile \
      python tts/kokoro_voice.py calibrate 200          # hauteur brute de la voix -> facteur pour 200 Hz
  ... python tts/kokoro_voice.py samples <dossier>      # quelques repliques de test (francais)
  ... python tts/kokoro_voice.py phonemes "<texte>"     # phonemes produits pour un texte (apres regles de la langue)
"""
import csv
import json
import os
import re
import subprocess
import sys
import tempfile

import numpy as np
import soundfile as sf
from kokoro import KPipeline

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tts"))
from languages import CURRENT, speakable  # noqa: E402  langue de travail (ARAVF_LANG)

CORPUS = os.path.join(ROOT, "corpus", "ada_corpus.tsv")
PITCH_FILE = os.path.join(ROOT, "tts", CURRENT["pitch_file"])
VOICE, SPEED, RATE = CURRENT["voice"], CURRENT["speed"], 24000

# Effets FICSIT : 3 branches melangees (voix, modulation en anneau a 70 Hz, reflet une octave plus haut),
# puis echo court et normalisation. {shift} : decalage de hauteur de la voix brute.
FX = (
    "[0:a]{shift}"
    "silenceremove=stop_periods=-1:stop_duration=0.3:stop_threshold=-45dB:stop_silence=0.3,"
    "equalizer=f=700:t=q:w=1.2:g=-3,equalizer=f=1800:t=q:w=1:g=7,highshelf=f=5000:g=-7,"
    "apad=pad_dur=1.2,asplit=3[a][b][c];"
    "[b]aeval='val(0)*sin(2*PI*70*t)':c=same[r];"
    "[c]asetrate=88200,aresample=44100,atempo=0.5,highpass=f=900,lowpass=f=5000,aecho=0.8:0.7:180:0.25[sh];"
    "[a][r][sh]amix=inputs=3:weights='1 0.05 0.04':normalize=0,"
    "aecho=0.8:0.7:50|100:0.14|0.07,lowpass=f=8000,loudnorm"
)

_pipe = None


def kokoro(text, voice=VOICE, speed=SPEED):
    """Synthese brute (24 kHz, float)."""
    global _pipe
    if _pipe is None:
        _pipe = KPipeline(lang_code=CURRENT["kokoro_lang"], repo_id="hexgrad/Kokoro-82M")
    return np.concatenate([np.asarray(a) for _, _, a in _pipe(text, voice=voice, speed=speed)])


def kokoro_text(speech):
    """Texte prononce (deja adapte par speakable) -> graphies propres a Kokoro pour la langue,
    verifiees sur ses phonemes (languages.py, tts_rules)."""
    for pat, rep in CURRENT["tts_rules"]:
        speech = re.sub(pat, rep, speech)
    return speech


def to_wav(audio, out, filters):
    """Audio brut (RATE) -> filtres ffmpeg -> wav mono 16 bits 44,1 kHz."""
    fd, raw = tempfile.mkstemp(suffix=".wav")
    os.close(fd)
    try:
        sf.write(raw, audio, RATE)
        os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
        subprocess.run(["ffmpeg", "-nostdin", "-y", "-v", "error", "-i", raw, "-filter_complex", filters,
                        "-ar", "44100", "-ac", "1", "-c:a", "pcm_s16le", out], check=True)
    finally:
        os.remove(raw)


def synth(speech, out):
    """Une replique : Kokoro -> hauteur -> effets FICSIT -> out."""
    with open(PITCH_FILE, encoding="utf-8") as f:
        ratio = json.load(f)["ratio"]
    shift = f"asetrate={RATE * ratio:.0f},aresample=44100,atempo={1 / ratio:.5f},"
    to_wav(kokoro(kokoro_text(speech)), out, FX.format(shift=shift))


def median_f0(audio, rate):
    """Hauteur mediane (Hz) des trames voisees, par autocorrelation."""
    frame, hop = int(0.04 * rate), int(0.01 * rate)
    lo, hi = int(rate / 400), int(rate / 80)
    f0s = []
    for i in range(0, len(audio) - frame, hop):
        x = audio[i:i + frame] - np.mean(audio[i:i + frame])
        if np.sqrt(np.mean(x * x)) < 0.02:
            continue
        ac = np.correlate(x, x, "full")[frame - 1:]
        lag = lo + int(np.argmax(ac[lo:hi]))
        if ac[lag] / (ac[0] + 1e-9) > 0.5:
            f0s.append(rate / lag)
    return float(np.median(f0s)) if f0s else 0.0


def calibrate(target_hz):
    """Mesure la hauteur brute de la voix sur quelques repliques du corpus, puis regle le facteur
    pour atteindre target_hz (200 Hz pour le francais et l'espagnol)."""
    with open(CORPUS, encoding="utf-8") as f:
        rows = [r for r in csv.DictReader(f, delimiter="\t", quoting=csv.QUOTE_NONE) if r["sub_index"]]
    texts = [r[CURRENT["column"]] for r in rows if 60 < len(r[CURRENT["column"]]) < 160][::97][:6]
    k = float(np.median([median_f0(kokoro(kokoro_text(speakable(t))), RATE) for t in texts]))
    info = {"kokoro_hz": k, "target_hz": target_hz, "ratio": target_hz / k}
    with open(PITCH_FILE, "w", encoding="utf-8") as f:
        json.dump(info, f, indent=1)
    print(f"{VOICE} brute : {k:.0f} Hz ; cible {target_hz:.0f} Hz : facteur {info['ratio']:.3f}")


SAMPLES = {
    "01-attention": "Votre attention, pionnière. Je suis ARA, votre instance personnelle de l'Assistant-Répertoire Artificiel.",
    "02-pardon": "Vous êtes désormais éligible au programme de pardon FICSIT. Je vous pardonnerai donc vos cinq prochaines... erreurs.",
    "03-humanite": "La Terre est en danger, et seuls les pionniers FICSIT nous offrent un espoir de survie. FICSIT compte sur vous... l'humanité compte sur vous.",
    "04-toilettes": "Juste pour bien comprendre, vous jetez de... l'eau aux toilettes.",
}


def phonemes(text):
    """Phonemes que Kokoro prononcera pour un texte de sous-titre (regles de la langue appliquees)."""
    global _pipe
    if _pipe is None:
        _pipe = KPipeline(lang_code=CURRENT["kokoro_lang"], repo_id="hexgrad/Kokoro-82M")
    speech = kokoro_text(speakable(text))
    print(f"texte    : {speech}")
    print(f"phonemes : {' '.join(p for _, p, _ in _pipe(speech, voice=VOICE))}")


def samples(folder):
    for name, text in SAMPLES.items():
        out = os.path.join(folder, name + ".wav")
        synth(speakable(text), out)
        print(f"  {name}  {sf.info(out).duration:.1f} s")


if __name__ == "__main__":
    commands = {"calibrate": lambda a: calibrate(float(a[0])), "samples": lambda a: samples(a[0]),
                "phonemes": lambda a: phonemes(a[0])}
    if len(sys.argv) != 3 or sys.argv[1] not in commands:
        sys.exit(__doc__)
    commands[sys.argv[1]](sys.argv[2:])
