"""Langues du doublage : une entree par pack de langue.

La langue de travail se choisit avec la variable d'environnement ARAVF_LANG (fr par defaut) :
  $env:ARAVF_LANG = "es"; uv run python tts/pipeline.py prepare

Ajouter une langue : une entree ici, son texte dans le corpus (extract/build-corpus.ps1 -Languages ...),
un mod de contenu pour son pack (voir docs/AJOUTER-UNE-LANGUE.md).
"""
import os
import re

# Adaptations communes : sigles lus comme des mots, guillemets et retours a la ligne retires
COMMON = [
    (r"M\.A\.M\.", "MAM"),
    (r"H\.U\.B\.", "Hub"),
    (r"A\.W\.E\.S\.O\.M\.E\.", "Awesome"),
    (r'[«»"“”]', ""),
    (r"\\n", " "),
]

# Francais : la traduction officielle s'adresse au joueur au feminin dans une quinzaine de repliques
# (intro, tutoriel...) et au masculin partout ailleurs ; le doublage passe tout au masculin.
FR_MASCULIN = [
    (r"la troisième pionnière", "le troisième pionnier"),
    (r"ma pionnière la plus précieuse", "mon pionnier le plus précieux"),
    (r"\btoute pionnière", "tout pionnier"),
    (r"\bune pionnière FICSIT accomplie", "un pionnier FICSIT accompli"),
    (r"\bune pionnière", "un pionnier"),
    (r"PIONNIÈ+RE", "PIONNIÉÉÉÉÉÉÉÉÉÉÉ"),
    (r"([Pp])ionnière", r"\1ionnier"),
    (r"vous être prête", "vous êtes prêt"),
    (r"l'employée FICSIT", "l'employé FICSIT"),
]

LANGUAGES = {
    "fr": {
        "mod": "AraVF",                 # mod qui porte le pack (le francais est dans le mod de base)
        "name": "Français",             # nom dans l'option, dans la langue elle-meme
        "column": "text_fr",            # colonne du corpus
        # texte du doublage (sous-titre -> texte prononce), avant les specificites du moteur de voix
        "rules": FR_MASCULIN + [(r"FICSMAS", "Fixmas"), (r"FICSIT", "Fixit"), (r"I\.A\.\.", "I.A.")] + COMMON,
        # Kokoro : langue, voix, vitesse, et graphies verifiees sur ses phonemes
        "kokoro_lang": "f",
        "voice": "ff_siwis",
        "speed": 0.94,
        "tts_rules": [
            (r"\bARA\b", "Ara"),                          # sinon epele a-er-a
            (r"\bFixit\b", "Fixite"),                     # fiksit (et non fiksi)
            (r"\bFixmas\b", "Fixmasse"),                  # fiksmas
            (r"\b([Pp])ipeline", r"\1ailleplaillne"),     # pipeline a l'anglaise (pajplajn)
        ],
        "pitch_file": "kokoro_pitch.json",
        "alien_voice": "ff_siwis",
    },
    "es": {
        "mod": "AraVF_ES",
        "name": "Español",
        "column": "text_es",
        "rules": [(r"FICSMAS", "Ficsmas"), (r"FICSIT", "Ficsit")] + COMMON,
        "kokoro_lang": "e",
        "voice": "ef_dora",
        "speed": 0.94,
        "tts_rules": [
            (r"\bFicsit\b", "Fícsit"),                 # accent sur la 1re syllabe, comme en anglais
            (r"\bFicsmas\b", "Fícsmas"),
            (r"\bMAM\b", "Mam"),                       # sinon epele eme-a-eme
            (r"\b(HUB|Hub)\b", "Jab"),                 # prononciation des joueurs hispanophones
        ],
        "pitch_file": "kokoro_pitch_es.json",
        "alien_voice": "ef_dora",
    },
}

LANG = os.environ.get("ARAVF_LANG", "fr")
if LANG not in LANGUAGES:
    raise SystemExit(f"ARAVF_LANG={LANG} inconnue ; langues : {', '.join(LANGUAGES)}")
CURRENT = LANGUAGES[LANG]


def speakable(text):
    """Sous-titre -> texte prononce, selon les regles de la langue de travail."""
    for pat, rep in CURRENT["rules"]:
        text = re.sub(pat, rep, text)
    return re.sub(r"\s+", " ", text).strip()
