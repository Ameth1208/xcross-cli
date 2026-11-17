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
    @{ Source = 'windows/ipa_inspect.py'; Dest = 'ipa_inspect.py' },
    @{ Source = 'windows/ipa_workflow.py'; Dest = 'ipa_workflow.py' },
    @{ Source = 'windows/xcross_ipa_bridge.dart'; Dest = 'xcross_ipa_bridge.dart' },
    @{ Source = 'windows/xcm.cmd'; Dest = 'xcm.cmd' },
    @{ Source = 'windows/start.cmd'; Dest = 'start.cmd' },
    @{ Source = 'windows/install.ps1'; Dest = 'install.ps1' },
    @{ Source = 'windows/uninstall.ps1'; Dest = 'uninstall.ps1' },
    @{ Source = 'linux/setup-flutter.sh'; Dest = 'setup-flutter.sh' },
    @{ Source = 'linux/linux-cli.sh'; Dest = 'linux-cli.sh' },
    @{ Source = 'assets/logo.svg'; Dest = 'logo.svg' },
    @{ Source = 'README.md'; Dest = 'README.md' },
    @{ Source = 'README.es.md'; Dest = 'README.es.md' },
    @{ Source = 'CHANGELOG.md'; Dest = 'CHANGELOG.md' }
)

New-Item -ItemType Directory -Path $target -Force | Out-Null
$stage = Join-Path ([IO.Path]::GetTempPath()) ('xcm-stage-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage | Out-Null
try {
foreach ($item in $files) {
    $src  = $item.Source
    $destName = $item.Dest
    $url  = "$base/$src"
    $dest = Join-Path $stage $destName
    Write-Host "Descargando $destName ..." -ForegroundColor DarkGray
    try {
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
    }
    catch {
        throw "No se pudo descargar $destName. Se conserva la instalacion anterior: $($_.Exception.Message)"
    }
}
$tokens = $null; $parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $stage 'windows-cli.ps1'), [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'El CLI descargado contiene errores de sintaxis; no se instalara.' }
foreach ($item in $files) { Copy-Item -LiteralPath (Join-Path $stage $item.Dest) -Destination (Join-Path $target $item.Dest) -Force }
}
finally {
    $resolvedStage = [IO.Path]::GetFullPath($stage)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($resolvedStage.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolvedStage) -like 'xcm-stage-*') {
        Remove-Item -LiteralPath $resolvedStage -Recurse -Force -ErrorAction SilentlyContinue
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
