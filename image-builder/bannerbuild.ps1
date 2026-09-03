# Renders image-builder/banner.html to banner.png at full resolution
# using headless Edge, then copies it to the mod root.
# Usage: powershell -File image-builder\build.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$edge = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
if (-not (Test-Path $edge)) { $edge = "C:\Program Files\Microsoft\Edge\Application\msedge.exe" }
$html = Join-Path $PSScriptRoot 'banner.html'
$out = Join-Path $PSScriptRoot 'banner.png'
# Reused by edit.ps1 so dragged positions/scales in localStorage survive into the render.
$profileDir = Join-Path $PSScriptRoot '.edge-profile'

# Edge writes its status line to stderr; don't let that abort the script.
$ErrorActionPreference = 'Continue'
& $edge --headless --disable-gpu --hide-scrollbars `
  --user-data-dir="$profileDir" --profile-directory=Default `
  --window-size=1152,768 --screenshot="$out" "file:///$($html -replace '\\','/')" 2>&1 | Out-Null
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $out)) { throw 'Screenshot failed' }

Copy-Item $out (Join-Path $root 'banner.png') -Force
Write-Host "Rendered $out -> $root\banner.png"
