<#
  Extrait les dialogues d'ARA/ADA depuis le pak de Satisfactory et produit
  corpus/ada_corpus.tsv : anglais + chaque langue demandee (colonnes text_en, text_<langue>).
  -Languages : cultures du jeu (dossiers Localization/Narrative/<culture>), ex. fr, es-ES ;
  la colonne prend le code court (es-ES -> text_es). -ListCultures : affiche les cultures disponibles.

  Prerequis : oo2core_9_win64.dll dans ce dossier (voir README).
  Usage : powershell -ExecutionPolicy Bypass -File extract\build-corpus.ps1
  Compatible Windows PowerShell 5.1.
#>
param(
  [string]$GameDir = 'C:\Program Files\Epic Games\SatisfactoryEarlyAccess',
  [string]$Oodle   = "$PSScriptRoot\oo2core_9_win64.dll",
  [string[]]$Languages = @('fr'),
  [switch]$ListCultures
)
$Languages = @($Languages | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$ErrorActionPreference = 'Stop'
$Root    = Split-Path $PSScriptRoot -Parent
$RawDir  = Join-Path $Root 'raw\locres'
$CorpDir = Join-Path $Root 'corpus'
$null = New-Item -ItemType Directory -Force -Path $RawDir, $CorpDir
$Pak = Join-Path $GameDir 'FactoryGame\Content\Paks\FactoryGame-Windows.pak'
if (-not (Test-Path $Pak))   { throw "pak introuvable : $Pak" }
if (-not (Test-Path $Oodle)) { throw "DLL Oodle introuvable : $Oodle (voir README)" }

Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class Oodle {
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern IntPtr LoadLibrary(string lpFileName);
  [DllImport("oo2core_9_win64.dll", CallingConvention=CallingConvention.Cdecl)]
  public static extern long OodleLZ_Decompress(byte[] c, long cs, byte[] r, long rl,
    int fuzz, int crc, int verb, IntPtr b, long bs, IntPtr cb, IntPtr cbu, IntPtr dm, long dms, int tp);
}
"@
if ([Oodle]::LoadLibrary($Oodle) -eq [IntPtr]::Zero) { throw "chargement de $Oodle impossible" }

$SEP = [char]1

function Read-FString($rd) {
  $len = $rd.ReadInt32()
  if ($len -eq 0) { return '' }
  if ($len -lt 0) { $x = $rd.ReadBytes((-$len)*2); return [Text.Encoding]::Unicode.GetString($x).TrimEnd([char]0) }
  $x = $rd.ReadBytes($len); return [Text.Encoding]::UTF8.GetString($x).TrimEnd([char]0)
}

# ---------- 1. footer + index du pak (UE5 pak v11, index non chiffre) ----------
$fs = [IO.File]::Open($Pak,'Open','Read','ReadWrite'); $br = New-Object IO.BinaryReader($fs)
$tailLen = 512; $fs.Position = $fs.Length - $tailLen; $tail = $br.ReadBytes($tailLen)
$magicPos = -1
for ($i = $tailLen - 4; $i -ge 0; $i--) {
  if ($tail[$i] -eq 0xE1 -and $tail[$i+1] -eq 0x12 -and $tail[$i+2] -eq 0x6F -and $tail[$i+3] -eq 0x5A) {
    $v = [BitConverter]::ToInt32($tail, $i+4)
    if ($v -ge 1 -and $v -le 12) { $magicPos = $fs.Length - $tailLen + $i; break }
  }
}
if ($magicPos -lt 0) { throw "footer du pak introuvable" }
$fs.Position = $magicPos; $null = $br.ReadInt32()
$pakVersion  = $br.ReadInt32()
$indexOffset = $br.ReadInt64()
$indexSize   = $br.ReadInt64()
$fs.Position = $magicPos - 1
if ($br.ReadByte() -ne 0) { throw "index chiffre : cle AES requise" }
Write-Host "pak version $pakVersion, index $indexSize octets"

$fs.Position = $indexOffset; $idx = $br.ReadBytes([int]$indexSize)
$r = New-Object IO.BinaryReader(New-Object IO.MemoryStream(,$idx))
$null = Read-FString $r           # mount point
$null = $r.ReadInt32()            # nb entrees
$null = $r.ReadUInt64()           # path hash seed
if ($r.ReadInt32() -ne 0) { $null=$r.ReadInt64(); $null=$r.ReadInt64(); $null=$r.ReadBytes(20) }
if ($r.ReadInt32() -eq 0) { throw "full directory index absent" }
$fdiOffset = $r.ReadInt64(); $fdiSize = $r.ReadInt64(); $null = $r.ReadBytes(20)
$encoded = $r.ReadBytes($r.ReadInt32())

$fs.Position = $fdiOffset; $fdi = $br.ReadBytes([int]$fdiSize)
$r2 = New-Object IO.BinaryReader(New-Object IO.MemoryStream(,$fdi))
$numDirs = $r2.ReadInt32()
$hits = New-Object Collections.Generic.List[object]
$cultures = New-Object 'System.Collections.Generic.SortedSet[string]'
$wanted = @('en-US') + $Languages
for ($d = 0; $d -lt $numDirs; $d++) {
  $dir = Read-FString $r2; $nf = $r2.ReadInt32()
  for ($f = 0; $f -lt $nf; $f++) {
    $fn = Read-FString $r2; $off = $r2.ReadInt32()
    if ($dir -match '^FactoryGame/Content/Localization/Narrative/([^/]+)/$') { $null = $cultures.Add($Matches[1]) }
    if ($dir -match '^FactoryGame/Content/Localization/' -and $dir -match '/([^/]+)/$' -and $wanted -contains $Matches[1] -and $fn -match '\.locres$') {
      $hits.Add([pscustomobject]@{ Dir=$dir; File=$fn; EncOff=$off })
    }
  }
}
if ($ListCultures) { Write-Host "cultures : $($cultures -join ', ')"; return }
Write-Host "$($hits.Count) fichiers locres cibles"

# ---------- 2. decodage des entrees + decompression Oodle ----------
$encMs = New-Object IO.MemoryStream(,$encoded)
$encR  = New-Object IO.BinaryReader($encMs)
foreach ($t in $hits) {
  $encMs.Position = $t.EncOff
  $v = $encR.ReadUInt32()
  if (($v -band 0x3f) -eq 0x3f) { $null = $encR.ReadUInt32() }
  $o32 = (($v -shr 31) -band 1) -ne 0
  $u32 = (($v -shr 30) -band 1) -ne 0
  $entryOffset = if ($o32) { [int64]$encR.ReadUInt32() } else { [int64]$encR.ReadUInt64() }
  $null        = if ($u32) { [int64]$encR.ReadUInt32() } else { [int64]$encR.ReadUInt64() }

  # relire l'entete FPakEntry reellement stocke dans le pak : source de verite
  $fs.Position = $entryOffset
  $null = $br.ReadInt64(); $null = $br.ReadInt64(); $usz = $br.ReadInt64()
  $m = $br.ReadUInt32(); $null = $br.ReadBytes(20)
  $blocks = New-Object Collections.Generic.List[object]
  if ($m -ne 0) {
    $n = $br.ReadInt32()
    for ($i=0; $i -lt $n; $i++) { $blocks.Add(@($br.ReadInt64(), $br.ReadInt64())) }
  }
  $null = $br.ReadByte(); $blockSize = $br.ReadUInt32()

  $name    = ($t.Dir -replace '.*/Localization/','') + $t.File
  $outFile = Join-Path $RawDir ($name -replace '[\\/]','_')
  if ($m -eq 0) {
    $fs.Position = $entryOffset + 53   # taille d'entete FPakEntry v11 non compressee
    [IO.File]::WriteAllBytes($outFile, $br.ReadBytes([int]$usz))
  } else {
    # offsets de bloc relatifs a l'entree (pak v5+) ou absolus
    $base = if ($blocks[0][0] -lt $entryOffset) { $entryOffset } else { 0 }
    $out = New-Object byte[] $usz; $written = 0
    foreach ($b in $blocks) {
      $fs.Position = $base + $b[0]
      $comp   = $br.ReadBytes([int]($b[1] - $b[0]))
      $rawLen = [Math]::Min([int64]$blockSize, $usz - $written)
      $raw    = New-Object byte[] $rawLen
      $rc = [Oodle]::OodleLZ_Decompress($comp, $comp.Length, $raw, $rawLen, 1, 0, 0,
              [IntPtr]::Zero, 0, [IntPtr]::Zero, [IntPtr]::Zero, [IntPtr]::Zero, 0, 3)
      if ($rc -ne $rawLen) { throw "$name : echec Oodle (retour=$rc attendu=$rawLen)" }
      [Array]::Copy($raw, 0, $out, $written, $rawLen); $written += $rawLen
    }
    [IO.File]::WriteAllBytes($outFile, $out)
  }
  Write-Host ("  extrait {0,-44} {1,10:N0} o" -f $name, $usz)
}
$br.Close(); $fs.Close()

# ---------- 3. parsing locres (format v3 : Optimized_CRC32_UTF16) ----------
function Read-LocRes([string]$path) {
  $ms = New-Object IO.MemoryStream(,[IO.File]::ReadAllBytes($path))
  $r  = New-Object IO.BinaryReader($ms)
  $null = $r.ReadBytes(16)          # magic
  $ver    = $r.ReadByte()
  $strOff = $r.ReadInt64()
  $save = $ms.Position; $ms.Position = $strOff
  $nStr = $r.ReadInt32(); $strings = New-Object string[] $nStr
  for ($i=0; $i -lt $nStr; $i++) {
    $strings[$i] = Read-FString $r
    if ($ver -ge 2) { $null = $r.ReadInt32() }   # ref count
  }
  $ms.Position = $save
  if ($ver -ge 2) { $null = $r.ReadUInt32() }    # entries count
  $nNs = $r.ReadUInt32()
  $map = @{}
  for ($n=0; $n -lt $nNs; $n++) {
    if ($ver -ge 2) { $null = $r.ReadUInt32() }  # hash du namespace
    $ns = Read-FString $r
    $nK = $r.ReadUInt32()
    for ($k=0; $k -lt $nK; $k++) {
      if ($ver -ge 2) { $null = $r.ReadUInt32() }  # hash de la cle
      $key = Read-FString $r
      $null = $r.ReadUInt32()                      # hash de la source
      $i = $r.ReadInt32()
      $map[$ns + $SEP + $key] = $strings[$i]
    }
  }
  $r.Close()
  return $map
}

$en = Read-LocRes (Join-Path $RawDir 'Narrative_en-US_Narrative.locres')
$tr = [ordered]@{}
foreach ($c in $Languages) {
  $tr[($c -split '-')[0]] = Read-LocRes (Join-Path $RawDir "Narrative_$($c)_Narrative.locres")
  Write-Host "locres $c : $($tr[($c -split '-')[0]].Count) entrees"
}
Write-Host "locres EN : $($en.Count) entrees"
# ---------- 4. corpus aligne ----------
$keys = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($m in $tr.Values) { foreach ($k in $m.Keys) { $null = $keys.Add($k) } }
$rows = New-Object Collections.Generic.List[object]
foreach ($k in $keys) {
  $parts = $k.Split($SEP, 2)
  $ns = $parts[0]; $key = $parts[1]
  $msg = $key; $idx = ''
  if ($key -match '/Subtitles\((\d+)\)$') { $idx = $Matches[1]; $msg = $key -replace '/Subtitles\(\d+\)$','' }
  $msg = $msg -replace '^.*/',''
  $texts = @(foreach ($m in $tr.Values) { if ($m.ContainsKey($k)) { $m[$k] } else { '' } })
  $rows.Add([pscustomobject]@{ Namespace = $ns; Message = $msg; Index = $idx; Key = $key
    En = $(if ($en.ContainsKey($k)) { $en[$k] } else { '' }); Texts = $texts })
}
$sorted = $rows | Sort-Object Namespace, Message, @{ Expression = { if ($_.Index -eq '') { -1 } else { [int]$_.Index } } }
$TAB = [char]9
$lines = New-Object Collections.Generic.List[string]
$lines.Add((@('namespace','message','sub_index','key','text_en') + @($tr.Keys | ForEach-Object { "text_$_" }) -join $TAB))
foreach ($x in $sorted) {
  $cols = @($x.Namespace, $x.Message, $x.Index, $x.Key, $x.En) + $x.Texts
  $lines.Add((@($cols | ForEach-Object { "$_".Replace("`r",'').Replace("`n",'\n') }) -join $TAB))
}
$outTsv = Join-Path $CorpDir 'ada_corpus.tsv'
[IO.File]::WriteAllLines($outTsv, $lines, (New-Object Text.UTF8Encoding($false)))

$spoken   = @($sorted | Where-Object { $_.Index -ne '' })
$messages = @($sorted | Select-Object -ExpandProperty Message -Unique).Count

Write-Host ""
Write-Host "corpus                 : $outTsv"
Write-Host "entrees                : $($sorted.Count)"
Write-Host "lignes parlees         : $($spoken.Count)"
Write-Host "messages MSG_ distincts: $messages"
$codes = @($tr.Keys)
for ($i = 0; $i -lt $codes.Count; $i++) {
  $chars   = ($spoken | ForEach-Object { $_.Texts[$i].Length } | Measure-Object -Sum).Sum
  $missing = @($sorted | Where-Object { $_.Texts[$i] -eq '' }).Count
  Write-Host ("{0,-23}: {1:N0} caracteres parles, {2} traduction(s) manquante(s)" -f $codes[$i], $chars, $missing)
}
