#requires -Version 5.1
$ErrorActionPreference='Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Solo disponible para Windows.' }
$target=Join-Path $env:LOCALAPPDATA 'Programs\XCrossCLI'
$userPath=[Environment]::GetEnvironmentVariable('Path','User')
$parts=@($userPath -split ';' | Where-Object { $_ -and $_.Trim() -and $_.TrimEnd('\') -ine $target.TrimEnd('\') })
[Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')
if(Test-Path -LiteralPath $target){ Remove-Item -LiteralPath $target -Recurse -Force }
Write-Host 'Comando xcm eliminado del PATH. Abre una nueva terminal.' -ForegroundColor Green
Write-Host 'La configuracion en AppData\Roaming\XCrossMenu se conserva.' -ForegroundColor Gray
