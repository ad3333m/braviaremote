# Draws the 1024px iOS AppIcon: a frosted glass remote on graphite.
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
$s = 1024
$bmp = New-Object System.Drawing.Bitmap $s, $s
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'
$rect = New-Object System.Drawing.RectangleF 0, 0, $s, $s
$bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, ([System.Drawing.Color]::FromArgb(58, 61, 70)), ([System.Drawing.Color]::FromArgb(14, 15, 18)), 90
$g.FillRectangle($bg, $rect)

function Glow([float]$x, [float]$y, [float]$w, [float]$h, [int]$alpha) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $p.AddEllipse($x, $y, $w, $h)
    $b = New-Object System.Drawing.Drawing2D.PathGradientBrush $p
    $b.CenterColor = [System.Drawing.Color]::FromArgb($alpha, 255, 255, 255)
    $b.SurroundColors = @([System.Drawing.Color]::FromArgb(0, 255, 255, 255))
    $g.FillPath($b, $p)
}
Glow -260 -520 1200 1000 46

function RoundRect([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $p.AddArc($x, $y, 2 * $r, 2 * $r, 180, 90)
    $p.AddArc($x + $w - 2 * $r, $y, 2 * $r, 2 * $r, 270, 90)
    $p.AddArc($x + $w - 2 * $r, $y + $h - 2 * $r, 2 * $r, 2 * $r, 0, 90)
    $p.AddArc($x, $y + $h - 2 * $r, 2 * $r, 2 * $r, 90, 90)
    $p.CloseFigure()
    $p
}

# remote body: frosted glass slab with a bright rim
$body = RoundRect 322 150 380 724 150
$fill = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.RectangleF 322, 150, 380, 724), ([System.Drawing.Color]::FromArgb(70, 255, 255, 255)), ([System.Drawing.Color]::FromArgb(22, 255, 255, 255)), 90
$g.FillPath($fill, $body)
$rim = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.RectangleF 322, 150, 380, 724), ([System.Drawing.Color]::FromArgb(230, 255, 255, 255)), ([System.Drawing.Color]::FromArgb(70, 255, 255, 255)), 90
$g.DrawPath((New-Object System.Drawing.Pen $rim, 10), $body)

# d-pad ring and OK button
$white = [System.Drawing.Color]::White
$g.DrawEllipse((New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(235, 255, 255, 255)), 22), 387, 245, 250, 250)
$g.FillEllipse((New-Object System.Drawing.SolidBrush $white), 462, 320, 100, 100)

# four buttons below the d-pad
$soft = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(200, 255, 255, 255))
$g.FillEllipse($soft, 402, 560, 74, 74)
$g.FillEllipse($soft, 548, 560, 74, 74)
$g.FillEllipse($soft, 402, 690, 74, 74)
$g.FillEllipse($soft, 548, 690, 74, 74)
$g.Dispose()

$bmp.Save((Join-Path $root 'ios\Assets.xcassets\AppIcon.appiconset\icon-1024.png'), [System.Drawing.Imaging.ImageFormat]::Png)
