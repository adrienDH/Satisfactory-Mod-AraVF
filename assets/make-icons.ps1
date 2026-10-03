<#
  Dessine les propositions d'icone du mod (512x512, pour ficsit.app ; le jeu utilise Resources/Icon128.png).
  Couleurs de FICSIT (orange / anthracite) + touche tricolore ; pas de logo du jeu (marque de Coffee Stain).

  Usage : powershell -ExecutionPolicy Bypass -File assets\make-icons.ps1
  Sortie : assets\icons\icon-<variante>-512.png
#>
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$Out = Join-Path $PSScriptRoot 'icons'
$null = New-Item -ItemType Directory -Force -Path $Out

$Orange = [Drawing.Color]::FromArgb(250, 149, 73)
$Dark   = [Drawing.Color]::FromArgb(38, 38, 43)
$Darker = [Drawing.Color]::FromArgb(26, 26, 30)
$Light  = [Drawing.Color]::FromArgb(242, 242, 242)
$Blue   = [Drawing.Color]::FromArgb(0, 85, 164)
$Red    = [Drawing.Color]::FromArgb(239, 65, 53)
$Font   = 'Segoe UI'

function New-Canvas { $b = New-Object Drawing.Bitmap 512, 512; $g = [Drawing.Graphics]::FromImage($b)
  $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'; $g.Clear([Drawing.Color]::Transparent); ,@($b, $g) }
function New-RoundRect([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
  $p = New-Object Drawing.Drawing2D.GraphicsPath
  $p.AddArc($x, $y, 2*$r, 2*$r, 180, 90); $p.AddArc($x+$w-2*$r, $y, 2*$r, 2*$r, 270, 90)
  $p.AddArc($x+$w-2*$r, $y+$h-2*$r, 2*$r, 2*$r, 0, 90); $p.AddArc($x, $y+$h-2*$r, 2*$r, 2*$r, 90, 90); $p.CloseFigure(); $p }
function Draw-Tricolor($g, [float]$x, [float]$y, [float]$w, [float]$h) {
  $third = $w / 3
  $g.FillRectangle((New-Object Drawing.SolidBrush $Blue),  $x,            $y, $third, $h)
  $g.FillRectangle((New-Object Drawing.SolidBrush $Light), $x + $third,   $y, $third, $h)
  $g.FillRectangle((New-Object Drawing.SolidBrush $Red),   $x + 2*$third, $y, $third, $h) }
function Draw-Text($g, [string]$text, [float]$size, [Drawing.Color]$color, [float]$cx, [float]$cy) {
  $f = New-Object Drawing.Font $Font, $size, ([Drawing.FontStyle]::Bold), ([Drawing.GraphicsUnit]::Pixel)
  $sf = New-Object Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
  $g.DrawString($text, $f, (New-Object Drawing.SolidBrush $color), (New-Object Drawing.RectangleF ($cx - 256), ($cy - 100), 512, 200), $sf) }
function Save($bmp, [string]$name) {
  $bmp.Save((Join-Path $Out "icon-$name-512.png"), [Drawing.Imaging.ImageFormat]::Png)
  Write-Host "  icon-$name" }

# ---------- A : onde vocale ----------
$c = New-Canvas; $b = $c[0]; $g = $c[1]
$g.FillPath((New-Object Drawing.SolidBrush $Dark), (New-RoundRect 8 8 496 496 72))
$heights = 60, 120, 200, 150, 250, 180, 110, 210, 140, 80, 40
$bw = 26; $gap = 12; $total = $heights.Count * $bw + ($heights.Count - 1) * $gap; $x0 = (512 - $total) / 2
for ($i = 0; $i -lt $heights.Count; $i++) {
  $h = $heights[$i]; $x = $x0 + $i * ($bw + $gap)
  $g.FillPath((New-Object Drawing.SolidBrush $Orange), (New-RoundRect $x (220 - $h/2) $bw $h 13)) }
Draw-Text $g 'FR' 120 $Light 256 400
Draw-Tricolor $g 176 462 160 14
Save $b 'A-onde'

# ---------- B : bulle de dialogue ----------
$c = New-Canvas; $b = $c[0]; $g = $c[1]
$g.FillPath((New-Object Drawing.SolidBrush $Orange), (New-RoundRect 8 8 496 496 72))
$bubble = New-RoundRect 70 90 372 270 60
$g.FillPath((New-Object Drawing.SolidBrush $Dark), $bubble)
$tail = New-Object Drawing.Drawing2D.GraphicsPath
$tail.AddPolygon([Drawing.PointF[]]@((New-Object Drawing.PointF 150, 350), (New-Object Drawing.PointF 250, 350), (New-Object Drawing.PointF 130, 440)))
$g.FillPath((New-Object Drawing.SolidBrush $Dark), $tail)
$pen = New-Object Drawing.Pen $Orange, 22; $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
foreach ($r in 45, 95, 145) { $g.DrawArc($pen, (180 - $r), (225 - $r), 2*$r, 2*$r, -50, 100) }
$g.FillEllipse((New-Object Drawing.SolidBrush $Orange), 162, 207, 36, 36)
Draw-Tricolor $g 330 400 132 60
Save $b 'B-bulle'

# ---------- C : panneau industriel ----------
$c = New-Canvas; $b = $c[0]; $g = $c[1]
$g.FillPath((New-Object Drawing.SolidBrush $Darker), (New-RoundRect 8 8 496 496 72))
$hex = New-Object Drawing.Drawing2D.GraphicsPath
$pts = 0..5 | ForEach-Object { $a = [Math]::PI / 3 * $_ - [Math]::PI / 2; New-Object Drawing.PointF (256 + 196 * [Math]::Cos($a)), (232 + 196 * [Math]::Sin($a)) }
$hex.AddPolygon([Drawing.PointF[]]$pts)
$g.FillPath((New-Object Drawing.SolidBrush $Dark), $hex)
$g.DrawPath((New-Object Drawing.Pen $Orange, 16), $hex)
Draw-Text $g 'IA' 150 $Orange 256 200
Draw-Text $g 'FR' 80 $Light 256 320
Draw-Tricolor $g 156 460 200 22
Save $b 'C-panneau'

# ======================== logo multilingue (2.0 : "FICSIT AI Voices (FR + packs)") ========================
$Grey = [Drawing.Color]::FromArgb(110, 110, 120)
function Draw-Wave($g, [float]$cy, [float]$scale, [Drawing.Color]$color) {
  $heights = 60, 120, 200, 150, 250, 180, 110, 210, 140, 80, 40
  $bw = 26 * $scale; $gap = 12 * $scale; $total = $heights.Count * $bw + ($heights.Count - 1) * $gap; $x0 = (512 - $total) / 2
  for ($i = 0; $i -lt $heights.Count; $i++) {
    $h = $heights[$i] * $scale; $x = $x0 + $i * ($bw + $gap)
    $g.FillPath((New-Object Drawing.SolidBrush $color), (New-RoundRect $x ($cy - $h/2) $bw $h (13 * $scale))) } }

# ---------- D : onde + "FR +" et pastilles de langues ----------
$c = New-Canvas; $b = $c[0]; $g = $c[1]
$g.FillPath((New-Object Drawing.SolidBrush $Dark), (New-RoundRect 8 8 496 496 72))
Draw-Wave $g 200 1 $Orange
Draw-Text $g 'FR +' 108 $Light 256 385
Draw-Tricolor $g 136 458 72 18
foreach ($i in 0..2) { $g.FillPath((New-Object Drawing.SolidBrush $Grey), (New-RoundRect (224 + $i * 52) 458 40 18 9)) }
Save $b 'D-onde-fr-plus'

# ---------- E : globe et onde ----------
$c = New-Canvas; $b = $c[0]; $g = $c[1]
$g.FillPath((New-Object Drawing.SolidBrush $Dark), (New-RoundRect 8 8 496 496 72))
$pen = New-Object Drawing.Pen $Grey, 10
$g.DrawEllipse($pen, 76, 66, 360, 360)
$g.DrawEllipse($pen, 186, 66, 140, 360)
$g.DrawLine($pen, 76, 246, 436, 246)
$g.DrawArc($pen, 96, 130, 320, 60, 0, -180); $g.DrawArc($pen, 96, 302, 320, 60, 0, 180)
Draw-Wave $g 246 0.8 $Orange
Draw-Tricolor $g 196 452 120 22
$g.FillPath((New-Object Drawing.SolidBrush $Orange), (New-RoundRect 330 448 30 30 15)); Draw-Text $g '+' 34 $Dark 345 461
Save $b 'E-globe'

# ---------- F : bulles superposees ----------
$c = New-Canvas; $b = $c[0]; $g = $c[1]
$g.FillPath((New-Object Drawing.SolidBrush $Dark), (New-RoundRect 8 8 496 496 72))
$back = New-RoundRect 210 70 250 190 46; $g.FillPath((New-Object Drawing.SolidBrush $Grey), $back)
Draw-Text $g '+' 110 $Dark 392 135
$front = New-RoundRect 52 170 300 230 54; $g.FillPath((New-Object Drawing.SolidBrush $Orange), $front)
$tail = New-Object Drawing.Drawing2D.GraphicsPath
$tail.AddPolygon([Drawing.PointF[]]@((New-Object Drawing.PointF 110, 390), (New-Object Drawing.PointF 190, 390), (New-Object Drawing.PointF 90, 462)))
$g.FillPath((New-Object Drawing.SolidBrush $Orange), $tail)
Draw-Text $g 'FR' 120 $Dark 202 280
Draw-Tricolor $g 300 440 150 26
Save $b 'F-bulles'

# ---------- generiques : onde au centre, petite touche francaise ----------
function Draw-FlagBadge($g, [float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
  # drapeau aux coins arrondis, entoure du fond pour se detacher de l'onde
  $g.FillPath((New-Object Drawing.SolidBrush $Dark), (New-RoundRect ($x - 8) ($y - 8) ($w + 16) ($h + 16) ($r + 8)))
  $clip = New-RoundRect $x $y $w $h $r
  $state = $g.Save(); $g.SetClip($clip); Draw-Tricolor $g $x $y $w $h; $g.Restore($state) }

# G : onde seule + rangee de "langues" (la premiere est le francais)
$c = New-Canvas; $b = $c[0]; $g = $c[1]
$g.FillPath((New-Object Drawing.SolidBrush $Dark), (New-RoundRect 8 8 496 496 72))
Draw-Wave $g 220 1.05 $Orange
$state = $g.Save(); $g.SetClip((New-RoundRect 96 420 64 40 12)); Draw-Tricolor $g 96 420 64 40; $g.Restore($state)   # puis 4 langues, 12 px d ecart
foreach ($i in 1..4) { $g.FillPath((New-Object Drawing.SolidBrush $Grey), (New-RoundRect (172 + ($i - 1) * 64) 420 52 40 12)) }
Save $b 'G-onde-langues'

# H : onde sur un globe discret + petit drapeau en coin
$c = New-Canvas; $b = $c[0]; $g = $c[1]
$g.FillPath((New-Object Drawing.SolidBrush $Dark), (New-RoundRect 8 8 496 496 72))
$faint = New-Object Drawing.Pen ([Drawing.Color]::FromArgb(90, 110, 110, 120)), 9
$g.DrawEllipse($faint, 66, 66, 380, 380); $g.DrawEllipse($faint, 181, 66, 150, 380); $g.DrawLine($faint, 66, 256, 446, 256)
$g.DrawArc($faint, 88, 128, 336, 64, 0, -180); $g.DrawArc($faint, 88, 320, 336, 64, 0, 180)
Draw-Wave $g 256 0.95 $Orange
Draw-FlagBadge $g 366 404 100 64 14
Save $b 'H-globe-discret'

# I : onde seule, pastille francaise en coin (comme une notification)
$c = New-Canvas; $b = $c[0]; $g = $c[1]
$g.FillPath((New-Object Drawing.SolidBrush $Dark), (New-RoundRect 8 8 496 496 72))
Draw-Wave $g 256 1.1 $Orange
Draw-FlagBadge $g 372 52 92 60 14
Save $b 'I-onde-pastille'

# ---------- avec le texte "FICSIT AI" (le nom seulement, pas le logo de Coffee Stain) ----------
# J : texte + onde + rangee de langues
$c = New-Canvas; $b = $c[0]; $g = $c[1]
$g.FillPath((New-Object Drawing.SolidBrush $Dark), (New-RoundRect 8 8 496 496 72))
Draw-Text $g 'FICSIT AI' 74 $Light 256 92
Draw-Wave $g 262 0.82 $Orange
$state = $g.Save(); $g.SetClip((New-RoundRect 96 420 64 40 12)); Draw-Tricolor $g 96 420 64 40; $g.Restore($state)
foreach ($i in 1..4) { $g.FillPath((New-Object Drawing.SolidBrush $Grey), (New-RoundRect (172 + ($i - 1) * 64) 420 52 40 12)) }
Save $b 'J-texte-langues'

# K : texte + onde + pastille francaise en coin
$c = New-Canvas; $b = $c[0]; $g = $c[1]
$g.FillPath((New-Object Drawing.SolidBrush $Dark), (New-RoundRect 8 8 496 496 72))
Draw-Wave $g 236 0.9 $Orange
Draw-Text $g 'FICSIT AI' 74 $Light 256 420
Draw-FlagBadge $g 384 46 84 54 12
Save $b 'K-texte-pastille'

# ---------- bulles : l'onde dans une bulle, "FICSIT AI" dans l'autre ----------
function Draw-Bubble($g, [float]$x, [float]$y, [float]$w, [float]$h, [float]$r, [Drawing.Color]$color, [bool]$tailLeft) {
  $g.FillPath((New-Object Drawing.SolidBrush $color), (New-RoundRect $x $y $w $h $r))
  $t = New-Object Drawing.Drawing2D.GraphicsPath
  if ($tailLeft) { $pts = @((New-Object Drawing.PointF ($x + 50), ($y + $h - 2)), (New-Object Drawing.PointF ($x + 120), ($y + $h - 2)), (New-Object Drawing.PointF ($x + 30), ($y + $h + 62))) }
  else { $pts = @((New-Object Drawing.PointF ($x + $w - 120), ($y + $h - 2)), (New-Object Drawing.PointF ($x + $w - 50), ($y + $h - 2)), (New-Object Drawing.PointF ($x + $w - 30), ($y + $h + 62))) }
  $t.AddPolygon([Drawing.PointF[]]$pts); $g.FillPath((New-Object Drawing.SolidBrush $color), $t) }
function Draw-WaveIn($g, [float]$cx, [float]$cy, [float]$scale, [Drawing.Color]$color) {
  $heights = 60, 120, 200, 150, 250, 180, 110, 210, 140, 80, 40
  $bw = 26 * $scale; $gap = 12 * $scale; $total = $heights.Count * $bw + ($heights.Count - 1) * $gap; $x0 = $cx - $total / 2
  for ($i = 0; $i -lt $heights.Count; $i++) {
    $h = $heights[$i] * $scale; $x = $x0 + $i * ($bw + $gap)
    $g.FillPath((New-Object Drawing.SolidBrush $color), (New-RoundRect $x ($cy - $h/2) $bw $h (13 * $scale))) } }

# L : bulle "FICSIT AI" (grise, derriere, en haut) et bulle orange avec l'onde (devant, en bas)
$c = New-Canvas; $b = $c[0]; $g = $c[1]
$g.FillPath((New-Object Drawing.SolidBrush $Dark), (New-RoundRect 8 8 496 496 72))
Draw-Bubble $g 150 44 310 132 40 $Grey $false
Draw-Text $g 'FICSIT AI' 56 $Light 305 112
Draw-Bubble $g 46 200 340 210 52 $Orange $true
Draw-WaveIn $g 216 305 0.66 $Dark
Draw-FlagBadge $g 392 420 76 48 11
Save $b 'L-bulles-onde'

# M : bulle orange "FICSIT AI" (devant, en haut) et bulle grise avec l'onde orange (derriere, en bas)
$c = New-Canvas; $b = $c[0]; $g = $c[1]
$g.FillPath((New-Object Drawing.SolidBrush $Dark), (New-RoundRect 8 8 496 496 72))
Draw-Bubble $g 126 196 340 210 52 $Grey $false
Draw-WaveIn $g 296 301 0.66 $Orange
Draw-Bubble $g 44 44 300 128 40 $Orange $true
Draw-Text $g 'FICSIT AI' 56 $Dark 194 110
Draw-FlagBadge $g 52 424 76 48 11
Save $b 'M-bulles-texte'
