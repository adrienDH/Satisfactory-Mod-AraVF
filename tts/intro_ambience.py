"""Ambiance de la capsule pour l'intro francaise, synthetisee (aucun son du jeu n'est redistribue).

Dans le jeu, l'ambiance de l'intro et la voix anglaise d'ADA sont dans la meme piste ; le mod la rend
muette en francais. Ce script recree une ambiance : du bruit dont l'equilibre des frequences suit,
a gros grain (16 bandes, moyenne glissante de 0,3 s), celui de l'ambiance d'origine.

  analyse : ambiance d'origine isolee en local (demucs) -> tts/intro_envelope.npz (chiffres seulement,
            versionne : inutile de refaire l'analyse)
  synthese : bruit stereo faconne par l'enveloppe -> tts/voices/intro_ambience.wav (commune a toutes les langues)

  uv run --with numpy --with soundfile --with scipy python tts/intro_ambience.py            # synthese
  uv run --with numpy --with soundfile --with scipy python tts/intro_ambience.py analyze    # analyse (rarement)

L'analyse attend raw/cine/demucs/htdemucs/787668894/no_vocals.wav : piste 787668894 de Play_Cinematic_DropPod
(extract/pak-extract.ps1 puis vgmstream), sans la voix (demucs --two-stems=vocals).
"""
import os
import sys

import numpy as np
import soundfile as sf
from scipy.ndimage import uniform_filter1d

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "raw", "cine", "demucs", "htdemucs", "787668894", "no_vocals.wav")
OUT = os.path.join(ROOT, "tts", "voices", "intro_ambience.wav")
ENVELOPE = os.path.join(ROOT, "tts", "intro_envelope.npz")
RATE = 48000
N_FFT, HOP = 4096, 1024
EDGES = np.geomspace(20, 16000, 17)     # 16 bandes, du grave a l'aigu
SMOOTH_S = 0.3
STEREO_CORR = 0.75                      # correlation gauche/droite mesuree sur l'original (0,74)


def stft_mag(x, rate):
    win = np.hanning(N_FFT)
    frames = np.lib.stride_tricks.sliding_window_view(np.pad(x, (N_FFT // 2, N_FFT // 2)), N_FFT)[::HOP]
    return np.abs(np.fft.rfft(frames * win, axis=1)), np.fft.rfftfreq(N_FFT, 1 / rate)


def analyze():
    """Energie par bande et par trame de l'ambiance d'origine, lissee dans le temps -> ENVELOPE."""
    a, r = sf.read(SOURCE)
    mono = a.mean(axis=1)
    if r != RATE:
        from scipy.signal import resample_poly
        mono = resample_poly(mono, RATE, r)
    mag, freqs = stft_mag(mono, RATE)
    band = np.digitize(freqs, EDGES) - 1
    env = np.stack([np.sqrt((mag[:, band == b] ** 2).mean(axis=1) + 1e-12) for b in range(len(EDGES) - 1)], axis=1)
    env = uniform_filter1d(env, size=max(1, int(SMOOTH_S * RATE / HOP)), axis=0)
    np.savez_compressed(ENVELOPE, env=env.astype(np.float32), length=len(mono), rms=np.sqrt(np.mean(a ** 2)))
    print(f"{ENVELOPE} : {env.shape[0]} trames x {env.shape[1]} bandes")


def synth(env, length, seed):
    """Bruit blanc -> spectre par bande impose par l'enveloppe (interpolee en frequence), reconstruction OLA."""
    rng = np.random.default_rng(seed)
    noise = rng.standard_normal(length + N_FFT)
    mag, freqs = stft_mag(noise, RATE)
    n = min(len(mag), len(env))
    centers = np.sqrt(EDGES[:-1] * EDGES[1:])
    gain = np.stack([np.interp(np.log(np.maximum(freqs, 1)), np.log(centers), env[t]) for t in range(n)])
    gain[:, freqs < 18] = 0
    win = np.hanning(N_FFT)
    frames = np.lib.stride_tricks.sliding_window_view(np.pad(noise, (N_FFT // 2, N_FFT // 2)), N_FFT)[::HOP][:n]
    spec = np.fft.rfft(frames * win, axis=1)
    spec = spec / (np.abs(spec) + 1e-9) * gain                  # phase du bruit, amplitude de l'enveloppe
    out = np.zeros(n * HOP + N_FFT)
    norm = np.zeros_like(out)
    for t, fr in enumerate(np.fft.irfft(spec, n=N_FFT, axis=1)):
        out[t * HOP:t * HOP + N_FFT] += fr * win
        norm[t * HOP:t * HOP + N_FFT] += win ** 2
    out = out / np.maximum(norm, 1e-6)
    return out[N_FFT // 2:N_FFT // 2 + length]


def main():
    data = np.load(ENVELOPE)
    env, length = data["env"].astype(np.float64), int(data["length"])
    common, left, right = (synth(env, length, s) for s in (1, 2, 3))
    k = np.sqrt(STEREO_CORR)
    stereo = np.stack([k * common + np.sqrt(1 - k * k) * left, k * common + np.sqrt(1 - k * k) * right], axis=1)
    # niveau : meme energie moyenne que l'ambiance d'origine
    stereo *= float(data["rms"]) / np.sqrt(np.mean(stereo ** 2))
    peak = np.abs(stereo).max()
    if peak > 0.98:
        stereo *= 0.98 / peak
    fade = np.linspace(0, 1, int(0.05 * RATE))
    stereo[:len(fade)] *= fade[:, None]
    stereo[-len(fade):] *= fade[::-1, None]
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    sf.write(OUT, stereo, RATE, subtype="PCM_16")
    print(f"{OUT} : {len(stereo) / RATE:.1f} s")


if __name__ == "__main__":
    analyze() if sys.argv[1:] == ["analyze"] else main()
