# Créer un pack de langue

*(English version: [CREATING-A-LANGUAGE-PACK.md](CREATING-A-LANGUAGE-PACK.md))*

Un pack de langue donne une voix à l'IA FICSIT dans une langue de plus. C'est un petit mod Satisfactory **sans
code** qui dépend du mod de base **AraVF**. Le joueur installe AraVF et les packs qu'il veut ; chaque pack ajoute sa
langue à *Options > Audio > Langue de l'IA FICSIT*.

Le texte vient de la **traduction officielle** du jeu dans cette langue : le pack n'ajoute que la voix. Elle est
synthétisée en local avec [Kokoro](https://huggingface.co/hexgrad/Kokoro-82M), puis traitée pour sonner comme l'IA FICSIT.

Exemple : l'espagnol (`es`, mod `AraVF_ES`). Les commandes sont en PowerShell, lancées à la racine du dépôt.

## Avant de commencer

- Faire l'installation décrite dans la section **Building** du [README](../README.md) : environnement de modding,
  Wwise, `config.local.ps1`, lien vers `mod/AraVF`, compilation de l'éditeur, `create_settings.py`, ambiance de l'intro.
- **Kokoro doit parler la langue** : anglais, espagnol, français, hindi, italien, japonais, portugais du Brésil,
  chinois. Sinon, il faut un autre moteur de voix **dont la licence autorise la diffusion**. Il se branche là où
  `tts/pipeline.py` appelle `kokoro_voice.synth(speech, out)`.
- **Environ 1 h** pour une langue gérée par Kokoro. La synthèse prend environ 30 min, la construction environ 10 min.

## 1. Extraire les textes du jeu

```powershell
powershell -ExecutionPolicy Bypass -File extract\build-corpus.ps1 -ListCultures     # langues du jeu
powershell -ExecutionPolicy Bypass -File extract\extract-all.ps1 -Languages fr,es-ES
```

Garder `fr` dans la liste : le pack français du mod de base utilise le même corpus. La colonne de `es-ES` est
`text_es`. Tout arrive dans `corpus/` et `raw/`, qui ne sont **jamais publiés**.

## 2. Déclarer la langue

Ajouter une entrée à `LANGUAGES` dans [`tts/languages.py`](../tts/languages.py). Voir l'entrée `es`, commentée :
- le mod du pack ;
- le nom affiché dans l'option, écrit dans la langue elle-même ;
- la colonne du corpus ;
- les règles de texte ;
- la langue et la voix Kokoro ;
- la voix des aliens.

- **`rules`** modifient ce que dit la voix, pas les sous-titres. On s'en sert pour les sigles et l'orthographe, et
  si on le souhaite pour le genre : le pack français s'adresse au joueur au masculin partout.
- **`tts_rules`** sont des graphies propres au moteur de voix. Exemples : un mot anglais prononcé à la manière
  locale, ou un sigle lu lettre par lettre.

## 3. Vérifier la prononciation

```powershell
$env:ARAVF_LANG = "es"
$kokoro = @("--python", "3.12", "--with", "kokoro>=0.9.4", "--with", "transformers>=4.44", "--with", "soundfile")
uv run @kokoro python tts/kokoro_voice.py phonemes "Bienvenido a FICSIT, analízalo en el MAM y construye el HUB."
```

Vérifier la prononciation de `FICSIT`, `FICSMAS`, `M.A.M.`, `HUB`, `A.W.E.S.O.M.E.`, du nom de l'IA dans la langue
et des mots anglais gardés par la traduction. Ajuster `tts_rules` jusqu'à ce que les phonèmes conviennent.

## 4. Générer les voix

```powershell
uv run @kokoro python tts/kokoro_voice.py calibrate 200   # hauteur : 200 Hz, comme les autres packs
uv run python tts/pipeline.py prepare                     # plan de doublage : tts/voices/es/plan.json
uv run @kokoro python tts/pipeline.py synth               # une voix par sous-titre ; reprend si interrompu
```

Relire ensuite la rubrique `skipped` de `tts/voices/es/plan.json`, qui liste les messages non doublés et pourquoi.
Trois messages sans sous-titre sont normaux. Écouter quelques fichiers de `tts/voices/es/lines/` avant de continuer.

## 5. Créer le mod du pack

1. Copier `packs/AraVF_ES` en `packs/AraVF_XX` (seulement `AraVF_ES.uplugin` et `Resources/`), et renommer le
   `.uplugin` en `AraVF_XX.uplugin`.
2. Le modifier : `FriendlyName`, `Description`, `CreatedBy`, version `1.0.0`. Garder les dépendances `SML` et
   `AraVF` (`^2.0.0`), et `RequiredOnRemote: false`.
3. Le rendre visible au projet SML :
   ```powershell
   New-Item -ItemType Junction -Path <SmlProject>\Mods\AraVF_XX -Target <depot>\packs\AraVF_XX
   ```

Le nom du mod doit être la valeur `mod` déclarée à l'étape 2.

## 6. Construire et installer

Jeu et éditeur Unreal fermés :

```powershell
powershell -ExecutionPolicy Bypass -File build-mod.ps1 -Lang es
```

En une dizaine de minutes, le script :
1. importe les voix dans Wwise ;
2. génère une SoundBank par message et les corrige pour le jeu ;
3. crée les assets `AkAudioEvent` et le pack `AraVFVoicePack` ;
4. empaquette le mod et le copie dans le jeu.

Chaque étape est vérifiée : une erreur arrête la construction et en donne la raison.

## 7. Tester en jeu

- *Options > Audio > Langue de l'IA FICSIT* propose la langue : la choisir.
- Déclencher un message (construire quelque chose, acheter un palier) et lancer une nouvelle partie pour l'intro.
- Le journal du jeu (`%LOCALAPPDATA%\FactoryGame\Saved\Logs\FactoryGame.log`) contient une ligne
  `LogAraVF: Display: Pack es (mod AraVF_ES) : 630 message(s) utilisable(s) sur 630`.

## 8. Publier sur ficsit.app

```powershell
powershell -ExecutionPolicy Bypass -File unreal\package-mod.ps1 -Mods AraVF_XX -Targets FactoryGameEGS,FactoryGameSteam -Release
```

1. Téléverser `<SmlProject>\Saved\ArchivedPlugins\AraVF_XX\AraVF_XX.zip` comme nouvelle version. Retirer d'abord
   les `.pdb`, inutiles aux joueurs.
2. **Mod reference** : le nom du mod. Elle n'est plus modifiable ensuite.
3. **Description** : préciser que c'est un pack de langue pour *FICSIT AI Voices (FR + packs)* (AraVF), et créditer
   la voix :
   - Kokoro-82M de hexgrad, Apache 2.0 ;
   - la licence des données de la voix Kokoro utilisée, indiquée dans son
     [VOICES.md](https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md).
4. **Generative AI Transparency** : *Generative AI was used in this mod's creation* (voix synthétisées).
5. **Network Activity** : *Does not contact external networks*.

## Fonctionnement d'un pack

| Asset | Rôle |
|---|---|
| `/<Mod>/AraVFVoicePack` | `UAraVFVoicePack` : code et nom de la langue, message → voix → horaires des sous-titres, voix des cinématiques |
| `/<Mod>/Audio/Play_<Mod>_*` | un évènement Wwise (et sa SoundBank) par message, plus l'ambiance de l'intro et l'évènement de remise à niveau |

- **Valeur de l'option** : elle est déduite du code de langue, donc stable d'une version à l'autre. Si le joueur
  désinstalle le pack de la langue choisie, l'IA reprend sa voix anglaise d'origine.
- **Sous-titres** : un message dont le nombre de sous-titres diffère de celui du jeu est ignoré par le pack et
  garde sa voix d'origine. Cela peut arriver après une mise à jour du jeu ; reconstruire le pack corrige.
- **Fichiers du jeu** : un pack ne fait que référencer les assets du jeu par leur chemin. Il ne contient aucun
  texte, son ou asset du jeu, seulement des voix synthétisées.
