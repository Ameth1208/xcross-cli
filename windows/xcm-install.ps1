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
    @{ Source = 'windows/xtool_workflow.py'; Dest = 'xtool_workflow.py' },
    @{ Source = 'windows/xtool-usb.ps1'; Dest = 'xtool-usb.ps1' },
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
# Pin every file to one commit, even if main changes during the download.
$commit = (Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/commits/$branch" -Headers @{ 'User-Agent' = 'XCrossCLI' }).sha
if ($commit -notmatch '^[a-f0-9]{40}$') { throw 'No se pudo resolver la version del paquete.' }
$base = "https://raw.githubusercontent.com/$repo/$commit"
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
foreach ($item in $files) {
    $file = Join-Path $stage $item.Dest
    if ((Get-Item -LiteralPath $file).Length -eq 0) { throw "Archivo vacio: $($item.Dest)" }
    if ([IO.Path]::GetExtension($file) -eq '.ps1') {
        $tokens = $null; $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count) { throw "Errores de sintaxis: $($item.Dest)" }
    }
}
$backup = Join-Path $stage 'backup'
New-Item -ItemType Directory -Path $backup | Out-Null
$applied = @()
try {
    foreach ($item in $files) {
        $destination = Join-Path $target $item.Dest
        if (Test-Path -LiteralPath $destination) { Copy-Item -LiteralPath $destination -Destination (Join-Path $backup $item.Dest) }
        $applied += $item.Dest
        Copy-Item -LiteralPath (Join-Path $stage $item.Dest) -Destination $destination -Force
    }
}
catch {
    foreach ($name in $applied) {
        $old = Join-Path $backup $name
        $destination = Join-Path $target $name
        if (Test-Path -LiteralPath $old) { Copy-Item -LiteralPath $old -Destination $destination -Force }
        elseif (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Force }
    }
    throw
}
Write-Host "Version de origen: $commit" -ForegroundColor DarkGray
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
