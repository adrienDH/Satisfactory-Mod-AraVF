<#
  Construit dans le projet Wwise le pack d'une langue, a partir de tts\voices\<langue>\plan.json :
  un son, un evenement Play_<Mod>_<Id> et UNE SoundBank <Mod>_<Id> par message (<Mod> : mod du pack,
  AraVF pour le francais, AraVF_ES pour l'espagnol...).

  Une banque par message, et non une banque commune : avec bPackageAsBulkData, la banque est
  embarquee en entier dans chaque evenement qui l'utilise.

  Reconstruit tout a chaque passage : les dossiers <Mod> (sons, evenements, banques) sont supprimes
  puis recrees. Le dossier commun AraVF_Targets (cibles des actions de l'intro) est conserve.

  Prerequis : serveur WAAPI lance sur le projet (WwiseConsole waapi-server <projet> --allow-migration).
  Usage : powershell -ExecutionPolicy Bypass -File wwise\setup-pack.ps1 -Lang fr
#>
param(
  [string]$Lang = 'fr',
  [string]$Waapi = 'http://127.0.0.1:8090/waapi',
  [string]$Conversion = '\Conversion Settings\Factory Conversion Settings\Vorbis\Vorbis Quality Medium'
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
$doc  = Get-Content (Join-Path $Root "tts\voices\$Lang\plan.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$plan = @($doc.messages)
$ModRef = $doc.mod
Write-Host "langue $Lang, mod $ModRef : $($plan.Count) messages"

$SoundRoot = '\Containers\Default Work Unit'
$EventRoot = '\Events\Default Work Unit'
$BankRoot  = '\SoundBanks\Default Work Unit'
$BusRoot   = '\Busses\Default Work Unit'
# Noms des bus du jeu (empreintes retrouvees dans son Init.bnk, voir find-vanilla-bus.ps1)
$BusPaths = [ordered]@{
  'main_ada_vo'  = "$BusRoot\Master Audio Bus\main_ada_vo"
  'vo_barks'     = "$BusRoot\Master Audio Bus\main_ada_vo\vo_barks"
  'vo_pelevator' = "$BusRoot\Master Audio Bus\main_ada_vo\vo_pelevator"
  'cinematic'    = "$BusRoot\Master Audio Bus\cinematic"
}
# Sons de la cinematique d'intro du jeu, vises par nos actions : des sons de substitution du projet,
# dont patch-action-targets.ps1 remplace l'identifiant par celui du jeu dans les actions (seulement).
# 631471445 = piste voix anglaise + ambiance, 267239500 = piste effets (lus dans Play_Cinematic_DropPod.bnk)
$GameTargets = [ordered]@{ 'aravf_target_intro_voice' = 631471445; 'aravf_target_intro_fx' = 267239500 }
$TargetRoot = "$SoundRoot\AraVF_Targets"
$TargetIdsFile = Join-Path $Root 'wwise\action-targets.json'
$ResetId = 'Cine_Reset'   # voir unreal/create_event_assets.py

function Invoke-Waapi([string]$uri, $arguments, $options = @{}) {
  $body = @{ uri = $uri; args = $arguments; options = $options } | ConvertTo-Json -Depth 12 -Compress
  try {
    Invoke-RestMethod -Uri $Waapi -Method Post -Body ([Text.Encoding]::UTF8.GetBytes($body)) -ContentType 'application/json; charset=utf-8'
  } catch { throw "WAAPI $uri : $($_.ErrorDetails.Message)" }
}
function Test-WwiseObject([string]$path) {
  try { return [bool](Invoke-Waapi 'ak.wwise.core.object.get' @{ from = @{ path = @($path) } } @{ return = @('id') }).return } catch { return $false }
}
function New-WwiseObject([string]$parent, [string]$type, [string]$name) {
  $null = Invoke-Waapi 'ak.wwise.core.object.create' @{ parent = $parent; type = $type; name = $name; onNameConflict = 'merge' }
}

# 0. Bus aux noms du jeu
if (Test-WwiseObject "$BusRoot\Main Audio Bus") {
  $null = Invoke-Waapi 'ak.wwise.core.object.setName' @{ object = "$BusRoot\Main Audio Bus"; value = 'Master Audio Bus' }
  Write-Host "  bus principal renomme : Main Audio Bus -> Master Audio Bus"
}
foreach ($b in $BusPaths.Values) {
  New-WwiseObject (Split-Path $b -Parent) 'Bus' (Split-Path $b -Leaf)
}

# 1. Nettoyage
foreach ($p in "$SoundRoot\$ModRef", "$EventRoot\$ModRef", "$BankRoot\$ModRef") {
  if (Test-WwiseObject $p) { $null = Invoke-Waapi 'ak.wwise.core.object.delete' @{ object = $p }; Write-Host "  supprime : $p" }
}

# 2. Import des sons, par lots, puis bus de sortie et compression
$sw = [Diagnostics.Stopwatch]::StartNew()
$batch = 100
$sounds = @($plan | ForEach-Object { [pscustomobject]@{ id = $_.id; wav = $_.wav; bus = $_.bus } })
# sons supplementaires (ambiance de l'intro) : joues par l'evenement en plus de la voix
$sounds += @($plan | ForEach-Object { $_.extras } | Where-Object { $_ })
foreach ($s in $sounds) { if (-not $BusPaths.Contains($s.bus)) { throw "bus inconnu pour $($s.id) : $($s.bus)" } }
for ($i = 0; $i -lt $sounds.Count; $i += $batch) {
  $slice = $sounds[$i..([Math]::Min($i + $batch, $sounds.Count) - 1)]
  # originalsSubFolder : copies des wav dans Originals\SFX\<Mod>\, sinon deux langues aux fichiers de meme nom s'ecrasent
  $imports = @($slice | ForEach-Object { @{ audioFile = $_.wav; originalsSubFolder = $ModRef
                                            objectPath = "$SoundRoot\<Folder>$ModRef\<Sound>${ModRef}_$($_.id)" } })
  $null = Invoke-Waapi 'ak.wwise.core.audio.import' @{ importOperation = 'replaceExisting'; default = @{ importLanguage = 'SFX' }; imports = $imports }
  $objects = @($slice | ForEach-Object { @{ object = "$SoundRoot\$ModRef\${ModRef}_$($_.id)"; '@OutputBus' = $BusPaths[$_.bus]; '@Conversion' = $Conversion } })
  $null = Invoke-Waapi 'ak.wwise.core.object.set' @{ objects = $objects }
}
Write-Host ("  {0} sons importes, bus et compression Vorbis appliques ({1:N0} s)" -f $sounds.Count, $sw.Elapsed.TotalSeconds)

# 3. Sons de substitution (cibles des actions de l'intro), communs a tous les packs : identifiants stables
New-WwiseObject $SoundRoot 'Folder' 'AraVF_Targets'
$ids = [ordered]@{}
foreach ($t in $GameTargets.Keys) {
  New-WwiseObject $TargetRoot 'Sound' $t
  $sid = (Invoke-Waapi 'ak.wwise.core.object.get' @{ from = @{ path = @("$TargetRoot\$t") } } @{ return = @('shortId') }).return[0].shortId
  $ids["$sid"] = $GameTargets[$t]
}
$ids | ConvertTo-Json | Set-Content -Encoding ascii $TargetIdsFile
Write-Host "  cibles de substitution : $(($ids.Keys | ForEach-Object { "$_ -> $($ids[$_])" }) -join ', ')"

# 4. Evenements Play
function New-IntroAction([string]$name, [int]$type, [string]$target, [double]$delay, [double]$fade, $volume = $null) {
  # Portee globale (@Scope = 1) : sinon l'action ne viserait que l'objet de jeu de la voix du pack.
  $a = @{ type = 'Action'; name = $name; '@ActionType' = $type; '@Scope' = 1; '@Target' = "$TargetRoot\$target"
          '@Delay' = $delay; '@FadeTime' = $fade }
  if ($null -ne $volume) { $a['@Volume'] = [double]$volume }
  return $a
}
for ($i = 0; $i -lt $plan.Count; $i += $batch) {
  $children = @($plan[$i..([Math]::Min($i + $batch, $plan.Count) - 1)] | ForEach-Object {
    $actions = @(@{ type = 'Action'; name = ''; '@ActionType' = 1; '@Target' = "$SoundRoot\$ModRef\${ModRef}_$($_.id)" })
    foreach ($x in @($_.extras | Where-Object { $_ })) {
      $actions += @{ type = 'Action'; name = "Play_$($x.id)"; '@ActionType' = 1; '@Target' = "$SoundRoot\$ModRef\${ModRef}_$($x.id)" }
    }
    # intro : piste anglaise du jeu muette (Set Voice Volume, et non Stop : un arret terminerait l'evenement
    # du jeu, et le mod couperait alors la voix du pack), piste d'effets baissee pendant chaque replique
    if ($_.mute_db) {
      $actions += New-IntroAction 'MuteEnglish' 12 'aravf_target_intro_voice' 0 0.05 $_.mute_db
      $actions += New-IntroAction 'UnmuteEnglish' 16 'aravf_target_intro_voice' ([double]$_.vanilla_duration) 0.5
    }
    $n = 0
    foreach ($w in $_.fx_duck) {
      $n++
      $actions += New-IntroAction ('FxDuck_{0:D2}' -f $n) 12 'aravf_target_intro_fx' ([Math]::Max(0, [double]$w[0] - 0.15)) 0.2 $_.fx_duck_db
      $actions += New-IntroAction ('FxRestore_{0:D2}' -f $n) 16 'aravf_target_intro_fx' ([double]$w[1] + 0.1) 0.5
    }
    @{ type = 'Event'; name = "Play_${ModRef}_$($_.id)"; children = $actions }
  })
  $null = Invoke-Waapi 'ak.wwise.core.object.create' @{ parent = $EventRoot; type = 'Folder'; name = $ModRef; onNameConflict = 'merge'; children = $children }
}
# remise a niveau des pistes de l'intro (intro passee ou interrompue), jouee par le mod a la fin de la cinematique
$hasIntro = [bool]@($plan | Where-Object { $_.trigger }).Count
if ($hasIntro) {
  $null = Invoke-Waapi 'ak.wwise.core.object.create' @{ parent = "$EventRoot\$ModRef"; type = 'Event'; name = "Play_${ModRef}_$ResetId"; onNameConflict = 'replace'
    children = @((New-IntroAction 'FxRestore' 16 'aravf_target_intro_fx' 0 0.5), (New-IntroAction 'UnmuteEnglish' 16 'aravf_target_intro_voice' 0 0.5)) }
}
Write-Host "  $($plan.Count + [int]$hasIntro) evenements crees"

# 5. Une SoundBank par evenement
$events = @($plan | ForEach-Object { $_.id }) + @(if ($hasIntro) { $ResetId })
$banks = @($events | ForEach-Object { @{ type = 'SoundBank'; name = "${ModRef}_$_" } })
$null = Invoke-Waapi 'ak.wwise.core.object.create' @{ parent = $BankRoot; type = 'Folder'; name = $ModRef; onNameConflict = 'merge'; children = $banks }
foreach ($id in $events) {
  $null = Invoke-Waapi 'ak.wwise.core.soundbank.setInclusions' @{
    soundbank = "$BankRoot\$ModRef\${ModRef}_$id"; operation = 'add'
    inclusions = @(@{ object = "$EventRoot\$ModRef\Play_${ModRef}_$id"; filter = @('events', 'structures', 'media') })
  }
}
Write-Host "  $($events.Count) SoundBanks creees"

$null = Invoke-Waapi 'ak.wwise.core.project.save' @{}
Write-Host ("Projet sauvegarde ({0:N0} s au total)" -f $sw.Elapsed.TotalSeconds)
