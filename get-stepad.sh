#!/usr/bin/env bash
#
# STEPAD NSP - instalación / actualización desde internet.
#
# Uso (Debian 12, como root):
#   curl -fsSL https://raw.githubusercontent.com/paulvtorres/stepad-nsp-release/main/get-stepad.sh | sudo bash
#
# Descarga el instalador trackeado en el branch main del repo release
# (stepad-nsp-installer.tar.gz). Publicar una versión nueva = subir ese
# archivo al git stepad-nsp-release y hacer push a main.
#
set -euo pipefail

URL="${1:-${STEPAD_INSTALLER_URL:-}}"
APP_USER="${APP_USER:-paulan}"
RELEASE_REPO="paulvtorres/stepad-nsp-release"

if [ "$(id -u)" -ne 0 ]; then
    echo "Ejecuta como root: ... | sudo bash"
    exit 1
fi

if [ -z "${URL}" ]; then
    echo "==> Descargando la última versión publicada en ${RELEASE_REPO}..."
    URL="https://raw.githubusercontent.com/${RELEASE_REPO}/main/stepad-nsp-installer.tar.gz"
fi

if ! curl -fsSLI "${URL}" >/dev/null 2>&1; then
    echo "ERROR: no se pudo descargar el instalador desde:"
    echo "  ${URL}"
    echo ""
    echo "Verifica que stepad-nsp-installer.tar.gz esté en main de ${RELEASE_REPO}."
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
