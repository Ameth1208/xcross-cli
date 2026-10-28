#requires -Version 5.1
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Solo disponible para Windows.' }
$target = Join-Path $env:LOCALAPPDATA 'Programs\XCrossCLI'
$source = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not (Test-Path -LiteralPath (Join-Path $source 'windows-cli.ps1'))) {
    throw 'No se encontro windows-cli.ps1 junto al instalador.'
}
New-Item -ItemType Directory -Path $target -Force | Out-Null
foreach($file in @('windows-cli.ps1','xcm.cmd','start.cmd','install.ps1','uninstall.ps1')) {
    $srcFile = Join-Path $source $file
    $dstFile = Join-Path $target $file
    if ($srcFile -ine $dstFile) { Copy-Item -LiteralPath $srcFile -Destination $dstFile -Force }
}
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$parts = @($userPath -split ';' | Where-Object { $_ -and $_.Trim() })
$alreadyPresent = @($parts | Where-Object { $_.TrimEnd('\') -ieq $target.TrimEnd('\') }).Count -gt 0
if (-not $alreadyPresent) {
    $parts += $target
    [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')
    Write-Host 'Se agrego xcm al PATH de usuario.' -ForegroundColor Green
}
else { Write-Host 'xcm ya estaba registrado en PATH.' -ForegroundColor Cyan }
if (($env:PATH -split ';') -notcontains $target) { $env:PATH += ";$target" }
Write-Host "Instalado en: $target" -ForegroundColor Green
Write-Host 'Abre una nueva ventana PowerShell para usar: xcm help' -ForegroundColor Cyan
Write-Host 'Para eliminarlo, usa Desinstalar-Comando-XCM.ps1 desde este paquete.' -ForegroundColor DarkGray
