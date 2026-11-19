"""Run the official Linux xtool from Windows through WSL; never transfer credentials.

IPA installation uses xtool's existing provisioning/signing/install pipeline.
Swift and a Darwin SDK are needed for source builds, not for installing an IPA.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zipfile

from ipa_inspect import inspect_ipa


# All user data travels as positional arguments, never as shell source.
LAUNCH = r'''
set -eu
# Prefer an explicitly selected usbmuxd socket. Otherwise reuse the Windows
# Apple Mobile Device Service when connect-usb configured the WSL-only relay.
if [ -z "${USBMUXD_SOCKET_ADDRESS:-}" ]; then
    gateway=$(ip route show default 2>/dev/null | awk 'NR==1 {print $3}')
    if [ -n "$gateway" ] && timeout 1 bash -c 'exec 3<>/dev/tcp/$1/27015' xcm-probe "$gateway" 2>/dev/null; then
        export USBMUXD_SOCKET_ADDRESS="$gateway:27015"
    fi
fi
managed="$HOME/.local/share/xcross-cli/xtool"
if [ -x "$managed" ]; then
    tool="$managed"
elif command -v xtool >/dev/null 2>&1; then
    tool=$(command -v xtool)
else
    echo 'Falta xtool en WSL. Ejecuta: xcm xtool install-tool' >&2
    exit 127
fi
cd "$1"
shift
exec env APPIMAGE_EXTRACT_AND_RUN=1 "$tool" "$@"
'''

INSTALL = r'''
set -eu
target="$HOME/.local/share/xcross-cli"
mkdir -p "$target"
stage=$(mktemp "$target/xtool-download.XXXXXX")
trap 'rm -f -- "$stage"' EXIT
cp -- "$1" "$stage"
chmod 755 "$stage"
env APPIMAGE_EXTRACT_AND_RUN=1 "$stage" --help >/dev/null
mv -f -- "$stage" "$target/xtool"
printf 'Instalado: %s/xtool\n' "$target"
'''


class XtoolError(Exception):
    pass


class Wsl:
    def __init__(self, distro=None):
        executable = shutil.which("wsl.exe")
        if not executable:
            raise XtoolError("Falta WSL. Instala una distribucion Linux con wsl --install y reinicia si Windows lo solicita.")
        self.prefix = [executable]
        distro = distro or os.environ.get("XCM_WSL_DISTRO")
        if distro:
            self.prefix += ["--distribution", distro]
        self.prefix += ["--exec"]
        self.capture(["true"])

    def capture(self, args, timeout=30):
        result = subprocess.run(self.prefix + list(args), capture_output=True, timeout=timeout)
        output = result.stdout.decode("utf-8", errors="replace").replace("\x00", "").strip()
        error = result.stderr.decode("utf-8", errors="replace").replace("\x00", "").strip()
        if result.returncode:
            raise XtoolError(error or output or f"WSL termino con codigo {result.returncode}")
        return output

    def path(self, path):
        return self.capture(["wslpath", "-a", "-u", str(Path(path).resolve())])

    def command(self, args, cwd="/tmp"):
        return self.prefix + ["bash", "-lc", LAUNCH, "xcm-xtool", cwd] + list(args)

    def xtool_capture(self, args, timeout=60):
        result = subprocess.run(self.command(args), capture_output=True, timeout=timeout)
        output = result.stdout.decode("utf-8", errors="replace")
        if result.returncode:
            raise XtoolError(result.stderr.decode("utf-8", errors="replace").strip() or output.strip())
        return output

    def run(self, args, cwd="/tmp", log=False):
        # Login inherits the console and is never recorded, including its output.
        command = self.command(args, cwd)
        if not log:
            return subprocess.run(command).returncode
        log_dir = Path(os.environ["APPDATA"]) / "XCrossMenu" / "logs"
        log_dir.mkdir(parents=True, exist_ok=True)
        import datetime
        import uuid
        stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
        path = log_dir / f"ipa-{stamp}-xtool-{uuid.uuid4().hex[:8]}.log"
        print(f"Log: {path}", flush=True)
        with path.open("w", encoding="utf-8") as target:
            with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT) as process:
                try:
                    while chunk := process.stdout.read1(4096):
                        text = chunk.decode("utf-8", errors="replace")
                        target.write(text)
                        target.flush()
                        print(text, end="", flush=True)
                    return process.wait()
                except BaseException:
                    process.terminate()
                    raise


def install_tool(wsl):
    arch = wsl.capture(["uname", "-m"])
    if arch not in ("x86_64", "aarch64"):
        raise XtoolError(f"Arquitectura WSL no soportada: {arch}")
    headers = {"User-Agent": "XCrossCLI", "Accept": "application/vnd.github+json"}
    request = urllib.request.Request("https://api.github.com/repos/xtool-org/xtool/releases/latest", headers=headers)
    with urllib.request.urlopen(request, timeout=30) as response:
        release = json.load(response)
    name = f"xtool-{arch}.AppImage"
    asset = next((a for a in release["assets"] if a["name"] == name), None)
    if not asset or not re.fullmatch(r"sha256:[0-9a-fA-F]{64}", asset.get("digest") or ""):
        raise XtoolError("La release no contiene el AppImage esperado con SHA256; no se instalara.")
    url = asset["browser_download_url"]
    if not url.startswith("https://github.com/xtool-org/xtool/releases/download/"):
        raise XtoolError("URL de descarga inesperada.")
    print(f"Descargando xtool {release['tag_name']} / {arch} ({asset['size'] // 1048576} MiB)...", flush=True)
    with tempfile.TemporaryDirectory(prefix="xcm-xtool-") as folder:
        archive = Path(folder) / name
        digest = hashlib.sha256()
        length = 0
        with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "XCrossCLI"}), timeout=60) as response:
            with archive.open("xb") as target:
                while chunk := response.read(1024 * 1024):
                    length += len(chunk)
                    digest.update(chunk)
                    target.write(chunk)
        if length != asset["size"] or digest.hexdigest().lower() != asset["digest"][7:].lower():
            raise XtoolError("Descarga incompleta o SHA256 incorrecto; se conserva xtool anterior.")
        print(f"SHA256 verificado: {digest.hexdigest()}", flush=True)
        result = subprocess.run(wsl.prefix + ["bash", "-c", INSTALL, "xcm-install", wsl.path(archive)])
        if result.returncode:
            raise XtoolError("El AppImage no pudo ejecutarse en WSL; se conserva xtool anterior.")
    print('Siguiente paso: xcm init ipa. Despues: xcm install "Koda.ipa"', flush=True)


def doctor(wsl):
    print("[OK] WSL disponible", flush=True)
    wsl.xtool_capture(["--help"])
    print("[OK] xtool ejecutable (sin necesitar FUSE)", flush=True)
    authenticated = "Logged in" in wsl.xtool_capture(["auth", "status"])
    print("[OK] Sesion xtool guardada" if authenticated else "[!] Falta sesion: ejecuta xcm init ipa para completar la preparacion.", flush=True)
    # An empty list is not a healthy device connection, even though xtool returns 0.
    devices = wsl.xtool_capture(["devices", "--no-wait"], timeout=30).strip()
    print(devices or "[!] Sin iPhone visible en WSL. Conecta/desbloquea/acepta Confiar y configura USBIPD o el relay usbmuxd.", flush=True)
    try:
        swift = wsl.capture(["bash", "-lc", "swift --version"], timeout=30)
        print("[OK] Swift Linux: " + swift.splitlines()[0], flush=True)
        sdks = wsl.capture(["bash", "-lc", "swift sdk list"], timeout=30)
        print("SDKs Swift Linux: " + sdks, flush=True)
    except XtoolError:
        print("[!] Swift Linux/SDK no disponible: necesario para compilar, no para instalar una IPA.", flush=True)
    print("USB WSL: https://learn.microsoft.com/windows/wsl/connect-usb", flush=True)
    visible = re.findall(r"\]:\s*(\S+)\s*$", devices, re.MULTILINE)
    return 0 if authenticated and visible else 1


def require_auth(wsl):
    if "Logged in" not in wsl.xtool_capture(["auth", "status"]):
        raise XtoolError("Falta preparar la sesion de IPA: ejecuta xcm init ipa. La sesion XCross no se copia a WSL.")


def login(wsl, mode="password", refresh=False):
    if not refresh and "Logged in" in wsl.xtool_capture(["auth", "status"]):
        print("[OK] Ya hay sesion xtool guardada. Para renovarla: xcm xtool auth --refresh", flush=True)
        return 0
    print("\nACCESO APPLE / INSTALACION DE IPA", flush=True)
    print("Escribe cada respuesta en esta terminal y pulsa Enter. No la envies al chat.", flush=True)
    if mode == "password":
        print("[1/3] Apple ID: escribe el correo de tu cuenta y pulsa Enter.", flush=True)
        print("[2/3] Password: escribe la contrasena y pulsa Enter. No veras caracteres; es normal.", flush=True)
        print("[3/3] Cuando se pida verification code, escribe el codigo 2FA y pulsa Enter.", flush=True)
        print("      Revisa tu dispositivo de confianza. Durante las etapas de progreso solo espera.", flush=True)
    else:
        print("xtool pedira Key ID, Issuer ID y ruta de la clave .p8 dentro de WSL. Confirma cada dato con Enter.", flush=True)
    print("xcm no registra esta conversacion de acceso. xtool conserva su propia sesion.\n", flush=True)
    return wsl.run(["auth", "login", "--mode", mode])


def configure_usb(wsl, remove=False):
    routes = json.loads(wsl.capture(["ip", "-j", "route", "get", "1.1.1.1"]))
    route = routes[0]
    gateway, client = route.get("gateway"), route.get("prefsrc")
    import ipaddress
    if not gateway or not client:
        raise XtoolError("WSL no usa una ruta NAT reconocida. Configura USBIPD o USBMUXD_SOCKET_ADDRESS manualmente.")
    gateway = str(ipaddress.IPv4Address(gateway))
    client = str(ipaddress.IPv4Address(client))
    helper = Path(__file__).with_name("xtool-usb.ps1")
    print("Windows pedira elevacion UAC para un relay limitado al IP de esta distribucion WSL.", flush=True)
    command = ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(helper),
               "-Gateway", gateway, "-ClientIP", client]
    if remove:
        command += ["-Remove"]
    return subprocess.run(command).returncode


def initialize(wsl, check=False):
    if check:
        return doctor(wsl)
    try:
        wsl.xtool_capture(["--help"])
        print("[OK] xtool ya instalado; no se vuelve a descargar.", flush=True)
    except XtoolError as error:
        # A broken existing executable needs diagnosis rather than a silent reinstall.
        if "Falta xtool en WSL" not in str(error):
            raise
        install_tool(wsl)
    if "Logged in" in wsl.xtool_capture(["auth", "status"]):
        print("[OK] Sesion guardada; no se vuelve a pedir Apple ID/2FA.", flush=True)
    else:
        print("[1/2] Inicia sesion en xtool dentro de esta terminal.", flush=True)
        code = login(wsl)
        if code:
            return code
        require_auth(wsl)
    try:
        require_device(wsl)
        print("[OK] iPhone visible; no se cambia el enlace USB.", flush=True)
    except XtoolError as error:
        if "No hay iPhone visible" not in str(error):
            raise
        print("[2/2] Preparando enlace USB Windows/WSL...", flush=True)
        code = configure_usb(wsl)
        if code:
            return code
    code = doctor(wsl)
    if not code:
        print('Listo para instalar IPA: xcm install "Koda.ipa"', flush=True)
        print("Este asistente prepara instalacion de IPA; las compilaciones iOS necesitan ademas Swift Linux y SDK.", flush=True)
    return code


def require_device(wsl, udid=None):
    output = wsl.xtool_capture(["devices", "--no-wait"], timeout=30)
    identifiers = re.findall(r"\]:\s*(\S+)\s*$", output, re.MULTILINE)
    if not identifiers:
        raise XtoolError("No hay iPhone visible en WSL. Ejecuta xcm xtool connect-usb, desbloquea y acepta Confiar; comprueba xcm xtool devices.")
    if udid and udid not in identifiers:
        raise XtoolError("El UDID no aparece en xtool devices; no se esperara indefinidamente a otro dispositivo.")


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--distro", help="Distribucion WSL; predeterminado: XCM_WSL_DISTRO o la predeterminada de WSL")
    actions = result.add_subparsers(dest="action", required=True)
    for name in ("install-tool", "setup", "doctor", "devices", "help", "connect-usb", "disconnect-usb"):
        actions.add_parser(name)
    auth = actions.add_parser("auth")
    auth.add_argument("--mode", choices=("password", "key"), default="password")
    auth.add_argument("--refresh", action="store_true", help="Renovar una sesion guardada explicitamente")
    init = actions.add_parser("init", help="Preparar instalacion de IPA sin repetir pasos ya completados")
    init.add_argument("--check", action="store_true", help="Solo diagnosticar, sin instalar ni iniciar sesion")
    install = actions.add_parser("install", help="Volver a firmar e instalar una IPA con la identidad xtool")
    install.add_argument("ipa", type=Path)
    install.add_argument("--udid")
    for operation in ("build", "run"):
        command = actions.add_parser(operation)
        command.add_argument("--project", type=Path, default=Path.cwd())
        command.add_argument("--configuration", choices=("debug", "release"), default="debug")
        if operation == "run":
            command.add_argument("--udid")
    sdk = actions.add_parser("sdk")
    sdk.add_argument("xip", type=Path)
    return result


def main(argv=None):
    args = parser().parse_args(argv)
    try:
        # Reject incompatible input before downloading, authenticating or touching devices.
        if args.action == "install":
            if args.ipa.suffix.lower() != ".ipa" or not args.ipa.is_file():
                raise XtoolError("Selecciona una IPA existente.")
            report = inspect_ipa(args.ipa)
            blocking = set(report["issues"]) - {"missing_signature", "adhoc_signature"}
            if blocking or report["signature"] not in ("missing", "adhoc", "present"):
                raise XtoolError("IPA incompatible: " + ", ".join(sorted(blocking)))
        if args.action in ("build", "run"):
            if not (args.project / "Package.swift").is_file() or not (args.project / "xtool.yml").is_file():
                raise XtoolError("Se requieren Package.swift y xtool.yml. Un .xcodeproj como iKoda necesita adaptacion; no se convierte automaticamente.")
        wsl = Wsl(args.distro)
        if args.action in ("init", "setup"):
            return initialize(wsl, check=getattr(args, "check", False))
        if args.action == "install-tool":
            install_tool(wsl)
            return 0
        if args.action in ("connect-usb", "disconnect-usb"):
            return configure_usb(wsl, remove=args.action == "disconnect-usb")
        if args.action == "doctor":
            return doctor(wsl)
        if args.action == "help":
            return wsl.run(["--help"])
        if args.action == "auth":
            return login(wsl, mode=args.mode, refresh=args.refresh)
        if args.action == "devices":
            return wsl.run(["devices", "--no-wait"])
        if args.action == "sdk":
            if args.xip.suffix.lower() != ".xip" or not args.xip.is_file():
                raise XtoolError("Selecciona un Xcode.xip existente descargado de Apple.")
            return wsl.run(["sdk", "install", wsl.path(args.xip)])
        if args.action == "install":
            require_auth(wsl)
            require_device(wsl, args.udid)
            print("xtool aprovisionara, reemplazara la firma de la copia temporal e instalara. La IPA original se conserva.", flush=True)
            command = ["install", wsl.path(args.ipa)]
            if args.udid:
                command += ["--udid", args.udid]
            return wsl.run(command, log=True)
        if args.action in ("build", "run"):
            command = ["dev", args.action, "--configuration", args.configuration]
            if args.action == "build":
                command += ["--ipa"]
            else:
                require_auth(wsl)
                require_device(wsl, args.udid)
                if args.udid:
                    command += ["--udid", args.udid]
            return wsl.run(command, cwd=wsl.path(args.project), log=True)
    except (XtoolError, OSError, ValueError, KeyError, zipfile.BadZipFile, subprocess.TimeoutExpired) as error:
        print(f"[X] xtool: {error}", file=sys.stderr, flush=True)
        return 1
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    raise SystemExit(main())
