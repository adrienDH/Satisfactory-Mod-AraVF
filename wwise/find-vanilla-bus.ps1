<#
  Indique sur quels bus de l'Init bank du jeu une banque d'origine envoie son son, avec leur nom.

  Les objets Wwise sont identifies par l'empreinte FNV-1 32 bits de leur nom en minuscules :
  on liste les bus de l'Init.bnk du jeu, on cherche lesquels la banque reference, puis on retrouve
  leur nom en essayant des combinaisons de mots plausibles.

  Usage : powershell -ExecutionPolicy Bypass -Command "& wwise\find-vanilla-bus.ps1 -Banks raw\bnk\VO_PlayerAction_Death_04.bnk,..."
#>
param(
  [Parameter(Mandatory)] [string[]]$Banks,
  [string]$GameInit
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
if (-not $GameInit) { $GameInit = Join-Path $Root 'raw\bnk\Init.bnk' }

Add-Type -TypeDefinition @"
using System; using System.Collections.Generic;
public static class VanillaBus {
  public static uint Id(string name) { uint h = 2166136261; foreach (byte c in System.Text.Encoding.ASCII.GetBytes(name.ToLowerInvariant())) { unchecked { h = (h * 16777619) ^ c; } } return h; }
  public static List<uint[]> Objects(byte[] b) {
    var res = new List<uint[]>(); int p = 0;
    while (p + 8 <= b.Length) {
      string tag = System.Text.Encoding.ASCII.GetString(b, p, 4); int size = BitConverter.ToInt32(b, p + 4);
      if (tag == "HIRC") { int q = p + 8; uint n = BitConverter.ToUInt32(b, q); q += 4;
        for (uint i = 0; i < n; i++) { res.Add(new uint[] { b[q], BitConverter.ToUInt32(b, q + 5) }); q += 5 + BitConverter.ToInt32(b, q + 1); } }
      p += 8 + size;
    }
    return res;
  }
  public static bool Contains(byte[] b, uint id) { byte[] x = BitConverter.GetBytes(id); for (int i = 0; i <= b.Length - 4; i++) if (b[i]==x[0] && b[i+1]==x[1] && b[i+2]==x[2] && b[i+3]==x[3]) return true; return false; }
  public static Dictionary<uint, string> Names(IEnumerable<uint> targets, string[] tokens, string[] seps) {
    var want = new HashSet<uint>(targets); var res = new Dictionary<uint, string>();
    Action<string> test = n => { uint h = Id(n); if (want.Contains(h) && !res.ContainsKey(h)) res[h] = n; };
    foreach (var a in tokens) { test(a);
      foreach (var s in seps) foreach (var b in tokens) { string n = a + s + b; test(n);
        foreach (var s2 in seps) foreach (var c in tokens) test(n + s2 + c); } }
    return res;
  }
}
"@

$busType = 8
$buses = [VanillaBus]::Objects([IO.File]::ReadAllBytes($GameInit)) | Where-Object { $_[0] -eq $busType } | ForEach-Object { $_[1] }
$tokens = 'master','main','audio','bus','vo','voice','voices','dialogue','dialog','dx','ada','barks','bark','narration','narrative',
          'mix','game','gamemix','ui','speech','radio','comms','hud','player','story','messages','message','ducking','duck','send',
          'aux','fx','sfx','music','amb','ambience','world','2d','3d','ficsmas','xmas','christmas','event','events','pelevator',
          'elevator','space','alien','mam','shop','intro','outro','onboarding','tier','tutorial','cinematic','cinematics','sequence',
          'priority','interruption','system','notification','notifications','pa','project','assembly','vehicle','vehicles','weather'
$seps = '', '_', ' ', '-'

$refs = @{}
foreach ($bank in $Banks) {
  $b = [IO.File]::ReadAllBytes((Resolve-Path $bank))
  $refs[$bank] = @($buses | Where-Object { [VanillaBus]::Contains($b, $_) })
}
[uint32[]]$allRefs = @($refs.Values | ForEach-Object { $_ } | Select-Object -Unique)
$names = [VanillaBus]::Names($allRefs, $tokens, $seps)
foreach ($bank in $Banks) {
  $list = $refs[$bank] | ForEach-Object { if ($names.ContainsKey($_)) { "$($names[$_]) ($_)" } else { "INCONNU ($_)" } }
  "{0,-40} {1}" -f [IO.Path]::GetFileNameWithoutExtension($bank), ($list -join ', ')
}
