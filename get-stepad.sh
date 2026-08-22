#!/usr/bin/env bash
#
# STEPAD NSP - instalación / actualización desde internet.
#
# Uso (Debian 12, como root):
#   curl -fsSL "https://raw.githubusercontent.com/paulvtorres/stepad-nsp-release/main/get-stepad.sh?v=$(date +%s)" | sudo bash
#
# Descarga el instalador trackeado en el branch main del repo release
# (stepad-nsp-installer.tar.gz). Publicar una versión nueva = subir ese
# archivo al git stepad-nsp-release y hacer push a main.
#
set -euo pipefail

URL="${1:-${STEPAD_INSTALLER_URL:-}}"
APP_USER="${APP_USER:-paulan}"
RELEASE_REPO="paulvtorres/stepad-nsp-release"
BASE="https://raw.githubusercontent.com/${RELEASE_REPO}/main"

if [ "$(id -u)" -ne 0 ]; then
    echo "Ejecuta como root: ... | sudo bash"
    exit 1
fi

download_installer() {
    echo "==> Descargando instalador: $1"
    curl -fsSL "$1" -o /tmp/stepad-nsp-installer.tar.gz
}

installer_ok() {
    tar -xOf /tmp/stepad-nsp-installer.tar.gz \
        stepad-nsp/backend/backups/models/backup_settings.py 2>/dev/null \
        | head -1 \
        | grep -q 'Integer, String'
}

if [ -z "${URL}" ]; then
    echo "==> Descargando la última versión publicada en ${RELEASE_REPO}..."
    VERSION="$(curl -fsSL "${BASE}/VERSION?$(date +%s)" | tr -d '\r\n' || true)"
    if [ -n "${VERSION}" ]; then
        echo "==> Versión en release: ${VERSION}"
    fi
    URL="${BASE}/stepad-nsp-installer.tar.gz?$(date +%s)"
fi

download_installer "${URL}"

if ! installer_ok; then
    echo "AVISO: paquete obsoleto en CDN; probando v2.5.19..."
    download_installer "${BASE}/stepad-nsp-installer-v2.5.19.tar.gz?$(date +%s)"
fi

if ! installer_ok; then
    echo "ERROR: el instalador descargado no incluye el fix de backup_settings."
    echo "Parche manual y reintento:"
    echo "  sudo sed -i 's/Integer\$/Integer, String/' /home/${APP_USER}/stepad-nsp/backend/backups/models/backup_settings.py"
    echo "  sudo bash /home/${APP_USER}/stepad-nsp/install.sh"
    exit 1
fi

id -u "${APP_USER}" >/dev/null 2>&1 || useradd -m -s /bin/bash "${APP_USER}"

echo "==> Extrayendo"
rm -rf "/home/${APP_USER}/stepad-nsp"
tar xzf /tmp/stepad-nsp-installer.tar.gz -C "/home/${APP_USER}"

echo "==> Instalando (detecta si ya existe una versión y la actualiza)"
bash "/home/${APP_USER}/stepad-nsp/install.sh"
