# Renders image-builder/thumbnail.html to thumbnail.png at full resolution
# using headless Edge, then copies it to the mod root.
# Usage: powershell -File image-builder\build.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$edge = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
if (-not (Test-Path $edge)) { $edge = "C:\Program Files\Microsoft\Edge\Application\msedge.exe" }
$html = Join-Path $PSScriptRoot 'thumbnail.html'
$out = Join-Path $PSScriptRoot 'thumbnail.png'

# Edge writes its status line to stderr; don't let that abort the script.
$ErrorActionPreference = 'Continue'
& $edge --headless --disable-gpu --hide-scrollbars `
  --window-size=1152,768 --screenshot="$out" "file:///$($html -replace '\\','/')" 2>&1 | Out-Null
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $out)) { throw 'Screenshot failed' }

Copy-Item $out (Join-Path $root 'thumbnail.png') -Force
Write-Host "Rendered $out -> $root\thumbnail.png"
