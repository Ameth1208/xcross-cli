# XCross CLI (xcm) v1.5.3 para Windows

![XCross CLI logo](assets/logo.svg)

## Ya tienes XCross preparado: instala directamente

```powershell
xcm install ".\Koda.ipa"
```

Desde 1.5.3, una IPA ya compilada, sin firma o con firma ad hoc, usa tu sesion
guardada de XCross en Windows. No necesita otra sesion Apple, WSL, xtool, zsign ni
un P12 manual. El adaptador 2.1.2 aprovisiona la app y sus extensiones compatibles,
firma una copia temporal e instala por USB. La IPA original se conserva y se guarda
una copia `Koda-xcross-signed.ipa` (con sufijo si ya existe).

En una carpeta con archivos `.ipa`, `xcm doctor` comprueba este flujo antes de
elegir un proyecto Flutter guardado. `xcm init ipa` tambien reutiliza XCross.
La compatibilidad y los limites de la cuenta los valida Apple durante la firma.
Se verifico la instalacion real de Koda v0.4, sus extensiones Share y Widgets, y
su presencia en el iPhone. No se comprobo la apertura ni la reproduccion de musica.

## Uso habitual: preparar una vez y trabajar

```powershell
xcm init
xcm install ".\Koda.ipa"
```

`init` detecta el proyecto actual o recuerda el flujo elegido; si falta contexto,
muestra tres opciones: instalar IPA, preparar Flutter iOS o usar Swift en Windows.
Para Koda puedes ir directamente a `xcm init ipa`. El asistente comprueba XCross,
su sesion guardada, las herramientas de firma y el iPhone USB; solicita acceso
solo si no hay identidad guardada. No instala la app ni descarga Swift Linux/SDK
para una IPA ya compilada.

`xcm init ipa --check` solo comprueba. `xcm init flutter` abre la preparacion Flutter
y `xcm init swift` prepara el compilador local. `setup`, `install` sin archivo y
`download all` conservan compatibilidad como accesos al mismo asistente. Los pasos
tecnicos siguen disponibles en **Herramientas avanzadas** y `xcm help --all`; la
ayuda normal muestra los comandos de uso habitual. `doctor` recuerda el flujo IPA
cuando no se ejecuta dentro de un proyecto reconocido.

El acceso Apple muestra instrucciones numeradas: correo + Enter, contrasena + Enter
(sin caracteres visibles) y codigo 2FA + Enter cuando se solicite. Durante las
etapas de progreso solo hay que esperar. La autenticacion usa la consola directamente
y no se registra. Las sesiones de XCross (Flutter) y xtool (IPA) son distintas;
un acceso correcto a una no inicia la otra. Para renovar xtool explicitamente usa
`xcm xtool auth --refresh`.

## Alternativa avanzada: instalar una IPA con xtool

Una IPA ya compilada puede tener firma **ad hoc**: aun necesita una identidad y
perfiles validos para tu iPhone. Ademas del flujo predeterminado XCross, puedes
seleccionar [xtool](https://github.com/xtool-org/xtool) mediante WSL explicitamente.

```powershell
xcm update-cli
xcm version
xcm xtool install-tool
xcm xtool auth
xcm xtool connect-usb
xcm xtool devices
xcm xtool doctor
xcm install ".\Koda.ipa" --backend xtool
```

Necesitas una distribucion WSL instalada. `install-tool` descarga el AppImage
oficial para la arquitectura de WSL, verifica tamano y SHA256 y lo instala en
`~/.local/share/xcross-cli/xtool`. No modifica el PATH de Linux y no necesita FUSE.
`auth` solicita Apple ID/2FA dentro de tu terminal; su salida no se registra y la
sesion es independiente de XCross. No compartas las credenciales por el chat.

`connect-usb` muestra UAC para enlazar el servicio Apple Mobile Device de Windows
(iTunes/Apple Devices) con WSL. El relay escucha solo en la interfaz WSL, puerto
27015, y la regla de firewall permite solo el IP de esa distribucion. Repite el
comando si cambia su IP. Desbloquea el iPhone y acepta Confiar. Tambien puedes usar
`xcm xtool disconnect-usb` para eliminar el relay y su regla de firewall. Puedes usar
USBIPD o configurar `USBMUXD_SOCKET_ADDRESS` en WSL. Si usas varias distribuciones,
establece `$env:XCM_WSL_DISTRO = 'Ubuntu-24.04'` o ejecuta, por ejemplo,
`xcm xtool --distro Ubuntu-24.04 doctor`.

En el menu IPA, **4 = Firmar + instalar (xtool)**; **6 = firma manual con zsign**.
`xcm install Koda.ipa` usa XCross de forma predeterminada. La seleccion explicita
`--backend xtool` autoriza reemplazar la firma de una copia temporal y aprovisionar
sus extensiones compatibles; conserva la IPA original y no genera una IPA firmada
exportable. Las credenciales, limites de la cuenta y permisos de Apple pueden
impedir la instalacion; no se garantiza compatibilidad con todas las extensiones.
`--backend xcross` conserva el flujo anterior. Los errores quedan en `xcm ipa logs`;
los errores anteriores al inicio de instalacion se muestran en pantalla.

**Instalar una IPA no necesita Swift Linux ni Xcode.xip.** Para compilar una app
Swift iOS, selecciona un proyecto adaptado con `Package.swift` y `xtool.yml`:

```powershell
xcm xtool sdk "C:\Downloads\Xcode.xip"
xcm xtool build --project "C:\repos\mi-app-xtool" --configuration release
xcm xtool run --project "C:\repos\mi-app-xtool"
```

Estos comandos requieren Swift y el SDK Darwin **dentro de WSL**; `xcm run/build`
tambien detecta `xtool.yml`. No convierten automaticamente `Koda.xcodeproj` a SwiftPM.

## Swift y mantenimiento del entorno (Windows)

`project set`, `project show`, `run`, `build` y `doctor` ahora detectan Flutter
(`pubspec.yaml`), Swift Package Manager (`Package.swift`) y proyectos Xcode
(`.xcodeproj` / `.xcworkspace` en la carpeta seleccionada). Se mantiene la ruta
guardada anteriormente. Prioridad: `--project`, carpeta actual y proyecto guardado.
En un monorepositorio, selecciona la carpeta concreta del proyecto. Los proyectos
con `Package.swift` y `xtool.yml` usan el backend iOS xtool de WSL.

Los paquetes Swift se compilan y ejecutan **en Windows**, con sus dependencias
compatibles con Windows. Una biblioteca se puede compilar, pero `run` requiere
un producto ejecutable. Esto no compila SwiftUI/UIKit para iPhone:

```powershell
xcm project set "C:\repos\paquete-swift"
xcm build --configuration release
xcm run --product MiEjecutable --args "argumento con espacios"
xcm doctor
xcm doctor --environment
xcm download all
xcm update --check
xcm update
xcm update --force
xcm update --check --ref main
xcm update-cli
xcm update-cli --local
```

`doctor` usa el diagnostico iOS de XCross para Flutter y comprueba la version de
Swift y el manifiesto para SwiftPM; no garantiza la compilacion de sus dependencias.
`doctor --environment` comprueba herramientas del host y la configuracion XCross,
sin necesitar un proyecto ni garantizar firma, SDK o conexion del iPhone.
`verify` y `check` son alias de `doctor`. Los fallos devuelven codigo de salida 1.

`download all` abre la preparacion guiada: Swift, XCross, dependencias, importacion
opcional del SDK y diagnostico final. Solo ofrece artefactos Flutter si el proyecto
detectado es Flutter. **Xcode.xip se obtiene manualmente de Apple**; el asistente
no puede descargarlo automaticamente. Las instalaciones conservan sus confirmaciones.

`update` actualiza el motor **XCross**; `--check` solo consulta, `--force` reinstala
la version publicada y `--ref` selecciona una referencia soportada por el motor.
Se detiene si falla la consulta y comprueba la version despues de actualizar.
`update-cli` actualiza **este CLI xcm**. El instalador remoto descarga todos los
archivos de un mismo commit, valida los scripts PowerShell y restaura los archivos
anteriores si falla la copia. La instalacion local valida el paquete antes de copiar.

### Caso iKoda: app nativa de Xcode

[iKoda](https://github.com/Ivorisnoob/iKoda) contiene `Koda.xcodeproj`, una app
SwiftUI y extensiones. El backend actual de XCross no expone un flujo para compilar
proyectos Xcode nativos desde Windows. `run`, `build` y `doctor` explican esta
limitacion y devuelven error; no intentan ejecutarlo como Flutter o como su
biblioteca `KodaCore`. Compilar el repositorio sin adaptarlo sigue usando Xcode;
la alternativa sin Mac requiere adaptar su app y extensiones al formato xtool.

Puedes descargar una IPA publicada sin compilar el repositorio:

```powershell
xcm download ipa --repo Ivorisnoob/iKoda --asset Koda.ipa --output .\Koda.ipa
xcm ipa inspect .\Koda.ipa
```

El comando descarga el asset exacto de la ultima release estable, comprueba su
tamano y el SHA256 de GitHub cuando existe, inspecciona la IPA y nunca sobrescribe
el destino ni instala en el telefono. Necesita Internet y Python para inspeccionar;
GitHub aplica limites a su API publica. Si falta SHA256, muestra la limitacion.

La IPA de iKoda v0.4 comprobada contiene firma **ad hoc**. Desde 1.5.3 usa tu sesion
XCross para volver a firmarla e instalarla. Tambien existen los
flujos AltStore/SideStore documentados por iKoda. Descargarla no la hace instalable
automaticamente. La inspeccion del ejecutable principal no valida sus extensiones.


Interfaz de terminal inspirada en los CLI modernos usados con asistentes de programación. **No incorpora un modelo de IA**, pero ofrece una experiencia ágil con teclado, paleta de comandos y órdenes reutilizables.

## Vista previa en vivo

Mira como se ve el menu del CLI: https://ameth1208.github.io/xcross-cli/

## Instalar desde GitHub (sin clonar)

**Windows (PowerShell):**
```powershell
irm https://raw.githubusercontent.com/Ameth1208/xcross-cli/main/windows/xcm-install.ps1 | iex
```

## Idioma / Language

El CLI es bilingue (ingles por defecto, espanol disponible):

```powershell
xcm language en
xcm language es
```

Para eliminar el comando global, usa `uninstall.ps1`. No se borran los ajustes guardados.

## Comandos directos (sin abrir el menú)

```powershell
xcm help
xcm doctor
xcm device
xcm devmode status
xcm devmode reveal
xcm devmode enable
xcm tunnel usb
xcm tunnel wifi
xcm xcode
xcm sdk install "C:\Users\USUARIO\Downloads\Xcode.xip"
xcm precache debug
xcm precache all
xcm project show
xcm project set "C:\Users\USUARIO\Documents\Github\LUMINA-v0.2-integracion\LUMINA-v0.2\lumina-mobile"
xcm bundle default
xcm bundle original
xcm sign
xcm sign com.example.luminaMobile
xcm run --usb -t lib/main.dart
xcm run --wifi
xcm update
```

## Compilar, firmar e instalar IPA en Windows

Instala una IPA existente con la configuracion de firma guardada en XCross:

```powershell
xcm install "C:\Apps\mi-app.ipa"
```

Primero se inspecciona el ejecutable principal. Una firma de dispositivo existente se conserva y se instala con `pymobiledevice3`. Si falta firma o es ad hoc, se usa la identidad guardada de XCross para aprovisionar, firmar una copia e instalarla. `--backend xtool` selecciona la alternativa WSL explicitamente. No se pide un P12 manual. Los binarios cifrados y las plataformas incompatibles se rechazan. iOS realiza la validacion definitiva. Conecta y desbloquea el iPhone por USB y acepta Confiar. La opcion **7** del menu principal abre este flujo. `xcm install` sin argumentos conserva la preparacion guiada.

Desde la carpeta del proyecto Flutter, abre `xcm ipa` o ejecuta:

```powershell
xcm ipa build --mode release
xcm ipa build --project "C:\proyectos\mi-app" --target lib/main.dart --flavor staging
xcm ipa sign ".\mi-app.ipa" --certificate ".\certificado.p12" --profile ".\app.mobileprovision" --output ".\mi-app-signed.ipa"
xcm ipa install ".\mi-app-signed.ipa"
xcm ipa install ".\mi-app-signed.ipa" --udid "UDID-DEL-IPHONE"
```

`build` usa `xcross flutter build --ipa`; requiere el entorno iOS de XCross y admite `debug`, `profile` y `release` (predeterminado). Prioriza `--project`, luego la carpeta actual si tiene `pubspec.yaml`, y finalmente el proyecto guardado. Una IPA compilada necesita una firma de distribucion o desarrollo valida para instalarse en el iPhone.

`sign` requiere [zsign para Windows](https://github.com/zhlynn/zsign#build) en PATH, un certificado `.p12` con clave privada y un perfil `.mobileprovision` compatible con la app, sus permisos y el dispositivo. XCross 2.1.2 no expone un comando independiente de firma de IPA. La clave del P12 se pide oculta y no se guarda ni se imprime; zsign la recibe como argumento del proceso. `--bundle-id` permite cambiar el identificador cuando el perfil lo admite. La salida predeterminada es `nombre-signed.ipa` junto a la original; se rechazan rutas de salida que ya existan. Apps con extensiones que necesitan perfiles separados requieren una configuracion de firma mas especifica con zsign.

Si ya contiene firma, `install` usa `pymobiledevice3 apps install --streaming`, sin compilarla ni modificar esa firma. Si falta, utiliza primero la firma automatica de XCross. Conecta el iPhone por USB, desbloquealo y acepta Confiar. Si hay varios iPhone, el CLI solicita el UDID; tambien puedes pasarlo con `--udid`. iOS valida la firma y el perfil durante la instalacion. Una IPA cifrada de App Store no se convierte en instalable mediante este flujo.

Las rutas relativas de IPA, certificados y perfiles parten de la carpeta donde ejecutas el comando. `xcm sign` conserva su funcion anterior de diagnostico; para firmar usa `xcm ipa sign` o `xcm sign-ipa`. Tambien existen `xcm build` y `xcm install-ipa`.

## Actualizar desde la carpeta actual

```powershell
xcm project update
xcm project update "C:\proyectos\mi-app"
xcm update-cli --local
```

`project update` (alias `update-project`) actualiza el repositorio Git de la carpeta actual, aunque no sea Flutter y aunque haya otro proyecto guardado. Requiere una rama con upstream y un arbol de trabajo limpio; ejecuta `git pull --ff-only` y rechaza historias divergentes sin crear merges ni descartar cambios.

`update-cli --local`, ejecutado desde la carpeta de este paquete o su subcarpeta `windows`, copia esta version a `%LOCALAPPDATA%\Programs\XCrossCLI` y registra `xcm` en el PATH del usuario. Es util para activar cambios locales sin publicarlos. `xcm update-cli` sigue descargando desde GitHub; `xcm update` actualiza la herramienta XCross.

Sin instalar globalmente, reemplaza `xcm` por `.\windows\xcm.cmd` desde esta carpeta.

## Diagnostico y firma automatica

```powershell
xcm ipa inspect ".\app.ipa"
xcm ipa logs
```

La inspeccion es de solo lectura y comprueba presencia de firma en el ejecutable principal; no garantiza confianza, vigencia ni todas las extensiones. Los errores de instalacion se resumen en pantalla y el detalle queda en `%APPDATA%\XCrossMenu\logs`. El menu pagina las opciones y adapta el texto al ancho disponible.

La firma automatica utiliza el motor nativo de XCross 2.1.2, fijado al commit `29af3b65f302e6cb1ca653cb78b1f9a096e091ca`, y sus credenciales existentes. Requiere XCross instalado, Git y Dart 3.10+ (se detecta el Dart de Flutter). La primera ejecucion descarga el codigo y las dependencias verificadas por su lockfile; no compila la aplicacion ni necesita su proyecto. El adaptador reutiliza la biblioteca nativa instalada con XCross en Windows. Si la sesion Apple no es utilizable, renuevala con `xcm auth`.

La IPA original se conserva y la copia firmada se guarda junto a ella como `app-xcross-signed.ipa` (con un sufijo unico si ya existe). El identificador puede recibir el prefijo del equipo segun la configuracion de XCross. Se verifico con una IPA real sin firma y luego reinstalando su copia firmada en un iPhone USB. No se verifico la apertura ni el funcionamiento interno de esa app.

El adaptador `windows/xcross_ipa_bridge.dart` se licencia AGPL-3.0-only y usa el motor XCross (AGPL-3.0); el resto del CLI conserva su licencia MIT.
