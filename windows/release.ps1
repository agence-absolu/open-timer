#!/usr/bin/env pwsh
# Construit l'app, la zippe pour distribution et calcule le sha256 (manifeste Scoop).
# Pendant de macos/release.sh.
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$project = 'src/OpenTimer.Windows/OpenTimer.Windows.csproj'

# Version lue depuis le csproj (source de vérité, pendant du CFBundleShortVersionString).
$version = ([xml](Get-Content $project)).Project.PropertyGroup.Version | Where-Object { $_ }
if (-not $version) { throw "Aucune <Version> trouvée dans $project" }

$zip = "OpenTimer-$version-win-x64.zip"

Write-Host '▸ Build…'
./build.ps1 | Out-Null

Write-Host "▸ Compression de dist/ -> $zip…"
Remove-Item $zip -ErrorAction SilentlyContinue
Compress-Archive -Path 'dist/*' -DestinationPath $zip

$sha = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
$size = [math]::Round((Get-Item $zip).Length / 1MB, 1)

Write-Host ''
Write-Host "✓ Artefact : $zip  ($size Mo)"
Write-Host "  version  : $version"
Write-Host "  sha256   : $sha"
Write-Host ''
Write-Host '── À reporter dans le manifeste Scoop (bucket/opentimer.json) ──'
Write-Host "  `"version`": `"$version`","
Write-Host "  `"hash`": `"$sha`""
Write-Host ''
Write-Host "Puis : créer une release GitHub taggée windows-v$version et y joindre $zip."
