# Creating a language pack

A language pack gives the FICSIT AI a voice in one more language. It is a small Satisfactory mod **without code**
that depends on the base mod **AraVF**: players install AraVF plus the packs they want, and each pack adds its
language to *Options > Audio > FICSIT AI Language*.

The text comes from the game's **official translation** of that language: the pack only adds a voice. The voice is
synthesized locally with [Kokoro](https://huggingface.co/hexgrad/Kokoro-82M), then processed to sound like the FICSIT AI.

Example used below: Spanish (`es`, mod `AraVF_ES`). Commands are PowerShell, run from the repository root.

## Before you start

- Complete the **Building** setup of the [README](../README.md): modding environment, Wwise, `config.local.ps1`,
  junction of `mod/AraVF`, editor build, `create_settings.py`, intro ambience.
- **Kokoro must speak the language.** Supported languages: English, Spanish, French, Hindi, Italian, Japanese,
  Brazilian Portuguese, Chinese. For any other language you need another voice engine **whose license allows
  redistribution**. It plugs in where `tts/pipeline.py` calls `kokoro_voice.synth(speech, out)`.
- **About 1 h of work** for a supported language. Synthesis takes about 30 min on a recent CPU, and building takes about 10 min.

## 1. Extract the game texts

```powershell
powershell -ExecutionPolicy Bypass -File extract\build-corpus.ps1 -ListCultures     # cultures in the game
powershell -ExecutionPolicy Bypass -File extract\extract-all.ps1 -Languages fr,es-ES
```

Keep `fr` in the list: the French base pack uses the same corpus. The column for `es-ES` is `text_es`.
Everything lands in `corpus/` and `raw/`, which are **never published**.

## 2. Declare the language

Add an entry to `LANGUAGES` in [`tts/languages.py`](../tts/languages.py):

```python
"es": {
    "mod": "AraVF_ES",            # mod reference of the pack
    "name": "Español",            # shown in the option, written in the language itself
    "column": "text_es",          # corpus column
    "rules": [(r"FICSMAS", "Ficsmas"), (r"FICSIT", "Ficsit")] + COMMON,   # subtitle -> spoken text
    "kokoro_lang": "e",           # Kokoro language code
    "voice": "ef_dora",           # Kokoro voice (female, like ADA)
    "speed": 0.94,
    "tts_rules": [                # spellings that fix Kokoro's pronunciation
        (r"\bFicsit\b", "Fícsit"),
        (r"\bMAM\b", "Mam"),
        (r"\b(HUB|Hub)\b", "Jab"),
    ],
    "pitch_file": "kokoro_pitch_es.json",
    "alien_voice": "ef_dora",     # voice used, with a choir effect, for the aliens
},
```

- **`rules`** change what the voice says, not the subtitles. Use them for acronyms and spelling, and if you
  want, for grammatical gender: the French pack addresses the player in the masculine everywhere.
- **`tts_rules`** are spelling tricks for one engine. Examples: an English word pronounced the local way, or an
  acronym spelled out letter by letter.

## 3. Check the pronunciation

```powershell
$env:ARAVF_LANG = "es"
$kokoro = @("--python", "3.12", "--with", "kokoro>=0.9.4", "--with", "transformers>=4.44", "--with", "soundfile")
uv run @kokoro python tts/kokoro_voice.py phonemes "Bienvenido a FICSIT, analízalo en el MAM y construye el HUB."
```

Check how these words come out: `FICSIT`, `FICSMAS`, `M.A.M.`, `HUB`, `A.W.E.S.O.M.E.`, the AI's name in your
language, and any English words the translation keeps. Adjust `tts_rules` until the phonemes sound right.

## 4. Generate the voices

```powershell
uv run @kokoro python tts/kokoro_voice.py calibrate 200   # pitch: 200 Hz, same as the other packs
uv run python tts/pipeline.py prepare                     # dubbing plan: tts/voices/es/plan.json
uv run @kokoro python tts/pipeline.py synth               # one voice per subtitle; resumes if interrupted
```

Then read the `skipped` section of `tts/voices/es/plan.json`. It lists the messages that won't be dubbed and why.
Three messages without subtitles are expected. Listen to a few files in `tts/voices/es/lines/` before going further.

## 5. Create the pack mod

1. Copy `packs/AraVF_ES` to `packs/AraVF_XX` (keep only `AraVF_ES.uplugin` and `Resources/`), and rename the
   `.uplugin` to `AraVF_XX.uplugin`.
2. Edit it: `FriendlyName`, `Description`, `CreatedBy`, version `1.0.0`. Keep the dependencies on `SML` and
   `AraVF` (`^2.0.0`), and `RequiredOnRemote: false`.
3. Make it visible to the SML project:
   ```powershell
   New-Item -ItemType Junction -Path <SmlProject>\Mods\AraVF_XX -Target <repo>\packs\AraVF_XX
   ```

The mod name must be the `mod` value declared in step 2.

## 6. Build and install

Close the game and the Unreal editor, then:

```powershell
powershell -ExecutionPolicy Bypass -File build-mod.ps1 -Lang es
```

In about 10 minutes, the script:
1. imports the voices into Wwise;
2. generates one SoundBank per message and patches them for the game;
3. creates the `AkAudioEvent` assets and the `AraVFVoicePack` asset;
4. packages the mod and copies it into the game.

Each step is checked: an error stops the build and tells you why.

## 7. Test in game

- *Options > Audio > FICSIT AI Language* lists your language. Select it.
- Trigger a message (for example, build something, or buy a milestone), and start a new game to hear the intro.
- The game log (`%LOCALAPPDATA%\FactoryGame\Saved\Logs\FactoryGame.log`) has a line like
  `LogAraVF: Display: Pack es (mod AraVF_ES) : 630 message(s) utilisable(s) sur 630`.

## 8. Publish on ficsit.app

```powershell
powershell -ExecutionPolicy Bypass -File unreal\package-mod.ps1 -Mods AraVF_XX -Targets FactoryGameEGS,FactoryGameSteam -Release
```

1. Upload `<SmlProject>\Saved\ArchivedPlugins\AraVF_XX\AraVF_XX.zip` as a new version. Remove the `.pdb`
   files first: players don't need them.
2. **Mod reference**: the mod name. It can't be changed after creation.
3. **Description**: say it is a language pack for *FICSIT AI Voices (FR + packs)* (AraVF), and credit the voice:
   - Kokoro-82M by hexgrad, Apache 2.0;
   - the voice data license of your Kokoro voice, listed in Kokoro's
     [VOICES.md](https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md).
4. **Generative AI transparency**: *Generative AI was used in this mod's creation* (synthesized voices).
5. **Network activity**: *Does not contact external networks*.

## How a pack works

A pack mod contains:

| Asset | Role |
|---|---|
| `/<Mod>/AraVFVoicePack` | `UAraVFVoicePack`: language code and name, message → voice event → subtitle timestamps, cinematic voices |
| `/<Mod>/Audio/Play_<Mod>_*` | one Wwise event (and SoundBank) per message, plus the intro ambience and reset events |

- **Option value**: derived from the language code, so a player's choice survives updates. If a player uninstalls
  the pack for the selected language, the AI falls back to the original English voice.
- **Subtitles**: a message whose subtitle count differs from the game's is ignored by the pack and keeps the
  original voice. This can happen after a game update; rebuilding the pack fixes it.
- **Game files**: packs reference game assets by path only. They contain no game text, sound or asset, only
  synthesized voices.
