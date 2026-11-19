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

# Ensure Unicode (logo/box chars) renders correctly on all Windows consoles.
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

$ErrorActionPreference = 'Stop'
$script:Version = '1.5.3'
$script:SettingsDir = Join-Path $env:APPDATA 'XCrossMenu'
$script:SettingsFile = Join-Path $script:SettingsDir 'settings.json'
$script:Settings = @{ XcodeXip = ''; FlutterProject = ''; BundleIdMode = 'default'; Language = 'en'; SetupWorkflow = '' }
$script:Language = 'en'
$script:ProjectOverride = ''

function Write-Title([string]$Text) {
    Write-Host ''
    Write-Host '  xcm ' -ForegroundColor Cyan -NoNewline
    Write-Host ('/ ' + $Text) -ForegroundColor White
    Write-Host '  ------------------------------------------------------------' -ForegroundColor DarkGray
}

function Write-Ok([string]$Text)   { Write-Host ('[OK] ' + $Text) -ForegroundColor Green }
function Msg([string]$En,[string]$Es){ if ($script:Language -eq 'es') { $Es } else { $En } }
function Write-Warn([string]$Text) { Write-Host ('[!] ' + $Text) -ForegroundColor Yellow }
function Write-Fail([string]$Text) { Write-Host ('[X] ' + $Text) -ForegroundColor Red }

function Pause-Menu {
    Write-Host ''
    if ($script:Language -eq 'es') {
        Write-Host '  [ cualquier tecla ] Volver al menu' -ForegroundColor DarkGray
    } else {
        Write-Host '  [ any key ] Back to menu' -ForegroundColor DarkGray
    }
    try { [void][Console]::ReadKey($true) }
    catch {
        if ($script:Language -eq 'es') { [void](Read-Host 'Continuar') } else { [void](Read-Host 'Continue') }
    }
}

function Confirm-Yes([string]$Question) {
    Write-Host ("  ? $Question  ") -ForegroundColor Yellow -NoNewline
    if ($script:Language -eq 'es') { Write-Host '[S]i / [N]o  ' -ForegroundColor DarkGray -NoNewline } else { Write-Host '[Y]es / [N]o  ' -ForegroundColor DarkGray -NoNewline }
    try {
        $key = [Console]::ReadKey($true)
        $answer = [string]$key.KeyChar
        Write-Host $answer
        if ($script:Language -eq 'es') { return ($answer -match '^[sSyY]$') } else { return ($answer -match '^[yY]$') }
    }
    catch {
        if ($script:Language -eq 'es') { $answer = Read-Host 'Responde S o N' } else { $answer = Read-Host 'Answer Y or N' }
        if ($script:Language -eq 'es') { return ($answer -match '^(s|si|yes|y)$') } else { return ($answer -match '^(y|yes)$') }
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

function Invoke-Tool([string]$Tool, [string[]]$Arguments = @(), [switch]$HideArguments) {
    if (-not (Test-Tool $Tool)) {
        Write-Fail (Msg "Tool not found in PATH: $Tool" "No encuentro $Tool en PATH.")
        return $false
    }
    if ($HideArguments) { Write-Host "> $Tool [arguments hidden]" -ForegroundColor DarkGray }
    else { Write-Host ("> $Tool " + ($Arguments -join ' ')) -ForegroundColor DarkGray }
    $previousErrorPreference = $ErrorActionPreference
    try {
        # Windows PowerShell wraps native stderr as ErrorRecord, even on success.
        # Tools such as Git report progress there; use their exit code instead.
        $ErrorActionPreference = 'Continue'
        # Out-Host conserva la interaccion y evita capturar stdout como retorno.
        & $Tool @Arguments 2>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.ToString() }
            else { $_ }
        } | Out-Host
        $code = $LASTEXITCODE
        if ($null -ne $code -and $code -ne 0) {
            Write-Fail (Msg "$Tool exited with code $code." "$Tool termino con codigo $code.")
            return $false
        }
        return $true
    }
    catch {
        Write-Fail $_.Exception.Message
        return $false
    }
    finally { $ErrorActionPreference = $previousErrorPreference }
}

function Invoke-InteractiveTool([string]$Tool, [string[]]$Arguments = @()) {
    if (-not (Test-Tool $Tool)) { Write-Fail "No encuentro $Tool en PATH."; return $false }
    try {
        $info = New-Object Diagnostics.ProcessStartInfo
        $info.FileName = (Get-Command $Tool).Source
        # Windows argument quoting; no shell, output pipe or transcript is used.
        $quoted = foreach ($argument in $Arguments) {
            $escaped = [regex]::Replace([string]$argument, '(\\*)"', '$1$1\"')
            $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
            '"' + $escaped + '"'
        }
        $info.Arguments = $quoted -join ' '
        $info.UseShellExecute = $false
        $info.RedirectStandardInput = $false
        $info.RedirectStandardOutput = $false
        $info.RedirectStandardError = $false
        $process = [Diagnostics.Process]::Start($info)
        try {
            $process.WaitForExit()
            if ($process.ExitCode -ne 0) { Write-Fail "$Tool termino con codigo $($process.ExitCode)."; return $false }
            return $true
        }
        finally { $process.Dispose() }
    }
    catch { Write-Fail $_.Exception.Message; return $false }
}

function Load-Settings {
    if (-not (Test-Path -LiteralPath $script:SettingsFile)) { return }
    try {
        $data = Get-Content -LiteralPath $script:SettingsFile -Raw | ConvertFrom-Json
        if ($data.XcodeXip) { $script:Settings.XcodeXip = [string]$data.XcodeXip }
        if ($data.FlutterProject) { $script:Settings.FlutterProject = [string]$data.FlutterProject }
        if ($data.SetupWorkflow -in @('ipa','flutter','swift')) { $script:Settings.SetupWorkflow = [string]$data.SetupWorkflow }
        if ($data.BundleIdMode -in @('default', 'original', 'prefixed')) {
            $script:Settings.BundleIdMode = [string]$data.BundleIdMode
        }
        if ($data.Language -in @('en','es')) {
            $script:Settings.Language = [string]$data.Language
            $script:Language = [string]$data.Language
        }
    }
    catch { Write-Warn (Msg 'Could not read previous settings. Using defaults.' 'No se pudo leer la configuracion anterior. Usare los valores predeterminados.') }
}

function Save-Settings {
    try {
        if (-not (Test-Path -LiteralPath $script:SettingsDir)) {
            New-Item -ItemType Directory -Path $script:SettingsDir -Force | Out-Null
        }
        $script:Settings.Language = $script:Language
        $script:Settings | ConvertTo-Json -Depth 2 | Set-Content -LiteralPath $script:SettingsFile -Encoding UTF8
    }
    catch { Write-Warn (Msg 'Could not save local settings.' 'No se pudo guardar la configuracion local.') }
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
        Write-Warn (Msg 'Swift not detected or version unreadable.' 'No se detecta Swift o no se puede leer su version.')
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
    Write-Host (Msg 'If you just installed tools, open a new terminal.' 'Si acabas de instalar herramientas, abre una nueva terminal.')
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
            Write-Fail (Msg 'Installation not verified. Check output and restart terminal if needed.' 'La instalacion no se verifico. Revisa la salida y reinicia la terminal si es necesario.')
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
    if ($ok) { Write-Ok (Msg 'Setup complete. Reopen PowerShell if a tool is missing from PATH.' 'Configuracion finalizada. Reabre PowerShell si falta alguna herramienta en PATH.') }
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
        Write-Fail (Msg 'File not found.' 'No se encontro el archivo indicado.')
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
        Write-Fail (Msg 'pymobiledevice3 not found. Run dependency installation.' 'No encuentro pymobiledevice3. Ejecuta la instalacion de dependencias.')
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
    catch { Write-Fail (Msg "Could not query USB devices: $($_.Exception.Message)" "No se pudieron consultar dispositivos USB: $($_.Exception.Message)") }
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
    catch { Write-Fail (Msg "Could not open tunnel window: $($_.Exception.Message)" "No se pudo abrir la ventana del tunel: $($_.Exception.Message)") }
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
    Write-Title 'Apple ID / Flutter (XCross)'
    if (-not (Test-Tool 'xcross')) { Write-Fail 'Instala xcross primero.'; return $false }
    Write-Warn 'xcross recomienda NO usar tu Apple ID principal: su autenticacion no es estandar.'
    Write-Host 'Usa preferiblemente una cuenta Apple de pruebas.'
    Write-Host 'Escribe cada respuesta cuando aparezca su pregunta y pulsa Enter.' -ForegroundColor Cyan
    $email = (Read-Host '[1/3] Correo Apple ID (escribelo y pulsa Enter)').Trim()
    if (-not $email -or $email -notmatch '^\S+@\S+\.\S+$') {
        Write-Warn (Msg 'No valid email provided.' 'No se proporciono un correo valido.')
        return $false
    }
    Write-Host ''
    Write-Host '[2/3] Cuando aparezca Password: escribe tu contrasena y pulsa Enter.' -ForegroundColor Cyan
    Write-Host '      No veras letras ni asteriscos mientras escribes: es normal.' -ForegroundColor DarkGray
    Write-Host '[3/3] Cuando aparezca verification code: escribe el codigo 2FA y pulsa Enter.' -ForegroundColor Cyan
    Write-Host '      Revisa tu dispositivo de confianza. Durante Signing in / Fetching solo espera.' -ForegroundColor DarkGray
    Write-Host 'Las respuestas se introducen aqui; xcm no las guarda ni las registra.' -ForegroundColor DarkGray
    Write-Host ''
    return (Invoke-InteractiveTool 'xcross' @('auth','--apple-id',$email))
}

function Get-ProjectKind([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Container)) { return 'unknown' }
    if (Test-Path -LiteralPath (Join-Path $Path 'pubspec.yaml') -PathType Leaf) { return 'flutter' }
    if ((Test-Path -LiteralPath (Join-Path $Path 'Package.swift') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $Path 'xtool.yml') -PathType Leaf)) { return 'xtool' }
    # Prefer an app project over a sibling library Package.swift.
    if (@(Get-ChildItem -LiteralPath $Path -Directory | Where-Object { $_.Extension -in @('.xcodeproj','.xcworkspace') }).Count) { return 'xcode' }
    if (Test-Path -LiteralPath (Join-Path $Path 'Package.swift') -PathType Leaf) { return 'swift' }
    return 'unknown'
}

function Select-Project {
    param([switch]$ForcePrompt, [string]$ExplicitPath = '', [switch]$Optional)
    $default = ''
    if ($ExplicitPath) {
        $default = $ExplicitPath
    }
    elseif ($script:ProjectOverride) {
        $default = $script:ProjectOverride
    }
    elseif ((Get-ProjectKind (Get-Location).Path) -ne 'unknown') {
        $default = (Get-Location).Path
    }
    elseif ($script:Settings.FlutterProject -and (Get-ProjectKind $script:Settings.FlutterProject) -ne 'unknown') {
        $default = $script:Settings.FlutterProject
    }
    if ($ForcePrompt) {
        if ($default) { Write-Host "  Proyecto actual: $default" -ForegroundColor DarkCyan }
        $entered = Read-Host '  Project path / Ruta (Flutter, Package.swift, Xcode)'
        if ($entered.Trim()) { $default = $entered.Trim().Trim('"').Trim("'") }
    }
    if ((Get-ProjectKind $default) -eq 'unknown') {
        if ($Optional) {
            Write-Warn (Msg 'No project selected. Setup will check host tools only.' 'Sin proyecto seleccionado. La preparacion comprobara solo el host.')
            return $null
        }
        Write-Fail (Msg 'No project found: expected pubspec.yaml, Package.swift or an Xcode project. Use xcm project set PATH.' 'No se encontro pubspec.yaml, Package.swift ni un proyecto Xcode. Usa xcm project set RUTA.')
        return $null
    }
    $resolved = (Resolve-Path -LiteralPath $default).Path
    $script:Settings.FlutterProject = $resolved
    Save-Settings
    return $resolved
}

function Select-FlutterProject {
    param([switch]$ForcePrompt, [string]$ExplicitPath = '')
    $project = Select-Project -ForcePrompt:$ForcePrompt -ExplicitPath $ExplicitPath
    if (-not $project) { return $null }
    if ((Get-ProjectKind $project) -ne 'flutter') {
        Write-Fail (Msg 'This command requires a Flutter project.' 'Este comando requiere un proyecto Flutter.')
        return $null
    }
    return $project
}

function Show-XcodeLimitation {
    Write-Fail (Msg 'This Xcode project needs a SwiftPM + xtool.yml adaptation for cross-compilation; xcm does not convert it automatically.' 'Este proyecto Xcode necesita adaptacion a SwiftPM + xtool.yml para compilacion cruzada; xcm no lo convierte automaticamente.')
    Write-Host (Msg 'xtool builds Swift iOS apps through WSL. You can also install a published IPA with xcm install PATH.ipa --backend xtool.' 'xtool compila apps Swift iOS mediante WSL. Tambien puedes instalar una IPA publicada con xcm install RUTA.ipa --backend xtool.')
    Write-Host 'iKoda: xcm download ipa --repo Ivorisnoob/iKoda --asset Koda.ipa --output .\Koda.ipa'
}

function Invoke-ProjectCommand {
    param([ValidateSet('run','build')][string]$Operation, [string[]]$Arguments = @())
    $path = ''; $product = ''; $swiftArgs = @(); $appArgs = @(); $flutterArgs = @(); $hasDeviceOption = $false; $hasSwiftOption = $false
    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        $arg = $Arguments[$i]
        if ($arg -in @('--args','--')) {
            if ($Operation -ne 'run') { Write-Fail '--args is only supported by run.'; return $false }
            $hasSwiftOption = $true
            if ($i + 1 -lt $Arguments.Count) { $appArgs = $Arguments[($i+1)..($Arguments.Count-1)] }
            break
        }
        if ($arg -in @('--project','--product','--configuration')) {
            if ($i + 1 -ge $Arguments.Count -or $Arguments[$i+1].StartsWith('-')) { Write-Fail "Falta valor para $arg"; return $false }
            $i++; $value = $Arguments[$i]
            if ($arg -eq '--project') { $path = $value }
            elseif ($arg -eq '--configuration') {
                if ($value -notin @('debug','release')) { Write-Fail 'Usa --configuration debug|release'; return $false }
                $hasSwiftOption = $true; $swiftArgs += @('--configuration',$value)
            }
            else {
                $hasSwiftOption = $true
                # Executable must follow all SwiftPM options, before application arguments.
                $product = $value
            }
        }
        else { $flutterArgs += $arg; $hasDeviceOption = $true }
    }
    $project = Select-Project -ExplicitPath $path
    if (-not $project) { return $false }
    $kind = Get-ProjectKind $project
    if ($kind -eq 'xtool') {
        $backendArgs = @($Operation) + $Arguments
        if ($Arguments -notcontains '--project') { $backendArgs += @('--project',$project) }
        return (Invoke-XtoolCommand -Arguments $backendArgs)
    }
    if ($kind -eq 'xcode') { Show-XcodeLimitation; return $false }
    if ($kind -eq 'flutter') {
        if ($hasSwiftOption) { Write-Fail 'Swift options require Package.swift.'; return $false }
        $previous = $script:ProjectOverride
        try {
            $script:ProjectOverride = $project
            if ($Operation -eq 'build') { return (Invoke-IpaCommand -Arguments (@('build') + $flutterArgs)) }
            # Keep the established Flutter argument parser.
            return (Invoke-XcmCommand -Verb 'flutter-run' -Arguments $flutterArgs)
        }
        finally { $script:ProjectOverride = $previous }
    }
    if ($hasDeviceOption) { Write-Fail 'SwiftPM runs on this PC. Use --product, --configuration and --args for app arguments; USB/Wi-Fi and Dart options are Flutter-only.'; return $false }
    $toolArgs = @($Operation,'--package-path',$project)
    if ($product -and $Operation -eq 'build') { $toolArgs += @('--product',$product) }
    $toolArgs += $swiftArgs
    if ($product -and $Operation -eq 'run') { $toolArgs += $product }
    if ($appArgs.Count -and -not $product) { Write-Fail 'Use --product NAME before --args application arguments.'; return $false }
    $toolArgs += $appArgs
    Push-Location -LiteralPath $project
    try { return (Invoke-Tool 'swift' $toolArgs) }
    finally { Pop-Location }
}

function Test-ProjectEnvironment {
    param([string]$Path = '')
    $project = Select-Project -ExplicitPath $Path
    if (-not $project) { return $false }
    $kind = Get-ProjectKind $project
    Write-Title "Doctor: $kind"
    Write-Host $project
    if ($kind -eq 'xtool') { return (Invoke-XtoolCommand -Arguments @('doctor')) }
    if ($kind -eq 'xcode') { Show-XcodeLimitation; return $false }
    if ($kind -eq 'swift') {
        if (-not (Invoke-Tool 'swift' @('--version'))) { return $false }
        Write-Warn (Msg 'Checking the package manifest only; this does not prove its dependencies build on Windows.' 'Se comprueba el manifiesto; esto no garantiza que sus dependencias compilen en Windows.')
        return (Invoke-Tool 'swift' @('package','--package-path',$project,'dump-package'))
    }
    Push-Location -LiteralPath $project
    try { return (Invoke-Tool 'xcross' @('flutter','doctor')) }
    finally { Pop-Location }
}

function Test-XcmEnvironment {
    Show-Environment
    $ok = Check-Swift
    foreach ($tool in @('git','xcross')) {
        if (-not (Test-Tool $tool)) { Write-Fail "$tool missing / no encontrado"; $ok = $false }
    }
    try {
        $python = Get-IpaPython
        if (-not (Invoke-Tool $python.Tool (@($python.Prefix) + @('--version')))) { $ok = $false }
    }
    catch { Write-Fail $_.Exception.Message; $ok = $false }
    if (Test-Tool 'xcross') {
        $configPaths = @((Join-Path $env:APPDATA 'xcross\config.yaml'), (Join-Path $env:APPDATA 'xcross\config.yml'))
        $hasConfig = $env:XCROSS_CONFIG -or @($configPaths | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }).Count
        if ($hasConfig) {
            if (-not (Invoke-Tool 'xcross' @('config','validate'))) { $ok = $false }
        }
        else { Write-Ok (Msg 'No optional XCross config; using PATH discovery.' 'Sin configuracion opcional XCross; se usa PATH.') }
    }
    Write-Warn (Msg 'Host tools only. For Swift iOS or IPA signing run: xcm xtool doctor. For Flutter iOS run doctor in its project.' 'Solo herramientas del host. Para Swift iOS o firma de IPA usa: xcm xtool doctor. Para Flutter iOS ejecuta doctor en su proyecto.')
    return $ok
}

function Test-CurrentIpaFolder {
    return ($null -ne (Get-ChildItem -LiteralPath (Get-Location).Path -Filter '*.ipa' -File -ErrorAction SilentlyContinue | Select-Object -First 1))
}

function Test-XcrossSavedIdentity {
    $root = Join-Path $env:APPDATA 'xcross'
    return ((Test-Path -LiteralPath (Join-Path $root 'grandslam-session.json') -PathType Leaf) -or
        (Test-Path -LiteralPath (Join-Path $root 'appstoreconnect.json') -PathType Leaf))
}

function Test-IpaEnvironment {
    Write-Title (Msg 'Doctor: IPA installation (XCross)' 'Doctor: instalacion de IPA (XCross)')
    $ok = $true
    foreach ($tool in @('xcross','git','pymobiledevice3')) {
        if (Test-Tool $tool) { Write-Ok "$tool disponible" }
        else { Write-Fail "$tool no encontrado"; $ok = $false }
    }
    try { [void](Get-IpaDart); Write-Ok 'Dart disponible para el adaptador de firma' }
    catch { Write-Fail $_.Exception.Message; $ok = $false }
    try { [void](Get-IpaPython); Write-Ok 'Python disponible para revisar la IPA' }
    catch { Write-Fail $_.Exception.Message; $ok = $false }
    if (Test-XcrossSavedIdentity) { Write-Ok (Msg 'Saved XCross identity available; no second login required.' 'Sesion XCross guardada disponible; no se necesita otro acceso.') }
    else { Write-Fail (Msg 'No saved XCross identity. Run xcm init ipa.' 'Falta sesion XCross. Ejecuta xcm init ipa.'); $ok = $false }
    $devices = @(Get-UsbDevices | Where-Object { $_.ConnectionType -eq 'USB' })
    if ($devices.Count) { foreach ($device in $devices) { Write-Ok ("iPhone USB: " + $device.DeviceName) } }
    else { Write-Fail (Msg 'No USB iPhone: connect, unlock and accept Trust.' 'No hay iPhone USB: conecta, desbloquea y acepta Confiar.'); $ok = $false }
    if ($ok) { Write-Ok (Msg 'Ready for xcm install "app.ipa". Apple validates provisioning during installation.' 'Preparado para xcm install "app.ipa". Apple valida el aprovisionamiento al instalar.') }
    return $ok
}

function Get-ReleaseIpa {
    param([string[]]$Arguments)
    $stage = $null
    try {
        $options = @{}
        for ($i=0; $i -lt $Arguments.Count; $i++) {
            $key = $Arguments[$i]
            if ($key -notin @('--repo','--asset','--output') -or $options.ContainsKey($key) -or $i+1 -ge $Arguments.Count) { throw 'Uso: xcm download ipa --repo OWNER/REPO --asset NAME.ipa --output PATH.ipa' }
            $i++; $options[$key] = $Arguments[$i]
        }
        $repo = $options['--repo']; $assetName = $options['--asset']; $output = $options['--output']
        if ($repo -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' -or -not $assetName -or -not $output) { throw 'Requiere --repo OWNER/REPO, --asset NAME.ipa y --output PATH.ipa.' }
        if ([IO.Path]::GetExtension($assetName) -ine '.ipa' -or [IO.Path]::GetExtension($output) -ine '.ipa') { throw 'Usa archivos .ipa.' }
        $destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($output)
        if (Test-Path -LiteralPath $destination) { throw "Ya existe: $destination" }
        $headers = @{ 'User-Agent'='XCrossCLI'; Accept='application/vnd.github+json' }
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -Headers $headers
        $assets = @($release.assets | Where-Object { $_.name -ceq $assetName })
        if ($assets.Count -ne 1) { throw "Asset no encontrado: $assetName. Disponibles: $($release.assets.name -join ', ')" }
        $asset = $assets[0]
        if ($asset.browser_download_url -notlike 'https://github.com/*') { throw 'URL de descarga inesperada.' }
        $stage = $destination + '.' + [Guid]::NewGuid().ToString('N') + '.partial'
        Write-Host "$repo / $($release.tag_name) / $assetName"
        Invoke-WebRequest -UseBasicParsing -Uri $asset.browser_download_url -Headers $headers -OutFile $stage
        if ((Get-Item -LiteralPath $stage).Length -ne $asset.size) { throw 'Descarga incompleta (size).' }
        $hash = (Get-FileHash -LiteralPath $stage -Algorithm SHA256).Hash
        if ($asset.digest -match '^sha256:([a-fA-F0-9]{64})$') {
            if ($hash -ine $Matches[1]) { throw 'SHA256 no coincide.' }
        }
        else { Write-Warn 'GitHub no publica un SHA256 para este asset; solo se verifico el tamano.' }
        $report = Get-IpaInspection $stage
        if ($report.issues -contains 'invalid_package') { throw 'IPA invalida.' }
        # File.Move refuses an existing destination, including one created mid-download.
        [IO.File]::Move($stage, $destination)
        Write-Ok "Descargado: $destination"
        Write-Host "SHA256: $hash"
        Show-IpaInspection $report
        if ($report.signature -eq 'adhoc') {
            Write-Warn (Msg 'Device signing is required. xcm install PATH.ipa reuses your saved XCross identity to sign a copy and install.' 'Se necesita firma para el dispositivo. xcm install RUTA.ipa usa tu sesion guardada de XCross para firmar una copia e instalar.')
        }
        else { Write-Host "xcm install `"$destination`"" }
        return $true
    }
    catch { Write-Fail $_.Exception.Message; return $false }
    finally { if ($stage -and (Test-Path -LiteralPath $stage)) { Remove-Item -LiteralPath $stage -Force } }
}

function Resolve-IpaFile([string]$Path) {
    if (-not $Path -or [IO.Path]::GetExtension($Path) -ine '.ipa' -or
        -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw (Msg 'Select an existing .ipa file.' 'Selecciona un archivo .ipa existente.')
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Get-IpaPython {
    foreach ($name in @('python','py')) {
        if (Test-Tool $name) {
            return @{ Tool=$name; Prefix=$(if ($name -eq 'py') { @('-3') } else { @() }) }
        }
    }
    throw (Msg 'Python is required for IPA inspection.' 'Se necesita Python para revisar la IPA.')
}

function Get-IpaInspection([string]$Path) {
    $python = Get-IpaPython
    $toolArgs = @($python.Prefix) + @((Join-Path $PSScriptRoot 'ipa_inspect.py'), $Path)
    $raw = & $python.Tool @toolArgs | Out-String
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo inspeccionar la IPA. Reinstala esta copia del CLI.' }
    return ($raw | ConvertFrom-Json)
}

function Show-IpaInspection($Report, [switch]$ReSign) {
    Write-Title (Msg 'IPA preflight' 'Revision de IPA')
    if ($Report.name) { Write-Host "  $($Report.name) | $($Report.bundle_id)" -ForegroundColor Cyan }
    switch ($Report.signature) {
        'missing' { Write-Warn (Msg 'No code signature found. This IPA needs signing before installation.' 'No tiene firma de codigo. Esta IPA necesita firma antes de instalarse.') }
        'adhoc' { Write-Warn (Msg 'Ad-hoc code signature only; this is not an Apple device signing identity.' 'Solo contiene firma ad-hoc de compilacion; no es una firma Apple para tu iPhone.') }
        'present' {
            if ($ReSign) { Write-Ok (Msg 'Code signature found. The selected xtool flow will replace it on a temporary copy.' 'Contiene firma. El flujo xtool seleccionado la reemplazara en una copia temporal.') }
            else { Write-Ok (Msg 'Code signature found. It will be preserved; iOS performs final validation.' 'Contiene firma. Se conserva; iOS realiza la validacion definitiva.') }
        }
        default { Write-Fail (Msg 'Invalid or unsupported IPA.' 'IPA invalida o no compatible.') }
    }
    Write-Host (Msg '  Inspection checks the main executable; it does not validate certificate trust or all embedded bundles.' '  Se revisa el ejecutable principal; no se valida la confianza del certificado ni todos los bundles internos.') -ForegroundColor DarkGray
}

function Invoke-IpaProcess([string]$Tool, [string[]]$Arguments) {
    $logDir = Join-Path $script:SettingsDir 'logs'
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    $log = Join-Path $logDir ('ipa-' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8) + '.log')
    $script:LastIpaLog = $log
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        Write-Host (Msg '  Working... Full details are being saved to a log.' '  Procesando... Los detalles se guardan en un registro.') -ForegroundColor Cyan
        & $Tool @Arguments 2>&1 | ForEach-Object {
            $line = $_.ToString()
            $line | Add-Content -LiteralPath $log -Encoding UTF8
            if ($line -match 'Signing app|Installing to device|Provisioning|^Installed:') { Write-Host $line -ForegroundColor DarkCyan }
        }
        $code = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousPreference }
    $details = if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Raw } else { '' }
    foreach ($line in ($details -split "`r?`n")) {
        if ($line.StartsWith('Signed IPA: ')) { Write-Ok $line }
    }
    if ($code -eq 0) { return $true }
    if ($details -match 'No code signature found|0xe800801c') {
        Write-Fail (Msg 'iOS rejected an unsigned executable. Signing is required.' 'iOS rechazo un ejecutable sin firma. Es necesario firmarlo.')
    }
    elseif ($details -match 'native function|native assets|sysv_abi_bridge') {
        Write-Fail (Msg 'The XCross native signing library could not load. Check the installed XCross runtime.' 'No se pudo cargar la biblioteca nativa de firma. Revisa la instalacion de XCross.')
    }
    elseif ($details -match 'session.*expired|sign in again|No usable Apple ID|auth.*again|ADI -800|GrandSlam') {
        Write-Fail (Msg 'XCross could not authenticate with Apple. Renew its session with: xcm auth' 'XCross no pudo autenticar con Apple. Renueva la sesion con: xcm auth')
    }
    elseif ($details -match 'ApplicationVerificationFailed|0xe8008015|provisioning profile') {
        Write-Fail (Msg 'iOS could not validate the signature/profile for this device.' 'iOS no pudo validar la firma/perfil para este dispositivo.')
    }
    else { Write-Fail (Msg "IPA operation failed (exit $code)." "La operacion IPA fallo (codigo $code).") }
    Write-Host "  Log: $log" -ForegroundColor Yellow
    return $false
}

function Get-IpaDart {
    if (Test-Tool 'dart') {
        $command = (Get-Command dart).Source
        $native = Join-Path (Split-Path $command) 'cache\dart-sdk\bin\dart.exe'
        if (Test-Path -LiteralPath $native -PathType Leaf) { return $native }
        if ([IO.Path]::GetExtension($command) -ieq '.exe') { return $command }
    }
    if (Test-Tool 'flutter') {
        $candidate = Join-Path (Split-Path (Get-Command flutter).Source) 'cache\dart-sdk\bin\dart.exe'
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    throw 'No se encontro Dart. Usa el Dart incluido en Flutter para la firma automatica.'
}

function Show-IpaLog {
    $log = $script:LastIpaLog
    if (-not $log) {
        $latest = Get-ChildItem -LiteralPath (Join-Path $script:SettingsDir 'logs') -Filter 'ipa-*.log' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latest) { $log = $latest.FullName }
    }
    if ($log -and (Test-Path -LiteralPath $log)) {
        Write-Host "Log: $log" -ForegroundColor Cyan
        Get-Content -LiteralPath $log | Out-Host
    }
    else { Write-Warn (Msg 'No IPA log found.' 'No hay registro de IPA.') }
}

function Install-NativeIpa([string]$Path, [string]$Udid, [switch]$ResignAdhoc) {
    $dart = Get-IpaDart
    $runtime = Join-Path $env:LOCALAPPDATA 'XCrossCLI\signing-runtime-v2.1.2'
    $commit = '29af3b65f302e6cb1ca653cb78b1f9a096e091ca'
    if (-not (Test-Path -LiteralPath $runtime)) {
        Write-Host (Msg '  Preparing the XCross signing engine (first run only)...' '  Preparando el motor de firma XCross (solo la primera vez)...')
        if (-not (Invoke-Tool 'git' @('clone','--depth','1','--branch','v2.1.2','https://github.com/arxdeus/xcross.git',$runtime))) { return $false }
    }
    $actual = & git -C $runtime rev-parse HEAD
    if ($LASTEXITCODE -ne 0 -or $actual -ne $commit) { throw 'El motor de firma no corresponde a la revision verificada de XCross 2.1.2.' }
    $packages = Join-Path $runtime '.dart_tool\package_config.json'
    if (-not (Test-Path -LiteralPath $packages)) {
        Push-Location -LiteralPath $runtime
        try { $ready = Invoke-Tool $dart @('pub','get','--enforce-lockfile') }
        finally { Pop-Location }
        if (-not $ready) { return $false }
    }
    $python = Get-IpaPython
    $toolArgs = @($python.Prefix) + @((Join-Path $PSScriptRoot 'ipa_workflow.py'), $Path,
        '--dart',$dart,'--packages',$packages,'--bridge',(Join-Path $PSScriptRoot 'xcross_ipa_bridge.dart'),'--udid',$Udid)
    if ($ResignAdhoc) { $toolArgs += '--resign-adhoc' }
    $previousMode = $env:XCROSS_BUNDLE_ID
    try {
        if ($script:Settings.BundleIdMode -in @('original','prefixed')) { $env:XCROSS_BUNDLE_ID = $script:Settings.BundleIdMode }
        Write-Host (Msg '  Signing a temporary copy using your saved XCross identity, then installing. No new login required.' '  Firmando una copia temporal con tu sesion guardada de XCross e instalando. Sin pedir otro acceso.') -ForegroundColor Cyan
        return (Invoke-IpaProcess $python.Tool $toolArgs)
    }
    finally { $env:XCROSS_BUNDLE_ID = $previousMode }
}

function Invoke-XtoolCommand {
    param([string[]]$Arguments = @())
    try {
        $python = Get-IpaPython
        $helper = Join-Path $PSScriptRoot 'xtool_workflow.py'
        if (-not (Test-Path -LiteralPath $helper -PathType Leaf)) { throw 'Falta xtool_workflow.py. Actualiza xcm con update-cli.' }
        $toolArgs = @($python.Prefix) + @($helper) + $Arguments
        # Display stdout via Out-Host rather than swallowing it into the boolean
        # return value. stdin stays interactive; authentication is never logged.
        $interactive = ($Arguments -contains 'auth') -or
            (($Arguments -contains 'init' -or $Arguments -contains 'setup') -and $Arguments -notcontains '--check')
        $ok = if ($interactive) { Invoke-InteractiveTool $python.Tool $toolArgs } else { Invoke-Tool $python.Tool $toolArgs }
        if ($Arguments.Count -and $Arguments[0] -in @('install','build','run')) {
            $latest = Get-ChildItem -LiteralPath (Join-Path $script:SettingsDir 'logs') -Filter 'ipa-*-xtool-*.log' -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($latest) { $script:LastIpaLog = $latest.FullName }
        }
        return $ok
    }
    catch { Write-Fail $_.Exception.Message; return $false }
}

function Invoke-IpaCommand {
    param([string[]]$Arguments = @())
    if ($Arguments.Count -eq 0) { Show-IpaMenu; return $true }
    $operation = $Arguments[0].ToLowerInvariant()
    if ($operation -eq 'logs' -and $Arguments.Count -eq 1) { Show-IpaLog; return $true }
    $allowed = @{
        build = @('--project','--mode','--target','--flavor')
        sign = @('--certificate','--profile','--output','--bundle-id')
        install = @('--udid','--backend')
        'install-xtool' = @('--udid')
        inspect = @()
    }
    if (-not $allowed.ContainsKey($operation)) {
        Write-Fail 'Uso: xcm ipa inspect|build|sign|install (xcm help)'; return $false
    }
    $options = @{}
    $inputPath = ''
    for ($i = 1; $i -lt $Arguments.Count; $i++) {
        $arg = $Arguments[$i]
        if ($arg -in $allowed[$operation]) {
            if ($options.ContainsKey($arg) -or $i + 1 -ge $Arguments.Count -or $Arguments[$i + 1] -like '--*') {
                Write-Fail "Valor ausente o repetido: $arg"; return $false
            }
            $i++
            $options[$arg] = $Arguments[$i]
        }
        elseif ($arg.StartsWith('-') -or $inputPath -or $operation -eq 'build') {
            Write-Fail "Argumento no reconocido: $arg"; return $false
        }
        else { $inputPath = $arg }
    }
    try {
        switch ($operation) {
            'inspect' {
                if (-not $inputPath) { $inputPath = (Read-Host 'IPA').Trim().Trim('"') }
                $report = Get-IpaInspection (Resolve-IpaFile $inputPath)
                Show-IpaInspection $report
                return ($report.issues -notcontains 'invalid_package')
            }
            'build' {
                $mode = if ($options['--mode']) { $options['--mode'].ToLowerInvariant() } else { 'release' }
                if ($mode -notin @('debug','profile','release')) { throw 'Usa --mode debug|profile|release' }
                $project = Select-FlutterProject -ExplicitPath $options['--project']
                if (-not $project) { return $false }
                $toolArgs = @('flutter','build','--ipa',"--$mode")
                if ($options['--target']) { $toolArgs += @('--target', $options['--target']) }
                if ($options['--flavor']) { $toolArgs += @('--flavor', $options['--flavor']) }
                Push-Location -LiteralPath $project
                try { $ok = Invoke-Tool 'xcross' $toolArgs }
                finally { Pop-Location }
                if ($ok) {
                    Write-Ok (Msg 'IPA build completed; see the output path above.' 'Compilacion IPA terminada; consulta la ruta indicada arriba.')
                    Write-Host (Msg 'For USB installation, sign the IPA with a certificate and provisioning profile first.' 'Para instalar por USB, firma primero la IPA con certificado y perfil de aprovisionamiento.')
                }
                return $ok
            }
            'sign' {
                if (-not $inputPath) { $inputPath = (Read-Host 'IPA').Trim().Trim('"') }
                $ipa = Resolve-IpaFile $inputPath
                if (-not (Test-Tool 'zsign')) {
                    Write-Warn (Msg 'Manual signing requires zsign + P12 + profile. For Apple ID signing without P12, use IPA menu option 4 or xcm install PATH.ipa --backend xtool.' 'La firma manual requiere zsign + P12 + perfil. Para firmar con Apple ID sin P12, usa la opcion 4 del menu IPA o xcm install RUTA.ipa --backend xtool.')
                    throw 'Falta zsign en PATH (opcional). Alternativa: xcm xtool install-tool, xcm xtool auth.'
                }
                $cert = $options['--certificate']
                if (-not $cert) { $cert = (Read-Host 'Certificado con clave privada (.p12)').Trim().Trim('"') }
                if ([IO.Path]::GetExtension($cert) -ine '.p12' -or -not (Test-Path -LiteralPath $cert -PathType Leaf)) {
                    throw 'Se requiere un certificado .p12 con su clave privada.'
                }
                $cert = (Resolve-Path -LiteralPath $cert).Path
                $profile = $options['--profile']
                if (-not $profile) { $profile = (Read-Host 'Perfil (.mobileprovision)').Trim().Trim('"') }
                if ([IO.Path]::GetExtension($profile) -ine '.mobileprovision' -or -not (Test-Path -LiteralPath $profile -PathType Leaf)) {
                    throw 'Se requiere un perfil .mobileprovision valido para la app y el dispositivo.'
                }
                $profile = (Resolve-Path -LiteralPath $profile).Path
                $output = $options['--output']
                if (-not $output) { $output = Join-Path (Split-Path -Parent $ipa) (([IO.Path]::GetFileNameWithoutExtension($ipa)) + '-signed.ipa') }
                $output = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($output)
                if ([IO.Path]::GetExtension($output) -ine '.ipa') { throw 'La salida debe terminar en .ipa.' }
                if ($output -ieq $ipa -or (Test-Path -LiteralPath $output)) { throw 'La salida ya existe o coincide con la IPA original. Usa --output con una ruta nueva.' }
                if (-not (Test-Path -LiteralPath (Split-Path -Parent $output) -PathType Container)) { throw 'La carpeta de salida no existe.' }
                $toolArgs = @('-k',$cert,'-m',$profile,'-o',$output)
                if ($options['--bundle-id']) { $toolArgs += @('-b',$options['--bundle-id']) }
                Write-Host (Msg 'Enter the P12 password (empty if none). It is not saved. zsign receives it as a process argument.' 'Introduce la clave del P12 (vacia si no tiene). No se guarda. zsign la recibe como argumento de proceso.')
                $secret = Read-Host 'P12 password' -AsSecureString
                $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
                try {
                    $password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
                    if ($password.Length) { $toolArgs += @('-p',$password) }
                    $toolArgs += $ipa
                    $ok = Invoke-Tool 'zsign' $toolArgs -HideArguments
                }
                finally {
                    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
                    $password = $null
                    $toolArgs = $null
                    $secret.Dispose()
                }
                if (-not $ok) { return $false }
                if (-not (Test-Path -LiteralPath $output -PathType Leaf) -or (Get-Item -LiteralPath $output).Length -eq 0) {
                    throw 'zsign no genero una IPA de salida valida.'
                }
                Write-Ok "IPA: $output"
                return $true
            }
            {$_ -in @('install','install-xtool')} {
                if (-not $inputPath) { $inputPath = (Read-Host (Msg 'IPA path' 'Ruta de la IPA')).Trim().Trim('"') }
                $ipa = Resolve-IpaFile $inputPath
                $report = Get-IpaInspection $ipa
                $backend = if ($operation -eq 'install-xtool') { 'xtool' } elseif ($options['--backend']) { $options['--backend'].ToLowerInvariant() } else { 'auto' }
                if ($backend -notin @('auto','xcross','xtool')) { throw 'Usa --backend auto|xcross|xtool.' }
                Show-IpaInspection $report -ReSign:($backend -eq 'xtool')
                $blocking = @($report.issues | Where-Object { $_ -notin @('missing_signature','adhoc_signature') })
                if ($blocking.Count) { throw ('IPA incompatible: ' + ($blocking -join ', ')) }
                if ($backend -eq 'xtool') {
                    Write-Warn (Msg 'xtool will provision and RE-SIGN a temporary copy, including supported extensions. Original IPA is preserved.' 'xtool aprovisionara y REEMPLAZARA la firma de una copia temporal, incluidas extensiones compatibles. La IPA original se conserva.')
                    if ($backend -eq 'auto' -and -not (Confirm-Yes (Msg 'Sign and install with xtool in WSL?' 'Firmar e instalar con xtool en WSL?'))) { return $false }
                    $backendArgs = @('install',$ipa)
                    if ($options['--udid']) { $backendArgs += @('--udid',$options['--udid']) }
                    return (Invoke-XtoolCommand -Arguments $backendArgs)
                }
                $devices = @(Get-UsbDevices | Where-Object { $_.ConnectionType -eq 'USB' })
                if ($devices.Count -eq 0) { throw 'No hay iPhone por USB. Conecta, desbloquea y acepta Confiar.' }
                $udid = $options['--udid']
                if (-not $udid -and $devices.Count -gt 1) {
                    foreach ($device in $devices) { Write-Host "$($device.DeviceName) | $($device.Identifier)" }
                    $udid = (Read-Host 'UDID del iPhone / Target UDID').Trim()
                    if (-not $udid) { throw 'Selecciona un UDID o usa --udid.' }
                }
                if ($udid) {
                    $devices = @($devices | Where-Object { $_.Identifier -eq $udid -or $_.UniqueDeviceID -eq $udid })
                    if ($devices.Count -ne 1) { throw 'El UDID no corresponde a un unico iPhone conectado por USB.' }
                }
                $device = $devices[0]
                $udid = if ($device.UniqueDeviceID) { $device.UniqueDeviceID } else { $device.Identifier }
                if (-not $udid) { throw 'No se pudo determinar el UDID.' }
                Write-Host "$($device.DeviceName) | $udid"
                if ($report.signature -in @('missing','adhoc')) { $ok = Install-NativeIpa -Path $ipa -Udid $udid -ResignAdhoc:($report.signature -eq 'adhoc') }
                else { $ok = Invoke-IpaProcess 'pymobiledevice3' @('apps','install','--udid',$udid,'--streaming',$ipa) }
                if ($ok) { Write-Ok (Msg 'IPA installed.' 'IPA instalada.') }
                return $ok
            }
        }
    }
    catch { Write-Fail $_.Exception.Message; return $false }
}

function Update-CurrentProject {
    param([string]$Path = '.')
    if (-not (Test-Tool 'git')) { Write-Fail 'Falta Git en PATH.'; return $false }
    try {
        $project = (Resolve-Path -LiteralPath $Path).Path
        if (-not (Test-Path -LiteralPath $project -PathType Container)) { throw 'Selecciona una carpeta.' }
        $root = & git -C $project rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -ne 0) { throw 'La carpeta actual no pertenece a un repositorio Git.' }
        $changes = & git -C $project status --porcelain 2>&1
        if ($LASTEXITCODE -ne 0) { throw ($changes -join "`n") }
        if ($changes) { throw 'Hay cambios locales. Guarda tus cambios en Git antes de actualizar.' }
        $upstream = & git -C $project rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>$null
        if ($LASTEXITCODE -ne 0) { throw 'La rama actual no tiene upstream o estas en detached HEAD.' }
        Write-Host "Proyecto: $root | upstream: $upstream"
        return (Invoke-Tool 'git' @('-C',$project,'pull','--ff-only'))
    }
    catch { Write-Fail $_.Exception.Message; return $false }
}

function Show-IpaMenu {
    $items = @(
        @{ Key='1'; Label=(Msg 'Check IPA' 'Revisar IPA'); Description=(Msg 'Read-only signature inspection' 'Revisar firma, sin instalar'); Command='inspect' },
        @{ Key='2'; Label=(Msg 'Install IPA' 'Instalar IPA'); Description=(Msg 'Reuse your saved XCross identity' 'Usar tu sesion guardada de XCross'); Command='install' },
        @{ Key='3'; Label=(Msg 'Build IPA (Flutter)' 'Compilar IPA (Flutter)'); Description='release / xcross'; Command='build' },
        @{ Key='4'; Label=(Msg 'Sign + install (xtool)' 'Firmar + instalar (xtool)'); Description='WSL + Apple ID / no P12'; Command='install-xtool' },
        @{ Key='5'; Label=(Msg 'Last IPA log' 'Ultimo registro IPA'); Description=(Msg 'Details of the last operation' 'Detalles de la ultima operacion'); Command='logs' },
        @{ Key='6'; Label=(Msg 'Manual signing (optional)' 'Firma manual (opcional)'); Description='zsign + P12 + mobileprovision'; Command='sign' },
        @{ Key='7'; Label=(Msg 'Prepare IPA installation' 'Preparar instalacion de IPA'); Description='xcm init ipa'; Command='init-ipa' }
    )
    while ($true) {
        $choice = Show-KeyMenu -Title 'IPA' -Subtitle (Get-Location).Path -Items $items -AllowPalette
        if ($choice -eq '__back__') { return }
        if ($choice -eq '__palette__') { Show-PaletteThenRun; continue }
        if ($choice -eq 'init-ipa') { [void](Initialize-Xcm -Arguments @('ipa')) }
        elseif ($choice -like 'xtool-*') { [void](Invoke-XtoolCommand -Arguments @($choice.Substring(6))) }
        else { [void](Invoke-IpaCommand -Arguments @($choice)) }
        Pause-Menu
    }
}

function Flutter-Doctor {
    [void](Test-ProjectEnvironment)
}

function Flutter-Run {
    param([ValidateSet('usb','wifi')][string]$Transport = 'usb', [string]$Target = '', [switch]$VerboseRun)
    Write-Title "Ejecutar proyecto ($Transport)"
    if (-not (Test-Tool 'xcross')) { Write-Fail 'Instala xcross primero.'; return $false }
    $project = Select-FlutterProject
    if (-not $project) { return $false }
    Write-Host "  Proyecto: $project" -ForegroundColor DarkGray
    Write-Host (Msg '  Tip: if there is no RSD tunnel, open another terminal with xcm tunnel usb.' '  Consejo: si no hay tunel RSD, abre otro terminal con xcm tunnel usb.') -ForegroundColor DarkGray
    Write-Host '  Hot Reload: r   |   Hot Restart: R   |   salir: q' -ForegroundColor Cyan
    $toolArgs = @('flutter', 'run', "--$Transport")
    if ($Target) {
        $targetFile = Join-Path $project $Target
        if (-not (Test-Path -LiteralPath $targetFile -PathType Leaf)) {
            Write-Fail "No existe el entrypoint: $targetFile"
            return $false
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
    try { return (Invoke-Tool 'xcross' $toolArgs) }
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
    Write-Host (Msg '2. Open on iPhone: Settings > General > Device Management & VPN.' '2. Abre en iPhone: Configuracion > General > Adm. de dispositivos y VPN.')
    Write-Host '3. Busca la identidad Apple Development usada para firmar la app.'
    Write-Host '4. Si el iPhone ofrece Confiar/Permitir y reiniciar, confirma desde el dispositivo.'
    Write-Host (Msg '5. Open the app directly from the iPhone before testing the debugger.' '5. Abre la app directamente desde el iPhone antes de probar el depurador.')
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
        @{ Key='6'; Label=(Msg 'Sign an existing IPA' 'Firmar una IPA existente'); Description='zsign + P12 + mobileprovision'; Command='ipa-sign' }
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
            'ipa-sign' { [void](Invoke-IpaCommand -Arguments @('sign')) }
        }
        Pause-Menu
    }
}

function Upgrade-Xcross {
    param([string[]]$Arguments = @())
    if (-not (Test-Tool 'xcross')) { Write-Fail 'Usa xcm xcross para instalar XCross.'; return $false }
    for ($i=0; $i -lt $Arguments.Count; $i++) {
        if ($Arguments[$i] -in @('--check','--force')) { continue }
        if ($Arguments[$i] -eq '--ref' -and $i+1 -lt $Arguments.Count -and -not $Arguments[$i+1].StartsWith('-')) { $i++; continue }
        Write-Fail 'Uso: xcm update [--check] [--force] [--ref REF]'; return $false
    }
    $checkArgs = @('update','--check') + @($Arguments | Where-Object { $_ -ne '--check' -and $_ -ne '--force' })
    if (-not (Invoke-Tool 'xcross' $checkArgs)) { return $false }
    if ($Arguments -contains '--check') { return $true }
    if (Confirm-Yes 'Actualizar xcross a la ultima version publicada?') {
        if (-not (Invoke-Tool 'xcross' (@('update') + $Arguments))) { return $false }
        Refresh-Path
        return (Invoke-Tool 'xcross' @('--version'))
    }
    return $false
}

function Guided-Setup {
    Write-Title 'Asistente de preparacion inicial'
    Write-Host '1) Swift >= 6.4  2) xcross  3) LLVM/Python/Build Tools'
    Write-Host '4) SDK desde Xcode.xip  5) Conexion USB  6) Modo desarrollador'
    if (-not (Install-Swift)) {
        Write-Warn 'Detenido en Swift. Si acabas de instalarlo, reinicia PowerShell y reintenta.'
        return $false
    }
    if (-not (Install-Xcross)) { return $false }
    if (-not (Install-Dependencies)) { return $false }
    if (Confirm-Yes 'Quieres importar ahora el SDK desde un archivo Xcode.xip local?') {
        Install-DarwinSdk
    }
    $project = Select-Project -Optional
    if ($project -and (Get-ProjectKind $project) -eq 'flutter' -and (Confirm-Yes 'Quieres descargar los artefactos iOS debug de Flutter con xcross?')) {
        Precache-FlutterIos -PreselectedMode 'debug'
    }
    if (Confirm-Yes 'Quieres comprobar la conexion USB del iPhone?') {
        [void](Show-UsbDevices)
    }
    Write-Host 'Despues usa las opciones del menu para Modo desarrollador, Autenticacion y Tunel.'
    if ($project) { return (Test-ProjectEnvironment -Path $project) }
    return (Test-XcmEnvironment)
}

function Initialize-Xcm {
    param([string[]]$Arguments = @())
    $mode = ''; $check = $false
    foreach ($argument in $Arguments) {
        if ($argument -eq '--check') { $check = $true }
        elseif ($argument -in @('ipa','flutter','swift') -and -not $mode) { $mode = $argument }
        else { Write-Fail 'Uso: xcm init [ipa|flutter|swift] [--check]'; return $false }
    }
    if (-not $mode) {
        $kind = Get-ProjectKind (Get-Location).Path
        $mode = switch ($kind) {
            'flutter' { 'flutter' }
            'swift' { 'swift' }
            {$_ -in @('xtool','xcode')} { 'ipa' }
            default { if (Test-CurrentIpaFolder) { 'ipa' } else { $script:Settings.SetupWorkflow } }
        }
    }
    if (-not $mode) {
        if ($check) { Write-Fail 'Selecciona el flujo: xcm init ipa|flutter|swift --check'; return $false }
        $mode = Show-KeyMenu -Title 'INIT' -Subtitle (Msg 'What do you want to prepare?' 'Que quieres preparar?') -Items @(
            @{Key='1'; Label=(Msg 'Install an IPA on iPhone' 'Instalar una IPA en iPhone'); Description='Apple login + USB'; Command='ipa'},
            @{Key='2'; Label=(Msg 'Flutter iOS project' 'Proyecto Flutter iOS'); Description='Swift + XCross + SDK'; Command='flutter'},
            @{Key='3'; Label=(Msg 'Swift package on Windows' 'Paquete Swift en Windows'); Description='Swift toolchain'; Command='swift'}
        )
        if ($mode -eq '__back__') { return $false }
    }
    Write-Title "Init / $mode"
    if (-not $check) { $script:Settings.SetupWorkflow = $mode; Save-Settings }
    switch ($mode) {
        'ipa' {
            if ($check) { return (Test-IpaEnvironment) }
            if (-not (Test-Tool 'xcross') -and -not (Install-Xcross)) { return $false }
            if (-not (Test-XcrossSavedIdentity) -and -not (Connect-AppleId)) { return $false }
            return (Test-IpaEnvironment)
        }
        'flutter' {
            if ($check) { return (Test-ProjectEnvironment) }
            return (Guided-Setup)
        }
        'swift' {
            if ($check) { return (Invoke-Tool 'swift' @('--version')) }
            return (Install-Swift)
        }
    }
}

function Get-MenuItems {
    return @(
        @{Key='N'; Label=(Msg 'Prepare environment' 'Preparar entorno'); Description='xcm init'; Command='init'},
        @{Key='1'; Label=(Msg 'Run project' 'Ejecutar proyecto'); Description='xcm run'; Command='run'},
        @{Key='7'; Label=(Msg 'Install IPA' 'Instalar IPA'); Description='xcm install app.ipa'; Command='install-ipa'},
        @{Key='2'; Label=(Msg 'Check environment' 'Comprobar entorno'); Description='xcm doctor'; Command='doctor'},
        @{Key='P'; Label=(Msg 'Projects' 'Proyectos'); Description='xcm project'; Command='projects'},
        @{Key='U'; Label=(Msg 'Update xcm' 'Actualizar xcm'); Description='xcm update-cli'; Command='update-cli'},
        @{Key='A'; Label=(Msg 'Advanced tools' 'Herramientas avanzadas'); Description='SDK / tunnels / signing'; Command='advanced'},
        @{Key='L'; Label=(Msg 'Language' 'Idioma'); Description='en / es'; Command='language'},
        @{Key='?'; Label=(Msg 'Help' 'Ayuda'); Description='xcm help'; Command='help'}
    )
}

function Get-AdvancedMenuItems {
    if ($script:Language -eq 'es') {
        return @(
            @{ Key='1'; Label='Ejecutar proyecto en iPhone'; Description='compilar, firmar, instalar, hot reload'; Command='run' },
            @{ Key='2'; Label='Diagnostico de Flutter'; Description='xcross flutter doctor'; Command='doctor' },
            @{ Key='3'; Label='Detectar iPhone'; Description='USB y version de iOS'; Command='device' },
            @{ Key='4'; Label='Modo desarrollador'; Description='estado y activacion'; Command='devmode' },
            @{ Key='5'; Label='Abrir tunel USB'; Description='abre PowerShell con permisos'; Command='tunnel-usb' },
            @{ Key='6'; Label='Abrir tunel Wi-Fi'; Description='enlace inalambrico'; Command='tunnel-wifi' },
            @{ Key='7'; Label='Instalar IPA existente'; Description='revisa y firma solo si falta'; Command='install-ipa' },
            @{ Key='D'; Label='Descargas y SDK'; Description='Swift, xcross, Xcode, precache'; Command='downloads' },
            @{ Key='F'; Label='Firma y App ID'; Description='autorizacion Apple Development'; Command='signing' },
            @{ Key='P'; Label='Proyectos Flutter / Swift'; Description='cambiar proyecto, VS Code, ejecutar'; Command='projects' },
            @{ Key='A'; Label='Compilar / firmar / instalar IPA'; Description='IPA nueva o existente'; Command='ipa' },
            @{ Key='G'; Label='Actualizar proyecto actual'; Description='Git pull --ff-only en esta carpeta'; Command='update-project' },
            @{ Key='I'; Label='Instalar comando xcm'; Description='disponible desde cualquier carpeta'; Command='install-cli' },
            @{ Key='U'; Label='Actualizar xcm'; Description='descarga la ultima version desde GitHub'; Command='update-cli' },
            @{ Key='X'; Label='Desinstalar xcm'; Description='elimina el comando global'; Command='uninstall-cli' },
            @{ Key='L'; Label='Idioma'; Description='cambiar ingles/espanol'; Command='language' },
            @{ Key='?'; Label='Comandos y ayuda'; Description='lista de comandos y ejemplos'; Command='help' }
        )
    }
    return @(
        @{ Key='1'; Label='Run project on iPhone'; Description='build, sign, install, hot reload'; Command='run' },
        @{ Key='2'; Label='Flutter diagnostics'; Description='xcross flutter doctor'; Command='doctor' },
        @{ Key='3'; Label='Detect iPhone'; Description='USB and iOS version'; Command='device' },
        @{ Key='4'; Label='Developer mode'; Description='status and activation'; Command='devmode' },
        @{ Key='5'; Label='Open USB tunnel'; Description='opens PowerShell with permissions'; Command='tunnel-usb' },
        @{ Key='6'; Label='Open Wi-Fi tunnel'; Description='wireless link'; Command='tunnel-wifi' },
        @{ Key='7'; Label='Install existing IPA'; Description='check, sign only if unsigned'; Command='install-ipa' },
        @{ Key='D'; Label='Downloads and SDK'; Description='Swift, xcross, Xcode, precache'; Command='downloads' },
        @{ Key='F'; Label='Signing and App ID'; Description='Apple Development authorization'; Command='signing' },
        @{ Key='P'; Label='Flutter / Swift projects'; Description='change project, VS Code, run'; Command='projects' },
        @{ Key='A'; Label='Build / sign / install IPA'; Description='new or existing IPA'; Command='ipa' },
        @{ Key='G'; Label='Update current project'; Description='Git pull --ff-only in this folder'; Command='update-project' },
        @{ Key='I'; Label='Install xcm command'; Description='available from any folder'; Command='install-cli' },
        @{ Key='U'; Label='Update xcm'; Description='download latest version from GitHub'; Command='update-cli' },
        @{ Key='X'; Label='Uninstall xcm'; Description='remove global command'; Command='uninstall-cli' },
        @{ Key='L'; Label='Language'; Description='switch English/Spanish'; Command='language' },
        @{ Key='?'; Label='Commands and help'; Description='command list and examples'; Command='help' }
    )
}

function Show-Menu {
    param([switch]$Advanced)
    $items = if ($Advanced) { Get-AdvancedMenuItems } else { Get-MenuItems }
    while ($true) {
        $choice = Show-KeyMenu -Title 'XCROSS CONSOLE' -Subtitle 'Flutter iOS  /  SwiftPM  /  Windows' -Items $items -AllowPalette
        if ($choice -eq '__back__') { return }
        if ($choice -eq '__palette__') { Show-PaletteThenRun; continue }
        switch ($choice) {
            'init' { [void](Initialize-Xcm) }
            'advanced' { Show-Menu -Advanced; continue }
            'run' { [void](Invoke-ProjectCommand -Operation run) }
            'doctor' { [void](Invoke-XcmCommand -Verb 'doctor') }
            'device' { [void](Show-UsbDevices) }
            'devmode' { Developer-Mode }
            'tunnel-usb' { Start-TunnelWindow 'usb' }
            'tunnel-wifi' { Start-TunnelWindow 'wifi' }
            'downloads' { Downloads-Menu; continue }
            'signing' { Signing-Menu; continue }
            'projects' { Projects-Menu; continue }
            'ipa' { Show-IpaMenu; continue }
            'install-ipa' { [void](Invoke-IpaCommand -Arguments @('install')) }
            'update-project' { [void](Update-CurrentProject) }
            'install-cli' { Install-XcmGlobal }
            'update-cli' { [void](Update-XcmGlobal) }
            'uninstall-cli' { Uninstall-XcmGlobal }
            'language' { Set-Language }
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
    $logo = @'
█   █  ███  █   █
 █ █ ░█ ░░░ ██ ██░
  █ ░ █░ ░░░█░█ █░░
 █ █ ░█░░   █░░░█░░
█ ░ █  ███  █░░ █░░
 ░ ░ ░  ░░░  ░░  ░░
  ░   ░  ░░░  ░   ░
'@
    Write-Host ''
    foreach ($line in ($logo -split "`r?`n")) {
        if ($line.Trim() -ne '') { Write-Host ("    " + $line) -ForegroundColor Cyan }
    }
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

function Format-MenuText([string]$Text, [int]$Width) {
    if ($Width -le 0) { return '' }
    if ($Text.Length -gt $Width) { return $Text.Substring(0, [Math]::Max(0, $Width - 1)) + '~' }
    return $Text.PadRight($Width)
}

function Show-KeyMenu {
    param([string]$Title, [string]$Subtitle, [object[]]$Items, [switch]$AllowPalette)
    $index = 0
    while ($true) {
        # Redraw instead of reusing cursor coordinates: wrapping and a short
        # terminal used to corrupt the border and hide selectable rows.
        $width = 80; $height = 40
        try {
            if ([Console]::WindowWidth -gt 0) { $width = [Console]::WindowWidth }
            if ([Console]::WindowHeight -gt 0) { $height = [Console]::WindowHeight }
        } catch {}
        $compact = $height -lt 35 -or $width -lt 80
        $pageSize = if ($compact) { [Math]::Max(3, $height - 10) } else { [Math]::Max(3, $height - 27) }
        $pageStart = [int]([Math]::Floor($index / $pageSize) * $pageSize)
        $pageEnd = [Math]::Min($Items.Count, $pageStart + $pageSize)
        $rowWidth = [Math]::Max(12, $width - 6)
        Clear-Host
        if ($compact) {
            Write-Host (Format-MenuText ("xcm / $Title") ([Math]::Max(12,$width - 2))) -ForegroundColor Cyan
            Write-Host (Format-MenuText $Subtitle ([Math]::Max(12,$width - 2))) -ForegroundColor DarkGray
            Write-Host ''
        }
        else { Show-Banner -Title $Title -Subtitle $Subtitle }
        for ($i = $pageStart; $i -lt $pageEnd; $i++) {
            $item = $Items[$i]
            $text = ('{0}  {1}' -f ([string]$item.Key).PadRight(2), [string]$item.Label)
            if ($width -ge 95) { $text = $text.PadRight(40) + ' ' + [string]$item.Description }
            $text = Format-MenuText $text $rowWidth
            if ($i -eq $index) { Write-Host ('  > ' + $text) -ForegroundColor Black -BackgroundColor Cyan }
            else { Write-Host ('    ' + $text) -ForegroundColor Gray }
        }
        Write-Host ''
        Write-Host (Format-MenuText ('  ' + [string]$Items[$index].Description) ([Math]::Max(12,$width - 2))) -ForegroundColor DarkCyan
        $keys = (@($Items[$pageStart..($pageEnd - 1)] | ForEach-Object { [string]$_.Key }) -join '/')
        Write-Host (Format-MenuText (Msg "  Keys: $keys (no Enter needed)" "  Teclas: $keys (sin pulsar Enter)") ([Math]::Max(12,$width - 2))) -ForegroundColor DarkGray
        Write-Host (Format-MenuText (Msg "  $($pageStart + 1)-$pageEnd / $($Items.Count) | Up/Down: move | Enter: select" "  $($pageStart + 1)-$pageEnd / $($Items.Count) | Flechas: mover | Enter: elegir") ([Math]::Max(12,$width - 2))) -ForegroundColor DarkGray
        if ($AllowPalette) { Write-Host (Msg '  / commands   ESC/0 back or exit' '  / comandos   ESC/0 atras o salir') -ForegroundColor DarkGray }
        else { Write-Host (Msg '  ESC/0 back' '  ESC/0 atras') -ForegroundColor DarkGray }
        try { $keyInfo = [Console]::ReadKey($true) }
        catch {
            $fallback = Read-Host (Msg 'Option' 'Opcion')
            foreach ($item in $Items) { if ($fallback -eq [string]$item.Key) { return [string]$item.Command } }
            if ($fallback -eq '0') { return '__back__' }
            if ($AllowPalette -and $fallback -eq '/') { return '__palette__' }
            continue
        }
        if ($keyInfo.Key -eq [ConsoleKey]::Escape) { return '__back__' }
        if ($keyInfo.Key -eq [ConsoleKey]::UpArrow) { $index=($index+$Items.Count-1)%$Items.Count; continue }
        if ($keyInfo.Key -eq [ConsoleKey]::DownArrow) { $index=($index+1)%$Items.Count; continue }
        if ($keyInfo.Key -eq [ConsoleKey]::Home) { $index=0; continue }
        if ($keyInfo.Key -eq [ConsoleKey]::End) { $index=$Items.Count-1; continue }
        if ($keyInfo.Key -in @([ConsoleKey]::RightArrow,[ConsoleKey]::Spacebar,[ConsoleKey]::Enter)) { return [string]$Items[$index].Command }
        $char = [string]$keyInfo.KeyChar
        if ($char -eq '0') { return '__back__' }
        if ($AllowPalette -and $char -eq '/') { return '__palette__' }
        foreach ($item in $Items) {
            if ($char.ToUpperInvariant() -eq ([string]$item.Key).ToUpperInvariant()) { return [string]$item.Command }
        }
    }
}

function Get-PaletteEntries {
    return @(
        @{ Name='init'; Detail='Preparar el entorno sin repetir pasos completados' },
        @{ Name='install'; Detail='Instalar una IPA existente' },
        @{ Name='build'; Detail='Compilar el proyecto seleccionado' },
        @{ Name='update-cli'; Detail='Actualizar xcm' },
        @{ Name='help --all'; Detail='Ver herramientas avanzadas y alias' },
        @{ Name='ipa'; Detail='Compilar, firmar e instalar IPA' },
        @{ Name='install-ipa'; Detail='Revisar IPA, firmar si falta e instalar' },
        @{ Name='ipa inspect'; Detail='Revisar firma de una IPA sin instalar' },
        @{ Name='ipa build'; Detail='Generar IPA release del proyecto Flutter actual' },
        @{ Name='ipa sign'; Detail='Firmar IPA con P12 y mobileprovision' },
        @{ Name='ipa install'; Detail='Instalar IPA existente por USB' },
        @{ Name='project update'; Detail='Actualizar repositorio de la carpeta actual' },
        @{ Name='update-cli --local'; Detail='Instalar esta copia local de xcm' },
        @{ Name='run'; Detail='Flutter por USB / SwiftPM en Windows' },
        @{ Name='run --wifi'; Detail='Ejecutar proyecto por Wi-Fi' },
        @{ Name='doctor'; Detail='Diagnostico segun tipo de proyecto' },
        @{ Name='doctor --environment'; Detail='Comprobar host sin proyecto' },
        @{ Name='download all'; Detail='Preparacion guiada del entorno' },
        @{ Name='update --check'; Detail='Consultar actualizacion de XCross' },
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
        @{ Name='project set'; Detail='Elegir carpeta Flutter / Swift / Xcode' },
        @{ Name='bundle original'; Detail='Usar identificador App ID original' },
        @{ Name='bundle prefixed'; Detail='Usar identificador App ID prefijado' },
        @{ Name='sign'; Detail='Diagnosticar firma de Apple' },
        @{ Name='trust'; Detail='Ayuda de desarrollador no confiable' },
        @{ Name='auth'; Detail='Apple ID para Flutter (XCross)' },
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
    $everyday = @('init','install','run','build','doctor','project show','project set','project update','update-cli','help','help --all')
    while ($true) {
        $q=$buffer.Trim()
        if ($q) {
            $matches=@($commands | Where-Object {
                $_.Name -match [regex]::Escape($q) -or $_.Detail -match [regex]::Escape($q)
            })
        }
        else { $matches=@($commands | Where-Object { $_.Name -in $everyday }) }
        if ($selected -ge $matches.Count) { $selected=0 }
        Clear-Host
        if ($script:Language -eq 'es') { Show-Banner -Title 'PALETA DE COMANDOS' -Subtitle 'Escribe para filtrar; sin Enter para seleccionar' } else { Show-Banner -Title 'COMMAND PALETTE' -Subtitle 'Type to filter commands; no Enter to select' }
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
        @{Key='1'; Label='Cambiar proyecto'; Description='pubspec.yaml, Package.swift, Xcode'; Command='set'},
        @{Key='2'; Label='Ver proyecto'; Description='muestra ruta guardada'; Command='show'},
        @{Key='3'; Label='Diagnostico del proyecto'; Description='Flutter / Swift / Xcode'; Command='doctor'},
        @{Key='4'; Label='Ejecutar proyecto'; Description='Flutter USB / Swift en este PC'; Command='usb'},
        @{Key='5'; Label='Ejecutar por Wi-Fi'; Description='xcross flutter run --wifi'; Command='wifi'},
        @{Key='6'; Label='Integrar VS Code'; Description='configurar archivos .vscode'; Command='vscode'}
        @{Key='7'; Label=(Msg 'Update current repository' 'Actualizar repositorio actual'); Description='Git pull --ff-only'; Command='update'}
    )
    while($true){
        $choice=Show-KeyMenu -Title 'PROYECTOS' -Subtitle 'Flutter, SwiftPM, Xcode' -Items $items -AllowPalette
        if($choice -eq '__back__'){return}
        if($choice -eq '__palette__'){Show-PaletteThenRun;continue}
        switch($choice){
            'set' {[void](Select-Project -ForcePrompt)}
            'show' {Show-CurrentProject}
            'doctor' {Flutter-Doctor}
            'usb' {[void](Invoke-ProjectCommand -Operation run)}
            'wifi' {[void](Invoke-ProjectCommand -Operation run -Arguments @('--wifi'))}
            'vscode' {Flutter-Ide}
            'update' {[void](Update-CurrentProject)}
        }
        Pause-Menu
    }
}

function Show-CurrentProject {
    Write-Title 'Project / Proyecto'
    $p=Select-Project
    if($p){Write-Ok "$p ($(Get-ProjectKind $p))"}
}

function Install-XcmGlobal {
    $installer=Join-Path $PSScriptRoot 'install.ps1'
    if(-not (Test-Path -LiteralPath $installer)){
        Write-Fail (Msg 'install.ps1 not found in package.' 'No se encontro install.ps1 en el paquete.')
        return
    }
    Write-Title 'Comando xcm global'
    Write-Host '  Copia los scripts a AppData local y agrega la carpeta a tu PATH de usuario.'
    Write-Host '  No requiere Administrador. Puedes revertirlo con el desinstalador.' -ForegroundColor DarkGray
    if(Confirm-Yes 'Instalar comando global xcm?') {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer 2>&1 | Out-Host
    }
}

function Uninstall-XcmGlobal {
    $uninstaller=Join-Path $PSScriptRoot 'uninstall.ps1'
    Write-Title 'Desinstalar xcm global'
    if(Test-Path -LiteralPath $uninstaller) {
        if(Confirm-Yes 'Eliminar el comando global xcm?') {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $uninstaller 2>&1 | Out-Host
        }
    }
    else {
        $target=Join-Path $env:LOCALAPPDATA 'Programs\XCrossCLI'
        if(Test-Path -LiteralPath $target) {
            if(Confirm-Yes "Eliminar $target y quitar del PATH?") {
                Remove-Item -LiteralPath $target -Recurse -Force
                $userPath=[Environment]::GetEnvironmentVariable('Path','User')
                $parts=@($userPath -split ';' | Where-Object { $_ -and $_.Trim() -and $_.TrimEnd('\') -ine $target.TrimEnd('\') })
                [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')
                Write-Ok 'xcm desinstalado.'
            }
        }
        else { Write-Warn 'xcm no esta instalado globalmente.' }
    }
}

function Set-Language {
    param([string]$Lang)
    if ($Lang) {
        $l = $Lang.ToLowerInvariant()
        if ($l -in @('en','es','english','spanish','ingles','espanol')) {
            if ($l -in @('es','spanish','espanol')) { $script:Language = 'es' } else { $script:Language = 'en' }
            $script:Settings.Language = $script:Language
            Save-Settings
            Write-Ok "Language set to $script:Language"
            return
        }
    }
    Write-Title 'Language'
    Write-Host '  Current: ' -NoNewline; Write-Host $script:Language -ForegroundColor Cyan
    Write-Host '  Usage: xcm language en|es'
    if (Confirm-Yes 'Switch to Spanish?') { $script:Language='es' } elseif (Confirm-Yes 'Switch to English?') { $script:Language='en' }
    $script:Settings.Language = $script:Language
    Save-Settings
    Write-Ok "Language: $script:Language"
}

function Update-XcmGlobal {
    param([switch]$Local)
    if ($Local) {
        $installer = Join-Path (Get-Location).Path 'windows\install.ps1'
        if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
            $installer = Join-Path (Get-Location).Path 'install.ps1'
        }
        if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
            Write-Fail (Msg 'Run update-cli --local from the XCross CLI package folder.' 'Ejecuta update-cli --local desde la carpeta del paquete XCross CLI.')
            return $false
        }
        return (Invoke-Tool 'powershell.exe' @('-NoProfile','-ExecutionPolicy','Bypass','-File',$installer))
    }
    Write-Title 'Actualizar xcm'
    $url='https://raw.githubusercontent.com/Ameth1208/xcross-cli/main/windows/xcm-install.ps1'
    Write-Host (Msg "  Downloading update from $url" "  Descargando actualizacion desde $url") -ForegroundColor DarkGray
    $tmp=Join-Path $env:TEMP ('xcm-install-' + [guid]::NewGuid().ToString('N') + '.ps1')
    try {
        Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing
        if (-not (Invoke-Tool 'powershell.exe' @('-NoProfile','-ExecutionPolicy','Bypass','-File',$tmp))) { return $false }
        Write-Ok 'xcm actualizado.'
        return $true
    }
    catch { Write-Fail $_.Exception.Message; return $false }
    finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
}

function Show-XcmHelp {
    param([switch]$All)
    if (-not $All) {
        Write-Title (Msg 'Everyday commands' 'Comandos habituales')
        Write-Host '  xcm init [ipa|flutter|swift] [--check]'
        Write-Host (Msg '      Prepare tools, login and USB for the selected workflow.' '      Preparar herramientas, sesion y USB segun el flujo elegido.')
        Write-Host '  xcm install "app.ipa"'
        Write-Host '  xcm run | build'
        Write-Host '  xcm doctor'
        Write-Host '  xcm project show|set|update [PATH]'
        Write-Host '  xcm update-cli'
        Write-Host '  xcm language en|es'
        Write-Host '  xcm version'
        Write-Host (Msg '  Advanced commands and compatibility aliases: xcm help --all' '  Comandos avanzados y alias compatibles: xcm help --all')
        return
    }
    Write-Host '  xcm init [ipa|flutter|swift] [--check]'
    Write-Host '  xcm xtool install-tool | auth [--refresh] | connect-usb | devices | doctor'
    Write-Host '  xcm install PATH.ipa --backend xtool [--udid UDID]'
    Write-Host '  xcm xtool build|run --project PATH [--configuration debug|release]'
    Write-Host '  xcm xtool sdk PATH-TO-Xcode.xip'
    Write-Host '  xcm xtool --distro Ubuntu-24.04 doctor'
    Write-Host (Msg 'Projects: Flutter iOS, SwiftPM on Windows, Swift iOS via xtool/WSL; Xcode projects need adaptation.' 'Proyectos: Flutter iOS, SwiftPM en Windows, Swift iOS con xtool/WSL; proyectos Xcode necesitan adaptacion.')
    Write-Host '  xcm run|build --project PATH [--product NAME] [--configuration debug|release]'
    Write-Host '  xcm run --project PATH --product NAME --args ARG1 ARG2'
    Write-Host '  xcm doctor --project PATH | xcm doctor --environment'
    Write-Host '  xcm download all'
    Write-Host '  xcm download ipa --repo Ivorisnoob/iKoda --asset Koda.ipa --output .\Koda.ipa'
    Write-Host '  xcm update --check | xcm update --force | xcm update --ref REF'
    if ($script:Language -eq 'es') { Write-Title 'Comandos disponibles' } else { Write-Title 'Available commands' }
    if ($script:Language -eq 'es') {
        $helpText = @'
  xcm                       Menu interactivo
  xcm help                  Mostrar esta ayuda
  xcm doctor                Diagnostico del proyecto
  xcm device                Detectar el iPhone por USB
  xcm devmode               Menu de desarrollador
  xcm tunnel usb|wifi       Abrir tunel RSD
  xcm sdk install [ruta]    Instalar SDK desde Xcode.xip
  xcm xcode                 Abrir descarga de Xcode.xip
  xcm install               Preparacion guiada
  xcm install ruta.ipa      Instalar IPA existente por USB (sin pedir P12)
  xcm swift                 Instalar Swift con winget
  xcm xcross                Instalar xcross
  xcm dependencies          Ejecutar xcross setup
  xcm precache debug|all    Descargar artefactos Flutter iOS
  xcm project show|set       Proyecto activo
  xcm run [--usb|--wifi]    Ejecutar proyecto
  xcm ipa                   Menu de compilacion, firma e instalacion
  xcm ipa build [--project ruta] [--mode release|profile|debug]
                [--target lib/main.dart] [--flavor nombre]
  xcm ipa sign ruta.ipa --certificate cert.p12 --profile app.mobileprovision
                [--output app-signed.ipa] [--bundle-id com.example.app]
  xcm ipa install ruta.ipa [--udid UDID]
  xcm ipa inspect ruta.ipa  Revisar sin instalar ni cambiar la IPA
  xcm ipa logs              Ver detalle de la ultima operacion
  xcm project update [ruta] Actualizar Git desde carpeta actual (ff-only)
  xcm bundle default|original|prefixed
  xcm sign [bundle-id]      Diagnosticar firma
  xcm trust                 Guia de confianza iOS
  xcm auth                  Conectar Apple ID
  xcm vscode                Configurar VS Code
  xcm update                Actualizar xcross
  xcm install-cli           Instalar comando xcm
  xcm uninstall-cli         Desinstalar comando xcm
  xcm update-cli            Actualizar xcm desde GitHub
  xcm update-cli --local    Instalar esta copia local de xcm
  xcm language en|es        Cambiar idioma
'@
    }
    else {
        $helpText = @'
  xcm                       Interactive menu
  xcm help                  Show this help
  xcm doctor                Project diagnostics
  xcm device                Detect iPhone over USB
  xcm devmode               Developer menu
  xcm tunnel usb|wifi       Open RSD tunnel
  xcm sdk install [path]    Install SDK from Xcode.xip
  xcm xcode                 Open Apple Xcode.xip download
  xcm install               Guided setup
  xcm install path.ipa      Install existing IPA over USB (no P12 prompt)
  xcm swift                 Install Swift via winget
  xcm xcross                Install xcross
  xcm dependencies          Run xcross setup
  xcm precache debug|all    Download Flutter iOS artifacts
  xcm project show|set       Active project
  xcm run [--usb|--wifi]    Run project
  xcm ipa                   Build, sign and install menu
  xcm ipa build [--project path] [--mode release|profile|debug]
                [--target lib/main.dart] [--flavor name]
  xcm ipa sign path.ipa --certificate cert.p12 --profile app.mobileprovision
                [--output app-signed.ipa] [--bundle-id com.example.app]
  xcm ipa install path.ipa [--udid UDID]
  xcm ipa inspect path.ipa  Inspect without installing or changing the IPA
  xcm ipa logs              Show the last operation log
  xcm project update [path] Update Git from current folder (ff-only)
  xcm bundle default|original|prefixed
  xcm sign [bundle-id]      Diagnose signing
  xcm trust                 iOS trust guide
  xcm auth                  Connect Apple ID
  xcm vscode                Configure VS Code
  xcm update                Update xcross
  xcm install-cli           Install xcm command
  xcm uninstall-cli         Uninstall xcm command
  xcm update-cli            Update xcm from GitHub
  xcm update-cli --local    Install this local copy of xcm
  xcm language en|es        Change language
'@
    }
    Write-Host $helpText -ForegroundColor Gray
    if ($script:Language -eq 'es') {
        Write-Host '  Ejemplo LUMINA:' -ForegroundColor Cyan
    } else {
        Write-Host '  LUMINA example:' -ForegroundColor Cyan
    }
    Write-Host '    xcm project set "C:\Users\USUARIO\Documents\Github\LUMINA-v0.2-integracion\LUMINA-v0.2\lumina-mobile"' -ForegroundColor Gray
    Write-Host '    xcm tunnel usb' -ForegroundColor Gray
    Write-Host '    xcm run --usb -t lib/main.dart' -ForegroundColor Gray
    Write-Host ''
    if ($script:Language -eq 'es') {
        Write-Host '  La paleta con / funciona dentro del menu; las opciones aceptan teclas sin Enter.' -ForegroundColor DarkGray
    } else {
        Write-Host '  The / palette works inside the menu; options accept keys without Enter.' -ForegroundColor DarkGray
    }
}

function Invoke-XcmCommand {
    param([string]$Verb, [string[]]$Arguments=@())
    $v=$Verb.TrimStart('/').ToLowerInvariant()
    switch($v){
        {$_ -in @('init','setup')} {return (Initialize-Xcm -Arguments $Arguments)}
        'xtool' {return (Invoke-XtoolCommand -Arguments $Arguments)}
        {$_ -in @('version','--version')} {Write-Host "XCross CLI (Windows) v$script:Version"; return $true}
        {$_ -in @('help','--help','-h','ayuda')} {
            if ($Arguments.Count -gt 1 -or ($Arguments.Count -eq 1 -and $Arguments[0] -ne '--all')) { Write-Fail 'Uso: xcm help [--all]'; return $false }
            Show-XcmHelp -All:($Arguments -contains '--all');return $true
        }
        {$_ -in @('menu','ui')} {Show-Menu;return $true}
        'install' {
            if ($Arguments.Count) { return (Invoke-IpaCommand -Arguments (@('install') + $Arguments)) }
            return (Initialize-Xcm)
        }
        'swift' {return (Install-Swift)}
        'xcross' {return (Install-Xcross)}
        {$_ -in @('dependencies','deps')} {return (Install-Dependencies)}
        'update' {return (Upgrade-Xcross -Arguments $Arguments)}
        'download' {
            if ($Arguments.Count -and $Arguments[0] -eq 'ipa') {
                $rest = @(); if ($Arguments.Count -gt 1) { $rest = $Arguments[1..($Arguments.Count-1)] }
                return (Get-ReleaseIpa -Arguments $rest)
            }
            if ($Arguments.Count -eq 1 -and $Arguments[0] -eq 'all') { return (Initialize-Xcm) }
            Write-Fail 'Uso: xcm download all | xcm download ipa --repo OWNER/REPO --asset NAME.ipa --output PATH.ipa'; return $false
        }
        'ipa' {return (Invoke-IpaCommand -Arguments $Arguments)}
        'build' {return (Invoke-ProjectCommand -Operation build -Arguments $Arguments)}
        'install-ipa' {return (Invoke-IpaCommand -Arguments (@('install') + $Arguments))}
        'sign-ipa' {return (Invoke-IpaCommand -Arguments (@('sign') + $Arguments))}
        'update-project' {
            if ($Arguments.Count -gt 1) { Write-Fail 'Uso: xcm update-project [ruta]'; return $false }
            $path = if ($Arguments.Count) { $Arguments[0] } else { '.' }
            return (Update-CurrentProject -Path $path)
        }
        'xcode' {Open-AppleDownloadPage;return $true}
        {$_ -in @('doctor','check','verify')} {
            if ($Arguments.Count -eq 0 -and (Get-ProjectKind (Get-Location).Path) -eq 'unknown') {
                if ((Test-CurrentIpaFolder) -or $script:Settings.SetupWorkflow -eq 'ipa') { return (Test-IpaEnvironment) }
                if ($script:Settings.SetupWorkflow -eq 'swift') { return (Invoke-Tool 'swift' @('--version')) }
            }
            if ($Arguments.Count -eq 1 -and $Arguments[0] -eq '--environment') { return (Test-XcmEnvironment) }
            $path = ''
            if ($Arguments.Count) {
                if ($Arguments.Count -ne 2 -or $Arguments[0] -ne '--project') { Write-Fail 'Uso: xcm doctor [--project PATH | --environment]'; return $false }
                $path = $Arguments[1]
            }
            return (Test-ProjectEnvironment -Path $path)
        }
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
                'update' {
                    if ($Arguments.Count -gt 2) { Write-Fail 'Uso: xcm project update [ruta]'; return $false }
                    $path = if ($Arguments.Count -eq 2) { $Arguments[1] } else { '.' }
                    return (Update-CurrentProject -Path $path)
                }
                'show' {Show-CurrentProject;return $true}
                'set' {
                    if($Arguments.Count -gt 1){
                        $p=$Arguments[1..($Arguments.Count-1)] -join ' '
                        $script:ProjectOverride=$p
                        $selected = Select-Project -ExplicitPath $p
                        $script:ProjectOverride=''
                        return [bool]$selected
                    }
                    else {return [bool](Select-Project -ForcePrompt)}
                }
                default {Write-Warn 'Uso: xcm project show|set|update [ruta]';return $false}
            }
        }
        'run' {return (Invoke-ProjectCommand -Operation run -Arguments $Arguments)}
        'flutter-run' {
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
                return (Flutter-Run -Transport $transport -Target $target -VerboseRun:$verbose)
            }
            finally{$script:ProjectOverride=$prev}
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
        'auth' {return (Connect-AppleId)}
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
        {$_ -in @('uninstall-cli','uninstall')} {Uninstall-XcmGlobal;return $true}
        {$_ -in @('update-cli','upgrade-cli')} {
            if ($Arguments.Count -gt 1 -or ($Arguments.Count -eq 1 -and $Arguments[0] -ne '--local')) {
                Write-Fail 'Uso: xcm update-cli [--local]'; return $false
            }
            if ($Arguments.Count) { return (Update-XcmGlobal -Local) }
            return (Update-XcmGlobal)
        }
        {$_ -in @('language','lang')} {Set-Language @Arguments;return $true}
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
# Preserve the argument boundaries supplied by the shell, including paths with spaces.
# Only the interactive command palette needs Split-CommandTokens.
switch($Action.ToLowerInvariant()){
    'usbtunnel' {Tunnel-Command 'usb'}
    'wifitunnel' {Tunnel-Command 'wifi'}
    'menu' {Show-Menu}
    default {
        $result=Invoke-XcmCommand -Verb $Action -Arguments $CommandArgs
        if(-not $result){exit 1}
    }
}
