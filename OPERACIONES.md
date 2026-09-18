# STEPAD NSP — Guia de Operaciones y Recuperacion

## Arquitectura General

```
┌─────────────────────────────────────────────────────┐
│                    USUARIOS                         │
│              (LAN / WiFi / VPN)                     │
└──────────────────────┬──────────────────────────────┘
                       │ DHCP + DNS + Firewall
┌──────────────────────▼──────────────────────────────┐
│                  NSP (Debian)                       │
│                                                     │
│  ┌─────────┐  ┌──────────┐  ┌───────────────────┐  │
│  │ Backend │  │ Frontend │  │    Servicios      │  │
│  │ FastAPI │  │ React/Vite│  │                   │  │
│  │ :8443   │  │ built-in │  │ PostgreSQL :5432  │  │
│  └────┬────┘  └──────────┘  │ dnsmasq :53/:67   │  │
│       │                     │ pdns-recursor :53  │  │
│       │                     │ suricata (NFQUEUE) │  │
│       │                     │ nftables (kernel)  │  │
│       │                     └───────────────────┘  │
│       │                                            │
│  ┌────▼────────────────────────────────────────┐   │
│  │          nftables (firewall del kernel)      │   │
│  │  harden-forward / harden-input / attack-block│   │
│  └─────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────┘
```

## Estructura del Codigo

```
/home/paulan/stepad-nsp/
├── backend/
│   ├── main.py                    # Punto de entrada
│   ├── core/
│   │   ├── bootstrap.py           # Registra e inicia componentes
│   │   ├── config/settings.py     # Variables de entorno y config
│   │   ├── config/paths.py        # Rutas de archivos criticos
│   │   ├── database/
│   │   │   ├── connection.py      # Engine SQLAlchemy (pool)
│   │   │   └── schema_migrations.py  # Migraciones Alembic
│   │   ├── health/
│   │   │   └── boot_health_check.py  # Auto-diagnostico arranque
│   │   ├── lifecycle/             # Ciclo de vida de componentes
│   │   └── components/            # Componentes del sistema
│   ├── api/
│   │   ├── components/api_component.py  # uvicorn + FastAPI
│   │   └── v1/routes/            # Endpoints REST
│   ├── firewall/
│   │   ├── services/
│   │   │   ├── firewall_hardening_service.py  # Deny-all + WAN edge
│   │   │   └── wan_edge_service.py  # Rate-limit SSH/8443
│   │   └── adapters/linux/        # nftables provider
│   ├── ips/
│   │   ├── services/
│   │   │   ├── attack_response_service.py  # Bloqueo IPs atacantes
│   │   │   ├── geoip_service.py   # Geolocalizacion local
│   │   │   ├── suricata_alert_ingest.py  # Ingesta de alertas IPS
│   │   │   └── threat_response_service.py  # Config de proteccion
│   │   └── models/
│   ├── dhcp/                      # Servidor DHCP
│   ├── dns/                       # DNS (pdns-recursor + dnsmasq)
│   ├── vpn/                       # WireGuard VPN
│   └── migrations/versions/       # Migraciones Alembic
├── frontend/
│   ├── src/
│   │   ├── pages/                 # Paginas de la UI
│   │   │   ├── Dashboard/         # Panel principal
│   │   │   ├── Protection/        # Firewall + IPS
│   │   │   ├── ExternalAttacks/   # Ataques externos
│   │   │   ├── Alerts/            # Alertas del sistema
│   │   │   └── ...
│   │   ├── services/api.js        # Clientes API
│   │   └── constants/navigation.js  # Menu de navegacion
│   └── dist/                      # Frontend compilado
├── install.sh                     # Instalador/actualizador
├── install.py                     # Setup inicial (admin, DB)
├── VERSION                        # Version actual
└── alembic.ini                    # Config de Alembic
```

## Archivos Criticos del Sistema

| Archivo | Propiedad | Que pasa si se borra/corrrompe |
|---------|-----------|-------------------------------|
| `/etc/stepad/stepad.env` | root:root 0600 | NSP no arranca (faltan secrets) |
| `/etc/stepad/dns/dnsmasq.conf` | root:root | DHCP y DNS local no funcionan |
| `/etc/stepad/dns/group-dns/*/recursor.yml` | root:root | DNS filtering no funciona |
| `/etc/systemd/system/stepad-nsp.service` | root:root | systemctl no encuentra el servicio |
| `/home/paulan/stepad-nsp/VERSION` | paulan | Check de actualizaciones falla |

## Base de Datos

- **PostgreSQL** en `127.0.0.1:5432`
- **Usuario:** `stepad_app`
- **Base:** `stepad_nsp`
- **Password:** en `/etc/stepad/stepad.env` (DB_PASSWORD)
- **Migraciones:** Alembic en `backend/migrations/versions/`
- **Version actual:** 0032

### Conectar a la DB
```bash
# Como root (lee password de stepad.env)
echo admin | sudo -S -u postgres psql -d stepad_nsp

# Como stepad_app
PGPASSWORD=$(grep DB_PASSWORD /etc/stepad/stepad.env | cut -d= -f2) \
  psql -h 127.0.0.1 -U stepad_app -d stepad_nsp
```

### Verificar schema
```sql
SELECT version_num FROM alembic_version;  -- Debe decir 0032
SELECT count(*) FROM users;               -- Debe ser >= 1
SELECT count(*) FROM alerts;              -- Alertas del sistema
```

## Firewall (nftables)

### Cadenas principales
- **harden-forward**: tráfico entre zonas (LAN↔WAN)
- **harden-input**: tráfico hacia el NSP
- **attack-block**: drop de IPs atacantes
- **c2-block**: drop de C2 conocidos

### Verificar reglas
```bash
sudo nft list ruleset
sudo nft list chain inet stepad harden-forward
sudo nft list set inet stepad auto_attack_v4
```

### Re-aplicar hardening
Desde el panel: Protección → Firewall → Aplicar hardening
O manualmente: `sudo nft -f /etc/stepad/nftables.conf`

## Servicios Clave

| Servicio | Comando | Que hace |
|----------|---------|----------|
| stepad-nsp | `systemctl restart stepad-nsp` | Backend + Frontend |
| postgresql | `systemctl status postgresql` | Base de datos |
| suricata | `systemctl start suricata` | IDS/IPS |
| dnsmasq | Lo maneja el NSP | DHCP + DNS local |
| pdns-recursor | `systemctl status pdns-recursor` | DNS filtering |

## Problemas Comunes y Soluciones

### 1. NSP no arranca
```bash
# Ver logs
sudo journalctl -u stepad-nsp.service -n 50

# Causas comunes:
# - PostgreSQL caido: sudo systemctl start postgresql
# - stepad.env corrupto: restaurar desde /etc/stepad/backup/
# - Migracion fallida: el fix de schema_migrations.py reintenta
```

### 2. Puerto 8443 no responde
```bash
# Verificar que el servicio esta activo
systemctl is-active stepad-nsp.service

# Verificar que escucha
ss -tlnp | grep 8443

# Si no escucha, reiniciar
sudo systemctl restart stepad-nsp.service
```

### 3. Usuarios sin internet
```bash
# Verificar dnsmasq (DHCP + DNS)
pgrep -a dnsmasq
ss -ulnp | grep ":67"

# Verificar nftables
sudo nft list chain inet stepad harden-forward

# Verificar que el servicio NSP esta corriendo
systemctl is-active stepad-nsp.service
```

### 4. Suricata no corriendo
```bash
sudo systemctl start suricata
sudo systemctl status suricata

# Verificar config
suricata -T -c /etc/suricata/suricata.yaml
```

### 5. Corte de energia — recuperacion
```bash
# 1. Verificar filesystem
sudo fsck -n /dev/sda1

# 2. Verificar PostgreSQL
sudo systemctl status postgresql
sudo -u postgres pg_isready

# 3. Verificar schema
PGPASSWORD=... psql -h 127.0.0.1 -U stepad_app -d stepad_nsp \
  -c "SELECT version_num FROM alembic_version"

# 4. Reiniciar NSP
sudo systemctl restart stepad-nsp.service

# 5. Verificar health check
grep "Health check" /home/paulan/stepad-nsp/logs/stepad.log | tail -5
```

### 6. Archivo stepad.env corrupto
```bash
# Restaurar desde backup
sudo cp /etc/stepad/backup/stepad.env /etc/stepad/stepad.env

# O recrear desde cero (genera nuevos secrets)
cd /home/paulan/stepad-nsp
sudo .venv/bin/python3 install.py
```

### 7. Base de datos corrupta
```bash
# Restaurar desde backup
sudo -u postgres dropdb stepad_nsp
sudo -u postgres createdb stepad_nsp
PGPASSWORD=... psql -h 127.0.0.1 -U stepad_app -d stepad_nsp \
  < /backup/stepad_nsp.sql

# O reiniciar para que Alembic re-aplique
sudo systemctl restart stepad-nsp.service
```

## Actualizar el NSP

### Desde la web (recomendado)
El panel muestra "Actualizar" cuando hay nueva version.

### Manual
```bash
curl -fsSL https://raw.githubusercontent.com/paulvtorres/stepad-nsp-release/main/get-stepad.sh | sudo bash
```

### Verificar version
```bash
cat /etc/stepad/version
cat /home/paulan/stepad-nsp/VERSION
```

## Monitoreo

### Alertas del sistema
El panel web pestaña "Alertas" muestra:
- **CRITICAL**: problemas que requieren accion inmediata
- **WARNING**: problemas que deben revisarse
- **INFO**: eventos informativos

### Health check de arranque
Al iniciar, el NSP verifica:
- PostgreSQL responde
- Schema de DB correcto
- Tablas criticas existen
- Archivos de config validos
- Cadenas nftables aplicadas

### Logs
```bash
# Service logs
sudo journalctl -u stepad-nsp.service -f

# App logs
tail -f /home/paulan/stepad-nsp/logs/stepad.log

# Suricata
tail -f /var/log/suricata/eve.json
```

## Red

### Interfaces
- **enp3s0**: WAN (Internet)
- **enp37s0**: LAN (192.168.100.x)
- **tailscale0**: VPN Tailscale (100.x.x.x)
- **wg0**: WireGuard VPN (10.200.0.x)

### DNS
- **pdns-recursor**: DNS filtering (reglas RPZ)
- **dnsmasq**: DNS local + DHCP (manejado por NSP)

## Backup

### Configuración
Desde el panel: Respaldos → Configurar

### Restaurar
```bash
# Con restic
restic -r /mnt/backup/stepad restore latest --target /tmp/restore
```

## Contacto y Soporte

- **Repo:** https://github.com/paulvtorres/stepad-nsp
- **Release:** https://github.com/paulvtorres/stepad-nsp-release
- **Docs:** /home/paulan/stepad-nsp/docs/
