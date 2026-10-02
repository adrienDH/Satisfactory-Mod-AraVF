"""Outil ponctuel : cree l'option Options > Audio > Langue de l'IA FICSIT, et la Game Feature qui la declare au jeu.
Les assets produits sont deja dans le mod ; a relancer seulement pour les recreer.

- /AraVF/AraVF : asset FGGameFeatureData du mod (comme le cree Alpakit pour un mod Game Feature),
  qui demande au jeu de chercher des FGUserSetting dans /AraVF/Settings ;
- /AraVF/Settings/US_AraVF_VoiceLanguage : duplique le reglage du jeu Dialogue Volume, pour heriter
  de sa categorie (Audio > General), de son gestionnaire (menu Options) et de ShowInBuilds=PublicBuilds,
  puis devient un selecteur de langue. Sa liste est remplie au demarrage du jeu par le mod (un choix par
  pack de langue installe, puis English) : les choix poses ici ne servent que dans l'editeur.

Rejouable : les deux assets sont recrees a chaque passage.
Lance par le commandlet (editeur ferme) :
  UnrealEditor-Cmd.exe <projet>.uproject -run=pythonscript -script="<ce fichier>" -unattended -nosplash
"""
import unreal

STR_ID = "AraVF.VoiceLanguage"          # doit correspondre a UAraVFSubsystem::VoiceLanguageOption
SETTING = "/AraVF/Settings/US_AraVF_VoiceLanguage"
TEMPLATE = "/Game/FactoryGame/Settings/OptionsMenu/Audio/US_DialogueVolume"
FEATURE = "/AraVF/AraVF"

lib = unreal.EditorAssetLibrary
unreal.AssetRegistryHelpers.get_asset_registry().scan_paths_synchronous(
    ["/AraVF", "/Game/FactoryGame/Settings/OptionsMenu/Audio"], True)

for path in (SETTING, FEATURE):
    if lib.does_asset_exist(path):
        lib.delete_asset(path)

# ---------- reglage ----------
setting = lib.duplicate_asset(TEMPLATE, SETTING)
if setting is None:
    raise RuntimeError(f"duplication de {TEMPLATE} impossible")
setting.set_editor_property("str_id", STR_ID)
# Textes anglais par defaut : le mod les remplace au demarrage par ceux de la langue du jeu
# (table Source/AraVF/Private/AraVFSettingTexts.inl).
setting.set_editor_property("display_name", unreal.Text("FICSIT AI Language"))
setting.set_editor_property("tool_tip", unreal.Text(
    "Voice of the FICSIT AI: original English or an installed language pack."))

selector = unreal.new_object(unreal.FGUserSetting_IntSelector, outer=setting)
choices = []
for label, value in (("Français", 0), ("English", 1)):
    choice = unreal.IntegerSelection()
    choice.set_editor_property("name", unreal.Text(label))
    choice.set_editor_property("value", value)
    choices.append(choice)
selector.set_editor_property("integer_selection_values", choices)
selector.set_editor_property("default_value", 0)
setting.set_editor_property("value_selector", selector)

# Emplacement (Audio > General) et priorite d'affichage herites tels quels du volume des dialogues :
# Python refuse de modifier MenuPriority (EditDefaultsOnly) dans la structure FSettingsWidgetLocationDescriptor.
widgets = setting.get_editor_property("widgets_to_create")
lib.save_loaded_asset(setting, only_if_is_dirty=False)
unreal.log(f"AraVF : reglage {SETTING} cree ({STR_ID}), {len(widgets)} emplacement(s) dans les options")

# ---------- Game Feature ----------
factory = unreal.DataAssetFactory()
factory.set_editor_property("data_asset_class", unreal.FGGameFeatureData)
feature = unreal.AssetToolsHelpers.get_asset_tools().create_asset("AraVF", "/AraVF", unreal.FGGameFeatureData, factory)
if feature is None:
    raise RuntimeError("creation de la Game Feature impossible")
rule = unreal.PrimaryAssetTypeInfo()
rule.set_editor_property("primary_asset_type", "FGUserSetting")
rule.set_editor_property("asset_base_class", unreal.SystemLibrary.conv_soft_class_path_to_soft_class_ref(
    unreal.SoftClassPath("/Script/FactoryGame.FGUserSetting")))
directory = unreal.DirectoryPath()
directory.set_editor_property("path", "/AraVF/Settings")
rule.set_editor_property("directories", [directory])
rules = unreal.PrimaryAssetRules()
rules.set_editor_property("priority", 2)
rules.set_editor_property("chunk_id", 1)
rule.set_editor_property("rules", rules)
feature.set_editor_property("primary_asset_types_to_scan", [rule])
lib.save_loaded_asset(feature, only_if_is_dirty=False)
unreal.log(f"AraVF : Game Feature {FEATURE} creee (FGUserSetting dans /AraVF/Settings)")
