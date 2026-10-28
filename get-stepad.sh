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
FIXED_URL=""
[ -n "${URL}" ] && FIXED_URL=1
APP_USER="${APP_USER:-paulan}"
RELEASE_REPO="paulvtorres/stepad-nsp-release"
BASE="https://raw.githubusercontent.com/${RELEASE_REPO}/main"

# Clave pública (Ed25519) que firma los instaladores. La privada vive
# SOLO en la máquina de desarrollo (~/.config/stepad/update-signing.key)
# y nunca se publica. Cambiar de clave = editar este bloque y republicar.
PUBKEY_PEM="$(cat <<'EOF'
-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEA1SUJEUgdTfDMbXLXRrkljB1NeV4LXa0qa0iQVPnvrwE=
-----END PUBLIC KEY-----
EOF
)"

# Comparación de versiones tipo v2.5.10 > v2.5.9 (no basta sort alfabético).
# Se usa para no DEGRADAR una instalación si el CDN sirve un VERSION atrasado:
# eso reinstalaba una versión vieja y, con los cambios de instalador, abortaba
# la actualización a mitad de camino.
version_ge() {
    [ -n "${1:-}" ] || return 1
    [ -n "${2:-}" ] || return 0
    [ "${1}" = "${2}" ] && return 0
    local lowest
    lowest="$(printf '%s\n%s\n' "${1}" "${2}" | sort -V | head -1)"
    [ "${lowest}" = "${2}" ]
}

# Autotest (lo usan los tests): --compare-versions
if [ "${1:-}" = "--compare-versions" ]; then
    if version_ge "${STEPAD_VC_A:-}" "${STEPAD_VC_B:-}"; then
        echo "ge"
    else
        echo "lt"
    fi
    exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "Ejecuta como root: ... | sudo bash"
    exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
    echo "ERROR: se requiere openssl para verificar la firma del instalador."
    exit 1
fi

download_installer() {
    echo "==> Descargando instalador: $1"
    curl -fsSL "$1" -o /tmp/stepad-nsp-installer.tar.gz
}

download_signature() {
    echo "==> Descargando firma: $1"
    if ! curl -fsSL "$1" -o /tmp/stepad-nsp-installer.tar.gz.sig; then
        echo "ERROR: no se pudo descargar la firma del instalador."
        echo "No se ejecutó nada. Reintenta en unos minutos."
        exit 1
    fi
}

verify_installer() {
    local pub=/tmp/stepad-nsp-update.pub.pem
    local sig=/tmp/stepad-nsp-installer.tar.gz.sig
    printf '%s\n' "${PUBKEY_PEM}" > "${pub}"
    openssl pkeyutl -verify -pubin -inkey "${pub}" -rawin \
        -in /tmp/stepad-nsp-installer.tar.gz -sigfile "${sig}" \
        >/dev/null 2>&1
}

installed_version() {
    local file="/etc/stepad/version"
    [ -r "${file}" ] || return 0
    tr -d '\r\n' < "${file}" || true
}

package_version() {
    tar -xOf /tmp/stepad-nsp-installer.tar.gz stepad-nsp/VERSION 2>/dev/null \
        | tr -d '\r\n' || true
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

    [[ "${content}" == *"Integer, String"* ]] || return 1

    # No degradar: si el paquete es más viejo que lo instalado, se trata
    # como "no válido" y el bucle reintenta (el CDN suele estar propagando).
    local installed pkg
    installed="$(installed_version)"
    pkg="$(package_version)"

    if [ -n "${installed}" ] && [ -n "${pkg}" ] \
       && ! version_ge "${pkg}" "${installed}"; then
        return 1
    fi

    return 0
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
SIG_URL="${URL%%\?*}.sig"
download_signature "${SIG_URL}?$(date +%s%N)"

attempt=1
max_attempts=5
wait_seconds=10

while ! installer_ok; do
    if [ "${attempt}" -ge "${max_attempts}" ]; then
        echo "ERROR: el instalador descargado no es utilizable tras ${attempt} intentos."
        echo "Causas posibles:"
        echo "  - El CDN de GitHub aún sirve un VERSION/paquete atrasado"
        echo "    (instalado: $(installed_version || echo '?'), paquete: $(package_version || echo '?'))"
        echo "  - El paquete no trae la migración 0009 o el fix de backup_settings."
        echo "Espera 1-2 minutos y repite el mismo comando. Nunca se degrada"
        echo "una instalación a una versión anterior: se aborta sin tocar nada."
        exit 1
    fi

    echo "AVISO: paquete obsoleto/incompleto (posible CDN sin propagar);"
    echo "       reintentando en ${wait_seconds}s (intento $((attempt + 1))/${max_attempts})..."
    sleep "${wait_seconds}"

    # Re-resolver la versión en cada reintento: si el CDN ya propagó,
    # el siguiente intento baja el paquete correcto.
    if [ -z "${FIXED_URL}" ]; then
        VERSION="$(curl -fsSL "${BASE}/VERSION?$(date +%s)" | tr -d '\r\n' || true)"
    fi

    if [ -n "${VERSION}" ]; then
        download_installer "${BASE}/stepad-nsp-installer-${VERSION}.tar.gz?$(date +%s%N)"
        SIG_URL="${BASE}/stepad-nsp-installer-${VERSION}.tar.gz.sig"
    else
        download_installer "${BASE}/stepad-nsp-installer.tar.gz?$(date +%s%N)"
        SIG_URL="${BASE}/stepad-nsp-installer.tar.gz.sig"
    fi
    download_signature "${SIG_URL}?$(date +%s%N)"

    attempt=$((attempt + 1))
    wait_seconds=$((wait_seconds + 10))
done

# Fail-closed: el instalador SOLO se ejecuta si la firma Ed25519 coincide
# con la clave pública incluida arriba. Un tarball alterado, truncado o
# servido por un CDN comprometido se rechaza aquí.
if ! verify_installer; then
    echo "ERROR: la firma del instalador NO es válida. Actualización abortada."
    echo "No se ejecutó nada. Reintenta en unos minutos; si persiste,"
    echo "verifica manualmente la firma con scripts/update-signing.pub.pem."
    exit 1
fi
echo "==> Firma del instalador verificada."

id -u "${APP_USER}" >/dev/null 2>&1 || useradd -m -s /bin/bash "${APP_USER}"

echo "==> Extrayendo"

# Blinda las claves ANTES de tocar la instalación: cada update guarda
# una copia versionada del env actual (incluye STEPAD_RESTIC_PASSWORD o
# cualquier secreto generado), de modo que NUNCA se pierde la capacidad
# de descifrar los repositorios de respaldo existentes aunque algo falle.
ENV_FILE="/etc/stepad/stepad.env"
if [ -f "${ENV_FILE}" ]; then
  BK_DIR="/etc/stepad/env-backups"
  mkdir -p "${BK_DIR}"
  chmod 0700 "${BK_DIR}"
  TS="$(date +%Y%m%d-%H%M%S)"
  if ! grep -q "STEPAD_RESTIC_PASSWORD" "${ENV_FILE}" >/dev/null 2>&1 \
     && command -v sha256sum >/dev/null 2>&1; then
    HASH="$(sha256sum "${ENV_FILE}" 2>/dev/null | cut -d' ' -f1 | cut -c1-8)"
  else
    HASH="missing-${TS}"
  fi
  DEST="${BK_DIR}/stepad.env.${TS}.${HASH}"
  cp -a "${ENV_FILE}" "${DEST}"
  chmod 0600 "${DEST}"
  find "${BK_DIR}" -maxdepth 1 -name "stepad.env.*" -type f -mtime +90 -delete 2>/dev/null
  echo "==> Env respaldado en ${DEST} (por si se necesita recuperar claves)"
fi

# La config de red/DHCP es estado propio de CADA máquina y vive en
# /etc/stepad/config.yaml. El instalador trae una config.yaml generica en
# el repo: sin este respaldo, el rm -rf de abajo la borraba y cada
# update podía dejar WAN/LAN con las interfaces de la maquina de
# desarrollo. Instalaciones viejas tenían la config dentro del repo:
# esa ruta se acepta como origen del respaldo.
SYSTEM_CONFIG="/etc/stepad/config.yaml"
LEGACY_CONFIG="/home/${APP_USER}/stepad-nsp/backend/shared/config/config.yaml"
CONFIG_BACKUP=""
if [ -f "${SYSTEM_CONFIG}" ]; then
  CONFIG_BACKUP="$(mktemp /tmp/stepad-config.XXXXXX)"
  cp -a "${SYSTEM_CONFIG}" "${CONFIG_BACKUP}"
  echo "==> config.yaml actual respaldado para restaurarlo tras el update"
elif [ -f "${LEGACY_CONFIG}" ]; then
  CONFIG_BACKUP="$(mktemp /tmp/stepad-config.XXXXXX)"
  cp -a "${LEGACY_CONFIG}" "${CONFIG_BACKUP}"
  echo "==> config.yaml (ruta antigua) respaldado para restaurarlo tras el update"
fi

rm -rf "/home/${APP_USER}/stepad-nsp"
tar xzf /tmp/stepad-nsp-installer.tar.gz -C "/home/${APP_USER}"

if [ -n "${CONFIG_BACKUP}" ] && [ -f "${CONFIG_BACKUP}" ]; then
  mkdir -p /etc/stepad
  cp -a "${CONFIG_BACKUP}" "${SYSTEM_CONFIG}"
  chown "${APP_USER}:${APP_USER}" "${SYSTEM_CONFIG}"
  chmod 0640 "${SYSTEM_CONFIG}"
  rm -f "${CONFIG_BACKUP}"
  echo "==> config.yaml de esta máquina restaurado en ${SYSTEM_CONFIG}"
fi

echo "==> Instalando (detecta si ya existe una versión y la actualiza)"
bash "/home/${APP_USER}/stepad-nsp/install.sh"
