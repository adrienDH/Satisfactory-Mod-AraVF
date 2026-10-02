<#
  Extrait des fichiers du .pak classique du jeu (UE5 pak v11, index non chiffre, Oodle).
  Complement de iostore-extract.ps1 : les fichiers qui ne sont pas des packages (.bnk, .locres...)
  sont ici, pas dans le conteneur IoStore.

  Usage : powershell -ExecutionPolicy Bypass -File extract\pak-extract.ps1 `
            -Files FactoryGame/Content/WwiseAudio/Init.bnk -OutDir raw\bnk
  Compatible Windows PowerShell 5.1.
#>
param(
  [Parameter(Mandatory)] [string[]]$Files,
  [Parameter(Mandatory)] [string]$OutDir,
  [string]$GameDir = 'C:\Program Files\Epic Games\SatisfactoryEarlyAccess',
  [string]$Oodle
)
$ErrorActionPreference = 'Stop'
if (-not $Oodle) { $Oodle = Join-Path $PSScriptRoot 'oo2core_9_win64.dll' }
$null = New-Item -ItemType Directory -Force -Path $OutDir

Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class OodlePak {
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern IntPtr LoadLibrary(string lpFileName);
  [DllImport("oo2core_9_win64.dll", CallingConvention=CallingConvention.Cdecl)]
  public static extern long OodleLZ_Decompress(byte[] c, long cs, byte[] r, long rl,
    int fuzz, int crc, int verb, IntPtr b, long bs, IntPtr cb, IntPtr cbu, IntPtr dm, long dms, int tp);
}
"@
if ([OodlePak]::LoadLibrary($Oodle) -eq [IntPtr]::Zero) { throw "chargement de $Oodle impossible" }

function Read-FString($rd) {
  $len = $rd.ReadInt32()
  if ($len -eq 0) { return '' }
  if ($len -lt 0) { return [Text.Encoding]::Unicode.GetString($rd.ReadBytes((-$len)*2)).TrimEnd([char]0) }
  return [Text.Encoding]::UTF8.GetString($rd.ReadBytes($len)).TrimEnd([char]0)
}

$Pak = Join-Path $GameDir 'FactoryGame\Content\Paks\FactoryGame-Windows.pak'
$fs = [IO.File]::Open($Pak,'Open','Read','ReadWrite'); $br = New-Object IO.BinaryReader($fs)

# footer + index (voir build-corpus.ps1 pour le detail du format)
$tailLen = 512; $fs.Position = $fs.Length - $tailLen; $tail = $br.ReadBytes($tailLen); $magicPos = -1
for ($i = $tailLen - 4; $i -ge 0; $i--) {
  if ($tail[$i] -eq 0xE1 -and $tail[$i+1] -eq 0x12 -and $tail[$i+2] -eq 0x6F -and $tail[$i+3] -eq 0x5A) {
    $v = [BitConverter]::ToInt32($tail, $i+4); if ($v -ge 1 -and $v -le 12) { $magicPos = $fs.Length - $tailLen + $i; break }
  }
}
if ($magicPos -lt 0) { throw "footer du pak introuvable" }
$fs.Position = $magicPos + 8; $indexOffset = $br.ReadInt64(); $indexSize = $br.ReadInt64()
$fs.Position = $indexOffset
$r = New-Object IO.BinaryReader(New-Object IO.MemoryStream(,$br.ReadBytes([int]$indexSize)))
$null = Read-FString $r; $null = $r.ReadInt32(); $null = $r.ReadUInt64()
if ($r.ReadInt32() -ne 0) { $null=$r.ReadInt64(); $null=$r.ReadInt64(); $null=$r.ReadBytes(20) }
if ($r.ReadInt32() -eq 0) { throw "full directory index absent" }
$fdiOffset = $r.ReadInt64(); $fdiSize = $r.ReadInt64(); $null = $r.ReadBytes(20)
$encoded = $r.ReadBytes($r.ReadInt32())

$wanted = @{}; foreach ($f in $Files) { $wanted[$f.Trim('/').ToLowerInvariant()] = $f }
$fs.Position = $fdiOffset
$r2 = New-Object IO.BinaryReader(New-Object IO.MemoryStream(,$br.ReadBytes([int]$fdiSize)))
$numDirs = $r2.ReadInt32(); $hits = @{}
for ($d = 0; $d -lt $numDirs; $d++) {
  $dir = Read-FString $r2; $nf = $r2.ReadInt32()
  for ($k = 0; $k -lt $nf; $k++) {
    $fn = Read-FString $r2; $off = $r2.ReadInt32()
    $full = ($dir + $fn).TrimStart('/').ToLowerInvariant()
    if ($wanted.ContainsKey($full)) { $hits[$full] = $off }
  }
}

$encMs = New-Object IO.MemoryStream(,$encoded); $encR = New-Object IO.BinaryReader($encMs)
foreach ($key in $wanted.Keys) {
  if (-not $hits.ContainsKey($key)) { Write-Warning "absent du pak : $($wanted[$key])"; continue }
  $encMs.Position = $hits[$key]
  $v = $encR.ReadUInt32()
  if (($v -band 0x3f) -eq 0x3f) { $null = $encR.ReadUInt32() }
  $o32 = (($v -shr 31) -band 1) -ne 0
  $entryOffset = if ($o32) { [int64]$encR.ReadUInt32() } else { [int64]$encR.ReadUInt64() }

  $fs.Position = $entryOffset
  $null = $br.ReadInt64(); $null = $br.ReadInt64(); $usz = $br.ReadInt64()
  $m = $br.ReadUInt32(); $null = $br.ReadBytes(20)
  $blocks = New-Object Collections.Generic.List[object]
  if ($m -ne 0) { $n = $br.ReadInt32(); for ($i=0; $i -lt $n; $i++) { $blocks.Add(@($br.ReadInt64(), $br.ReadInt64())) } }
  $null = $br.ReadByte(); $blockSize = $br.ReadUInt32()

  if ($m -eq 0) { $fs.Position = $entryOffset + 53; $out = $br.ReadBytes([int]$usz) }
  else {
    $base = if ($blocks[0][0] -lt $entryOffset) { $entryOffset } else { 0 }
    $out = New-Object byte[] $usz; $written = 0
    foreach ($b in $blocks) {
      $fs.Position = $base + $b[0]; $comp = $br.ReadBytes([int]($b[1] - $b[0]))
      $rawLen = [Math]::Min([int64]$blockSize, $usz - $written); $raw = New-Object byte[] $rawLen
      $rc = [OodlePak]::OodleLZ_Decompress($comp, $comp.Length, $raw, $rawLen, 1,0,0,[IntPtr]::Zero,0,[IntPtr]::Zero,[IntPtr]::Zero,[IntPtr]::Zero,0,3)
      if ($rc -ne $rawLen) { throw "$key : echec Oodle" }
      [Array]::Copy($raw, 0, $out, $written, $rawLen); $written += $rawLen
    }
  }
  $dest = Join-Path $OutDir ([IO.Path]::GetFileName($wanted[$key]))
  [IO.File]::WriteAllBytes($dest, $out)
  Write-Host ("  {0,-70} {1,10:N0} o" -f $wanted[$key], $out.Length)
}
$br.Close(); $fs.Close()
