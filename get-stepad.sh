#!/usr/bin/env bash
#
# STEPAD NSP - instalación desde internet en un solo comando.
#
# Uso:
#   curl -fsSL https://raw.githubusercontent.com/paulvtorres/stepad-nsp-release/main/get-stepad.sh | sudo bash
#
# Descarga SIEMPRE la última versión publicada en GitHub Releases
# del repo stepad-nsp-release (a menos que pases una URL explícita).
#
set -euo pipefail

URL="${1:-${STEPAD_INSTALLER_URL:-}}"
APP_USER="${APP_USER:-paulan}"

RELEASE_REPO="paulvtorres/stepad-nsp-release"

if [ "$(id -u)" -ne 0 ]; then
    echo "Ejecuta como root: ... | sudo bash"
    exit 1
fi

# Si no se pasó una URL, resolver la última versión publicada.
if [ -z "${URL}" ]; then
    echo "==> Buscando la última versión de STEPAD NSP..."
    URL="$(
        curl -fsSL "https://api.github.com/repos/${RELEASE_REPO}/releases/latest" \
        | grep -o 'browser_download_url": "[^"]*stepad-nsp-installer[^"]*"' \
        | head -1 \
        | cut -d'"' -f4
    )"
fi

if [ -z "${URL}" ]; then
    echo "ERROR: no se encontró la última versión. Publica una release o pasa la URL manualmente:"
    echo "  sudo bash get-stepad.sh <URL-del-instalador>"
    exit 1
fi

id -u "${APP_USER}" >/dev/null 2>&1 || useradd -m -s /bin/bash "${APP_USER}"

echo "==> Descargando instalador: ${URL}"
curl -fsSL "${URL}" -o /tmp/stepad-nsp-installer.tar.gz

echo "==> Extrayendo"
rm -rf "/home/${APP_USER}/stepad-nsp"
tar xzf /tmp/stepad-nsp-installer.tar.gz -C "/home/${APP_USER}"

echo "==> Instalando (detecta si ya existe una versión y la actualiza)"
bash "/home/${APP_USER}/stepad-nsp/install.sh"
