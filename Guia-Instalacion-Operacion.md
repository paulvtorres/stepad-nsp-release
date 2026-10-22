# STEPAD NSP — Guía de Instalación y Operación

Documento de referencia para la instalación en el cliente, el monitoreo
remoto y la operación/administración de STEPAD NSP, cubriendo los
requisitos de gobernanza (SLA, revisiones, control de cambios, etc.).

---

## 1. Requisitos de hardware

- **CPU:** 2+ núcleos (x86-64). Recomendado 4 para IPS Suricata.
- **RAM:** mínimo 4 GB (Suricata con ~52k reglas usa ~600 MB).
- **Disco:** 40 GB+ (logs 1 año, respaldos cifrados).
- **Red:** 2 interfaces Ethernet (LAN + WAN).
- **OS:** Debian 13 (trixie), instalación limpia.

> Referencia medida: i5-2450M (2011), 5.7 GB RAM → Suricata inline a
> ~26% CPU de base. Para enlaces >300 Mbps considerar hardware superior.

---

## 2. Instalación (en el cliente)

```bash
# 1) Instalar Debian 13 mínima (root + red WAN funcionando).

# 2) Descargar e instalar la NSP (con usuario root o sudo):
curl -fsSL -o get-stepad.sh https://github.com/paulvtorres/stepad-nsp-release/.../get-stepad.sh
sudo bash get-stepad.sh

# 3) Durante el instalador (checkbox):
#    - Activar Tailscale (recomendado para monitoreo remoto)
#    - VPN: se desactiva por defecto en el primer arranque
```

Al terminar:

- Se crea el usuario **admin** con **contraseña aleatoria** (en
  `/etc/stepad/stepad-admin-credentials.txt`).
- La web queda en `https://<ip>:8443` (certificado autofirmado).
- **Primer arranque:** configurar red LAN, contraseña de admin,
  habilitar **MFA** y revisar el panel.

---

## 3. Configuración inicial recomendada (línea base)

Tras el primer login, aplicar esta línea base:

| Área | Acción |
|---|---|
| Seguridad → Hardening | Activar **Deny-all por defecto** |
| Seguridad → Hardening | Definir **horario de acceso administrativo** |
| Seguridad → Categorías | Revisar categorías activas (adultos/apuestas/juegos/malware por defecto) |
| Grupos | Crear grupos por área y asignar **perfil de navegación** |
| Ajustes → Notificaciones | Configurar **SMTP** (correo para alertas/respaldos) |
| Ajustes → SIEM | Configurar reenvío **syslog** a su SOC/SIEM; responsable de revisión de logs |
| Ajustes → Copias | Activar copias automáticas + **enviar cifrado por email** |
| Usuarios | Crear cuentas **nominativas** (una por administrador), sin compartidas |

---

## 4. Monitoreo remoto

### 4.1 Tailscale (recomendado — sin tocar el router del cliente)
1. El gateway ya está en el tailnet (autenticado en la instalación).
2. En tu equipo/celular: instalar Tailscale e iniciar sesión con la
   **misma cuenta**.
3. Entrar al panel desde cualquier red:
   ```
   https://<ip-tailscale-del-gateway>:8443
   ```
> No requiere reenvío de puertos ni DDNS; funciona tras CGNAT.

### 4.2 VPN WireGuard (clásico)
- Requiere en el router del cliente: reenviar **UDP 51820** al gateway
  + **DDNS** si la IP pública es dinámica.
- Generar un peer por administrador (claves individuales) desde la
  página VPN.
- Entrar al panel en `https://10.200.0.1:8443`.

### 4.3 Escritorio remoto de usuarios (RustDesk)
- Pantalla **Seguridad → Acceso remoto**.
- Activa el servidor OSS en el NSP y, para teletrabajo, marca
  **Exponer a Internet** (TCP 21115–21117, UDP 21116).
- Opcional: host DNS público si la WAN cambia (DDNS).
- En cada PC (oficina y remoto): cliente [RustDesk](https://rustdesk.com/),
  ID/Relay = host del panel, Key = clave pública del panel.
- No sustituye la VPN de administración del NSP.

### 4.4 Notificaciones por correo (monitoreo pasivo)
- Alertas críticas del **IPS** (Suricata) y avisos del sistema.
- **Respaldo cifrado** por email (fuera del sitio).
- Reportes periódicos (diario/semanal/mensual).

---

## 5. Políticas de gobernanza (operación)

Estas políticas se administran por **proceso** (no son funciones del
firewall) y deben quedar documentadas/contratadas:

### 5.1 SLA de corrección por criticidad
| Criticidad | Plazo de corrección |
|---|---|
| Crítica | 7 días |
| Alta | 30 días |
| Media | 60 días |
| Baja | Según planificación |

> Uso: ante una vulnerabilidad detectada por el IPS/escaneo, registrar
> la fecha y aplicar el parche dentro del plazo de su severidad. La NSP
> permite **parcheo virtual** (bloqueo por firmas) mientras se aplica el
> parche real.

### 5.2 Revisiones periódicas (dentro de la NSP)
| Revisión | Frecuencia | Dónde |
|---|---|---|
| Reglas del firewall | 6 meses | Seguridad → Hardening → "Marcar revisión" |
| Accesos administrativos | 6 meses | Seguridad → Hardening → "Marcar revisión" |
| Logs (responsable designado) | 7 días (ideal diario) | Ajustes → SIEM → "Marcar revisión" |
| Actualizaciones | Al publicarse | Ajustes → Actualizaciones (revisar cambios pendientes antes de aplicar) |

### 5.3 Control de cambios formal
- Todo cambio queda **auditado** (Auditoría: quién/cuándo/qué).
- Antes de aplicar: capturar una **revisión de configuración** (para
  rollback) y, si aplica, revisar los **cambios pendientes** en
  Actualizaciones.
- **Evaluación/aprobación:** proceso del cliente (documentar en el
  control de cambios corporativo); la NSP deja la trazabilidad.

### 5.4 Acceso remoto
- **Autorización previa:** todo acceso remoto debe solicitarse,
  justificarse y documentarse antes de habilitarse.
- **Mínimo necesario:** credenciales/peers individuales con alcance
  limitado.
- **Horario:** usar la ventana de acceso administrativo de la NSP.
- **Revocación:** al desvincular un colaborador o terminar un contrato
  de proveedor → eliminar su usuario y su peer WireGuard de inmediato.

### 5.5 Respaldo y restauración
- Copias **automáticas diarias** + **cifradas (AES-256)** + **envío por
  email** (fuera del sitio).
- **Clave de descifrado** (`STEPAD_BACKUP_KEY` en
  `/etc/stepad/stepad.env`): guardarla en un gestor de contraseñas o
  caja de seguridad del cliente — sin ella no se pueden descifrar.
- **Prueba de restauración (con evidencia):** al menos 1 vez al año,
  restaurar en un equipo de prueba el respaldo y documentar:
  fecha, quien lo hizo, resultado, y copia del registro (captura).
- **Continuidad:** al no haber HA, restaurar desde el respaldo cifrado
  en el equipo de respaldo es el procedimiento de recuperación.

### 5.6 Escaneo de vulnerabilidades y pentest
- **Escaneo periódico:** ejecutar cada mes una herramienta externa
  (ej. OpenVAS/Greenbone en una VM aparte, o un escáner comercial)
  contra el perímetro; registrar resultados y plan de remediación.
- **Pentest anual:** contratar un tercero para pruebas de penetración
  internas y externas; documentar hallazgos y remediación.

### 5.7 Cuentas y privilegios
- **Nominativas:** prohibidas las cuentas compartidas; una por persona.
- **Mínimo privilegio:** solo administradores con rol ADMIN; el resto
  con rol OPERATOR (acceso de lectura/operación).
- **Revisión de accesos** cada 6 meses (la NSP lo recuerda).
- **Segregación de funciones:** idealmente el auditor de logs no es el
  mismo que ejecuta cambios (proceso del cliente).

---

## 6. Actualización

- La NSP se actualiza desde **Ajustes → Actualizaciones**: muestra los
  **cambios pendientes** (commits) para revisarlos antes de aplicar.
- **Ambiente controlado:** validar primero en un equipo de prueba
  (staging) y luego aplicar en producción.
- La actualización hace pull, actualiza dependencias, reconstruye el
  frontend y reinicia el servicio.

---

## 7. Seguridad de la plataforma (resumen de lo incluido)

- Contraseñas robustas + expiración 90 días + MFA obligatoria.
- Bloqueo por intentos fallidos (3 → 30 min) y timeout de 15 min.
- Deny-all por defecto (sin acceso entrante desde Internet salvo
  retorno establecido).
- IPS Suricata con firmas actualizadas a diario + parcheo virtual.
- Filtrado web por categorías + dominios + feed de malware/phishing.
- Perfiles de navegación por grupo (área/rol).
- VPN WireGuard + acceso remoto por Tailscale.
- Respaldo cifrado AES-256 + retención 1 año + copia fuera del sitio.
- Logs: syslog a SIEM, protección (permisos/rotación), responsable de
  revisión.
- Revisiones periódicas recordadas por la NSP (firewall, accesos, logs).
