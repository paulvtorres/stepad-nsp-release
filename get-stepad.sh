#!/usr/bin/env bash
#
# STEPAD NSP - instalador universal (siempre la última versión).
#
# Uso (en un Debian 12 limpio, como root):
#   curl -fsSL https://raw.githubusercontent.com/paulvtorres/stepad-nsp-release/main/get-stepad.sh | sudo bash
#
# También puedes pasar la URL directa de un instalador:
#   sudo bash get-stepad.sh https://github.com/paulvtorres/stepad-nsp-release/releases/download/v2.0.1/stepad-nsp-installer-v2.0.1.tar.gz
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
    echo "==> Buscando la última versión..."

    # 1) Si cada release incluye el asset con nombre fijo, esta URL
    #    (sin API y sin python3) apunta siempre a la última versión.
    URL="https://github.com/${RELEASE_REPO}/releases/latest/download/stepad-nsp-installer.tar.gz"
    if ! curl -fsSI "${URL}" >/dev/null 2>&1; then
        # 2) Resolución por API (solo curl + sed, disponibles en un Debian limpio).
        URL="$(curl -sS "https://api.github.com/repos/${RELEASE_REPO}/releases/latest" | sed -n 's/.*"browser_download_url": "\([^"]*stepad-nsp-installer[^"]*\)".*/\1/p' | head -1 || true)"
    fi
fi

if [ -z "${URL}" ]; then
    echo "ERROR: no se pudo resolver la última versión."
    echo "Descarga el instalador e instala a mano:"
    echo "  tar xzf stepad-nsp-installer-*.tar.gz && cd stepad-nsp && sudo bash install.sh"
    exit 1
fi

id -u "${APP_USER}" >/dev/null 2>&1 || useradd -m -s /bin/bash "${APP_USER}"

echo "==> Descargando instalador: ${URL}"
curl -fsSL "${URL}" -o /tmp/stepad-nsp-installer.tar.gz

echo "==> Extrayendo"
rm -rf "/home/${APP_USER}/stepad-nsp"
tar xzf /tmp/stepad-nsp-installer.tar.gz -C "/home/${APP_USER}"

echo "==> Instalando (detecta si ya existe una versión y pregunta S/N)"
bash "/home/${APP_USER}/stepad-nsp/install.sh"
