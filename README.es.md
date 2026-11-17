# XCross CLI (xcm) v1.3.0 para Windows

![XCross CLI logo](assets/logo.svg)


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

Si ya tienes una IPA firmada para tu iPhone, instala directamente:

```powershell
xcm install "C:\Apps\mi-app.ipa"
```

Solo necesitas `pymobiledevice3`, los controladores USB de Apple y el iPhone conectado, desbloqueado y con Confiar aceptado. No se pide certificado `.p12`, perfil, Apple ID, Xcode ni proyecto Flutter para instalar. iOS valida la firma que ya contiene la IPA; esto no permite instalar un paquete sin firma valida. La opcion **7** del menu abre esta instalacion directa. `xcm install` sin argumentos conserva la preparacion guiada.

Desde la carpeta del proyecto Flutter, abre `xcm ipa` o ejecuta:

```powershell
xcm ipa build --mode release
xcm ipa build --project "C:\proyectos\mi-app" --target lib/main.dart --flavor staging
xcm ipa sign ".\mi-app.ipa" --certificate ".\certificado.p12" --profile ".\app.mobileprovision" --output ".\mi-app-signed.ipa"
xcm ipa install ".\mi-app-signed.ipa"
xcm ipa install ".\mi-app-signed.ipa" --udid "UDID-DEL-IPHONE"
```

`build` usa `xcross flutter build --ipa`; requiere el entorno iOS de XCross y admite `debug`, `profile` y `release` (predeterminado). Prioriza `--project`, luego la carpeta actual si tiene `pubspec.yaml`, y finalmente el proyecto guardado. Una IPA compilada necesita una firma de distribucion o desarrollo valida para instalarse en el iPhone.

`sign` requiere [zsign para Windows](https://github.com/zhlynn/zsign#build) en PATH, un certificado `.p12` con clave privada y un perfil `.mobileprovision` compatible con la app, sus permisos y el dispositivo. XCross 2.0.5 no expone un comando independiente de firma de IPA. La clave del P12 se pide oculta y no se guarda ni se imprime; zsign la recibe como argumento del proceso. `--bundle-id` permite cambiar el identificador cuando el perfil lo admite. La salida predeterminada es `nombre-signed.ipa` junto a la original; se rechazan rutas de salida que ya existan. Apps con extensiones que necesitan perfiles separados requieren una configuracion de firma mas especifica con zsign.

`install` instala una IPA existente con `pymobiledevice3 apps install --streaming`, sin compilarla ni modificar su firma. Conecta el iPhone por USB, desbloquealo y acepta Confiar. Si hay varios iPhone, el CLI solicita el UDID; tambien puedes pasarlo con `--udid`. iOS valida la firma y el perfil durante la instalacion. Una IPA cifrada de App Store no se convierte en instalable mediante este flujo.

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
