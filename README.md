<p align="center"><img src="assets/icons/icon-L-bulles-onde-512.png" alt="FICSIT AI Voices logo" width="160"></p>

# FICSIT AI Voices (FR + packs)

A Satisfactory mod that gives the FICSIT AI (ADA) a voice in other languages than English, using the game's own
official translations — plus the tools to produce new language packs.

- **Base mod `AraVF`** — on ficsit.app as [FICSIT AI Voices (FR + packs)](https://ficsit.app/mod/AraVF):
  - the option *Options > Audio > FICSIT AI Language*;
  - voice replacement for the 630 ADA messages, the alien communications, the drop-pod intro and the
    launch cinematic;
  - the **French** voice.
- **Language packs**: one small content-only mod per language, depending on AraVF. Example: [`packs/AraVF_ES`](packs/AraVF_ES) (Spanish).
  **[How to create a language pack →](docs/CREATING-A-LANGUAGE-PACK.md)**

> Code comments and script messages are in French; the documentation is in English
> ([version française du guide](docs/AJOUTER-UNE-LANGUE.md)).

## How it works in game

- **Messages**: `UFGMessage::mAudioEvent` and the subtitle timestamps are replaced in memory with the selected
  pack's voice, and restored when *English* is selected. Changes apply immediately, even mid-game.
- **Launch cinematic**: the Wwise ID of each game event is swapped for the pack's voice event.
- **Intro**: one game track mixes ADA's English voice and the drop-pod ambience. When the cinematic starts, the
  pack plays its voice, mutes that track, ducks the sound-effects track during each line, and plays a
  **synthesized** drop-pod rumble. No game audio is redistributed.
- **Packs**: at startup AraVF looks for an asset `/<ModName>/AraVFVoicePack` (class `UAraVFVoicePack`) in every
  installed mod, and adds one entry per pack to the option. Packs contain no code.

## Repository layout

| Path | Content |
|---|---|
| `mod/AraVF/` | base mod: C++ (`Source/`), `.uplugin`, icon |
| `packs/AraVF_ES/` | Spanish pack (`.uplugin` and icon; its content is generated) |
| `extract/` | extraction of texts, message assets and Wwise banks from **your own** game install |
| `tts/` | dubbing pipeline: languages, Kokoro voice, alien voice, intro ambience |
| `wwise/` | builds a pack in the Wwise project (WAAPI) and patches the generated banks |
| `unreal/` | editor Python scripts (Wwise events, pack asset, option) and packaging |
| `build-mod.ps1` | one command from generated voices to an installed mod |

Nothing extracted from the game (texts, assets, sounds) and no generated voice is stored in this repository:
`corpus/`, `raw/` and `tts/voices/` are created locally and ignored by git.

## Building

Requirements:
- Windows, the [SML modding environment](https://docs.ficsit.app/satisfactory-modding/latest/Development/BeginnersGuide/dependencies.html)
  (Visual Studio 2022, Unreal Engine CSS, SML starter project);
- **Wwise** at the version the game uses — check the line `Loading Wwise SoundEngine` in
  `%LOCALAPPDATA%\FactoryGame\Saved\Logs\FactoryGame.log`. Build 502094 runs Wwise 2025.1.6, so use the SML
  `dev` branch with Wwise 2025.1.6.9117 and integration 2025.1.6.4248;
- a Wwise license that covers more than 200 sounds (the free non-commercial license does);
- [uv](https://docs.astral.sh/uv/) for Python and [ffmpeg](https://ffmpeg.org/) on the `PATH`;
- `oo2core_9_win64.dll` (Oodle) in `extract/`, taken from another Unreal game. It is not redistributed.

Setup:
1. Copy `config.example.ps1` to `config.local.ps1` and set your paths.
2. Make the mods visible to the SML project. Use directory junctions, or copy the folders:
   ```powershell
   New-Item -ItemType Junction -Path <SmlProject>\Mods\GameFeatures\AraVF -Target <repo>\mod\AraVF
   New-Item -ItemType Junction -Path <SmlProject>\Mods\AraVF_ES -Target <repo>\packs\AraVF_ES
   ```
3. Build the editor once (Development Editor, Win64).
4. Create the option asset and Game Feature data, once:
   ```powershell
   & "<Engine>\Engine\Binaries\Win64\UnrealEditor-Cmd.exe" <SmlProject>\FactoryGame.uproject -run=pythonscript -script="<repo>\unreal\create_settings.py" -unattended
   ```
5. Generate the intro ambience (shared by all packs) from the stored envelope:
   `uv run --with numpy --with soundfile --with scipy python tts/intro_ambience.py`

Then follow [the language pack guide](docs/CREATING-A-LANGUAGE-PACK.md) from step 1. For the French base mod,
use the language code `fr`.

## Wwise pitfalls (game build 502094)

| Symptom in game | Cause | Fix |
|---|---|---|
| subtitle but no sound, "Trying to open a nameless file" | game runs Wwise 2025.1.6 (docs still say 2023) | SML `dev` branch + Wwise 2025.1.6 |
| error 92 "Init bank not loaded" | bank project ID differs from the game's | `wwise/patch-project-id.ps1` |
| error 92 again | sound routed to a bus that doesn't exist in the game | game bus names (`main_ada_vo`, `vo_barks`…), checked by `check-bank-deps.ps1` |
| more than 200 sounds refused | trial license, and the Mac platform isn't covered | non-commercial license, `--platform Windows` |
| volume action has no effect | default scope is "Game Object" | `@Scope = 1` (global) |
| intro goes silent | `Stop` on the game event ends the cinematic | `Set Voice Volume` instead of `Stop` |
| two languages overwrite each other | same `.wav` file names in `Originals\SFX` | `originalsSubFolder` per mod |

## Voices and licenses

- **Kokoro-82M** by hexgrad, Apache 2.0. French voice `ff_siwis`, trained on the SIWIS French Speech
  Synthesis Database (CC BY). Spanish voice `ef_dora`. Credit the model and voice data on each pack's page.
- ADA herself is text-to-speech in the game (Google WaveNet `en-US-Wavenet-C`, according to the modding docs and
  Coffee Stain), so the packs use synthesized voices too. Declare it in the *AI usage* section on ficsit.app.

## License

Code and documentation: [MIT](LICENSE). Satisfactory and its content belong to Coffee Stain Studios.
