Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap(256, 256)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

# Background circle
$brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(20, 25, 40))
$g.FillEllipse($brush, 10, 10, 236, 236)

# Cyan/Teal accent ring
$pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(0, 180, 255), 16)
$g.DrawArc($pen, 35, 35, 186, 186, 45, 270)

# "B" text in center
$font = New-Object System.Drawing.Font("Segoe UI", 90, [System.Drawing.FontStyle]::Bold)
$textBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0, 220, 255))
$sf = New-Object System.Drawing.StringFormat
$sf.Alignment = [System.Drawing.StringAlignment]::Center
$sf.LineAlignment = [System.Drawing.StringAlignment]::Center
$g.DrawString("B", $font, $textBrush, [System.Drawing.RectangleF]::FromLTRB(0, 0, 256, 256), $sf)

$g.Dispose()

# Save as ICO
$iconHandle = $bmp.GetHicon()
$icon = [System.Drawing.Icon]::FromHandle($iconHandle)
$fs = New-Object System.IO.FileStream("C:\DualBoot\bazzite.ico", [System.IO.FileMode]::Create)
$icon.Save($fs)
$fs.Close()
$bmp.Dispose()
Write-Host "Created C:\DualBoot\bazzite.ico cleanly."
