# XCross CLI (xcm) v1.2.0 para Windows

![XCross CLI logo](assets/logo.svg)


Interfaz de terminal inspirada en los CLI modernos usados con asistentes de programación. **No incorpora un modelo de IA**, pero ofrece una experiencia ágil con teclado, paleta de comandos y órdenes reutilizables.

## Vista previa en vivo

Mira como se ve el menu del CLI: https://ameth1208.github.io/xcross-cli/

## Instalar desde GitHub (sin clonar)

**Windows (PowerShell):**
```powershell
irm https://raw.githubusercontent.com/Ameth1208/xcross-cli/main/windows/xcm-install.ps1 | iex

## Idioma / Language

El CLI es bilingue (ingles por defecto, espanol disponible):

```powershell
xcm language en
xcm language es

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
