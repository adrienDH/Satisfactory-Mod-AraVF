"""Cree les assets Unreal d'un pack de langue, a partir de son plan (tts/voices/<ARAVF_LANG>/plan.json) :

1. un AkAudioEvent par evenement Wwise du pack (Play_<Mod>_<Id>), dans /<Mod>/Audio, comme le menu
   Audiokinetic > Audiokinetic Event du Content Browser (la fabrique nomme l'objet Wwise comme l'asset) ;
   les assets Play_<Mod>_* qui ne correspondent plus a rien sont supprimes ;
2. le pack /<Mod>/AraVFVoicePack (UAraVFVoicePack) : langue, messages doubles avec leurs horaires,
   voix des cinematiques. Le mod de base AraVF le trouve au demarrage du jeu.

Lance par le commandlet (editeur ferme), avec ARAVF_LANG dans l'environnement :
  UnrealEditor-Cmd.exe <projet>.uproject -run=pythonscript -script="<ce fichier>" -unattended -nosplash
"""
import json
import os

import unreal

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LANG = os.environ.get("ARAVF_LANG", "fr")
MODS = os.path.join(os.environ["ARAVF_SML_PROJECT"], "Mods")   # pose par build-mod.ps1 (config.local.ps1)
RESET_ID = "Cine_Reset"   # voir wwise/setup-pack.ps1

with open(os.path.join(ROOT, "tts", "voices", LANG, "plan.json"), encoding="utf-8") as f:
    doc = json.load(f)
MOD = doc["mod"]
plan = doc["messages"]
mod_dir = next((d for d in (os.path.join(MODS, "GameFeatures", MOD), os.path.join(MODS, MOD)) if os.path.isdir(d)), None)
if mod_dir is None:
    raise RuntimeError(f"dossier du mod {MOD} introuvable dans {MODS} (voir docs/AJOUTER-UNE-LANGUE.md)")
CONTENT = os.path.join(mod_dir, "Content", "Audio")
DEST = f"/{MOD}/Audio"
PREFIX = f"Play_{MOD}_"


def event_path(ident):
    name = PREFIX + ident
    return f"{DEST}/{name}.{name}"


# ---------- 1. evenements ----------
events = {PREFIX + p["id"] for p in plan}
if any(p.get("trigger") for p in plan):
    events.add(PREFIX + RESET_ID)

# En commandlet, le registre des assets n'a pas indexe le contenu des plugins : sans ce scan,
# les suppressions echouent ("could not be found in the Asset Registry").
unreal.AssetRegistryHelpers.get_asset_registry().scan_paths_synchronous([f"/{MOD}"], True)
existing = {os.path.splitext(n)[0] for n in os.listdir(CONTENT) if n.endswith(".uasset")} if os.path.isdir(CONTENT) else set()

removed = 0
for name in sorted(existing - events):
    if name.startswith(PREFIX) and unreal.EditorAssetLibrary.delete_asset(f"{DEST}/{name}"):
        removed += 1

tools = unreal.AssetToolsHelpers.get_asset_tools()
created, failed = 0, 0
for name in sorted(events - existing):
    asset = tools.create_asset(name, DEST, unreal.AkAudioEvent, unreal.AkAudioEventFactory())
    if asset is None:
        unreal.log_error(f"AraVF : echec de creation de {DEST}/{name}")
        failed += 1
        continue
    unreal.EditorAssetLibrary.save_loaded_asset(asset, only_if_is_dirty=False)
    created += 1
unreal.log(f"AraVF : [{LANG}] {created} evenement(s) cree(s), {removed} supprime(s), "
           f"{len(events & existing)} conserve(s), {failed} echec(s)")

# ---------- 2. pack de langue ----------
PACK = f"/{MOD}/AraVFVoicePack"
if unreal.EditorAssetLibrary.does_asset_exist(PACK):
    pack = unreal.EditorAssetLibrary.load_asset(PACK)
else:
    factory = unreal.DataAssetFactory()
    factory.set_editor_property("data_asset_class", unreal.AraVFVoicePack)
    pack = tools.create_asset("AraVFVoicePack", f"/{MOD}", unreal.AraVFVoicePack, factory)
    if pack is None:
        raise RuntimeError(f"creation de {PACK} impossible")

messages, swaps, triggers = [], [], []
for p in plan:
    if not p.get("cine"):
        m = unreal.AraVFMessageVoice()
        m.set_editor_property("message", p["asset"])
        m.set_editor_property("event", event_path(p["id"]))
        m.set_editor_property("time_stamps", [float(t) for t in p["timestamps"]])
        messages.append(m)
    elif p.get("trigger"):
        t = unreal.AraVFCinematicTrigger()
        t.set_editor_property("game_event_name", p["trigger"])
        t.set_editor_property("event", event_path(p["id"]))
        t.set_editor_property("reset_event", event_path(RESET_ID))
        triggers.append(t)
    else:
        s = unreal.AraVFCinematicSwap()
        s.set_editor_property("game_event", p["vanilla_event"])
        s.set_editor_property("event", event_path(p["id"]))
        swaps.append(s)

pack.set_editor_property("language_code", LANG)
pack.set_editor_property("language_name", unreal.Text(doc["language_name"]))
pack.set_editor_property("messages", messages)
pack.set_editor_property("cinematic_swaps", swaps)
pack.set_editor_property("cinematic_triggers", triggers)
unreal.EditorAssetLibrary.save_loaded_asset(pack, only_if_is_dirty=False)
unreal.log(f"AraVF : [{LANG}] pack {PACK} : {len(messages)} message(s), {len(swaps)} voix de cinematique remplacee(s), "
           f"{len(triggers)} ajoutee(s)")

# Bilan lu par build-mod.ps1 (les messages unreal.log n'apparaissent pas dans la console du commandlet)
with open(os.path.join(ROOT, "tts", "voices", LANG, "unreal-result.json"), "w", encoding="utf-8") as f:
    json.dump({"pack": PACK, "messages": len(messages), "swaps": len(swaps), "triggers": len(triggers),
               "events_created": created, "events_removed": removed, "events_failed": failed}, f)
