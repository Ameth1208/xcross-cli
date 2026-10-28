#Requires -Version 5.1
<#
.SYNOPSIS
  Remote installer for XCross CLI on Windows.
.DESCRIPTION
  Downloads the latest files from GitHub and installs xcm globally.
  Usage (PowerShell):
    irm https://raw.githubusercontent.com/Ameth1208/xcross-cli/main/windows/xcm-install.ps1 | iex
#>
$ErrorActionPreference = 'Stop'

$repo   = 'Ameth1208/xcross-cli'
$branch = 'main'
$base   = "https://raw.githubusercontent.com/$repo/$branch"
$target = Join-Path $env:LOCALAPPDATA 'Programs\XCrossCLI'

$files = @(
    @{ Source = 'windows/windows-cli.ps1'; Dest = 'windows-cli.ps1' },
    @{ Source = 'windows/xcm.cmd'; Dest = 'xcm.cmd' },
    @{ Source = 'windows/start.cmd'; Dest = 'start.cmd' },
    @{ Source = 'windows/install.ps1'; Dest = 'install.ps1' },
    @{ Source = 'windows/uninstall.ps1'; Dest = 'uninstall.ps1' },
    @{ Source = 'linux/setup-flutter.sh'; Dest = 'setup-flutter.sh' },
    @{ Source = 'linux/linux-cli.sh'; Dest = 'linux-cli.sh' },
    @{ Source = 'assets/logo.svg'; Dest = 'logo.svg' },
    @{ Source = 'README.md'; Dest = 'README.md' }
)

New-Item -ItemType Directory -Path $target -Force | Out-Null
foreach ($item in $files) {
    $src  = $item.Source
    $destName = $item.Dest
    $url  = "$base/$src"
    $dest = Join-Path $target $destName
    Write-Host "Descargando $destName ..." -ForegroundColor DarkGray
    try {
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
    }
    catch {
        Write-Warning "No se pudo descargar $destName : $($_.Exception.Message)"
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
