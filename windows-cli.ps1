#requires -Version 5.1
<#
.SYNOPSIS
  Menu interactivo para preparar Flutter iOS + xcross en Windows.
.DESCRIPTION
  No modifica el iPhone sin consentimiento. No almacena contrasenas de Apple.
  Necesita Windows PowerShell 5.1 o PowerShell 7 en Windows.
#>
[CmdletBinding()]
param(
    [string]$Action = 'Menu',
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CommandArgs = @()
)

$ErrorActionPreference = 'Stop'
$script:Version = '1.2.0'
$script:SettingsDir = Join-Path $env:APPDATA 'XCrossMenu'
$script:SettingsFile = Join-Path $script:SettingsDir 'settings.json'
$script:Settings = @{ XcodeXip = ''; FlutterProject = ''; BundleIdMode = 'default' }
$script:ProjectOverride = ''

function Write-Title([string]$Text) {
    Write-Host ''
    Write-Host '  xcm ' -ForegroundColor Cyan -NoNewline
    Write-Host ('/ ' + $Text) -ForegroundColor White
    Write-Host '  ------------------------------------------------------------' -ForegroundColor DarkGray
}

function Write-Ok([string]$Text)   { Write-Host ('[OK] ' + $Text) -ForegroundColor Green }
function Write-Warn([string]$Text) { Write-Host ('[!] ' + $Text) -ForegroundColor Yellow }
function Write-Fail([string]$Text) { Write-Host ('[X] ' + $Text) -ForegroundColor Red }

function Pause-Menu {
    Write-Host ''
    Write-Host '  [ cualquier tecla ] Volver al menu' -ForegroundColor DarkGray
    try { [void][Console]::ReadKey($true) }
    catch { [void](Read-Host 'Continuar') }
}

function Confirm-Yes([string]$Question) {
    Write-Host ("  ? $Question  ") -ForegroundColor Yellow -NoNewline
    Write-Host '[S]i / [N]o  ' -ForegroundColor DarkGray -NoNewline
    try {
        $key = [Console]::ReadKey($true)
        $answer = [string]$key.KeyChar
        Write-Host $answer
        return ($answer -match '^[sSyY]$')
    }
    catch {
        $answer = Read-Host 'Responde S o N'
        return ($answer -match '^(s|si|sí|y|yes)$')
    }
}

function Test-Tool([string]$Name) {
    return ($null -ne (Get-Command -Name $Name -ErrorAction SilentlyContinue))
}

function Refresh-Path {
    # Un instalador puede haber modificado el PATH de usuario/sistema.
    $paths = @()
    foreach ($scope in @('Machine', 'User')) {
        $value = [Environment]::GetEnvironmentVariable('Path', $scope)
        if ($value) { $paths += ($value -split ';') }
    }
    $paths += ($env:PATH -split ';')
    $env:PATH = (($paths | Where-Object { $_ -and $_.Trim() } | Select-Object -Unique) -join ';')
}

function Invoke-Tool([string]$Tool, [string[]]$Arguments = @()) {
    if (-not (Test-Tool $Tool)) {
        Write-Fail "No encuentro $Tool en PATH."
        return $false
    }
    Write-Host ("> $Tool " + ($Arguments -join ' ')) -ForegroundColor DarkGray
    try {
        # Out-Host conserva la interaccion y evita capturar stdout como retorno.
        & $Tool @Arguments 2>&1 | Out-Host
        $code = $LASTEXITCODE
        if ($null -ne $code -and $code -ne 0) {
            Write-Fail "$Tool termino con codigo $code."
            return $false
        }
        return $true
    }
    catch {
        Write-Fail $_.Exception.Message
        return $false
    }
}

function Load-Settings {
    if (-not (Test-Path -LiteralPath $script:SettingsFile)) { return }
    try {
        $data = Get-Content -LiteralPath $script:SettingsFile -Raw | ConvertFrom-Json
        if ($data.XcodeXip) { $script:Settings.XcodeXip = [string]$data.XcodeXip }
        if ($data.FlutterProject) { $script:Settings.FlutterProject = [string]$data.FlutterProject }
        if ($data.BundleIdMode -in @('default', 'original', 'prefixed')) {
            $script:Settings.BundleIdMode = [string]$data.BundleIdMode
        }
    }
    catch { Write-Warn 'No se pudo leer la configuracion anterior. Usare los valores predeterminados.' }
}

function Save-Settings {
    try {
        if (-not (Test-Path -LiteralPath $script:SettingsDir)) {
            New-Item -ItemType Directory -Path $script:SettingsDir -Force | Out-Null
        }
        $script:Settings | ConvertTo-Json -Depth 2 | Set-Content -LiteralPath $script:SettingsFile -Encoding UTF8
    }
    catch { Write-Warn 'No se pudo guardar la configuracion local.' }
}

function Get-SwiftVersion {
    if (-not (Test-Tool 'swift')) { return $null }
    try {
        $raw = (& swift --version 2>&1 | Out-String)
        if ($raw -match '(?:Apple\s+)?Swift version\s+(\d+)\.(\d+)') {
            return [Version]::new([int]$Matches[1], [int]$Matches[2])
        }
    }
    catch { }
    return $null
}

function Check-Swift {
    $version = Get-SwiftVersion
    if ($null -eq $version) {
        Write-Warn 'No se detecta Swift o no se puede leer su version.'
        return $false
    }
    Write-Host "Swift detectado: $version"
    if ($version -lt [Version]'6.4') {
        Write-Fail 'Se necesita Swift 6.4 o superior para este flujo.'
        return $false
    }
    return $true
}

function Show-Environment {
    Write-Title 'Diagnostico del entorno'
    Refresh-Path
    foreach ($name in @('winget', 'swift', 'clang', 'ld64.lld', 'python', 'py', 'pymobiledevice3', 'xcross', 'flutter')) {
        if (Test-Tool $name) {
            Write-Ok ($name.PadRight(17) + 'disponible')
        }
        else {
            Write-Warn ($name.PadRight(17) + 'no encontrado')
        }
    }
    [void](Check-Swift)
    if (Test-Tool 'xcross') { [void](Invoke-Tool 'xcross' @('--version')) }
    Write-Host ''
    Write-Host 'Nota: Python o py pueden ser alternativos; no necesitas los dos.'
    Write-Host 'Si acabas de instalar herramientas, abre una nueva terminal.'
}

function Install-Swift {
    Refresh-Path
    if (Check-Swift) {
        Write-Ok 'Swift ya cumple el requisito.'
        return $true
    }
    if (-not (Test-Tool 'winget')) {
        Write-Fail 'winget no esta disponible. Instala Swift desde https://www.swift.org/install/windows/'
        return $false
    }
    if (-not (Confirm-Yes 'Instalar/actualizar Swift mediante winget?')) { return $false }
    $present = Test-Tool 'swift'
    if ($present) {
        $ok = Invoke-Tool 'winget' @('upgrade', '--id', 'Swift.Toolchain', '--exact', '--source', 'winget', '--accept-source-agreements', '--accept-package-agreements')
    }
    else {
        $ok = Invoke-Tool 'winget' @('install', '--id', 'Swift.Toolchain', '--exact', '--source', 'winget', '--accept-source-agreements', '--accept-package-agreements')
    }
    Refresh-Path
    if (-not $ok -or -not (Check-Swift)) {
        Write-Warn 'Si Swift se instalo pero no aparece en PATH, cierra PowerShell y abrelo de nuevo.'
        return $false
    }
    return $true
}

function Install-Xcross {
    Refresh-Path
    if (Test-Tool 'xcross') {
        Write-Ok 'xcross ya esta instalado.'
        return $true
    }
    $url = 'https://raw.githubusercontent.com/arxdeus/xcross/main/install.ps1'
    Write-Host 'Fuente oficial:' -ForegroundColor Cyan
    Write-Host $url
    if (-not (Confirm-Yes 'Descargar y ejecutar el instalador oficial de xcross?')) { return $false }
    $download = Join-Path ([IO.Path]::GetTempPath()) ('xcross-official-' + [Guid]::NewGuid().ToString('N') + '.ps1')
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $download
        $hash = Get-FileHash -LiteralPath $download -Algorithm SHA256
        Write-Host ('SHA256 del instalador descargado: ' + $hash.Hash)
        Write-Warn 'El codigo descargado es externo. Puedes inspeccionarlo antes de aceptar.'
        if (-not (Confirm-Yes 'Ejecutar el script descargado ahora?')) { return $false }
        # Proceso separado: impide que `exit` dentro del instalador cierre este menu.
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $download 2>&1 | Out-Host
        $code = $LASTEXITCODE
        Refresh-Path
        if ($code -ne 0 -or -not (Test-Tool 'xcross')) {
            Write-Fail 'La instalacion no se verifico. Revisa la salida y reinicia la terminal si es necesario.'
            return $false
        }
        Write-Ok 'xcross instalado y disponible.'
        return $true
    }
    catch {
        Write-Fail $_.Exception.Message
        return $false
    }
    finally { Remove-Item -LiteralPath $download -Force -ErrorAction SilentlyContinue }
}

function Install-Dependencies {
    if (-not (Check-Swift)) {
        Write-Warn 'Instala Swift 6.4+ antes de ejecutar xcross setup.'
        return $false
    }
    if (-not (Test-Tool 'xcross')) {
        Write-Fail 'Primero instala xcross.'
        return $false
    }
    Write-Host 'xcross setup administra LLVM, VS Build Tools, Python y pymobiledevice3.'
    Write-Host 'Mostrara sus propias confirmaciones antes de instalar paquetes.'
    if (-not (Confirm-Yes 'Ejecutar xcross setup?')) { return $false }
    $args = @('setup')
    if (Test-Tool 'winget') { $args += @('--manager', 'winget') }
    $ok = Invoke-Tool 'xcross' $args
    Refresh-Path
    if ($ok) { Write-Ok 'Configuracion finalizada. Reabre PowerShell si falta alguna herramienta en PATH.' }
    return $ok
}

function Select-Xip {
    $default = ''
    if ($script:Settings.XcodeXip -and (Test-Path -LiteralPath $script:Settings.XcodeXip -PathType Leaf)) {
        $default = $script:Settings.XcodeXip
    }
    else {
        $downloads = Join-Path $env:USERPROFILE 'Downloads'
        $found = Get-ChildItem -Path $downloads -Filter 'Xcode*.xip' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($found) { $default = $found.FullName }
    }
    if ($default) { Write-Host "Archivo detectado: $default" }
    else {
        Write-Warn 'xcross NO descarga Xcode.xip: Apple proporciona el archivo desde su portal (requiere Apple ID).'
        if (Confirm-Yes 'Quieres abrir ahora las descargas oficiales de Xcode?') { Open-AppleDownloadPage }
    }
    $answer = Read-Host 'Ruta a Xcode.xip (ENTER = archivo detectado)'
    $path = if ($answer.Trim()) { $answer.Trim().Trim('"').Trim("'") } else { $default }
    if (-not $path -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Write-Fail 'No se encontro el archivo indicado.'
        return $null
    }
    if ([IO.Path]::GetExtension($path) -ine '.xip') {
        Write-Fail 'El archivo debe ser un .xip completo de Xcode.'
        return $null
    }
    $script:Settings.XcodeXip = (Resolve-Path -LiteralPath $path).Path
    Save-Settings
    return $script:Settings.XcodeXip
}

function Install-DarwinSdk {
    Write-Title 'Importar SDK de iOS desde Xcode.xip'
    if (-not (Check-Swift)) { return }
    if (-not (Test-Tool 'xcross')) { Write-Fail 'xcross no esta instalado.'; return }
    $xip = Select-Xip
    if (-not $xip) { return }
    Write-Warn 'La extraccion puede requerir varios GB libres y bastante tiempo.'
    Write-Warn 'El SDK queda ligado a la version de Swift activa en este momento.'
    if (Confirm-Yes "Instalar el SDK desde $xip ?") {
        [void](Invoke-Tool 'xcross' @('sdk', 'install', $xip))
    }
}

function Get-UsbDevices {
    if (-not (Test-Tool 'pymobiledevice3')) {
        Write-Fail 'No encuentro pymobiledevice3. Ejecuta la instalacion de dependencias.'
        return
    }
    try {
        $output = & pymobiledevice3 usbmux list 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            Write-Fail $output.Trim()
            return
        }
        $devices = ConvertFrom-Json -InputObject $output
        foreach ($device in @($devices)) { if ($null -ne $device) { Write-Output $device } }
    }
    catch { Write-Fail "No se pudieron consultar dispositivos USB: $($_.Exception.Message)" }
}

function Show-UsbDevices {
    Write-Title 'iPhone detectados por USB'
    $devices = @(Get-UsbDevices)
    if ($devices.Count -eq 0) {
        Write-Warn 'No hay iPhone detectado. Revisa cable USB, desbloqueo y Confiar en este ordenador.'
        return $false
    }
    foreach ($d in $devices) {
        Write-Ok "$($d.DeviceName) | iOS $($d.ProductVersion) | $($d.ConnectionType)"
        Write-Host "    Modelo: $($d.ProductType)"
    }
    return $true
}

function Developer-Mode {
    Write-Title 'Modo desarrollador'
    $devices = @(Get-UsbDevices)
    if ($devices.Count -eq 0) { Write-Warn 'Conecta y desbloquea el iPhone por USB.'; return }
    if ($devices.Count -gt 1) { Write-Warn 'Conecta un solo iPhone para evitar modificar otro dispositivo.'; return }
    Write-Host "  $($devices[0].DeviceName) - iOS $($devices[0].ProductVersion)" -ForegroundColor Gray
    $items = @(
        @{ Key='1'; Label='Consultar estado'; Description='developer-mode-status'; Command='status' },
        @{ Key='2'; Label='Mostrar opcion en Ajustes'; Description='reveal-developer-mode'; Command='reveal' },
        @{ Key='3'; Label='Solicitar activacion'; Description='puede reiniciar el iPhone'; Command='enable' },
        @{ Key='4'; Label='Como confiar en la app'; Description='guia para el aviso de iOS'; Command='trust' }
    )
    while ($true) {
        $selection = Show-KeyMenu -Title 'DEVELOPER MODE' -Subtitle 'Elige con una tecla, flechas + derecha o espacio' -Items $items -AllowPalette
        if ($selection -eq '__back__') { return }
        if ($selection -eq '__palette__') { Show-PaletteThenRun; continue }
        switch ($selection) {
            'status' { [void](Invoke-Tool 'pymobiledevice3' @('amfi','developer-mode-status')) }
            'reveal' {
                $ok=Invoke-Tool 'pymobiledevice3' @('amfi','reveal-developer-mode')
                if ($ok) { Write-Ok 'Solicitud enviada. Revisa Ajustes > Privacidad y seguridad.' }
            }
            'enable' {
                Write-Warn 'Puede reiniciar el iPhone. Debes confirmar la activacion en el dispositivo.'
                if (Confirm-Yes 'Solicitar activacion ahora?') { [void](Invoke-Tool 'pymobiledevice3' @('amfi','enable-developer-mode')) }
            }
            'trust' { Show-DeveloperTrustGuide }
        }
        Pause-Menu
    }
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Start-TunnelWindow([string]$Transport) {
    if (-not (Test-Tool 'xcross')) { Write-Fail 'Instala xcross antes de continuar.'; return }
    $subAction = if ($Transport -eq 'wifi') { 'WifiTunnel' } else { 'UsbTunnel' }
    $exe = Join-Path $PSHOME 'powershell.exe'
    if (-not (Test-Path -LiteralPath $exe)) { $exe = 'powershell.exe' }
    $arguments = "-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$PSCommandPath`" -Action $subAction"
    try {
        if (Test-Admin) {
            Start-Process -FilePath $exe -ArgumentList $arguments | Out-Null
        }
        else {
            Write-Host 'Windows solicitara permisos de administrador para abrir el tunel.'
            Start-Process -FilePath $exe -ArgumentList $arguments -Verb RunAs | Out-Null
        }
        Write-Ok 'Tunel iniciado en otra ventana. Manten esa ventana abierta.'
        Write-Host 'Vuelve aqui para ejecutar Flutter cuando el tunel informe que esta listo.'
    }
    catch { Write-Fail "No se pudo abrir la ventana del tunel: $($_.Exception.Message)" }
}

function Tunnel-Command([string]$Transport) {
    Write-Title "Tunel iOS ($Transport)"
    if (-not (Test-Admin)) {
        Write-Fail 'Este paso requiere ejecutar PowerShell como administrador.'
        return
    }
    Write-Warn 'Manten esta ventana abierta mientras trabajas con Flutter.'
    Write-Warn 'Conecta y desbloquea el iPhone. Confirma Confiar si lo pide.'
    $args = @('tunnel')
    if ($Transport -eq 'wifi') { $args += '--wifi' }
    [void](Invoke-Tool 'xcross' $args)
}

function Connect-AppleId {
    Write-Title 'Autenticacion para firma iOS'
    if (-not (Test-Tool 'xcross')) { Write-Fail 'Instala xcross primero.'; return }
    Write-Warn 'xcross recomienda NO usar tu Apple ID principal: su autenticacion no es estandar.'
    Write-Host 'Usa preferiblemente una cuenta Apple de pruebas.'
    $email = (Read-Host 'Correo de la cuenta Apple de pruebas').Trim()
    if (-not $email -or $email -notmatch '^\S+@\S+\.\S+$') {
        Write-Warn 'No se proporciono un correo valido.'
        return
    }
    Write-Host 'xcross pedira las credenciales y el codigo 2FA de forma interactiva.'
    if (Confirm-Yes "Conectar $email ?") { [void](Invoke-Tool 'xcross' @('auth', '--apple-id', $email)) }
}

function Select-FlutterProject {
    param([switch]$ForcePrompt, [string]$ExplicitPath = '')
    $default = ''
    if ($ExplicitPath) {
        $default = $ExplicitPath
    }
    elseif ($script:ProjectOverride) {
        $default = $script:ProjectOverride
    }
    elseif (Test-Path -LiteralPath (Join-Path (Get-Location).Path 'pubspec.yaml') -PathType Leaf) {
        $default = (Get-Location).Path
    }
    elseif ($script:Settings.FlutterProject -and (Test-Path -LiteralPath (Join-Path $script:Settings.FlutterProject 'pubspec.yaml') -PathType Leaf)) {
        $default = $script:Settings.FlutterProject
    }
    if ($ForcePrompt) {
        if ($default) { Write-Host "  Proyecto actual: $default" -ForegroundColor DarkCyan }
        $entered = Read-Host '  Ruta del proyecto Flutter (vacío = detectado)'
        if ($entered.Trim()) { $default = $entered.Trim().Trim('"').Trim("'") }
    }
    if (-not $default -or -not (Test-Path -LiteralPath (Join-Path $default 'pubspec.yaml') -PathType Leaf)) {
        Write-Fail 'No se encontro pubspec.yaml. Usa: xcm project set "C:\ruta\proyecto"'
        return $null
    }
    $resolved = (Resolve-Path -LiteralPath $default).Path
    $script:Settings.FlutterProject = $resolved
    Save-Settings
    return $resolved
}

function Flutter-Doctor {
    Write-Title 'Flutter doctor'
    if (-not (Test-Tool 'xcross')) { Write-Fail 'Instala xcross primero.'; return }
    $project = Select-FlutterProject
    if (-not $project) { return }
    Write-Host "  Proyecto: $project" -ForegroundColor DarkGray
    Push-Location -LiteralPath $project
    try { [void](Invoke-Tool 'xcross' @('flutter', 'doctor')) }
    finally { Pop-Location }
}

function Flutter-Run {
    param([ValidateSet('usb','wifi')][string]$Transport = 'usb', [string]$Target = '', [switch]$VerboseRun)
    Write-Title "Ejecutar Flutter ($Transport)"
    if (-not (Test-Tool 'xcross')) { Write-Fail 'Instala xcross primero.'; return }
    $project = Select-FlutterProject
    if (-not $project) { return }
    Write-Host "  Proyecto: $project" -ForegroundColor DarkGray
    Write-Host '  Consejo: si no hay tunel RSD, abre otro terminal con xcm tunnel usb.' -ForegroundColor DarkGray
    Write-Host '  Hot Reload: r   |   Hot Restart: R   |   salir: q' -ForegroundColor Cyan
    $toolArgs = @('flutter', 'run', "--$Transport")
    if ($Target) {
        $targetFile = Join-Path $project $Target
        if (-not (Test-Path -LiteralPath $targetFile -PathType Leaf)) {
            Write-Fail "No existe el entrypoint: $targetFile"
            return
        }
        $toolArgs += @('-t', $Target)
    }
    if ($VerboseRun) { $toolArgs += '-v' }
    $previousBundleMode = [Environment]::GetEnvironmentVariable('XCROSS_BUNDLE_ID', 'Process')
    if ($script:Settings.BundleIdMode -in @('original', 'prefixed')) {
        $env:XCROSS_BUNDLE_ID = $script:Settings.BundleIdMode
        Write-Host "  App ID solicitado: $($script:Settings.BundleIdMode)" -ForegroundColor DarkGray
    }
    else {
        Remove-Item -Path Env:XCROSS_BUNDLE_ID -ErrorAction SilentlyContinue
        Write-Host '  App ID: usar la seleccion / configuracion predeterminada de xcross.' -ForegroundColor DarkGray
    }
    Push-Location -LiteralPath $project
    try { [void](Invoke-Tool 'xcross' $toolArgs) }
    finally {
        Pop-Location
        if ($null -eq $previousBundleMode) { Remove-Item -Path Env:XCROSS_BUNDLE_ID -ErrorAction SilentlyContinue }
        else { $env:XCROSS_BUNDLE_ID = $previousBundleMode }
    }
}

function Flutter-Ide {
    if (-not (Test-Tool 'xcross')) { Write-Fail 'Instala xcross primero.'; return }
    $project = Select-FlutterProject
    if (-not $project) { return }
    Write-Warn 'xcross ide vscode puede crear o modificar archivos bajo .vscode/.'
    if (-not (Confirm-Yes 'Configurar el proyecto para VS Code?')) { return }
    Push-Location -LiteralPath $project
    try { [void](Invoke-Tool 'xcross' @('ide', 'vscode')) }
    finally { Pop-Location }
}

function Open-AppleDownloadPage {
    Write-Title 'Descargar Xcode.xip desde Apple'
    Write-Host 'El SDK de iOS para xcross se extrae de un Xcode.xip completo.'
    Write-Host 'El archivo lo distribuye Apple; xcross no dispone de un comando sdk download.'
    Write-Host 'Puedes necesitar iniciar sesion con tu Apple ID en el navegador.'
    $url = 'https://developer.apple.com/download/all/?q=Xcode'
    try {
        Start-Process -FilePath $url
        Write-Ok 'Se abrio el portal oficial de descargas de Apple.'
        Write-Host 'Descarga Xcode.xip, vuelve a este menu y elige instalar el SDK.'
    }
    catch { Write-Fail "No pude abrir el navegador: $($_.Exception.Message)"; Write-Host $url }
}

function Precache-FlutterIos {
    param([string]$PreselectedMode = '')
    Write-Title 'Descargar artefactos iOS con xcross'
    if (-not (Test-Tool 'xcross')) {
        Write-Fail 'Primero instala xcross desde la opcion 1 o el menu de descargas.'
        return
    }
    $project = Select-FlutterProject
    if (-not $project) { return }
    $mode = $PreselectedMode
    if (-not $mode) {
        Write-Host 'debug: motor Flutter para probar en iPhone y Hot Reload.'
        Write-Host 'profile/release: incluye el compilador AOT cuando esta disponible.'
        Write-Host 'all: obtiene los artefactos de debug, profile y release.'
        $answer = (Read-Host 'Modo de descarga [debug/profile/release/all] (ENTER=debug)').Trim().ToLowerInvariant()
        $mode = if ($answer) { $answer } else { 'debug' }
    }
    if ($mode -notin @('debug', 'profile', 'release', 'all')) {
        Write-Fail 'Modo no reconocido. Usa debug, profile, release o all.'
        return
    }
    Write-Host 'xcross descargara los artefactos para la version de Flutter de tu proyecto.'
    Write-Host 'Esto NO descarga Xcode.xip ni soluciona por si solo un certificado no confiable.'
    if (-not (Confirm-Yes "Descargar artefactos iOS para modo $mode ?")) { return }
    Push-Location -LiteralPath $project
    try {
        if (Invoke-Tool 'xcross' @('flutter', 'precache', '--mode', $mode)) {
            Write-Ok 'Descarga/preparacion de artefactos finalizada.'
        }
    }
    finally { Pop-Location }
}

function Downloads-Menu {
    $items = @(
        @{ Key='1'; Label='Instalar / actualizar Swift'; Description='winget - Swift 6.4+'; Command='swift' },
        @{ Key='2'; Label='Descargar xcross'; Description='instalador oficial de GitHub'; Command='xcross' },
        @{ Key='3'; Label='Dependencias xcross'; Description='LLVM, Python, Build Tools'; Command='dependencies' },
        @{ Key='4'; Label='Abrir Xcode en Apple'; Description='descarga manual de Xcode.xip'; Command='xcode' },
        @{ Key='5'; Label='Instalar SDK iOS'; Description='xcross sdk install Xcode.xip'; Command='sdk' },
        @{ Key='6'; Label='Descargar Flutter Debug'; Description='xcross flutter precache --mode debug'; Command='precache-debug' },
        @{ Key='7'; Label='Descargar Flutter completo'; Description='debug, profile, release'; Command='precache-all' },
        @{ Key='8'; Label='Actualizar xcross'; Description='xcross update'; Command='update' },
        @{ Key='9'; Label='Preparacion guiada'; Description='instalar paso a paso'; Command='install' }
    )
    while ($true) {
        $choice = Show-KeyMenu -Title 'DESCARGAS Y TOOLCHAIN' -Subtitle 'Preparar Flutter iOS sin una Mac' -Items $items -AllowPalette
        if ($choice -eq '__back__') { return }
        if ($choice -eq '__palette__') { Show-PaletteThenRun; continue }
        switch ($choice) {
            'swift' { [void](Install-Swift) }
            'xcross' { [void](Install-Xcross) }
            'dependencies' { [void](Install-Dependencies) }
            'xcode' { Open-AppleDownloadPage }
            'sdk' { Install-DarwinSdk }
            'precache-debug' { Precache-FlutterIos -PreselectedMode 'debug' }
            'precache-all' { Precache-FlutterIos -PreselectedMode 'all' }
            'update' { Upgrade-Xcross }
            'install' { Guided-Setup }
        }
        Pause-Menu
    }
}

function Set-BundleIdentity {
    $items = @(
        @{ Key='1'; Label='Automatico'; Description='dejar que xcross / proyecto elija'; Command='default' },
        @{ Key='2'; Label='Original'; Description='com.example.luminaMobile (si Apple lo permite)'; Command='original' },
        @{ Key='3'; Label='Con prefijo'; Description='identificador XCR-...'; Command='prefixed' }
    )
    $mode = Show-KeyMenu -Title 'IDENTIDAD DE LA APP' -Subtitle ("Actual: " + $script:Settings.BundleIdMode) -Items $items -AllowPalette
    if ($mode -eq '__palette__') { Show-PaletteThenRun; return }
    if ($mode -notin @('default','original','prefixed')) { return }
    $script:Settings.BundleIdMode = $mode
    Save-Settings
    Write-Ok "Configuracion de App ID guardada: $mode"
    Write-Warn 'Cambiar el App ID no hace confiable al certificado Apple Development.'
}

function Show-DeveloperTrustGuide {
    Write-Title 'Autorizar una app de desarrollo en iPhone'
    Write-Host '1. Conecta el iPhone y comprueba que el Modo desarrollador esta activo.'
    Write-Host '2. Abre en iPhone: Configuracion > General > Adm. de dispositivos y VPN.'
    Write-Host '3. Busca la identidad Apple Development usada para firmar la app.'
    Write-Host '4. Si el iPhone ofrece Confiar/Permitir y reiniciar, confirma desde el dispositivo.'
    Write-Host '5. Abre la app directamente desde el iPhone antes de probar el depurador.'
    Write-Warn 'xcross NO puede forzar la confianza desde Windows: la autorizacion ocurre en iOS.'
    Write-Warn 'Si no aparece esa identidad o el dispositivo prohibe apps de desarrollador,'
    Write-Warn 'revisa restricciones de Tiempo de uso o perfiles administrados (MDM).'
}

function Diagnose-Signing {
    param([string]$BundleId = '')
    Write-Title 'Diagnostico de firma y dispositivos'
    if (-not (Test-Tool 'pymobiledevice3')) {
        Write-Fail 'Falta pymobiledevice3. Ejecuta xcm dependencies.'
        return
    }
    if (-not (Show-UsbDevices)) { return }
    Write-Host '  Modo desarrollador:' -ForegroundColor Cyan
    [void](Invoke-Tool 'pymobiledevice3' @('amfi','developer-mode-status'))
    Write-Host ''
    Write-Host '  Perfiles de aprovisionamiento:' -ForegroundColor Cyan
    [void](Invoke-Tool 'pymobiledevice3' @('provision','list'))
    if ($BundleId) {
        Write-Host "  Bundle ID solicitado: $BundleId" -ForegroundColor Cyan
        [void](Invoke-Tool 'pymobiledevice3' @('apps', 'query', $BundleId))
    }
    Write-Warn 'La confianza en Apple Development se autoriza en el iPhone, no por el CLI.'
}

function Signing-Menu {
    $items = @(
        @{ Key='1'; Label='Diagnosticar firma'; Description='iPhone, Developer Mode, provisioning'; Command='sign' },
        @{ Key='2'; Label='Elegir App ID'; Description='automatico / original / prefijado'; Command='bundle' },
        @{ Key='3'; Label='Confiar en Apple Development'; Description='instrucciones en el iPhone'; Command='trust' },
        @{ Key='4'; Label='Autenticar Apple ID'; Description='xcross auth --apple-id'; Command='auth' },
        @{ Key='5'; Label='Modo desarrollador'; Description='revelar, consultar o activar'; Command='devmode' }
    )
    while ($true) {
        $choice = Show-KeyMenu -Title 'FIRMA Y CONFIANZA' -Subtitle 'Una firma valida no equivale a desarrollador autorizado' -Items $items -AllowPalette
        if ($choice -eq '__back__') { return }
        if ($choice -eq '__palette__') { Show-PaletteThenRun; continue }
        switch ($choice) {
            'sign' { Diagnose-Signing }
            'bundle' { Set-BundleIdentity }
            'trust' { Show-DeveloperTrustGuide }
            'auth' { Connect-AppleId }
            'devmode' { Developer-Mode }
        }
        Pause-Menu
    }
}

function Upgrade-Xcross {
    if (-not (Test-Tool 'xcross')) { Write-Fail 'Instala xcross primero.'; return }
    [void](Invoke-Tool 'xcross' @('update', '--check'))
    if (Confirm-Yes 'Actualizar xcross a la ultima version publicada?') {
        [void](Invoke-Tool 'xcross' @('update'))
    }
}

function Guided-Setup {
    Write-Title 'Asistente de preparacion inicial'
    Write-Host '1) Swift >= 6.4  2) xcross  3) LLVM/Python/Build Tools'
    Write-Host '4) SDK desde Xcode.xip  5) Conexion USB  6) Modo desarrollador'
    if (-not (Install-Swift)) {
        Write-Warn 'Detenido en Swift. Si acabas de instalarlo, reinicia PowerShell y reintenta.'
        return
    }
    if (-not (Install-Xcross)) { return }
    if (-not (Install-Dependencies)) { return }
    if (Confirm-Yes 'Quieres importar ahora el SDK desde un archivo Xcode.xip local?') {
        Install-DarwinSdk
    }
    if (Confirm-Yes 'Quieres descargar los artefactos iOS debug de Flutter con xcross?') {
        Precache-FlutterIos -PreselectedMode 'debug'
    }
    if (Confirm-Yes 'Quieres comprobar la conexion USB del iPhone?') {
        [void](Show-UsbDevices)
    }
    Write-Host 'Despues usa las opciones del menu para Modo desarrollador, Autenticacion y Tunel.'
}

function Show-Menu {
    $items = @(
        @{ Key='1'; Label='Ejecutar Flutter en iPhone'; Description='compilar, firmar, instalar, hot reload'; Command='run' },
        @{ Key='2'; Label='Diagnostico de Flutter'; Description='xcross flutter doctor'; Command='doctor' },
        @{ Key='3'; Label='Detectar iPhone'; Description='USB y version de iOS'; Command='device' },
        @{ Key='4'; Label='Modo desarrollador'; Description='estado y activacion'; Command='devmode' },
        @{ Key='5'; Label='Abrir tunel USB'; Description='abre PowerShell con permisos'; Command='tunnel-usb' },
        @{ Key='6'; Label='Abrir tunel Wi-Fi'; Description='enlace inalambrico'; Command='tunnel-wifi' },
        @{ Key='D'; Label='Descargas y SDK'; Description='Swift, xcross, Xcode, precache'; Command='downloads' },
        @{ Key='F'; Label='Firma y App ID'; Description='autorizacion Apple Development'; Command='signing' },
        @{ Key='P'; Label='Proyectos Flutter'; Description='cambiar proyecto, VS Code, ejecutar'; Command='projects' },
        @{ Key='I'; Label='Instalar comando xcm'; Description='disponible desde cualquier carpeta'; Command='install-cli' },
        @{ Key='?'; Label='Comandos y ayuda'; Description='lista de comandos y ejemplos'; Command='help' }
    )
    while ($true) {
        $choice = Show-KeyMenu -Title 'XCROSS CONSOLE' -Subtitle 'Flutter iOS  /  Windows  /  developer toolkit' -Items $items -AllowPalette
        if ($choice -eq '__back__') { return }
        if ($choice -eq '__palette__') { Show-PaletteThenRun; continue }
        switch ($choice) {
            'run' { Flutter-Run -Transport 'usb' }
            'doctor' { Flutter-Doctor }
            'device' { [void](Show-UsbDevices) }
            'devmode' { Developer-Mode }
            'tunnel-usb' { Start-TunnelWindow 'usb' }
            'tunnel-wifi' { Start-TunnelWindow 'wifi' }
            'downloads' { Downloads-Menu; continue }
            'signing' { Signing-Menu; continue }
            'projects' { Projects-Menu; continue }
            'install-cli' { Install-XcmGlobal }
            'help' { Show-XcmHelp }
        }
        Pause-Menu
    }
}


# ----------------------------------------------
# XCM Console UI and standalone command router.
# ----------------------------------------------
function Show-Banner {
    param([string]$Title, [string]$Subtitle)
    Write-Host ''
    Write-Host '    xcm' -NoNewline -ForegroundColor Cyan
    Write-Host '  /  XCross Console' -NoNewline -ForegroundColor White
    Write-Host ("                                    v" + $script:Version) -ForegroundColor DarkGray
    Write-Host '    ---------------------------------------------------------------' -ForegroundColor DarkGray
    Write-Host ("    $Title") -ForegroundColor White
    Write-Host ("    $Subtitle") -ForegroundColor DarkGray
    Write-Host ''
    $x = if (Test-Tool 'xcross') { 'ready' } else { 'missing' }
    $s = if (Test-Tool 'swift') { 'ready' } else { 'missing' }
    Write-Host '    xcross ' -NoNewline -ForegroundColor DarkGray
    Write-Host $x -NoNewline -ForegroundColor $(if ($x -eq 'ready') { 'Green' } else { 'Yellow' })
    Write-Host '     swift ' -NoNewline -ForegroundColor DarkGray
    Write-Host $s -ForegroundColor $(if ($s -eq 'ready') { 'Green' } else { 'Yellow' })
    if ($script:Settings.FlutterProject) {
        $name = Split-Path -Leaf $script:Settings.FlutterProject
        Write-Host ("    Proyecto: $name") -ForegroundColor DarkGray
    }
    Write-Host ''
}

function Show-KeyMenu {
    param([string]$Title, [string]$Subtitle, [object[]]$Items, [switch]$AllowPalette)
    $index = 0
    while ($true) {
        Clear-Host
        Show-Banner -Title $Title -Subtitle $Subtitle
        for ($i = 0; $i -lt $Items.Count; $i++) {
            $item = $Items[$i]
            $key = [string]$item['Key']
            $label = [string]$item['Label']
            $desc = [string]$item['Description']
            $first = ('  {0}  {1}' -f $key.PadRight(2), $label.PadRight(32))
            if ($i -eq $index) {
                Write-Host ('  >' + $first) -ForegroundColor Black -BackgroundColor Cyan -NoNewline
                Write-Host ('  ' + $desc) -ForegroundColor Cyan
            }
            else {
                Write-Host ('   ' + $first) -ForegroundColor Gray -NoNewline
                Write-Host ('  ' + $desc) -ForegroundColor DarkGray
            }
        }
        Write-Host ''
        Write-Host '    ---------------------------------------------------------------' -ForegroundColor DarkGray
        Write-Host '    Flechas: mover   |   -> / ESPACIO: ejecutar   |   1-9: acceso directo' -ForegroundColor DarkCyan
        if ($AllowPalette) {
            Write-Host '    / : comandos    |   ESC / 0 : atras o salir' -ForegroundColor DarkGray
        }
        else { Write-Host '    ESC / 0 : atras' -ForegroundColor DarkGray }
        try { $keyInfo = [Console]::ReadKey($true) }
        catch {
            $fallback=Read-Host 'Opcion'
            foreach ($item in $Items) {
                if ($fallback -eq [string]$item['Key']) { return [string]$item['Command'] }
            }
            if ($fallback -eq '0') { return '__back__' }
            if ($fallback -eq '/') { return '__palette__' }
            continue
        }
        if ($keyInfo.Key -eq [ConsoleKey]::Escape) { return '__back__' }
        if ($keyInfo.Key -eq [ConsoleKey]::UpArrow) { $index=($index+$Items.Count-1)%$Items.Count; continue }
        if ($keyInfo.Key -eq [ConsoleKey]::DownArrow) { $index=($index+1)%$Items.Count; continue }
        if ($keyInfo.Key -eq [ConsoleKey]::Home) { $index=0; continue }
        if ($keyInfo.Key -eq [ConsoleKey]::End) { $index=$Items.Count-1; continue }
        if ($keyInfo.Key -in @([ConsoleKey]::RightArrow,[ConsoleKey]::Spacebar,[ConsoleKey]::Enter)) {
            return [string]$Items[$index]['Command']
        }
        $char = [string]$keyInfo.KeyChar
        if ($char -eq '0') { return '__back__' }
        if ($AllowPalette -and $char -eq '/') { return '__palette__' }
        foreach ($item in $Items) {
            if ($char.ToUpperInvariant() -eq ([string]$item['Key']).ToUpperInvariant()) {
                return [string]$item['Command']
            }
        }
    }
}

function Get-PaletteEntries {
    return @(
        @{ Name='run'; Detail='Compilar y abrir Flutter por USB' },
        @{ Name='run --wifi'; Detail='Ejecutar Flutter por Wi-Fi' },
        @{ Name='doctor'; Detail='Comprobar herramientas y Flutter' },
        @{ Name='device'; Detail='Listar iPhone conectados' },
        @{ Name='devmode status'; Detail='Consultar modo desarrollador' },
        @{ Name='devmode reveal'; Detail='Mostrar Developer Mode en Ajustes' },
        @{ Name='devmode enable'; Detail='Solicitar activar Developer Mode' },
        @{ Name='tunnel usb'; Detail='Iniciar tunel RSD USB' },
        @{ Name='tunnel wifi'; Detail='Preparar tunel Wi-Fi' },
        @{ Name='sdk install'; Detail='Importar Xcode.xip al SDK' },
        @{ Name='xcode'; Detail='Abrir descargas Apple Xcode' },
        @{ Name='precache debug'; Detail='Descargar Flutter iOS Debug' },
        @{ Name='precache all'; Detail='Descargar Flutter iOS completo' },
        @{ Name='project show'; Detail='Ver proyecto actual' },
        @{ Name='project set'; Detail='Elegir carpeta Flutter' },
        @{ Name='bundle original'; Detail='Usar identificador App ID original' },
        @{ Name='bundle prefixed'; Detail='Usar identificador App ID prefijado' },
        @{ Name='sign'; Detail='Diagnosticar firma de Apple' },
        @{ Name='trust'; Detail='Ayuda de desarrollador no confiable' },
        @{ Name='auth'; Detail='Autenticacion Apple ID' },
        @{ Name='vscode'; Detail='Configurar VS Code' },
        @{ Name='install-cli'; Detail='Instalar comando xcm en PATH' },
        @{ Name='update'; Detail='Actualizar xcross' },
        @{ Name='help'; Detail='Todos los comandos de XCM' }
    )
}

function Show-CommandPalette {
    $buffer=''
    $selected=0
    $commands=Get-PaletteEntries
    while ($true) {
        $q=$buffer.Trim()
        if ($q) {
            $matches=@($commands | Where-Object {
                $_.Name -match [regex]::Escape($q) -or $_.Detail -match [regex]::Escape($q)
            })
        }
        else { $matches=@($commands) }
        if ($selected -ge $matches.Count) { $selected=0 }
        Clear-Host
        Show-Banner -Title 'COMMAND PALETTE' -Subtitle 'Escribe para filtrar comandos; sin Enter para seleccionar'
        Write-Host ('    / ' + $buffer + '_') -ForegroundColor Cyan
        Write-Host ''
        $limit=[Math]::Min(11,$matches.Count)
        for($i=0;$i -lt $limit;$i++){
            $cmd=$matches[$i]
            $line=('  /' + ([string]$cmd.Name).PadRight(25) + ' ' + [string]$cmd.Detail)
            if($i -eq $selected){ Write-Host ('  > '+$line) -BackgroundColor DarkCyan -ForegroundColor White }
            else { Write-Host ('    '+$line) -ForegroundColor Gray }
        }
        if($matches.Count -gt $limit){ Write-Host ("    + $($matches.Count - $limit) comandos mas") -ForegroundColor DarkGray }
        if($matches.Count -eq 0){ Write-Host '    Comando libre: ejecuta con FLECHA DERECHA o Enter.' -ForegroundColor Yellow }
        Write-Host ''
        Write-Host '    Flechas: navegar   -> / TAB: ejecutar   ESC: cancelar   ENTER: enviar texto' -ForegroundColor DarkCyan
        try { $ki=[Console]::ReadKey($true) }
        catch {
            $inputLine=Read-Host 'Comando'
            if($inputLine){ return $inputLine }
            return $null
        }
        if($ki.Key -eq [ConsoleKey]::Escape){ return $null }
        if($ki.Key -eq [ConsoleKey]::Backspace){ if($buffer.Length -gt 0){ $buffer=$buffer.Substring(0,$buffer.Length-1) }; $selected=0; continue }
        if($ki.Key -eq [ConsoleKey]::UpArrow){if($matches.Count -gt 0){$selected=($selected+$matches.Count-1)%$matches.Count};continue}
        if($ki.Key -eq [ConsoleKey]::DownArrow){if($matches.Count -gt 0){$selected=($selected+1)%$matches.Count};continue}
        if($ki.Key -in @([ConsoleKey]::RightArrow,[ConsoleKey]::Tab)){
            if($matches.Count -eq 0 -and $q){return $q}
            if($matches.Count -gt 0){return [string]$matches[$selected].Name}
            continue
        }
        if($ki.Key -eq [ConsoleKey]::Enter){
            if($q){return $q}
            if($matches.Count -gt 0){return [string]$matches[$selected].Name}
            continue
        }
        if($ki.KeyChar -and [int][char]$ki.KeyChar -ge 32 -and [int][char]$ki.KeyChar -le 126){
            if($buffer.Length -lt 160){$buffer += [string]$ki.KeyChar; $selected=0}
        }
    }
}

function Split-CommandTokens([string]$Line) {
    # Quoted Windows paths (double or single quotes) are preserved as one argument.
    $tokens=New-Object System.Collections.Generic.List[string]
    $rx='"[^"]*"|''[^'']*''|\S+'
    foreach($m in [regex]::Matches($Line,$rx)){
        $value=$m.Value
        if($value.Length -ge 2 -and (($value[0] -eq '"' -and $value[$value.Length-1] -eq '"') -or ($value[0] -eq "'" -and $value[$value.Length-1] -eq "'"))){
            $value=$value.Substring(1,$value.Length-2)
        }
        $tokens.Add($value)
    }
    return $tokens.ToArray()
}

function Show-PaletteThenRun {
    $line=Show-CommandPalette
    if(-not $line){return}
    $tokens=@(Split-CommandTokens $line)
    if($tokens.Count -eq 0){return}
    $verb=([string]$tokens[0]).TrimStart('/')
    $rest=@()
    if($tokens.Count -gt 1){$rest=@($tokens[1..($tokens.Count-1)])}
    Write-Title ("/"+$line)
    try { [void](Invoke-XcmCommand -Verb $verb -Arguments $rest) }
    catch { Write-Fail $_.Exception.Message }
    Pause-Menu
}

function Projects-Menu {
    $items=@(
        @{Key='1'; Label='Cambiar proyecto'; Description='elige ruta a carpeta con pubspec.yaml'; Command='set'},
        @{Key='2'; Label='Ver proyecto'; Description='muestra ruta guardada'; Command='show'},
        @{Key='3'; Label='Diagnostico Flutter'; Description='xcross flutter doctor'; Command='doctor'},
        @{Key='4'; Label='Ejecutar por USB'; Description='xcross flutter run --usb'; Command='usb'},
        @{Key='5'; Label='Ejecutar por Wi-Fi'; Description='xcross flutter run --wifi'; Command='wifi'},
        @{Key='6'; Label='Integrar VS Code'; Description='configurar archivos .vscode'; Command='vscode'}
    )
    while($true){
        $choice=Show-KeyMenu -Title 'PROYECTOS FLUTTER' -Subtitle 'Trabaja con LUMINA o cualquier proyecto Flutter' -Items $items -AllowPalette
        if($choice -eq '__back__'){return}
        if($choice -eq '__palette__'){Show-PaletteThenRun;continue}
        switch($choice){
            'set' {[void](Select-FlutterProject -ForcePrompt)}
            'show' {Show-CurrentProject}
            'doctor' {Flutter-Doctor}
            'usb' {Flutter-Run -Transport 'usb'}
            'wifi' {Flutter-Run -Transport 'wifi'}
            'vscode' {Flutter-Ide}
        }
        Pause-Menu
    }
}

function Show-CurrentProject {
    Write-Title 'Proyecto Flutter'
    $p=Select-FlutterProject
    if($p){Write-Ok $p}
}

function Install-XcmGlobal {
    $installer=Join-Path $PSScriptRoot 'Instalar-Comando-XCM.ps1'
    if(-not (Test-Path -LiteralPath $installer)){
        Write-Fail 'No se encontro el instalador en el paquete ZIP.'
        return
    }
    Write-Title 'Comando xcm global'
    Write-Host '  Copia los scripts a AppData local y agrega la carpeta a tu PATH de usuario.'
    Write-Host '  No requiere Administrador. Puedes revertirlo con el desinstalador.' -ForegroundColor DarkGray
    if(Confirm-Yes 'Instalar comando global xcm?') {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer 2>&1 | Out-Host
    }
}

function Show-XcmHelp {
    Write-Title 'Comandos disponibles'
    $helpText = @'
  xcm                       Menu interactivo (sin Enter para elegir)
  xcm help                  Mostrar esta ayuda
  xcm doctor                Comprobar dependencias y Flutter
  xcm device                Detectar el iPhone por USB
  xcm devmode               Menu de desarrollador
  xcm devmode status        Comprobar Developer Mode
  xcm devmode reveal        Solicitar mostrar Developer Mode
  xcm devmode enable        Solicitar activarlo (confirmacion + reinicio)
  xcm tunnel usb            Abrir tunel RSD USB
  xcm tunnel wifi           Abrir tunel RSD Wi-Fi
  xcm sdk install [ruta]    Instalar SDK desde Xcode.xip
  xcm xcode                 Abrir descarga de Xcode.xip de Apple
  xcm install               Preparacion guiada
  xcm swift                 Instalar Swift con winget
  xcm xcross                Instalar xcross
  xcm dependencies          Ejecutar xcross setup
  xcm precache debug|all    Descargar artefactos Flutter iOS
  xcm project show          Ver proyecto activo
  xcm project set [ruta]    Seleccionar proyecto Flutter
  xcm run [--usb|--wifi] [-t archivo] [--project ruta] [-v]
  xcm bundle default|original|prefixed
  xcm sign [bundle-id]      Diagnosticar firma / perfiles
  xcm trust                 Guia de confianza iOS (no elude seguridad)
  xcm auth                  Conectar Apple ID desde xcross
  xcm vscode                Configurar VS Code
  xcm update                Actualizar xcross
  xcm install-cli           Instalar comando xcm en el PATH
'@
    Write-Host $helpText -ForegroundColor Gray
    Write-Host '  Ejemplo LUMINA:' -ForegroundColor Cyan
    Write-Host '    xcm project set "C:\Users\USUARIO\Documents\Github\LUMINA-v0.2-integracion\LUMINA-v0.2\lumina-mobile"' -ForegroundColor Gray
    Write-Host '    xcm tunnel usb' -ForegroundColor Gray
    Write-Host '    xcm run --usb -t lib/main.dart' -ForegroundColor Gray
    Write-Host ''
    Write-Host '  La paleta con / funciona dentro del menu; las opciones aceptan teclas sin Enter.' -ForegroundColor DarkGray
}

function Invoke-XcmCommand {
    param([string]$Verb, [string[]]$Arguments=@())
    $v=$Verb.TrimStart('/').ToLowerInvariant()
    switch($v){
        {$_ -in @('help','--help','-h','ayuda')} {Show-XcmHelp;return $true}
        {$_ -in @('menu','ui')} {Show-Menu;return $true}
        'install' {Guided-Setup;return $true}
        'swift' {[void](Install-Swift);return $true}
        'xcross' {[void](Install-Xcross);return $true}
        {$_ -in @('dependencies','deps','setup')} {[void](Install-Dependencies);return $true}
        'update' {Upgrade-Xcross;return $true}
        'xcode' {Open-AppleDownloadPage;return $true}
        {$_ -in @('doctor','check')} {Show-Environment;Flutter-Doctor;return $true}
        {$_ -in @('device','devices','iphone')} {[void](Show-UsbDevices);return $true}
        'sdk' {
            if($Arguments.Count -eq 0 -or $Arguments[0] -ne 'install'){
                Write-Warn 'Uso: xcm sdk install [ruta-Xcode.xip]';return $false
            }
            if($Arguments.Count -ge 2){
                $xip=$Arguments[1..($Arguments.Count-1)] -join ' '
                if(-not (Test-Path -LiteralPath $xip -PathType Leaf)) {Write-Fail "No existe: $xip";return $false}
                if([IO.Path]::GetExtension($xip) -ine '.xip'){Write-Fail 'Se requiere Xcode.xip';return $false}
                if(-not (Check-Swift)){return $false}
                if(Confirm-Yes "Importar SDK desde $xip?") {[void](Invoke-Tool 'xcross' @('sdk','install',$xip))}
            }
            else {Install-DarwinSdk}
            return $true
        }
        'precache' {
            $mode=if($Arguments.Count -gt 0){$Arguments[0].ToLowerInvariant()}else{'debug'}
            if($mode -notin @('debug','profile','release','all')){Write-Fail 'Usa debug, profile, release o all';return $false}
            Precache-FlutterIos -PreselectedMode $mode
            return $true
        }
        'project' {
            $sub=if($Arguments.Count){$Arguments[0].ToLowerInvariant()}else{'show'}
            switch($sub){
                'show' {Show-CurrentProject;return $true}
                'set' {
                    if($Arguments.Count -gt 1){
                        $p=$Arguments[1..($Arguments.Count-1)] -join ' '
                        $script:ProjectOverride=$p
                        [void](Select-FlutterProject -ExplicitPath $p)
                        $script:ProjectOverride=''
                    }
                    else {[void](Select-FlutterProject -ForcePrompt)}
                    return $true
                }
                default {Write-Warn 'Uso: xcm project show|set [ruta]';return $false}
            }
        }
        'run' {
            $transport='usb';$target='';$override='';$verbose=$false
            for($i=0;$i -lt $Arguments.Count;$i++){
                $arg=$Arguments[$i]
                switch($arg){
                    '--usb' {$transport='usb'}
                    '--wifi' {$transport='wifi'}
                    {$_ -in @('-v','--verbose')} {$verbose=$true}
                    {$_ -in @('-t','--target','--project')} {
                        if(($i+1) -ge $Arguments.Count){Write-Fail "Falta valor para $arg";return $false}
                        $i++
                        if($arg -eq '--project'){$override=$Arguments[$i]}
                        else{$target=$Arguments[$i]}
                    }
                    default {Write-Fail "Argumento no reconocido: $arg";return $false}
                }
            }
            $prev=$script:ProjectOverride
            try{
                if($override){$script:ProjectOverride=$override}
                Flutter-Run -Transport $transport -Target $target -VerboseRun:$verbose
            }
            finally{$script:ProjectOverride=$prev}
            return $true
        }
        'bundle' {
            if($Arguments.Count -eq 0){Set-BundleIdentity;return $true}
            $mode=$Arguments[0].ToLowerInvariant()
            if($mode -notin @('default','original','prefixed')){Write-Fail 'Usa default, original o prefixed';return $false}
            $script:Settings.BundleIdMode=$mode
            Save-Settings
            Write-Ok "App ID: $mode (no cambia la confianza del certificado)"
            return $true
        }
        {$_ -in @('sign','signing')} {
            $bundle=if($Arguments.Count){$Arguments[0]}else{''}
            Diagnose-Signing -BundleId $bundle
            return $true
        }
        'trust' {Show-DeveloperTrustGuide;return $true}
        'auth' {Connect-AppleId;return $true}
        'vscode' {Flutter-Ide;return $true}
        'devmode' {
            if($Arguments.Count -eq 0){Developer-Mode;return $true}
            $sub=$Arguments[0].ToLowerInvariant()
            if($sub -eq 'status') { [void](Invoke-Tool 'pymobiledevice3' @('amfi','developer-mode-status'));return $true }
            if($sub -eq 'reveal') { [void](Invoke-Tool 'pymobiledevice3' @('amfi','reveal-developer-mode'));return $true }
            if($sub -eq 'enable') {
                Write-Warn 'El iPhone puede reiniciarse y solicitara confirmacion en pantalla.'
                if(Confirm-Yes 'Activar Modo desarrollador?') { [void](Invoke-Tool 'pymobiledevice3' @('amfi','enable-developer-mode')) }
                return $true
            }
            Write-Warn 'Uso: xcm devmode status|reveal|enable'
            return $false
        }
        'tunnel' {
            $transport=if($Arguments.Count -gt 0){$Arguments[0].ToLowerInvariant()}else{'usb'}
            if($transport -notin @('usb','wifi')){Write-Fail 'Usa usb o wifi';return $false}
            if(Test-Admin){Tunnel-Command $transport}else{Start-TunnelWindow $transport}
            return $true
        }
        'install-cli' {Install-XcmGlobal;return $true}
        default {Write-Fail "Comando no reconocido: $Verb";Show-XcmHelp;return $false}
    }
}

if ($env:OS -ne 'Windows_NT') {
    Write-Fail 'Este paquete esta creado para Windows.'
    exit 1
}
try { [Console]::OutputEncoding=[System.Text.UTF8Encoding]::new($false) }
catch {}
Load-Settings
Refresh-Path
# Windows PowerShell 5.1 can merge remaining arguments into a single value.
if ($PSVersionTable.PSVersion.Major -le 5 -and $CommandArgs.Count -eq 1 -and $CommandArgs[0] -match '\s') {
    $CommandArgs = @(Split-CommandTokens ([string]$CommandArgs[0]))
}
switch($Action.ToLowerInvariant()){
    'usbtunnel' {Tunnel-Command 'usb'}
    'wifitunnel' {Tunnel-Command 'wifi'}
    'menu' {Show-Menu}
    default {
        $result=Invoke-XcmCommand -Verb $Action -Arguments $CommandArgs
        if(-not $result){exit 1}
    }
}
