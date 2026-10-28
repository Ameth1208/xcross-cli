#!/usr/bin/env bash
# xcross.sh - Instalador facilitado para crear aplicaciones Flutter
# Uso: chmod +x xcross.sh && ./xcross.sh
# Este script prepara Flutter SDK + xcross para desarrollo multiplataforma.

set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-stable}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/development}"
FLUTTER_DIR="$INSTALL_DIR/flutter"

info() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
ok()   { echo -e "\033[1;32m[OK]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
err()  { echo -e "\033[1;31m[ERR]\033[0m $*"; }

detect_os() {
  case "$(uname -s)" in
    Linux*)  echo "linux" ;;
    Darwin*) echo "macos" ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    *) err "SO no soportado: $(uname -s)"; exit 1 ;;
  esac
}

OS="$(detect_os)"
info "Sistema detectado: $OS"

# 1. Dependencias basicas
install_deps() {
  info "Verificando dependencias basicas (git, curl, unzip)..."
  if command -v git >/dev/null 2>&1 && command -v curl >/dev/null 2>&1 && command -v unzip >/dev/null 2>&1; then
    ok "Dependencias presentes."
    return
  fi
  case "$OS" in
    linux)
      if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update -y
        sudo apt-get install -y git curl unzip xz-utils
      elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y git curl unzip xz
      elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -Sy --noconfirm git curl unzip xz
      else
        err "Gestor de paquetes no soportado. Instala git, curl, unzip manualmente."
        exit 1
      fi
      ;;
    macos)
      if ! command -v brew >/dev/null 2>&1; then
        info "Instalando Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      fi
      brew install git curl unzip
      ;;
    windows)
      warn "En Windows usa el instalador PowerShell (Instalar-Comando-XCM.ps1) o winget."
      ;;
  esac
  ok "Dependencias instaladas."
}

# 2. Flutter SDK
install_flutter() {
  if command -v flutter >/dev/null 2>&1; then
    ok "Flutter ya esta instalado: $(flutter --version | head -n 1)"
    return
  fi
  info "Instalando Flutter SDK ($FLUTTER_VERSION) en $FLUTTER_DIR ..."
  mkdir -p "$INSTALL_DIR"
  if [ ! -d "$FLUTTER_DIR" ]; then
    git clone https://github.com/flutter/flutter.git -b "$FLUTTER_VERSION" "$FLUTTER_DIR"
  fi
  export PATH="$FLUTTER_DIR/bin:$PATH"
  flutter --version
  ok "Flutter instalado."
}

# 3. xcross
install_xcross() {
  if command -v xcross >/dev/null 2>&1; then
    ok "xcross ya esta instalado."
    return
  fi
  info "Instalando xcross (https://github.com/arxdeus/xcross)..."
  case "$OS" in
    linux|macos)
      if command -v cargo >/dev/null 2>&1; then
        cargo install --git https://github.com/arxdeus/xcross xcross 2>/dev/null || warn "xcross no disponible via cargo; revisa el repo oficial."
      else
        warn "Rust/cargo no encontrado. xcross requiere Rust. Instala Rust: https://rustup.rs"
      fi
      ;;
    windows)
      warn "En Windows, xcross se instala con el script oficial: https://raw.githubusercontent.com/arxdeus/xcross/main/install.ps1"
      ;;
  esac
}

# 4. PATH persistente
persist_path() {
  info "Configurando PATH persistente..."
  SHELL_RC=""
  case "${SHELL:-}" in
    */zsh)  SHELL_RC="$HOME/.zshrc" ;;
    */bash) SHELL_RC="$HOME/.bashrc" ;;
    *)      SHELL_RC="$HOME/.profile" ;;
  esac
  if ! grep -q 'flutter/bin' "$SHELL_RC" 2>/dev/null; then
    echo "export PATH=\"\$HOME/development/flutter/bin:\$PATH\"" >> "$SHELL_RC"
    ok "PATH agregado a $SHELL_RC"
  else
    ok "PATH ya configurado."
  fi
}

main() {
  install_deps
  install_flutter
  install_xcross
  persist_path
  echo ""
  ok "Instalacion completada."
  info "Recarga tu shell: source ${SHELL_RC:-~/.bashrc}"
  info "Verifica con: flutter doctor"
  info "Crea tu primera app: flutter create mi_app && cd mi_app && flutter run"
}

main "$@"
