<#
  Analyse les messages du jeu extraits (raw\narrative, via iostore-extract.ps1) et produit
  corpus\messages.tsv : un message par ligne, avec son chemin d'asset, son evenement audio
  d'origine, ses interlocuteurs et son nombre de sous-titres.

  Usage : powershell -ExecutionPolicy Bypass -File extract\analyze-messages.ps1
#>
param(
  [string]$GameDir = 'C:\Program Files\Epic Games\SatisfactoryEarlyAccess'
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
$In   = Join-Path $Root 'raw\narrative'

# evenements audio du jeu, d'apres le manifeste (le plus long prefixe l'emporte)
$events = Get-Content (Join-Path $GameDir 'Manifest_UFSFiles_Win64.txt') | ForEach-Object { ($_ -split "`t")[0] } |
  Where-Object { $_ -like 'FactoryGame/Content/WwiseAudio/Events/*.uasset' } |
  ForEach-Object { '/Game/' + $_.Substring('FactoryGame/Content/'.Length).Replace('.uasset', '') }
$eventSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($e in $events) { $null = $eventSet.Add($e) }
# banques d'evenement du jeu : Event/NN/<Nom>.bnk
$banks = @{}
Get-Content (Join-Path $GameDir 'Manifest_UFSFiles_Win64.txt') | ForEach-Object { ($_ -split "`t")[0] } |
  Where-Object { $_ -match '^FactoryGame/Content/WwiseAudio/Event/\d+/[^/]+\.bnk$' } |
  ForEach-Object { $banks[[IO.Path]::GetFileNameWithoutExtension($_)] = $_ }

$rows = New-Object Collections.Generic.List[string]
$rows.Add((@('message','asset','event','bank','senders','subtitles') -join "`t"))
foreach ($f in Get-ChildItem $In -Recurse -Filter 'MSG_*.uasset') {
  $txt = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($f.FullName))
  $name = $f.BaseName
  $rel  = $f.FullName.Substring($In.Length + 1).Replace('\', '/').Replace('.uasset', '')
  $asset = "/Game/FactoryGame/Narrative/$rel.$name"

  # evenement : plus long chemin connu du manifeste qui prefixe une occurrence de /Game/WwiseAudio/Events/.
  # Unreal stocke a part le suffixe numerique d'un nom sans zero initial (FName "X_10" = "X" + numero) :
  # le chemin lu s'arrete alors a "X", et le numero est le dernier nombre du nom du message
  # (MSG_..._10 -> ..._10 ; MSG_Tier1_Schematic_1-1 -> Play_VO_Tier1_Schematic_1_1).
  $suffix = if ($name -match '[_-](\d+)$') { '_' + [int]$Matches[1] } else { '' }
  $event = ''
  foreach ($m in [regex]::Matches($txt, '/Game/WwiseAudio/Events/[A-Za-z0-9_\-/\.]+')) {
    $s = $m.Value
    while ($s.Length -gt 0) {
      if ($eventSet.Contains($s)) { break }
      if ($suffix -and $eventSet.Contains($s + $suffix)) { $s = $s + $suffix; break }
      $s = $s.Substring(0, $s.Length - 1)
    }
    if ($s.Length -gt $event.Length) { $event = $s }
  }
  $eventName = if ($event) { $event.Substring($event.LastIndexOf('/') + 1) } else { '' }
  $bank = if ($eventName -and $banks.ContainsKey($eventName)) { $banks[$eventName] } else { '' }

  $senders = ([regex]::Matches($txt, '/Message/Sender/(Sender_[A-Za-z0-9]+(?:_[A-Z][A-Za-z0-9]*)*)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique) -join ','
  $subs = ([regex]::Matches($txt, [regex]::Escape($name) + '/Subtitles\(\d+\)') | ForEach-Object { $_.Value } | Sort-Object -Unique).Count
  $rows.Add((@($name, $asset, $event, $bank, $senders, $subs) -join "`t"))
}
$out = Join-Path $Root 'corpus\messages.tsv'
[IO.File]::WriteAllLines($out, $rows, (New-Object Text.UTF8Encoding($false)))
Write-Host "$($rows.Count - 1) messages -> $out"
