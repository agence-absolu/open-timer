#!/usr/bin/env pwsh
# Compile OpenTimer pour Windows et produit un exécutable unique autonome dans dist/.
# Pendant de macos/build.sh.
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$project = 'src/OpenTimer.Windows/OpenTimer.Windows.csproj'
$out = 'dist'

Write-Host '▸ Publication release…'
dotnet publish $project -c Release -o $out

$exe = Join-Path $out 'OpenTimer.exe'
if (-not (Test-Path $exe)) { throw "Exécutable introuvable : $exe" }

$size = [math]::Round((Get-Item $exe).Length / 1MB, 1)
Write-Host ''
Write-Host "✓ $exe prêt ($size Mo)."
Write-Host "  Lance-le :   .\$exe"
