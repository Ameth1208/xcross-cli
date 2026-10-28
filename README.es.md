# XCross CLI (xcm) v1.2.0 para Windows

![XCross CLI logo](logo.svg)

```
█   █  ███  █   █
 █ █ ░█ ░░░ ██ ██░
  █ ░ █░ ░░░█░█ █░░
 █ █ ░█░░   █░░░█░░
█ ░ █  ███  █░░ █░░
 ░ ░ ░  ░░░  ░░  ░░
  ░   ░  ░░░  ░   ░
```

Interfaz de terminal inspirada en los CLI modernos usados con asistentes de programación. **No incorpora un modelo de IA**, pero ofrece una experiencia ágil con teclado, paleta de comandos y órdenes reutilizables.

## Empezar

1. Descomprime este ZIP en una carpeta permanente.
2. Ejecuta `start.cmd` para abrir el menú, o `xcm.cmd` desde esa carpeta. (En Linux, usa `linux-cli.sh`.)
3. Usa las **flechas** para navegar y **flecha derecha o barra espaciadora** para ejecutar, **sin pulsar Enter**. También puedes pulsar directamente `1`–`9`, `D`, `F`, `P`, `I` o `?` donde aparezcan en el menú. `Esc` o `0` vuelve atrás.
4. Pulsa `/` dentro del menú para abrir una **paleta de comandos**, filtra escribiendo y elige con flecha derecha o `Tab` (no hace falta Enter). Para comandos con argumentos libres, escribe todo y usa flecha derecha cuando no haya sugerencias; Enter también funciona.

La introducción de rutas, emails y otros textos libres se confirma con Enter, porque son formularios de texto. Los comandos externos (xcross / Python / winget) pueden mostrar sus propios diálogos y pedir confirmación. Las opciones de confirmación de este menú aceptan **S** o **N** sin Enter; para volver a la pantalla anterior basta cualquier tecla.

## Instalar `xcm` como comando global

Ejecuta `install.ps1` con PowerShell o pulsa `I` en el menú y confirma. Copia los scripts a `%LOCALAPPDATA%\Programs\XCrossCLI` y agrega esta carpeta al `PATH` de usuario. **No requiere administrador**. Abre una **nueva terminal** para usar `xcm` desde cualquier carpeta.

Puedes ejecutar el instalador manualmente así:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
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

**Sin instalar el comando global**, cambia `xcm` por `./xcm.cmd` en los ejemplos si estás en la carpeta descomprimida.

## Sobre descargas y firma

- La instalación guiada (`xcm install`) prepara Swift, xcross y las dependencias. `xcross setup` puede instalar LLVM, Python, Visual Studio Build Tools, etc.
- `xcm xcode` abre las descargas oficiales de Apple. `xcross sdk install` **no descarga Xcode.xip**: importa el SDK desde el archivo ya descargado, asociado a la versión de Swift activa.
- `xcm precache debug` y `all` descargan los artefactos del motor Flutter para iOS. Se ejecutan desde el proyecto Flutter seleccionado.
- En iOS 27 un aviso de **«Desarrollador no confiable»** debe resolverse **en el iPhone** con la autorización del desarrollador. Cambiar el Bundle ID o volver a descargar Flutter no autoriza certificados. El menú ofrece diagnóstico con `xcm sign` y guía con `xcm trust`.
- `xcm tunnel usb` puede requerir PowerShell como administrador. El menú abre una ventana elevada cuando es necesario. El túnel debe mantenerse abierto durante la depuración.
- Para la autenticación de xcross con Apple ID, considera una cuenta de pruebas separada; los métodos no oficiales pueden provocar verificaciones o bloqueos.

## Cómo funciona internamente

Todo está escrito en PowerShell sin dependencias extra para la interfaz. El CLI llama las herramientas instaladas en tu equipo: `winget`, `swift`, `xcross`, `pymobiledevice3`, `flutter`. **No incluye ni redistribuye Apple SDK, credenciales, Swift, xcross ni los motores de Flutter**. No almacena contraseñas. Conserva el proyecto actual, la ruta de `Xcode.xip` y el modo de App ID en `%APPDATA%\XCrossMenu\settings.json`.

Los instaladores descargados desde terceros requieren confirmación. El script oficial de xcross proviene de `https://raw.githubusercontent.com/arxdeus/xcross/main/install.ps1` y se muestra el SHA-256 calculado localmente para que lo puedas inspeccionar; esto no equivale a una verificación de firma de código del instalador.

## Compatibilidad y validación

Diseñado para Windows PowerShell 5.1 o posterior. Se preservan las funcionalidades de v1.1.0 y el mismo archivo de ajustes. **No se ha podido ejecutar ni probar en Windows real con un iPhone en este entorno**; antes de confiar en el menú para un proyecto importante, realiza una prueba local con `xcm help`, `xcm doctor`, `xcm device` y `xcm run`.

En caso de fallo, ejecuta directamente los comandos oficiales del proyecto en https://github.com/arxdeus/xcross para obtener logs completos.
