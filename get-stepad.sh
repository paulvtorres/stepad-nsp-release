#!/usr/bin/env bash
set -euo pipefail
URL="${1:-${STEPAD_INSTALLER_URL:-}}"
APP_USER="${APP_USER:-paulan}"
RELEASE_REPO="paulvtorres/stepad-nsp-release"
if [ "$(id -u)" -ne 0 ]; then
    echo "Ejecuta como root: ... | sudo bash"
    exit 1
fi
if [ -z "${URL}" ]; then
    echo "==> Buscando la última versión..."
    URL="$(curl -sS "https://api.github.com/repos/${RELEASE_REPO}/releases/latest" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    urls = [a['browser_download_url'] for a in d.get('assets', []) if 'stepad-nsp-installer' in a['browser_download_url']]
    if urls:
        print(urls[0])
" 2>/dev/null || true)"
fi
if [ -z "${URL}" ]; then
    echo "ERROR: no se pudo resolver la última versión."
    echo "Usa la URL directa (sin API):"
    echo "  sudo bash get-stepad.sh https://github.com/${RELEASE_REPO}/releases/latest/download/stepad-nsp-installer-v2.0.0.tar.gz"
    exit 1
fi
id -u "${APP_USER}" >/dev/null 2>&1 || useradd -m -s /bin/bash "${APP_USER}"
echo "==> Descargando instalador: ${URL}"
curl -fsSL "${URL}" -o /tmp/stepad-nsp-installer.tar.gz
echo "==> Extrayendo"
rm -rf "/home/${APP_USER}/stepad-nsp"
tar xzf /tmp/stepad-nsp-installer.tar.gz -C "/home/${APP_USER}"
echo "==> Instalando (detecta si existe una versión y actualiza)"
bash "/home/${APP_USER}/stepad-nsp/install.sh"
