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
    # OJO: con `pipefail` activo, "tar -xOf ... | head -1 | grep -q ..."
    # puede fallar por una condicion de carrera de SIGPIPE (head/grep
    # cierran la tuberia antes de que tar termine de escribir), lo que
    # reporta "incompleto" aunque el contenido sea correcto. Por eso se
    # captura la salida completa en variables y se compara con bash
    # nativo (sin tuberias hacia comandos que cortan la lectura).
    local listing content

    listing="$(tar -tzf /tmp/stepad-nsp-installer.tar.gz 2>/dev/null || true)"

    if [[ "${listing}" != *"stepad-nsp/backend/migrations/versions/0009_email_subjects.py"* ]]; then
        return 1
    fi

    content="$(tar -xOf /tmp/stepad-nsp-installer.tar.gz \
        stepad-nsp/backend/backups/models/backup_settings.py 2>/dev/null || true)"

    [[ "${content}" == *"Integer, String"* ]]
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

attempt=1
max_attempts=5
wait_seconds=10

while ! installer_ok; do
    if [ "${attempt}" -ge "${max_attempts}" ]; then
        echo "ERROR: el instalador descargado sigue incompleto/obsoleto tras ${attempt} intentos"
        echo "(falta la migración 0009 o el fix de backup_settings)."
        echo "Esto suele ser el CDN de GitHub propagando el release; espera 1-2"
        echo "minutos y reintenta el mismo comando, o aplica el parche manual:"
        echo "  sudo sed -i 's/Integer\$/Integer, String/' /home/${APP_USER}/stepad-nsp/backend/backups/models/backup_settings.py"
        echo "  sudo bash /home/${APP_USER}/stepad-nsp/install.sh"
        exit 1
    fi

    echo "AVISO: paquete obsoleto/incompleto (posible CDN sin propagar);"
    echo "       reintentando en ${wait_seconds}s (intento $((attempt + 1))/${max_attempts})..."
    sleep "${wait_seconds}"

    if [ -n "${VERSION}" ] && [ $((attempt % 2)) -eq 1 ]; then
        download_installer "${BASE}/stepad-nsp-installer-${VERSION}.tar.gz?$(date +%s%N)"
    else
        download_installer "${BASE}/stepad-nsp-installer.tar.gz?$(date +%s%N)"
    fi

    attempt=$((attempt + 1))
    wait_seconds=$((wait_seconds + 10))
done

id -u "${APP_USER}" >/dev/null 2>&1 || useradd -m -s /bin/bash "${APP_USER}"

echo "==> Extrayendo"
rm -rf "/home/${APP_USER}/stepad-nsp"
tar xzf /tmp/stepad-nsp-installer.tar.gz -C "/home/${APP_USER}"

echo "==> Instalando (detecta si ya existe una versión y la actualiza)"
bash "/home/${APP_USER}/stepad-nsp/install.sh"
