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
APP_DIR="/home/${APP_USER}/stepad-nsp"
RELEASE_REPO="paulvtorres/stepad-nsp-release"
BASE="https://raw.githubusercontent.com/${RELEASE_REPO}/main"

# Guard: un equipo marcado como DESARROLLO conserva el repo y el venv;
# el instalador los borra. Actualizarlo con: git pull + restart.
DEV_MARKER="/etc/stepad/development"
case "${1:-}" in
    --compare-versions|--help|-h) SELFTEST=1 ;;
    *) SELFTEST=0 ;;
esac
if [ "${SELFTEST}" -eq 0 ] && [ -e "${DEV_MARKER}" ] && [ "${STEPAD_ALLOW_INSTALL:-0}" != "1" ]; then
    echo "ERROR: ${DEV_MARKER} existe: este equipo está marcado como DESARROLLO." >&2
    echo "El instalador borra el repositorio (.git) y el venv." >&2
    echo "Actualizá con: git -C ~/stepad-nsp pull && sudo systemctl restart stepad-nsp" >&2
    echo "Para forzar igualmente (no recomendado): STEPAD_ALLOW_INSTALL=1" >&2
    exit 1
fi


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

# ---------------------------------------------------------------------------
# Rollback de actualización
# ---------------------------------------------------------------------------
ROLLBACK_DIR="${STEPAD_ROLLBACK_DIR:-/var/lib/stepad/rollback}"

rollback_point_for() {
    local wanted="${1:-}"
    if [ -n "${wanted}" ]; then
        ls -1t "${ROLLBACK_DIR}/${wanted}"-*.app.tar.gz 2>/dev/null | head -1
    else
        ls -1t "${ROLLBACK_DIR}"/*.app.tar.gz 2>/dev/null | head -1
    fi
}

do_rollback() {
    local wanted="${1:-}" app db version stem safety db_host db_name db_user
    local local_pg=0 health_url health_ok=0 i
    if [ ! -d "${ROLLBACK_DIR}" ]; then
        echo "ERROR: no hay puntos de retorno en ${ROLLBACK_DIR}."
        exit 1
    fi
    app="$(rollback_point_for "${wanted}")"
    if [ -z "${app}" ] || [ ! -f "${app}" ]; then
        echo "ERROR: no encontré un punto de retorno${wanted:+ para ${wanted}}."
        echo "Disponibles:"
        ls -1t "${ROLLBACK_DIR}"/*.app.tar.gz 2>/dev/null | while read -r f; do
            printf '  %s\n' "$(basename "${f%.app.tar.gz}")"
        done
        exit 1
    fi
    stem="${app%.app.tar.gz}"
    db="${stem}.db.sql.gz"
    version="$(cat "${stem}.version" 2>/dev/null || echo '?')"

    echo "==> Rollback a ${version}"
    echo "    Código: $(basename "${app}")"
    if [ -f "${db}" ]; then
        echo "    Base:   $(basename "${db}")"
    elif [ "${STEPAD_ROLLBACK_ALLOW_NO_DB:-0}" != "1" ]; then
        echo "ERROR: el punto no tiene volcado de base de datos."
        echo "Restaurar solo el código puede dejar esquema/datos incompatibles."
        echo "Si aun así querés continuar: STEPAD_ROLLBACK_ALLOW_NO_DB=1"
        exit 1
    fi

    echo "==> Deteniendo servicio"
    systemctl stop stepad-nsp 2>/dev/null || true

    safety="${ROLLBACK_DIR}/pre-rollback-$(date +%Y%m%d-%H%M%S).tar.gz"
    if [ -d "${APP_DIR}/backend" ]; then
        tar czf "${safety}" -C "${APP_DIR}" \
            --exclude=.venv --exclude=.git --exclude=node_modules \
            --exclude=__pycache__ --exclude=.pytest_cache . 2>/dev/null \
            && echo "    Estado actual guardado: $(basename "${safety}")"
    fi

    echo "==> Restaurando código ${version}"
    rm -rf "${APP_DIR}/backend" "${APP_DIR}/frontend" "${APP_DIR}/scripts" \
        "${APP_DIR}/docs" "${APP_DIR}/install.sh" "${APP_DIR}/install.py" \
        "${APP_DIR}/requirements.txt" "${APP_DIR}/VERSION" \
        "${APP_DIR}/alembic.ini" "${APP_DIR}/stepad-nsp.service" 2>/dev/null
    if ! tar xzf "${app}" -C "${APP_DIR}"; then
        echo "ERROR: no se pudo extraer el código; el servicio queda detenido."
        exit 1
    fi
    chown -R "${APP_USER}:${APP_USER}" "${APP_DIR}" 2>/dev/null || true
    cp -f "${stem}.version" /etc/stepad/version 2>/dev/null || true

    if [ -f "${db}" ]; then
        echo "==> Restaurando base de datos"
        if [ -r /etc/stepad/stepad.env ]; then
            set -a
            # shellcheck disable=SC1091
            . /etc/stepad/stepad.env
            set +a
        fi
        db_host="${DB_HOST:-127.0.0.1}"
        db_name="${DB_NAME:-stepad_nsp}"
        db_user="${DB_USER:-stepad_nsp}"
        case "${db_host}" in ""|localhost|127.0.0.1|::1) local_pg=1 ;; esac
        if [ "${local_pg}" = "1" ] && command -v runuser >/dev/null 2>&1 \
           && runuser -u postgres -- true >/dev/null 2>&1; then
            runuser -u postgres -- dropdb --if-exists "${db_name}" || true
            runuser -u postgres -- createdb -O "${db_user}" "${db_name}" || {
                echo "ERROR: no se pudo crear ${db_name}."
                exit 1
            }
            # Restore AS THE APP USER so every table is owned by it.
            if ! gunzip -c "${db}" | PGPASSWORD="${DB_PASSWORD:-}" psql \
                -h 127.0.0.1 -p "${DB_PORT:-5432}" -U "${db_user}" \
                -q -v ON_ERROR_STOP=1 -d "${db_name}" >/dev/null; then
                echo "ERROR: falló la restauración de la base. Servicio detenido."
                exit 1
            fi
        else
            export PGPASSWORD="${DB_PASSWORD:-}"
            psql -h "${db_host}" -p "${DB_PORT:-5432}" -U "${db_user}" -d postgres \
                -v ON_ERROR_STOP=1 -c "DROP DATABASE IF EXISTS \"${db_name}\";" || true
            psql -h "${db_host}" -p "${DB_PORT:-5432}" -U "${db_user}" -d postgres \
                -v ON_ERROR_STOP=1 -c "CREATE DATABASE \"${db_name}\";" || {
                echo "ERROR: no se pudo crear ${db_name}."
                exit 1
            }
            if ! gunzip -c "${db}" | PGPASSWORD="${DB_PASSWORD:-}" psql \
                -h "${db_host}" -p "${DB_PORT:-5432}" -U "${db_user}" \
                -q -v ON_ERROR_STOP=1 -d "${db_name}" >/dev/null; then
                echo "ERROR: falló la restauración de la base. Servicio detenido."
                exit 1
            fi
            unset PGPASSWORD
        fi
        echo "    Base restaurada."
    fi

    echo "==> Reiniciando servicio"
    systemctl restart stepad-nsp || true

    health_url="${STEPAD_HEALTH_URL:-https://127.0.0.1:8443/healthz}"
    for i in $(seq 1 90); do
        if systemctl is-active --quiet stepad-nsp \
           && curl -sk --max-time 3 "${health_url}" 2>/dev/null \
              | grep -q '"status":"ok"'; then
            health_ok=1
            break
        fi
        sleep 2
    done

    if [ "${health_ok}" = "1" ]; then
        echo "==> Rollback completado: ${version} activo y /healthz OK."
        exit 0
    fi

    echo "ERROR: el servicio no respondió /healthz tras 180 s."
    systemctl status stepad-nsp --no-pager -n 20 2>/dev/null || true
    echo "El punto de retorno se conserva en ${stem}."
    exit 1
}

case "${1:-}" in
    --rollback)
        do_rollback "${2:-}"
        ;;
    --rollback-list)
        ls -1t "${ROLLBACK_DIR}"/*.app.tar.gz 2>/dev/null | while read -r f; do
            printf '%s\n' "$(basename "${f%.app.tar.gz}")"
        done
        exit 0
        ;;
esac

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

    # La versión del paquete debe coincidir EXACTAMENTE con la versión
    # resuelta del release. Antes bastaba con que no fuera más vieja, así
    # que un CDN que servía 508 bajo la URL de 509 instalaba 508 sin avisar.
    if [ -n "${VERSION:-}" ] && [ -n "${pkg}" ] && [ "${pkg}" != "${VERSION}" ]; then
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

    if [ -n "${FIXED_URL}" ]; then
        # URL explícita: se reintenta EXACTAMENTE el mismo paquete (nunca
        # se cambia a "latest", que podría no ser lo que pidió el usuario).
        FIXED_BASE="${URL%%\?*}"
        download_installer "${FIXED_BASE}?$(date +%s%N)"
        SIG_URL="${FIXED_BASE}.sig"
    else
        # Re-resolver la versión en cada reintento: si el CDN ya propagó,
        # el siguiente intento baja el paquete correcto.
        VERSION="$(curl -fsSL "${BASE}/VERSION?$(date +%s)" | tr -d '\r\n' || true)"

        if [ -n "${VERSION}" ]; then
            download_installer "${BASE}/stepad-nsp-installer-${VERSION}.tar.gz?$(date +%s%N)"
            SIG_URL="${BASE}/stepad-nsp-installer-${VERSION}.tar.gz.sig"
        else
            download_installer "${BASE}/stepad-nsp-installer.tar.gz?$(date +%s%N)"
            SIG_URL="${BASE}/stepad-nsp-installer.tar.gz.sig"
        fi
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
  # Cap por cantidad: el limite de 90 dias no alcanza (habia miles).
  ls -1t "${BK_DIR}"/stepad.env.* 2>/dev/null | tail -n +201 | xargs -r rm -f 2>/dev/null
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

echo "==> Guardando punto de retorno (rollback)"
if tar -xOf /tmp/stepad-nsp-installer.tar.gz \
    stepad-nsp/scripts/rollback-point.sh > /tmp/stepad-rollback-point.sh 2>/dev/null; then
    STEPAD_APP_DIR="/home/${APP_USER}/stepad-nsp" \
        bash /tmp/stepad-rollback-point.sh || true
    rm -f /tmp/stepad-rollback-point.sh
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
STEPAD_SKIP_ROLLBACK_POINT=1 bash "/home/${APP_USER}/stepad-nsp/install.sh"
