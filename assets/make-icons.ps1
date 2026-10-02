<#
  Dessine les propositions d'icone du mod (512x512 pour ficsit.app, 128x128 pour le jeu).
  Couleurs de FICSIT (orange / anthracite) + touche tricolore ; pas de logo du jeu (marque de Coffee Stain).

  Usage : powershell -ExecutionPolicy Bypass -File assets\make-icons.ps1
  Sortie : assets\icons\icon-<variante>-512.png et -128.png
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
  $small = New-Object Drawing.Bitmap 128, 128; $gs = [Drawing.Graphics]::FromImage($small)
  $gs.InterpolationMode = 'HighQualityBicubic'; $gs.SmoothingMode = 'AntiAlias'; $gs.PixelOffsetMode = 'HighQuality'
  $gs.DrawImage($bmp, 0, 0, 128, 128); $small.Save((Join-Path $Out "icon-$name-128.png"), [Drawing.Imaging.ImageFormat]::Png)
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
