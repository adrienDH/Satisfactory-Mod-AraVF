<#
  Aligne l'identifiant de projet des SoundBanks du mod sur celui du jeu.

  Pourquoi : depuis Wwise 2025, le moteur audio refuse une banque dont l'identifiant de projet
  (champ BKHD, octet 0x18) differe de celui de la banque d'initialisation chargee, avec l'erreur
  92 "The Init bank was not loaded yet". Les banques du jeu portent l'identifiant du projet
  Wwise de Coffee Stain ; celles d'un projet sans licence portent 0.

  L'identifiant de reference est lu dans l'Init.bnk du jeu (extrait avec pak-extract.ps1).
  A lancer apres chaque generation des SoundBanks, avant l'empaquetage.

  Usage : powershell -ExecutionPolicy Bypass -File wwise\patch-project-id.ps1
  Compatible Windows PowerShell 5.1.
#>
param(
  [string]$Banks    = '',
  [string]$Pattern  = 'AraVF_*.bnk',
  [string]$GameInit
)
$ErrorActionPreference = 'Stop'
if (-not $Banks) {   # banques generees du projet SML (config.local.ps1)
  . (Join-Path (Split-Path $PSScriptRoot -Parent) 'config.local.ps1')
  $Banks = Join-Path $Config.SmlProject 'SatisfactoryModLoader_WwiseProject/GeneratedSoundBanks/Windows'
}
$Root = Split-Path $PSScriptRoot -Parent
if (-not $GameInit) { $GameInit = Join-Path $Root 'raw\bnk\Init.bnk' }

$ProjectIdOffset = 0x18   # BKHD : tag(4) taille(4) version(4) bankId(4) langue(4) alignement(4) projectId(4)

function Read-Header([byte[]]$b, [string]$name) {
  if ([Text.Encoding]::ASCII.GetString($b, 0, 4) -ne 'BKHD') { throw "$name : pas d'en-tete BKHD en debut de fichier" }
  [pscustomobject]@{
    Version   = [BitConverter]::ToUInt32($b, 8)
    BankId    = [BitConverter]::ToUInt32($b, 12)
    ProjectId = [BitConverter]::ToUInt32($b, $ProjectIdOffset)
  }
}

if (-not (Test-Path $GameInit)) {
  & (Join-Path $Root 'extract\pak-extract.ps1') -Files 'FactoryGame/Content/WwiseAudio/Init.bnk' -OutDir (Split-Path $GameInit -Parent)
}
$ref = Read-Header ([IO.File]::ReadAllBytes($GameInit)) 'Init.bnk du jeu'
Write-Host ("Init.bnk du jeu : format v{0}, identifiant de projet {1}" -f $ref.Version, $ref.ProjectId)

foreach ($f in Get-ChildItem (Join-Path $Banks $Pattern)) {
  $b = [IO.File]::ReadAllBytes($f.FullName)
  $h = Read-Header $b $f.Name
  if ($h.Version -ne $ref.Version) { throw "$($f.Name) : format v$($h.Version) different du jeu (v$($ref.Version)) : mauvaise version de Wwise ?" }
  if ($h.ProjectId -eq $ref.ProjectId) { Write-Host "  $($f.Name) : deja a $($ref.ProjectId)"; continue }
  [Array]::Copy([BitConverter]::GetBytes([uint32]$ref.ProjectId), 0, $b, $ProjectIdOffset, 4)
  [IO.File]::WriteAllBytes($f.FullName, $b)
  Write-Host ("  {0} : identifiant de projet {1} -> {2}" -f $f.Name, $h.ProjectId, $ref.ProjectId)
}
