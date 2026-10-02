<#
  Verifie qu'une SoundBank du mod ne depend que d'objets presents dans l'Init bank du JEU.

  Pourquoi : le jeu charge sa propre Init bank, pas celle du projet Wwise du mod. Si une banque du mod
  reference un objet de NOTRE Init bank (bus, effet, peripherique...) absent de celle du jeu, Wwise la
  refuse avec l'erreur 92 "The Init bank was not loaded yet". Les objets sont identifies par l'empreinte
  de leur nom : un bus du mod doit porter exactement le nom d'un bus du jeu.

  Methode : on liste les objets de notre Init.bnk, on cherche lesquels sont references dans la banque du
  mod, et on verifie qu'ils existent dans l'Init.bnk du jeu.

  Usage : powershell -ExecutionPolicy Bypass -File wwise\check-bank-deps.ps1
  Code de sortie 1 si une dependance manque.
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

Add-Type -TypeDefinition @"
using System; using System.Collections.Generic;
public static class BankDeps {
  // (type, id) de chaque objet de la section HIRC
  public static List<uint[]> Objects(byte[] b) {
    var res = new List<uint[]>(); int p = 0;
    while (p + 8 <= b.Length) {
      string tag = System.Text.Encoding.ASCII.GetString(b, p, 4); int size = BitConverter.ToInt32(b, p + 4);
      if (tag == "HIRC") {
        int q = p + 8; uint n = BitConverter.ToUInt32(b, q); q += 4;
        for (uint i = 0; i < n; i++) { res.Add(new uint[] { b[q], BitConverter.ToUInt32(b, q + 5) }); q += 5 + BitConverter.ToInt32(b, q + 1); }
      }
      p += 8 + size;
    }
    return res;
  }
  public static bool Contains(byte[] b, uint id) {
    byte[] x = BitConverter.GetBytes(id);
    for (int i = 0; i <= b.Length - 4; i++) if (b[i]==x[0] && b[i+1]==x[1] && b[i+2]==x[2] && b[i+3]==x[3]) return true;
    return false;
  }
}
"@

$gameIds = @{}; foreach ($o in [BankDeps]::Objects([IO.File]::ReadAllBytes($GameInit))) { $gameIds[$o[1]] = $o[0] }
$ourInit = [BankDeps]::Objects([IO.File]::ReadAllBytes((Join-Path $Banks 'Init.bnk')))
Write-Host "Init du jeu : $($gameIds.Count) objets ; notre Init : $($ourInit.Count) objets"

$missing = 0
foreach ($f in Get-ChildItem (Join-Path $Banks $Pattern)) {
  $bank = [IO.File]::ReadAllBytes($f.FullName)
  $refs = @($ourInit | Where-Object { [BankDeps]::Contains($bank, $_[1]) })
  $bad  = @($refs | Where-Object { -not $gameIds.ContainsKey($_[1]) })
  Write-Host ("  {0} : {1} dependance(s) vers l'Init, {2} absente(s) du jeu" -f $f.Name, $refs.Count, $bad.Count)
  foreach ($r in $refs) { Write-Host ("      objet type {0,-3} ID {1,10}  {2}" -f $r[0], $r[1], $(if ($gameIds.ContainsKey($r[1])) { 'present dans le jeu' } else { 'ABSENT DU JEU' })) }
  $missing += $bad.Count
}
if ($missing -gt 0) { Write-Host "ECHEC : $missing dependance(s) absente(s) de l'Init bank du jeu"; exit 1 }
Write-Host "OK : toutes les dependances existent dans l'Init bank du jeu"
