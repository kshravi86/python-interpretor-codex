<#
.SYNOPSIS
  Prepare App Store screenshots by scaling and padding images to exact device sizes.

.DESCRIPTION
  Reads all PNG/JPG images from a source folder (default: attachments) and produces
  two output sets with exact App Store sizes:
    - iPhone 6.7": 1290 x 2796 (portrait)
    - iPhone 6.5": 1242 x 2688 (portrait)

  Images are scaled to fit while preserving aspect ratio, then centered and padded
  with a background color (default: white) to match the exact target dimensions.

.PARAMETER Source
  Input folder containing your raw screenshots (default: attachments)

.PARAMETER Out67
  Output folder for 6.7" images (default: attachments\export-6p7)

.PARAMETER Out65
  Output folder for 6.5" images (default: attachments\export-6p5)

.PARAMETER Background
  Background color used for padding (hex like #FFFFFF). Default: #FFFFFF

.EXAMPLE
  pwsh -File scripts/prepare_app_store_screenshots.ps1

.EXAMPLE
  pwsh -File scripts/prepare_app_store_screenshots.ps1 -Source attachments -Background "#E6F4FF"
#>

param(
  [string]$Source = "attachments",
  [string]$Out67 = "attachments\export-6p7",
  [string]$Out65 = "attachments\export-6p5",
  [string]$Background = "#FFFFFF"
)

$ErrorActionPreference = 'Stop'

function Resolve-PathSmart {
  param([string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
  $scriptDir = Split-Path -Parent $PSCommandPath
  $cwd = (Get-Location).Path
  $scriptCandidate = Join-Path $scriptDir $Path
  $cwdCandidate = Join-Path $cwd $Path
  if (Test-Path $scriptCandidate) { return (Resolve-Path $scriptCandidate).Path }
  if (Test-Path $cwdCandidate)    { return (Resolve-Path $cwdCandidate).Path }
  # Default to CWD candidate so subsequent creation occurs there
  return $cwdCandidate
}

# Normalize paths; prefer existing under script dir, else CWD
$Source = Resolve-PathSmart $Source
$Out67  = Resolve-PathSmart $Out67
$Out65  = Resolve-PathSmart $Out65

function Convert-HexToColor {
  param([string]$Hex)
  $h = $Hex.Trim()
  if ($h.StartsWith('#')) { $h = $h.Substring(1) }
  if ($h.Length -eq 3) { $h = "$($h[0])$($h[0])$($h[1])$($h[1])$($h[2])$($h[2])" }
  if ($h.Length -ne 6) { throw "Invalid hex color: $Hex" }
  $r = [Convert]::ToInt32($h.Substring(0,2),16)
  $g = [Convert]::ToInt32($h.Substring(2,2),16)
  $b = [Convert]::ToInt32($h.Substring(4,2),16)
  return [System.Drawing.Color]::FromArgb($r,$g,$b)
}

function Resize-Pad {
  param(
    [string]$InPath,
    [string]$OutPath,
    [int]$TargetW,
    [int]$TargetH,
    [System.Drawing.Color]$Bg
  )
  $img = [System.Drawing.Image]::FromFile($InPath)
  try {
    $scale = [Math]::Min($TargetW / $img.Width, $TargetH / $img.Height)
    $newW = [int][Math]::Round($img.Width * $scale)
    $newH = [int][Math]::Round($img.Height * $scale)
    $bmp = New-Object System.Drawing.Bitmap($TargetW, $TargetH)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
      $g.Clear($Bg)
      $g.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::HighQuality
      $g.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
      $g.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
      $x = [int](($TargetW - $newW) / 2)
      $y = [int](($TargetH - $newH) / 2)
      $g.DrawImage($img, $x, $y, $newW, $newH)
    } finally {
      $g.Dispose()
    }
    $dir = Split-Path -Parent $OutPath
    if (!(Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    # Save via FileStream to avoid intermittent GDI+ generic errors
    $fs = [System.IO.File]::Open($OutPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try {
      $bmp.Save($fs, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
      $fs.Dispose()
    }
  } finally {
    $img.Dispose()
    if ($bmp) { $bmp.Dispose() }
  }
}

Write-Host "Preparing App Store screenshots..." -ForegroundColor Cyan
Write-Host " Source:    $Source"
Write-Host " Output 6.7: $Out67 (1290x2796)"
Write-Host " Output 6.5: $Out65 (1242x2688)"
Write-Host " Background: $Background"

if (!(Test-Path $Source)) { throw "Source folder not found: $Source" }

Add-Type -AssemblyName System.Drawing
$bgColor = Convert-HexToColor $Background

$images = Get-ChildItem -File $Source -Include *.png,*.jpg,*.jpeg -Recurse
if ($images.Count -eq 0) { Write-Warning "No images found in $Source"; exit 0 }

$processed = 0
foreach ($img in $images) {
  $name = $img.Name
  $outFile67 = Join-Path $Out67 $name
  $outFile65 = Join-Path $Out65 $name
  Write-Host "Processing $name..." -ForegroundColor Green
  # 6.7" (1284 x 2778) and 6.5" (1242 x 2688)
  Resize-Pad -InPath $img.FullName -OutPath $outFile67 -TargetW 1284 -TargetH 2778 -Bg $bgColor
  Resize-Pad -InPath $img.FullName -OutPath $outFile65 -TargetW 1242 -TargetH 2688 -Bg $bgColor
  $processed++
}

Write-Host "Done. Processed $processed image(s)." -ForegroundColor Cyan
Write-Host " Outputs:"
Write-Host "  - $Out67 (6.7-inch)"
Write-Host "  - $Out65 (6.5-inch)"
