#requires -Version 5.1
param(
    [Parameter(Mandatory=$true)][ValidatePattern('^(\d{1,3}\.){3}\d{1,3}$')][string]$Gateway,
    [Parameter(Mandatory=$true)][ValidatePattern('^(\d{1,3}\.){3}\d{1,3}$')][string]$ClientIP,
    [switch]$Remove
)
$ErrorActionPreference = 'Stop'
try {
    [void][Net.IPAddress]::Parse($Gateway)
    [void][Net.IPAddress]::Parse($ClientIP)
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $arguments = @(
            '-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $PSCommandPath),
            '-Gateway',$Gateway,'-ClientIP',$ClientIP
        )
        if ($Remove) { $arguments += '-Remove' }
        $process = Start-Process -FilePath powershell.exe -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -Wait -PassThru
        exit $process.ExitCode
    }
    $ruleName = 'XCross-xtool-WSL-USB-' + $Gateway.Replace('.','-')
    if ($Remove) {
        $rule = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue
        if ($rule) {
            & netsh interface portproxy delete v4tov4 "listenaddress=$Gateway" listenport=27015 protocol=tcp | Out-Host
            if ($LASTEXITCODE -ne 0) { throw 'No se pudo eliminar el relay.' }
            $rule | Remove-NetFirewallRule
        }
        exit 0
    }
    if (-not (Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort 27015 -State Listen -ErrorAction SilentlyContinue)) {
        throw 'Apple Mobile Device Service no escucha en 127.0.0.1:27015. Instala/abre iTunes o Apple Devices y conecta el iPhone.'
    }
    # Only bind the WSL virtual interface, never 0.0.0.0 or a public interface.
    $address = Get-NetIPAddress -IPAddress $Gateway -AddressFamily IPv4 -ErrorAction Stop
    if ($address.InterfaceAlias -notmatch 'WSL') { throw 'La direccion no pertenece a una interfaz WSL.' }
    & netsh interface portproxy add v4tov4 "listenaddress=$Gateway" listenport=27015 connectaddress=127.0.0.1 connectport=27015 protocol=tcp | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo crear el relay de Apple Mobile Device Service.' }
    $existing = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue
    if ($existing) {
        $existing | Get-NetFirewallAddressFilter | Set-NetFirewallAddressFilter -LocalAddress $Gateway -RemoteAddress $ClientIP | Out-Null
    }
    else {
        New-NetFirewallRule -Name $ruleName -DisplayName 'XCross xtool WSL USB' -Direction Inbound -Action Allow `
            -Protocol TCP -LocalPort 27015 -LocalAddress $Gateway -RemoteAddress $ClientIP -InterfaceAlias $address.InterfaceAlias | Out-Null
    }
    exit 0
}
catch {
    Write-Error $_.Exception.Message -ErrorAction Continue
    exit 1
}
