<#
  Empaquete des mods comme Alpakit (Shipping, Win64) et les copie dans le jeu.
    -Targets : versions du jeu a compiler (FactoryGameEGS = Epic, FactoryGameSteam = Steam).
    -Release : archive de publication fusionnee, comme "Alpakit Release" (-merge) :
               <SmlProject>\Saved\ArchivedPlugins\<Mod>\<Mod>.zip, a televerser sur ficsit.app.
  Chemins : config.local.ps1. Journal : <SmlProject>\Saved\package-mod.log.

  Usage : powershell -ExecutionPolicy Bypass -File unreal\package-mod.ps1 -Mods AraVF -Targets FactoryGameEGS,FactoryGameSteam
#>
param(
  [Parameter(Mandatory)] [string[]]$Mods,
  [string[]]$Targets = @(),
  [switch]$Release
)
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'config.local.ps1')

# "powershell -File" transmet "A,B" comme une seule chaine : on la decoupe
$Mods    = @($Mods    | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$Targets = @($Targets | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
# noms concatenes dans une ligne de commande cmd.exe : identifiants simples seulement
foreach ($v in $Mods + $Targets) {
  if ($v -notmatch '^[A-Za-z0-9_]+$') { throw "nom de mod ou de cible invalide : $v" }
}

$proj = Join-Path $Config.SmlProject 'FactoryGame.uproject'
$uat  = Join-Path $Config.Engine 'Engine\Build\BatchFiles\RunUAT.bat'
$log  = Join-Path $Config.SmlProject 'Saved\package-mod.log'
$targetArgs = ($Targets | ForEach-Object { "-Target=$_" }) -join ' '

"=== debut : $(Get-Date) (cibles : $(if ($Targets) { $Targets -join ', ' } else { 'par defaut' })) ===" | Out-File $log -Encoding utf8
foreach ($mod in $Mods) {
  $start = Get-Date
  "=== $mod ===" | Out-File $log -Append -Encoding utf8
  $cmd = "`"$uat`" -ScriptsForProject=`"$proj`" PackagePlugin -project=`"$proj`" -clientconfig=Shipping -serverconfig=Shipping " +
         "-utf8output -DLCName=$mod -build -platform=Win64 -nocompileeditor -installed $targetArgs $(if ($Release) { '-merge ' })" +
         "-CopyToGameDirectory_Windows=`"$($Config.GameDir)`""
  cmd.exe /c "$cmd 2>&1" | Out-File $log -Append -Encoding utf8
  $code = $LASTEXITCODE
  "=== fin $mod : code $code, $([Math]::Round(((Get-Date) - $start).TotalMinutes, 1)) min ===" | Out-File $log -Append -Encoding utf8
  if ($code -ne 0) { exit $code }
}
