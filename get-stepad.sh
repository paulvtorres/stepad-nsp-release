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
    URL="$(curl -fsSL "https://api.github.com/repos/${RELEASE_REPO}/releases/latest" | grep -o 'browser_download_url": "[^"]*stepad-nsp-installer[^"]*"' | head -1 | cut -d'"' -f4)"
fi
if [ -z "${URL}" ]; then
    echo "ERROR: no se encontró la última versión. Publica una release."
    exit 1
fi
id -u "${APP_USER}" >/dev/null 2>&1 || useradd -m -s /bin/bash "${APP_USER}"
echo "==> Descargando: ${URL}"
curl -fsSL "${URL}" -o /tmp/stepad-nsp-installer.tar.gz
echo "==> Extrayendo"
rm -rf "/home/${APP_USER}/stepad-nsp"
tar xzf /tmp/stepad-nsp-installer.tar.gz -C "/home/${APP_USER}"
echo "==> Instalando (detecta si existe una versión y actualiza)"
bash "/home/${APP_USER}/stepad-nsp/install.sh"
