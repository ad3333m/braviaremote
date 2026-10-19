# Draws the 1024px iOS AppIcon: a TV with a play mark on an indigo-to-cyan gradient.
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
$s = 1024
$bmp = New-Object System.Drawing.Bitmap $s, $s
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'
$rect = New-Object System.Drawing.RectangleF 0, 0, $s, $s
$bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, ([System.Drawing.Color]::FromArgb(91, 76, 242)), ([System.Drawing.Color]::FromArgb(18, 184, 219)), 45
$g.FillRectangle($bg, $rect)

# soft highlight, like light on glass
$glow = New-Object System.Drawing.Drawing2D.GraphicsPath
$glow.AddEllipse(-200, -420, 1100, 900)
$pgb = New-Object System.Drawing.Drawing2D.PathGradientBrush $glow
$pgb.CenterColor = [System.Drawing.Color]::FromArgb(70, 255, 255, 255)
$pgb.SurroundColors = @([System.Drawing.Color]::FromArgb(0, 255, 255, 255))
$g.FillPath($pgb, $glow)

function RoundRect([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $p.AddArc($x, $y, 2 * $r, 2 * $r, 180, 90)
    $p.AddArc($x + $w - 2 * $r, $y, 2 * $r, 2 * $r, 270, 90)
    $p.AddArc($x + $w - 2 * $r, $y + $h - 2 * $r, 2 * $r, 2 * $r, 0, 90)
    $p.AddArc($x, $y + $h - 2 * $r, 2 * $r, 2 * $r, 90, 90)
    $p.CloseFigure()
    $p
}

# TV: frosted screen, white rim, stand
$screen = RoundRect 192 262 640 400 56
$g.FillPath((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(60, 255, 255, 255))), $screen)
$pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 40
$pen.LineJoin = 'Round'; $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
$g.DrawPath($pen, $screen)
$g.DrawLine($pen, 512, 682, 512, 742)
$g.DrawLine($pen, 392, 762, 632, 762)

# play mark
$tri = [System.Drawing.PointF[]]@((New-Object System.Drawing.PointF 462, 380), (New-Object System.Drawing.PointF 462, 544), (New-Object System.Drawing.PointF 592, 462))
$g.FillPolygon([System.Drawing.Brushes]::White, $tri)
$g.Dispose()

$bmp.Save((Join-Path $root 'ios\Assets.xcassets\AppIcon.appiconset\icon-1024.png'), [System.Drawing.Imaging.ImageFormat]::Png)
