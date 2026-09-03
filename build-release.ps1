[CmdletBinding()]
param(
    [string]$OutputDirectory = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$modRoot = $PSScriptRoot
$infoPath = Join-Path $modRoot 'info.json'
if (-not (Test-Path -LiteralPath $infoPath -PathType Leaf)) {
    throw "Missing required mod metadata: $infoPath"
}

$info = Get-Content -LiteralPath $infoPath -Raw | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($info.name) -or [string]::IsNullOrWhiteSpace($info.version)) {
    throw 'info.json must contain non-empty name and version properties.'
}

$packageName = '{0}_{1}' -f $info.name, $info.version
$outputDirectoryPath = [System.IO.Path]::GetFullPath($OutputDirectory)
$zipPath = Join-Path $outputDirectoryPath "$packageName.zip"

$includedFiles = @(
    'info.json'
    'control.lua'
    'data.lua'
    'data-final-fixes.lua'
    'poc.lua'
    'changelog.txt'
    'README.md'
    'thumbnail.png'
    'banner.png'
)
$includedDirectories = @(
    'graphics'
    'lib'
    'locale'
)

$files = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
foreach ($relativePath in $includedFiles) {
    $path = Join-Path $modRoot $relativePath
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $files.Add((Get-Item -LiteralPath $path))
    }
}

foreach ($relativePath in $includedDirectories) {
    $path = Join-Path $modRoot $relativePath
    if (Test-Path -LiteralPath $path -PathType Container) {
        foreach ($file in Get-ChildItem -LiteralPath $path -File -Recurse) {
            $files.Add($file)
        }
    }
}

foreach ($requiredFile in @('info.json', 'control.lua')) {
    if (-not $files.FullName.Contains((Join-Path $modRoot $requiredFile))) {
        throw "Missing required mod file: $requiredFile"
    }
}

New-Item -ItemType Directory -Path $outputDirectoryPath -Force | Out-Null
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$archive = [System.IO.Compression.ZipFile]::Open(
    $zipPath,
    [System.IO.Compression.ZipArchiveMode]::Create
)
try {
    foreach ($file in ($files | Sort-Object FullName -Unique)) {
        $relativePath = $file.FullName.Substring($modRoot.Length).TrimStart('\', '/')
        $entryName = "$packageName/$($relativePath.Replace('\', '/'))"
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $archive,
            $file.FullName,
            $entryName,
            [System.IO.Compression.CompressionLevel]::Optimal
        ) | Out-Null
    }
}
finally {
    $archive.Dispose()
}

$archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    $entryNames = @($archive.Entries | ForEach-Object FullName)
    $expectedInfoPath = "$packageName/info.json"
    $invalidEntries = @($entryNames | Where-Object {
        $_ -match '\\' -or -not $_.StartsWith("$packageName/")
    })
    $duplicates = @($entryNames | Group-Object | Where-Object Count -gt 1)

    if ($expectedInfoPath -notin $entryNames) {
        throw "Archive does not contain $expectedInfoPath."
    }
    if ($invalidEntries.Count -gt 0) {
        throw "Archive contains invalid entry paths: $($invalidEntries -join ', ')"
    }
    if ($duplicates.Count -gt 0) {
        throw "Archive contains duplicate entries: $($duplicates.Name -join ', ')"
    }
    if ($entryNames.Count -eq 0) {
        throw 'Archive contains no files.'
    }
}
finally {
    $archive.Dispose()
}

$zip = Get-Item -LiteralPath $zipPath
Write-Host "Built $($zip.FullName)"
Write-Host "Package: $packageName"
Write-Host "Files: $($entryNames.Count)"
Write-Host "Size: $($zip.Length) bytes"
Write-Host 'Validation: passed'