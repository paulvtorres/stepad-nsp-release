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
    # El instalador debe traer TODAS las migraciones (hasta la mas
    # reciente conocida) y el hotfix de backup_settings. Si falta
    # cualquiera de las dos, es un tarball incompleto/obsoleto (p. ej.
    # servido por una copia en cache de una version anterior).
    tar -tzf /tmp/stepad-nsp-installer.tar.gz 2>/dev/null \
        | grep -q 'stepad-nsp/backend/migrations/versions/0009_email_subjects.py' \
        || return 1

    tar -xOf /tmp/stepad-nsp-installer.tar.gz \
        stepad-nsp/backend/backups/models/backup_settings.py 2>/dev/null \
        | head -1 \
        | grep -q 'Integer, String'
}

VERSION=""

if [ -z "${URL}" ]; then
    echo "==> Descargando la última versión publicada en ${RELEASE_REPO}..."
    VERSION="$(curl -fsSL "${BASE}/VERSION?$(date +%s)" | tr -d '\r\n' || true)"
    if [ -n "${VERSION}" ]; then
        echo "==> Versión en release: ${VERSION}"
        # Preferir el paquete FIJADO a esa version (URL unica que nunca
        # se sobreescribe) en vez del nombre generico "latest": ese
        # nombre SI se sobreescribe en cada release y el CDN de GitHub
        # puede tardar en refrescarlo, sirviendo por minutos una copia
        # vieja/incompleta bajo el mismo nombre (p. ej. sin la ultima
        # migracion de base de datos).
        URL="${BASE}/stepad-nsp-installer-${VERSION}.tar.gz?$(date +%s)"
    else
        URL="${BASE}/stepad-nsp-installer.tar.gz?$(date +%s)"
    fi
fi

download_installer "${URL}"

if ! installer_ok; then
    echo "AVISO: paquete obsoleto/incompleto; reintentando con el nombre genérico..."
    download_installer "${BASE}/stepad-nsp-installer.tar.gz?$(date +%s)"
fi

if ! installer_ok; then
    echo "AVISO: sigue obsoleto/incompleto; reintentando en 5s (propagación de CDN)..."
    sleep 5
    if [ -n "${VERSION}" ]; then
        download_installer "${BASE}/stepad-nsp-installer-${VERSION}.tar.gz?$(date +%s)-retry"
    else
        download_installer "${BASE}/stepad-nsp-installer.tar.gz?$(date +%s)-retry"
    fi
fi

if ! installer_ok; then
    echo "ERROR: el instalador descargado sigue incompleto/obsoleto tras reintentos"
    echo "(falta la migración 0009 o el fix de backup_settings)."
    echo "Espera un minuto (propagación de CDN) y reintenta el mismo comando, o"
    echo "aplica el parche manual:"
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
