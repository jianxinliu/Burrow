param(
    [string]$SourceIcon,
    [string]$OutputDir
)

$ErrorActionPreference = "Stop"

$windowsRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent $windowsRoot

if ([string]::IsNullOrWhiteSpace($SourceIcon)) {
    $SourceIcon = Join-Path $repoRoot "brand\app-icon.png"
}

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $windowsRoot "Assets"
}

$brandFontsDir = Join-Path $repoRoot "brand\fonts"
$assetFontsDir = Join-Path $OutputDir "Fonts"

if (-not (Test-Path -LiteralPath $SourceIcon)) {
    throw "Source icon not found: $SourceIcon"
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
New-Item -ItemType Directory -Force -Path $assetFontsDir | Out-Null

if (Test-Path -LiteralPath $brandFontsDir) {
    Get-ChildItem -LiteralPath $brandFontsDir -Filter *.woff2 |
        Copy-Item -Destination $assetFontsDir -Force
}

Add-Type -AssemblyName System.Drawing

function New-ScaledBitmap {
    param(
        [System.Drawing.Image]$Source,
        [int]$Width,
        [int]$Height,
        [bool]$Transparent,
        [int]$IconPercent
    )

    $bitmap = [System.Drawing.Bitmap]::new($Width, $Height)
    $bitmap.SetResolution(96, 96)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality

    if ($Transparent) {
        $graphics.Clear([System.Drawing.Color]::Transparent)
    }
    else {
        $graphics.Clear([System.Drawing.ColorTranslator]::FromHtml("#121217"))
    }

    $maxWidth = [Math]::Max(1, [int]($Width * $IconPercent / 100))
    $maxHeight = [Math]::Max(1, [int]($Height * $IconPercent / 100))
    $scale = [Math]::Min($maxWidth / $Source.Width, $maxHeight / $Source.Height)
    $drawWidth = [Math]::Max(1, [int]($Source.Width * $scale))
    $drawHeight = [Math]::Max(1, [int]($Source.Height * $scale))
    $x = [int](($Width - $drawWidth) / 2)
    $y = [int](($Height - $drawHeight) / 2)
    $graphics.DrawImage($Source, $x, $y, $drawWidth, $drawHeight)
    $graphics.Dispose()
    return $bitmap
}

function Save-PngAsset {
    param(
        [System.Drawing.Image]$Source,
        [string]$Name,
        [int]$Width,
        [int]$Height,
        [bool]$Transparent = $true,
        [int]$IconPercent = 100
    )

    $path = Join-Path $OutputDir $Name
    $bitmap = New-ScaledBitmap -Source $Source -Width $Width -Height $Height -Transparent $Transparent -IconPercent $IconPercent
    try {
        $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $bitmap.Dispose()
    }
}

function Get-PngBytes {
    param(
        [System.Drawing.Image]$Source,
        [int]$Size
    )

    $bitmap = New-ScaledBitmap -Source $Source -Width $Size -Height $Size -Transparent $true -IconPercent 100
    $stream = [System.IO.MemoryStream]::new()
    try {
        $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
        return $stream.ToArray()
    }
    finally {
        $stream.Dispose()
        $bitmap.Dispose()
    }
}

function Write-Ico {
    param(
        [System.Drawing.Image]$Source,
        [string]$Path,
        [int[]]$Sizes
    )

    $images = foreach ($size in $Sizes) {
        [PSCustomObject]@{
            Size = $size
            Bytes = Get-PngBytes -Source $Source -Size $size
        }
    }

    $stream = [System.IO.File]::Create($Path)
    $writer = [System.IO.BinaryWriter]::new($stream)
    try {
        $writer.Write([UInt16]0)
        $writer.Write([UInt16]1)
        $writer.Write([UInt16]$images.Count)

        $offset = 6 + (16 * $images.Count)
        foreach ($image in $images) {
            $dimension = if ($image.Size -ge 256) { 0 } else { $image.Size }
            $writer.Write([byte]$dimension)
            $writer.Write([byte]$dimension)
            $writer.Write([byte]0)
            $writer.Write([byte]0)
            $writer.Write([UInt16]1)
            $writer.Write([UInt16]32)
            $writer.Write([UInt32]$image.Bytes.Length)
            $writer.Write([UInt32]$offset)
            $offset += $image.Bytes.Length
        }

        foreach ($image in $images) {
            $writer.Write([byte[]]$image.Bytes)
        }
    }
    finally {
        $writer.Dispose()
        $stream.Dispose()
    }
}

$source = [System.Drawing.Image]::FromFile((Resolve-Path -LiteralPath $SourceIcon).Path)
try {
    Save-PngAsset -Source $source -Name "Square44x44Logo.scale-200.png" -Width 88 -Height 88
    Save-PngAsset -Source $source -Name "Square44x44Logo.targetsize-24_altform-unplated.png" -Width 24 -Height 24
    Save-PngAsset -Source $source -Name "Square44x44Logo.targetsize-48_altform-lightunplated.png" -Width 48 -Height 48
    Save-PngAsset -Source $source -Name "LockScreenLogo.scale-200.png" -Width 48 -Height 48
    Save-PngAsset -Source $source -Name "StoreLogo.png" -Width 50 -Height 50
    Save-PngAsset -Source $source -Name "Square150x150Logo.scale-200.png" -Width 300 -Height 300
    Save-PngAsset -Source $source -Name "Wide310x150Logo.scale-200.png" -Width 620 -Height 300 -Transparent $false -IconPercent 42
    Save-PngAsset -Source $source -Name "SplashScreen.scale-200.png" -Width 1240 -Height 600 -Transparent $false -IconPercent 28
    Write-Ico -Source $source -Path (Join-Path $OutputDir "AppIcon.ico") -Sizes @(16, 24, 32, 48, 64, 128, 256)
}
finally {
    $source.Dispose()
}

Write-Host "Generated Windows brand assets in $OutputDir"
