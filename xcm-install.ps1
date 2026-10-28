#Requires -Version 5.1
<#
.SYNOPSIS
  Remote installer for XCross CLI on Windows.
.DESCRIPTION
  Downloads the latest files from GitHub and installs xcm globally.
  Usage (PowerShell):
    irm https://raw.githubusercontent.com/Ameth1208/xcross-cli/main/xcm-install.ps1 | iex
#>
$ErrorActionPreference = 'Stop'

$repo   = 'Ameth1208/xcross-cli'
$branch = 'main'
$base   = "https://raw.githubusercontent.com/$repo/$branch"
$target = Join-Path $env:LOCALAPPDATA 'Programs\XCrossCLI'

$files = @(
    'windows-cli.ps1',
    'xcm.cmd',
    'start.cmd',
    'install.ps1',
    'uninstall.ps1',
    'setup-flutter.sh',
    'linux-cli.sh',
    'logo.svg',
    'README.md'
)

New-Item -ItemType Directory -Path $target -Force | Out-Null
foreach ($f in $files) {
    $url  = "$base/$f"
    $dest = Join-Path $target $f
    Write-Host "Descargando $f ..." -ForegroundColor DarkGray
    try {
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
    }
    catch {
        Write-Warning "No se pudo descargar $f : $($_.Exception.Message)"
    }
}

# Add to user PATH
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$parts = @($userPath -split ';' | Where-Object { $_ -and $_.Trim() })
$already = @($parts | Where-Object { $_.TrimEnd('\') -ieq $target.TrimEnd('\') }).Count -gt 0
if (-not $already) {
    $parts += $target
    [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')
    Write-Host 'Se agrego xcm al PATH de usuario.' -ForegroundColor Green
}
else { Write-Host 'xcm ya estaba en PATH.' -ForegroundColor Cyan }

if (($env:PATH -split ';') -notcontains $target) { $env:PATH += ";$target" }
Write-Host "Instalado en: $target" -ForegroundColor Green
Write-Host 'Abre una nueva terminal y usa: xcm help' -ForegroundColor Cyan
Write-Host 'O ejecuta directamente: start.cmd' -ForegroundColor DarkGray
