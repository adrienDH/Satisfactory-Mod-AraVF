<#
  Fait viser aux actions des banques du mod des sons du jeu, a la place de sons de substitution.

  Pourquoi : une action Wwise ne peut cibler qu'un objet du projet. Pour arreter ou baisser les pistes
  de la cinematique d'intro du jeu, setup-pack.ps1 cree des sons de substitution et ecrit dans
  wwise\action-targets.json : identifiant de substitution -> identifiant du son du jeu. On remplace ici
  la cible des actions (objets HIRC de type 3, champ ulTargetID) et seulement elle : les sons de
  substitution gardent leur identifiant, pour ne pas en creer un second avec celui du jeu.

  A lancer apres patch-project-id.ps1, avant check-bank-deps.ps1.
  Usage : powershell -ExecutionPolicy Bypass -File wwise\patch-action-targets.ps1
#>
param(
  [string]$Banks   = '',
  [string]$Pattern = 'AraVF*_Cine_*.bnk'
)
$ErrorActionPreference = 'Stop'
if (-not $Banks) {   # banques generees du projet SML (config.local.ps1)
  . (Join-Path (Split-Path $PSScriptRoot -Parent) 'config.local.ps1')
  $Banks = Join-Path $Config.SmlProject 'SatisfactoryModLoader_WwiseProject/GeneratedSoundBanks/Windows'
}
$map = @{}
$json = Get-Content (Join-Path $PSScriptRoot 'action-targets.json') -Raw | ConvertFrom-Json
foreach ($prop in $json.PSObject.Properties) { $map[[uint32]$prop.Name] = [uint32]$prop.Value }

foreach ($f in Get-ChildItem (Join-Path $Banks $Pattern)) {
  $b = [IO.File]::ReadAllBytes($f.FullName)
  $count = 0; $p = 0
  while ($p -lt $b.Length - 8) {
    $tag = [Text.Encoding]::ASCII.GetString($b, $p, 4); $size = [BitConverter]::ToInt32($b, $p + 4)
    if ($tag -eq 'HIRC') {
      $q = $p + 12; $n = [BitConverter]::ToUInt32($b, $p + 8)
      for ($i = 0; $i -lt $n; $i++) {
        $type = $b[$q]; $len = [BitConverter]::ToInt32($b, $q + 1); $obj = $q + 5
        if ($type -eq 3) {   # Action : ulID (4), ulActionType (2), ulTargetID (4)
          $target = [BitConverter]::ToUInt32($b, $obj + 6)
          if ($map.ContainsKey($target)) {
            [Array]::Copy([BitConverter]::GetBytes($map[$target]), 0, $b, $obj + 6, 4); $count++
          }
        }
        $q = $obj + $len
      }
    }
    $p += 8 + $size
  }
  if ($count) {
    [IO.File]::WriteAllBytes($f.FullName, $b)
    Write-Host "  $($f.Name) : $count action(s) redirigee(s) vers les sons du jeu"
  }
}
