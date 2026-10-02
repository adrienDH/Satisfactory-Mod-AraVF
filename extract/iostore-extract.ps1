<#
  Extrait les donnees de packages d'un conteneur IoStore UE5 (.utoc/.ucas) du jeu.
  Sert a recuperer des assets du jeu stockes hors du .pak classique (messages, evenements...).

  Un fichier :
    powershell -ExecutionPolicy Bypass -File extract\iostore-extract.ps1 `
      -AssetPath FactoryGame/Content/WwiseAudio/InitBank.uasset -Out raw\InitBank.bin
  En lot (tous les fichiers d'un dossier correspondant a un motif, arborescence conservee) :
    powershell -ExecutionPolicy Bypass -File extract\iostore-extract.ps1 `
      -Prefix FactoryGame/Content/FactoryGame/Narrative -Filter 'MSG_*.uasset' -OutDir raw\narrative
  Prerequis : oo2core_9_win64.dll dans extract\ (voir README).
  Compatible Windows PowerShell 5.1.
#>
param(
  [string]$AssetPath,
  [string]$Out,
  [string]$Prefix,
  [string]$Filter = '*',
  [string]$OutDir,
  [string]$GameDir = 'C:\Program Files\Epic Games\SatisfactoryEarlyAccess',
  [string]$Container = 'FactoryGame-Windows',
  [string]$Oodle
)
$ErrorActionPreference = 'Stop'
# $PSScriptRoot est vide dans les valeurs par defaut des parametres d'un script avance (PS 5.1)
if (-not $Oodle) { $Oodle = Join-Path $PSScriptRoot 'oo2core_9_win64.dll' }
if (-not (($AssetPath -and $Out) -or ($Prefix -and $OutDir))) { throw "utiliser -AssetPath/-Out ou -Prefix/-OutDir" }

Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class OodleIo {
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern IntPtr LoadLibrary(string lpFileName);
  [DllImport("oo2core_9_win64.dll", CallingConvention=CallingConvention.Cdecl)]
  public static extern long OodleLZ_Decompress(byte[] c, long cs, byte[] r, long rl,
    int fuzz, int crc, int verb, IntPtr b, long bs, IntPtr cb, IntPtr cbu, IntPtr dm, long dms, int tp);
}
"@
if ([OodleIo]::LoadLibrary($Oodle) -eq [IntPtr]::Zero) { throw "chargement de $Oodle impossible" }

$paks = Join-Path $GameDir 'FactoryGame\Content\Paks'
$toc  = [IO.File]::ReadAllBytes((Join-Path $paks "$Container.utoc"))
$r = New-Object IO.BinaryReader(New-Object IO.MemoryStream(,$toc))

# ---------- en-tete FIoStoreTocHeader ----------
$magic = [Text.Encoding]::ASCII.GetString($r.ReadBytes(16))
if ($magic -ne '-==--==--==--==-') { throw "magic utoc inattendu : $magic" }
$version = $r.ReadByte(); $null = $r.ReadByte(); $null = $r.ReadUInt16()
$headerSize   = $r.ReadUInt32()
$entryCount   = $r.ReadUInt32()
$blockCount   = $r.ReadUInt32()
$blockEntrySz = $r.ReadUInt32()
$methodCount  = $r.ReadUInt32()
$methodLen    = $r.ReadUInt32()
$blockSize    = $r.ReadUInt32()
$dirIndexSize = $r.ReadUInt32()
$null = $r.ReadUInt32()                 # PartitionCount
$null = $r.ReadUInt64()                 # ContainerId
$null = $r.ReadBytes(16)                # EncryptionKeyGuid
$flags = $r.ReadByte(); $null = $r.ReadByte(); $null = $r.ReadUInt16()
$seedsCount   = $r.ReadUInt32()
$null = $r.ReadUInt64()                 # PartitionSize
$noHashCount  = $r.ReadUInt32()
Write-Host ("utoc v{0} : {1} entrees, {2} blocs de {3} o" -f $version, $entryCount, $blockCount, $blockSize)
if ($flags -band 0x02) { throw "conteneur chiffre : non pris en charge" }

$pos = [int64]$headerSize
$offLenPos   = $pos + 12L * $entryCount; $pos = $offLenPos + 10L * $entryCount
$pos += 4L * $seedsCount + 4L * $noHashCount
$blocksPos   = $pos;           $pos += [int64]$blockEntrySz * $blockCount
$methodsPos  = $pos;           $pos += [int64]$methodLen * $methodCount
$methods = @('None')
for ($i = 0; $i -lt $methodCount; $i++) {
  $methods += [Text.Encoding]::ASCII.GetString($toc, [int]($methodsPos + $i * $methodLen), [int]$methodLen).TrimEnd([char]0)
}
if ($flags -band 0x08) {                # Signed
  $r.BaseStream.Position = $pos
  $hashSize = $r.ReadInt32(); $pos += 4 + 2L * $hashSize + 20L * $blockCount
}
$dirPos = $pos

# ---------- index des repertoires -> chemin complet de chaque fichier ----------
function Read-FStr($rd) {
  $len = $rd.ReadInt32()
  if ($len -eq 0) { return '' }
  if ($len -lt 0) { return [Text.Encoding]::Unicode.GetString($rd.ReadBytes((-$len) * 2)).TrimEnd([char]0) }
  return [Text.Encoding]::UTF8.GetString($rd.ReadBytes($len)).TrimEnd([char]0)
}
$d = New-Object IO.BinaryReader(New-Object IO.MemoryStream($toc, [int]$dirPos, [int]$dirIndexSize))
$null = Read-FStr $d                                            # mount point
$nDirs = $d.ReadInt32(); $dirs = New-Object 'object[]' $nDirs
for ($i = 0; $i -lt $nDirs; $i++) { $dirs[$i] = @($d.ReadUInt32(), $d.ReadUInt32(), $d.ReadUInt32(), $d.ReadUInt32()) } # Name, FirstChild, NextSibling, FirstFile
$nFiles = $d.ReadInt32(); $files = New-Object 'object[]' $nFiles
for ($i = 0; $i -lt $nFiles; $i++) { $files[$i] = @($d.ReadUInt32(), $d.ReadUInt32(), $d.ReadUInt32()) }               # Name, NextFile, UserData
$nStr = $d.ReadInt32(); $strings = New-Object string[] $nStr
for ($i = 0; $i -lt $nStr; $i++) { $strings[$i] = Read-FStr $d }

$NONE = [uint32]::MaxValue
$all = New-Object 'System.Collections.Generic.Dictionary[string,int]' ([StringComparer]::OrdinalIgnoreCase)
$stack = New-Object System.Collections.Stack
$stack.Push(@(0, ''))
while ($stack.Count -gt 0) {
  $item = $stack.Pop(); $di = $item[0]; $path = $item[1]
  $f = $dirs[$di][3]
  while ($f -ne $NONE) { $all[$path + $strings[$files[$f][0]]] = [int]$files[$f][2]; $f = $files[$f][1] }
  $c = $dirs[$di][1]
  while ($c -ne $NONE) { $stack.Push(@($c, ($path + $strings[$dirs[$c][0]] + '/'))); $c = $dirs[$c][2] }
}

# ---------- selection ----------
$jobs = New-Object Collections.Generic.List[object]
if ($AssetPath) {
  $key = $AssetPath.Trim('/')
  if (-not $all.ContainsKey($key)) { throw "fichier introuvable : $AssetPath" }
  $jobs.Add(@($key, $Out))
} else {
  $pre = $Prefix.Trim('/') + '/'
  foreach ($k in $all.Keys) {
    if ($k.StartsWith($pre, [StringComparison]::OrdinalIgnoreCase) -and ([IO.Path]::GetFileName($k) -like $Filter)) {
      $jobs.Add(@($k, (Join-Path $OutDir ($k.Substring($pre.Length) -replace '/', '\'))))
    }
  }
  Write-Host "$($jobs.Count) fichier(s) a extraire sous $Prefix ($Filter)"
}

# ---------- extraction ----------
$ucas = [IO.File]::Open((Join-Path $paks "$Container.ucas"), 'Open', 'Read', 'ReadWrite')
$ur = New-Object IO.BinaryReader($ucas)
foreach ($job in $jobs) {
  $entry = $all[$job[0]]
  $o = $offLenPos + 10L * $entry
  $chunkOff = [int64]0; $chunkLen = [int64]0
  for ($i = 0; $i -lt 5; $i++) { $chunkOff = ($chunkOff -shl 8) -bor $toc[$o + $i] }
  for ($i = 5; $i -lt 10; $i++) { $chunkLen = ($chunkLen -shl 8) -bor $toc[$o + $i] }

  $first = [int64][Math]::Floor($chunkOff / $blockSize)
  $last  = [int64][Math]::Floor(($chunkOff + $chunkLen - 1) / $blockSize)
  $ms = New-Object IO.MemoryStream
  for ($b = $first; $b -le $last; $b++) {
    $e = $blocksPos + [int64]$blockEntrySz * $b
    $bOff  = [BitConverter]::ToUInt64($toc, [int]$e) -band 0xFFFFFFFFFF
    $bComp = ([BitConverter]::ToUInt32($toc, [int]$e + 4) -shr 8) -band 0xFFFFFF
    $w2    = [BitConverter]::ToUInt32($toc, [int]$e + 8)
    $bRaw  = $w2 -band 0xFFFFFF
    $bMeth = $methods[$w2 -shr 24]
    $ucas.Position = [int64]$bOff
    $comp = $ur.ReadBytes([int]$bComp)
    if ($bMeth -eq 'None') { $raw = $comp }
    elseif ($bMeth -eq 'Oodle') {
      $raw = New-Object byte[] $bRaw
      $rc = [OodleIo]::OodleLZ_Decompress($comp, $comp.Length, $raw, $bRaw, 1, 0, 0, [IntPtr]::Zero, 0, [IntPtr]::Zero, [IntPtr]::Zero, [IntPtr]::Zero, 0, 3)
      if ($rc -ne $bRaw) { throw "echec Oodle sur le bloc $b ($($job[0]))" }
    } else { throw "compression non prise en charge : $bMeth" }
    $ms.Write($raw, 0, $raw.Length)
  }
  $buf = $ms.ToArray()
  $data = New-Object byte[] $chunkLen
  [Array]::Copy($buf, [int]($chunkOff - $first * $blockSize), $data, 0, [int]$chunkLen)
  $null = New-Item -ItemType Directory -Force -Path (Split-Path $job[1] -Parent)
  [IO.File]::WriteAllBytes($job[1], $data)
  if ($AssetPath) { Write-Host ("{0} : {1:N0} o -> {2}" -f $job[0], $chunkLen, $job[1]) }
}
$ucas.Close()
if (-not $AssetPath) { Write-Host "$($jobs.Count) fichier(s) ecrit(s) dans $OutDir" }
