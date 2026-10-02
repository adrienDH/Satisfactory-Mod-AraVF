"""Voix des aliens (communications etranges, technologies aliens, cri de l'intro) : Kokoro + effet de choeur.

Comme dans le jeu, c'est la meme synthese vocale que l'IA, avec d'autres effets : la phrase a trois hauteurs,
legerement decalees, dans un echo leger. Voix Kokoro : "alien_voice" de la langue (languages.py).

  uv run --python 3.12 --with "kokoro>=0.9.4" --with "transformers>=4.44" --with soundfile \
      python tts/alien_voice.py samples <dossier>
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kokoro_voice  # noqa: E402
from languages import CURRENT, speakable  # noqa: E402

SPEED = 0.85
CHOIR = (
    "[0:a]asplit=3[a][b][c];"
    "[a]asetrate={r}*0.80,aresample={r},atempo=1.25[lo];"
    "[b]adelay=25,volume=0.8[mid];"
    "[c]asetrate={r}*1.26,aresample={r},atempo=0.7937,adelay=45,volume=0.45[hi];"
    "[lo][mid][hi]amix=inputs=3:normalize=0,"
    "aecho=0.8:0.9:120|240|420:0.22|0.14|0.07,highpass=f=90,lowpass=f=7000,"
    "aresample=44100,loudnorm=I=-18:TP=-2"
).format(r=kokoro_voice.RATE)


def synth(speech, out):
    """Une replique alien (texte deja adapte par speakable) -> out."""
    audio = kokoro_voice.kokoro(kokoro_voice.kokoro_text(speech), CURRENT["alien_voice"], SPEED)
    kokoro_voice.to_wav(audio, out, CHOIR)


SAMPLES = {
    "symphonie": "Symphonie terminée. Vous n'êtes pas la non-effigie ?",
    "effigie": "L'effigie n'a pas de chant, seulement des échos. Mais elle navigue dans le lit de la rivière.",
}


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] != "samples":
        sys.exit(__doc__)
    for name, text in SAMPLES.items():
        synth(speakable(text), os.path.join(sys.argv[2], f"alien_{name}.wav"))
        print("  ", name)
