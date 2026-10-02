<#
  Reconstruit le pack d'une langue de bout en bout, a partir des voix deja generees (tts\voices\<langue>).
  Le francais est dans le mod de base AraVF ; les autres langues sont des mods de contenu (AraVF_ES...).

  Etapes : assemblage (horaires) -> Wwise (sons, evenements, une banque par message, via WAAPI) ->
  generation des banques -> identifiant de projet du jeu et cibles des actions -> verification des
  dependances -> assets Unreal (evenements et pack de langue) -> empaquetage et copie dans le jeu.

  Usage : powershell -ExecutionPolicy Bypass -File build-mod.ps1 [-Lang es]
  Prerequis : config.local.ps1 (modele : config.example.ps1) ; jeu et editeur Unreal fermes ;
  voix generees (tts\pipeline.py prepare puis synth) ; licence Wwise couvrant plus de 200 sons.
#>
param([ValidatePattern('^[a-z]{2,3}$')][string]$Lang = 'fr')
$ErrorActionPreference = 'Stop'
$Repo    = $PSScriptRoot
$configFile = Join-Path $Repo 'config.local.ps1'
if (-not (Test-Path $configFile)) { throw "config.local.ps1 absent : copier config.example.ps1 et l'adapter" }
. $configFile
$Project = $Config.SmlProject
$Wproj   = "$Project\SatisfactoryModLoader_WwiseProject\SatisfactoryModLoader_WwiseProject.wproj"
$Banks   = "$Project\SatisfactoryModLoader_WwiseProject\GeneratedSoundBanks\Windows"
$Console = $Config.WwiseConsole
$Editor  = Join-Path $Config.Engine 'Engine\Binaries\Win64\UnrealEditor-Cmd.exe'
$env:ARAVF_SML_PROJECT = $Project   # lu par unreal/create_event_assets.py
$Waapi   = 'http://127.0.0.1:8090/waapi'
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')

function Step([string]$title) { Write-Host ""; Write-Host "=== $title ===" }
function Check([string]$what) { if ($LASTEXITCODE -ne 0) { throw "$what a echoue (code $LASTEXITCODE)" } }
# Lance un script ; n'affiche que les lignes qui correspondent a $Show (toutes si vide) ; s'arrete en cas d'echec.
function Invoke-Script([string]$path, [string[]]$arguments = @(), [string]$Show = '') {
  $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $path @arguments 2>&1
  $code = $LASTEXITCODE
  $out | Where-Object { -not $Show -or "$_" -match $Show } | ForEach-Object { "$_" }
  if ($code -ne 0) { $out | Select-Object -Last 10 | ForEach-Object { "$_" }; throw "$path a echoue (code $code)" }
}

if (Get-Process -Name 'FactoryGame*' -ErrorAction SilentlyContinue) { throw "le jeu est ouvert : ferme-le" }
if (Get-Process -Name 'UnrealEditor' -ErrorAction SilentlyContinue) { throw "l'editeur Unreal est ouvert : ferme-le" }
Set-Location $Repo
$env:ARAVF_LANG = $Lang
$Mod = (Get-Content "tts/voices/$Lang/plan.json" -Raw -Encoding UTF8 | ConvertFrom-Json).mod
Write-Host "langue $Lang -> mod $Mod"

Step "Assemblage"
uv run python tts/pipeline.py assemble; Check "l'assemblage"

Step "Wwise : sons, evenements, banques"
Stop-Process -Name WwiseConsole -Force -ErrorAction SilentlyContinue
$server = Start-Process -FilePath $Console -ArgumentList "waapi-server `"$Wproj`" --allow-migration" -PassThru -WindowStyle Hidden
try {
  $ok = $false
  for ($i = 0; $i -lt 30 -and -not $ok; $i++) {
    Start-Sleep -Seconds 2
    try { $null = Invoke-RestMethod -Uri $Waapi -Method Post -Body '{"uri":"ak.wwise.core.getInfo","args":{},"options":{}}' -ContentType 'application/json'; $ok = $true } catch {}
  }
  if (-not $ok) { throw "le serveur WAAPI ne repond pas" }
  Invoke-Script wwise/setup-pack.ps1 @('-Lang', $Lang, '-Waapi', $Waapi)
} finally { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2 }

Step "Generation des banques"
$gen = & $Console generate-soundbank $Wproj --platform Windows 2>&1   # le jeu n'existe que sur Windows
$gen | Select-String -Pattern 'Fatal|Error|completed|MediaDuplicated' | ForEach-Object { $_.Line }
# code 2 = termine avec avertissements ; un doublon de media signale deux packs qui partagent un fichier
if ($gen -match 'Fatal Error' -or -not ($gen -match 'Process completed')) { throw "generation des banques en erreur (licence Wwise ?)" }
if ($gen -match 'MediaDuplicated') { throw "media partage entre deux SoundBanks (voir ci-dessus)" }

Step "Identifiant de projet, cibles des actions, dependances"
Invoke-Script wwise/patch-project-id.ps1 @('-Banks', $Banks) -Show 'Init.bnk du jeu'
Invoke-Script wwise/patch-action-targets.ps1 @('-Banks', $Banks)
Invoke-Script wwise/check-bank-deps.ps1 @('-Banks', $Banks) -Show 'ECHEC|OK :'

Step "Assets Unreal : evenements et pack de langue"
$result = "tts/voices/$Lang/unreal-result.json"   # bilan ecrit par le script (ses logs ne sortent pas en console)
Remove-Item $result -ErrorAction SilentlyContinue
$log = & $Editor "$Project\FactoryGame.uproject" -run=pythonscript "-script=$Repo\unreal\create_event_assets.py" -unattended -nosplash -nop4 -stdout 2>&1
if (-not (Test-Path $result)) {
  $log | Select-String -Pattern 'Error|Traceback' | Select-Object -Last 15 | ForEach-Object { $_.Line }
  throw "creation des assets Unreal en erreur"
}
$r = Get-Content $result -Raw | ConvertFrom-Json
Write-Host "  $($r.pack) : $($r.messages) messages, $($r.swaps + $r.triggers) voix de cinematique ; evenements : $($r.events_created) cree(s), $($r.events_removed) supprime(s), $($r.events_failed) echec(s)"
if ($r.events_failed -gt 0) { throw "evenements Unreal non crees : $($r.events_failed)" }

Step "Empaquetage"
& powershell -NoProfile -ExecutionPolicy Bypass -File unreal/package-mod.ps1 -Mods $Mod -Targets FactoryGameEGS,FactoryGameSteam
$packageLog = "$Project\Saved\package-mod.log"
$result = Get-Content $packageLog -Encoding utf8 | Select-String -Pattern 'BUILD SUCCESSFUL|BUILD FAILED|=== fin'
$result | ForEach-Object { $_.Line }
if (-not ($result -match 'BUILD SUCCESSFUL') -or ($result -match 'BUILD FAILED')) { throw "empaquetage en erreur (voir $packageLog)" }
