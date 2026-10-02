# Local paths used by the build scripts.
# Copy this file to config.local.ps1 (ignored by git) and adapt the paths to your machine.
$Config = @{
  # SML starter project (https://docs.ficsit.app/satisfactory-modding/latest/Development/BeginnersGuide/project_setup.html)
  SmlProject   = 'C:\Modding\SatisfactoryModLoader'
  # Unreal Engine CSS (Coffee Stain's fork, installed from github.com/satisfactorymodding/UnrealEngine)
  Engine       = 'C:\Program Files\Unreal Engine - CSS'
  # Wwise authoring console, same version as the game's Wwise (see README)
  WwiseConsole = 'C:\Audiokinetic\Wwise_2025.1.6.9117\Authoring\x64\Release\bin\WwiseConsole.exe'
  # Satisfactory installation: the mod is copied there after packaging; the extraction scripts read it
  GameDir      = 'C:\Program Files\Epic Games\SatisfactoryEarlyAccess'
}
