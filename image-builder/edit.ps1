# Opens banner.html and thumbnail.html in a normal (non-headless) Edge window
# using the same persistent profile the render scripts read from, so dragged
# positions/scales saved to localStorage are picked up by bannerbuild.ps1 and
# thumbnailbuild.ps1.
# Usage: powershell -File image-builder\edit.ps1
$ErrorActionPreference = 'Stop'
$edge = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
if (-not (Test-Path $edge)) { $edge = "C:\Program Files\Microsoft\Edge\Application\msedge.exe" }
$profileDir = Join-Path $PSScriptRoot '.edge-profile'
$banner = Join-Path $PSScriptRoot 'banner.html'
$thumbnail = Join-Path $PSScriptRoot 'thumbnail.html'

& $edge --user-data-dir="$profileDir" --profile-directory=Default `
  "file:///$($banner -replace '\\','/')" `
  "file:///$($thumbnail -replace '\\','/')"
