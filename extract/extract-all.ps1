<#
  Extrait du jeu installe tout ce dont le pipeline a besoin (rien de tout cela n'est publie) :
    corpus/ada_corpus.tsv     textes de l'IA en anglais et dans chaque langue demandee
    raw/narrative/            assets des messages (MSG_*), pour leurs sous-titres et interlocuteurs
    corpus/messages.tsv       un message par ligne : asset, evenement audio, interlocuteurs
    raw/bnk/Init.bnk          banque d'initialisation du jeu (bus, identifiant de projet)
    raw/vanilla-bus.txt       bus de sortie de la voix de chaque message
  Prerequis : config.local.ps1 (GameDir) et extract/oo2core_9_win64.dll (voir README).

  Usage : powershell -ExecutionPolicy Bypass -File extract\extract-all.ps1 -Languages fr,es-ES
          (cultures disponibles : extract\build-corpus.ps1 -ListCultures)
#>
param([string[]]$Languages = @('fr'))
$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
. (Join-Path $Root 'config.local.ps1')
$Languages = @($Languages | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
function Run([string]$script, [hashtable]$arguments) {
  Write-Host "=== $script"
  & (Join-Path $PSScriptRoot $script) @arguments
}

Run 'build-corpus.ps1' @{ GameDir = $Config.GameDir; Languages = $Languages }
Run 'iostore-extract.ps1' @{ GameDir = $Config.GameDir; Prefix = 'FactoryGame/Content/FactoryGame/Narrative'
                             Filter = 'MSG_*.uasset'; OutDir = (Join-Path $Root 'raw\narrative') }
Run 'analyze-messages.ps1' @{ GameDir = $Config.GameDir }
Run 'pak-extract.ps1' @{ GameDir = $Config.GameDir; Files = @('FactoryGame/Content/WwiseAudio/Init.bnk'); OutDir = (Join-Path $Root 'raw\bnk') }

# bus des voix : banques des evenements des messages, puis bus qu'elles referencent dans l'Init du jeu
$messages = Import-Csv (Join-Path $Root 'corpus\messages.tsv') -Delimiter "`t"
$banks = @($messages | Where-Object { $_.bank } | ForEach-Object { $_.bank } | Sort-Object -Unique)
$voDir = Join-Path $Root 'raw\bnk\vo'
Run 'pak-extract.ps1' @{ GameDir = $Config.GameDir; Files = $banks; OutDir = $voDir }
Write-Host "=== bus des voix"
$files = @(Get-ChildItem $voDir -Filter *.bnk | ForEach-Object { $_.FullName })
& (Join-Path $Root 'wwise\find-vanilla-bus.ps1') -Banks $files | Set-Content -Encoding utf8 (Join-Path $Root 'raw\vanilla-bus.txt')
Write-Host "raw\vanilla-bus.txt : $($files.Count) banques"
