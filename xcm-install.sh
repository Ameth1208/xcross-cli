#!/usr/bin/env bash
# Remote installer for XCross CLI on Linux/macOS.
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Ameth1208/xcross-cli/main/xcm-install.sh | bash
set -euo pipefail

REPO="Ameth1208/xcross-cli"
BRANCH="main"
BASE="https://raw.githubusercontent.com/$REPO/$BRANCH"
BIN="$HOME/.local/bin"
mkdir -p "$BIN"

fetch() {
  local file="$1" dest="$2"
  echo "Descargando $file ..."
  curl -fsSL "$BASE/$file" -o "$dest"
}

fetch "linux-cli.sh" "$BIN/xcm"
chmod +x "$BIN/xcm"

# Optional helpers
fetch "setup-flutter.sh" "$BIN/setup-flutter.sh" 2>/dev/null && chmod +x "$BIN/setup-flutter.sh" || true

# PATH
if [[ ":$PATH:" != *":$BIN:"* ]]; then
  echo "Agrega a tu shell rc:  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo "Instalado en: $BIN/xcm"
echo "Usa: xcm help"
echo "O ejecuta el menu: xcm"
