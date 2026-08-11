#!/usr/bin/env bash
#
# STEPAD NSP - instalador universal (siempre la última versión).
#
# Uso (en un Debian 12 limpio, como root):
#   curl -fsSL https://raw.githubusercontent.com/paulvtorres/stepad-nsp-release/main/get-stepad.sh | sudo bash
#
# También puedes pasar la URL directa de un instalador:
#   sudo bash get-stepad.sh https://github.com/paulvtorres/stepad-nsp-release/releases/download/v2.0.2/stepad-nsp-installer-v2.0.2.tar.gz
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
    if ! curl -fsSLI "${URL}" >/dev/null 2>&1; then
        API_JSON="$(curl -sS "https://api.github.com/repos/${RELEASE_REPO}/releases/latest" || true)"

        # 2) Resolución por API con sed (solo curl + sed).
        URL="$(printf '%s' "${API_JSON}" | sed -n 's/.*"browser_download_url": "\([^"]*stepad-nsp-installer[^"]*\)".*/\1/p' | head -1 || true)"

        # 3) Fallback con python3 (por si el formato cambia).
        if [ -z "${URL}" ]; then
            URL="$(printf '%s' "${API_JSON}" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    for a in d.get("assets", []):
        u = a.get("browser_download_url", "")
        if "stepad-nsp-installer" in u:
            print(u)
            break
except Exception:
    pass
' 2>/dev/null || true)"
        fi
    fi
fi

if [ -z "${URL}" ]; then
    echo "ERROR: no se pudo resolver la última versión."
    echo "La API de GitHub tiene límite de peticiones por hora; espera unos minutos y reintenta."
    echo "O usa la URL directa de la versión publicada:"
    echo "  curl -fsSL https://github.com/${RELEASE_REPO}/releases/latest/download/stepad-nsp-installer-v2.0.2.tar.gz | tar xz && cd stepad-nsp && sudo bash install.sh"
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
