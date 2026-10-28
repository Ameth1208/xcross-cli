#!/usr/bin/env bash
# XCross CLI (Linux) v1.2.0
# Terminal helper for Flutter development on Linux, inspired by XCross CLI for Windows.
# Usage: chmod +x xcross-linux.sh && ./xcross-linux.sh [command]

set -u

VERSION="1.2.0"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/xcross-menu"
CONFIG_FILE="$CONFIG_DIR/settings.json"
PROJECT_DIR=""
BUNDLE_MODE="default"

# ---------- colors ----------
C='\033[1;36m'; W='\033[1;37m'; G='\033[1;32m'; Y='\033[1;33m'; R='\033[1;31m'; D='\033[0;90m'; N='\033[0m'

title()   { echo; echo -e "  ${C}xcm${N} ${W}/ $1${N}"; echo -e "  ${D}------------------------------------------------------------${N}"; }
ok()      { echo -e "  ${G}[OK]${N} $1"; }
warn()    { echo -e "  ${Y}[!]${N} $1"; }
fail()    { echo -e "  ${R}[X]${N} $1"; }
info()    { echo -e "  $1"; }

pause_menu() {
  echo; echo -e "  ${D}[ cualquier tecla ] Volver al menu${N}";
  read -rsn1
}

confirm() {
  echo -ne "  ${Y}? $1${N}  ${D}[S]i / [N]o${N}  "
  read -rsn1 ans; echo "$ans"
  [[ "$ans" =~ ^[sSyY]$ ]]
}

has() { command -v "$1" >/dev/null 2>&1; }

# ---------- settings ----------
load_settings() {
  if [[ -f "$CONFIG_FILE" ]]; then
    PROJECT_DIR=$(grep -o '"FlutterProject"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" 2>/dev/null | sed 's/.*:"\(.*\)"/\1/')
    BUNDLE_MODE=$(grep -o '"BundleIdMode"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" 2>/dev/null | sed 's/.*:"\(.*\)"/\1/')
    [[ -z "$BUNDLE_MODE" ]] && BUNDLE_MODE="default"
  fi
}
save_settings() {
  mkdir -p "$CONFIG_DIR"
  cat > "$CONFIG_FILE" <<EOF
{
  "FlutterProject": "$PROJECT_DIR",
  "BundleIdMode": "$BUNDLE_MODE"
}
EOF
}

# ---------- commands ----------
cmd_help() {
  title "Ayuda"
  cat <<'EOF'
  Uso: xcm [comando] [args]

  Comandos:
    help            Muestra esta ayuda
    doctor          Verifica herramientas instaladas (flutter, git, adb, xcross)
    device          Lista dispositivos conectados (adb / flutter devices)
    project show    Muestra el proyecto Flutter seleccionado
    project set DIR Selecciona un proyecto Flutter
    run [--usb|--wifi] [-t file]   Ejecuta flutter run
    precache debug|all   Descarga artefactos del motor Flutter
    bundle default|original   Selecciona modo de Bundle ID
    sign [id]       Info de firma (Linux: configura keystore manualmente)
    install         Instala xcm como comando global en ~/.local/bin
    tunnel usb|wifi Configura tunnel USB/WiFi via adb
    trust           Guia de confianza/firma en dispositivo
    update          Actualiza Flutter y dependencias
    version         Version del CLI
    menu            Abre el menu interactivo (por defecto)

  Sin instalar como comando global, ejecuta: ./xcross-linux.sh <comando>
EOF
}

cmd_version() { echo "XCross CLI (Linux) v$VERSION"; }

cmd_doctor() {
  title "Doctor"
  for t in flutter dart git adb xcross python3; do
    if has "$t"; then ok "$t: $(command -v $t)"; else fail "$t: no encontrado"; fi
  done
  if has flutter; then
    echo; flutter --version 2>&1 | head -n 3
    echo; flutter doctor 2>&1 | head -n 20
  fi
}

cmd_device() {
  title "Dispositivos"
  if has flutter; then flutter devices; fi
  if has adb; then echo; adb devices -l; fi
}

cmd_project_show() {
  title "Proyecto Flutter"
  if [[ -n "$PROJECT_DIR" ]]; then
    info "Proyecto: $PROJECT_DIR"
    if [[ -f "$PROJECT_DIR/pubspec.yaml" ]]; then ok "pubspec.yaml encontrado"; else warn "No parece un proyecto Flutter"; fi
  else
    warn "No hay proyecto seleccionado. Usa: xcm project set <ruta>"
  fi
}

cmd_project_set() {
  local dir="${1:-}"
  if [[ -z "$dir" ]]; then read -rp "  Ruta del proyecto Flutter: " dir; fi
  if [[ -d "$dir" ]]; then
    PROJECT_DIR="$(cd "$dir" && pwd)"
    save_settings
    ok "Proyecto establecido: $PROJECT_DIR"
  else
    fail "Directorio no existe: $dir"
  fi
}

cmd_run() {
  title "Run"
  local target="lib/main.dart" mode="usb"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --usb) mode="usb"; shift ;;
      --wifi) mode="wifi"; shift ;;
      -t) target="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  if [[ -z "$PROJECT_DIR" ]]; then fail "Selecciona un proyecto primero (xcm project set)."; return; fi
  cd "$PROJECT_DIR" || return
  if [[ "$mode" == "wifi" ]]; then
    warn "Modo WiFi: asegurate de que el dispositivo este en la misma red y habilitado para depuracion inalambrica."
  fi
  info "Ejecutando: flutter run -t $target"
  flutter run -t "$target"
}

cmd_precache() {
  title "Precache"
  if ! has flutter; then fail "flutter no encontrado"; return; fi
  if [[ -z "$PROJECT_DIR" ]]; then fail "Selecciona un proyecto primero."; return; fi
  cd "$PROJECT_DIR" || return
  case "${1:-debug}" in
    debug) flutter precache --ios 2>/dev/null || flutter precache ;;
    all)   flutter precache --all ;;
    *)     warn "Uso: xcm precache debug|all" ;;
  esac
}

cmd_bundle() {
  title "Bundle ID"
  case "${1:-}" in
    default)  BUNDLE_MODE="default"; save_settings; ok "Modo: default" ;;
    original) BUNDLE_MODE="original"; save_settings; ok "Modo: original" ;;
    *) warn "Uso: xcm bundle default|original" ;;
  esac
}

cmd_sign() {
  title "Firma"
  if [[ -n "${1:-}" ]]; then info "Bundle ID: $1"; fi
  info "En Linux, configura tu keystore en android/app/build.gradle y firma con:"
  info "  keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload"
  info "Modo actual: $BUNDLE_MODE"
}

cmd_update() {
  title "Update"
  if has flutter; then flutter upgrade; fi
  if [[ -n "$PROJECT_DIR" && -f "$PROJECT_DIR/pubspec.yaml" ]]; then
    cd "$PROJECT_DIR" && flutter pub get
  fi
}

# ---------- install as global command ----------
cmd_install() {
  title "Instalar xcm (Linux)"
  local bin="$HOME/.local/bin"
  mkdir -p "$bin"
  local src
  src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  cp "$src" "$bin/xcm"
  chmod +x "$bin/xcm"
  ok "Instalado en $bin/xcm"
  if [[ ":$PATH:" != *":$bin:"* ]]; then
    warn "$bin no esta en PATH. Agrega a tu shell rc:"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
  else
    ok "PATH ya incluye $bin"
  fi
  info "Abre una nueva terminal y usa: xcm help"
}

# ---------- tunnel ----------
cmd_tunnel() {
  title "Tunnel"
  if ! has adb; then fail "adb no encontrado"; return; fi
  case "${1:-usb}" in
    usb)
      info "Configurando reverse USB (tcp:8081)..."
      adb reverse tcp:8081 tcp:8081 && ok "USB reverse listo"
      ;;
    wifi)
      info "Habilitando depuracion inalambrica..."
      adb tcpip 5555
      warn "Conecta con: adb connect <IP_DEL_DISPOSITIVO>:5555"
      ;;
    *)
      warn "Uso: xcm tunnel usb|wifi"
      ;;
  esac
}

# ---------- trust guidance ----------
cmd_trust() {
  title "Trust / firma"
  info "En Android, habilita 'Opciones de desarrollador' y 'Depuracion USB' en el dispositivo."
  info "Acepta el dialogo RSA al conectar por primera vez."
  info "Para firma de release, configura keystore en android/app/build.gradle."
  info "Modo Bundle ID actual: $BUNDLE_MODE"
}

# ---------- menu ----------
menu() {
  load_settings
  while true; do
    title "Menu principal"
    echo "  1) Doctor (verificar herramientas)"
    echo "  2) Dispositivos"
    echo "  3) Proyecto: mostrar"
    echo "  4) Proyecto: seleccionar"
    echo "  5) Run (USB)"
    echo "  6) Run (WiFi)"
    echo "  7) Precache debug"
    echo "  8) Precache all"
    echo "  9) Bundle ID: default/original"
    echo "  I) Instalar xcm global"
    echo "  T) Tunnel (usb/wifi)"
    echo "  R) Trust / firma"
    echo "  D) Doctor detallado"
    echo "  F) Firma / keystore"
    echo "  P) Project show"
    echo "  U) Update"
    echo "  H) Ayuda"
    echo "  0) Salir"
    echo
    read -rsn1 choice
    echo
    case "$choice" in
      1) cmd_doctor; pause_menu ;;
      2) cmd_device; pause_menu ;;
      3) cmd_project_show; pause_menu ;;
      4) cmd_project_set; pause_menu ;;
      5) cmd_run --usb; pause_menu ;;
      6) cmd_run --wifi; pause_menu ;;
      7) cmd_precache debug; pause_menu ;;
      8) cmd_precache all; pause_menu ;;
      9) echo "  1) default  2) original"; read -rsn1 b; [[ "$b" == "1" ]] && cmd_bundle default || cmd_bundle original; pause_menu ;;
      [iI]) cmd_install; pause_menu ;;
      [tT]) echo "  1) usb  2) wifi"; read -rsn1 b; [[ "$b" == "1" ]] && cmd_tunnel usb || cmd_tunnel wifi; pause_menu ;;
      [rR]) cmd_trust; pause_menu ;;
      [dD]) cmd_doctor; pause_menu ;;
      [fF]) cmd_sign; pause_menu ;;
      [pP]) cmd_project_show; pause_menu ;;
      [uU]) cmd_update; pause_menu ;;
      [hH]) cmd_help; pause_menu ;;
      0|[qQ]) echo "  Saliendo."; exit 0 ;;
      *) warn "Opcion no valida"; sleep 1 ;;
    esac
  done
}

# ---------- dispatch ----------
load_settings
case "${1:-menu}" in
  help) shift; cmd_help "$@" ;;
  version|--version|-v) cmd_version ;;
  doctor) shift; cmd_doctor "$@" ;;
  device) shift; cmd_device "$@" ;;
  project)
    shift
    case "${1:-}" in
      show) cmd_project_show ;;
      set) shift; cmd_project_set "$@" ;;
      *) cmd_project_show ;;
    esac ;;
  run) shift; cmd_run "$@" ;;
  precache) shift; cmd_precache "$@" ;;
  bundle) shift; cmd_bundle "$@" ;;
  sign) shift; cmd_sign "$@" ;;
  install) shift; cmd_install "$@" ;;
  tunnel) shift; cmd_tunnel "$@" ;;
  trust) shift; cmd_trust "$@" ;;
  update) shift; cmd_update "$@" ;;
  menu) menu ;;
  *) menu ;;
esac