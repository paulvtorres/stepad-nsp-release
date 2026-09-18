# Incidentes 2026-08-24 — Lentitud, YouTube/WhatsApp, Navegación en vivo

Host de producción: `100.97.46.90` (panel `https://100.97.46.90:8443/`)  
Fuente de verdad / desarrollo: `192.168.100.194` (este repo se aplica aquí primero).  
LAN prod: `enp3s0` / `192.168.1.1` · WAN: `enp2s0` / `192.168.100.11`  
No confundir con el box Tailscale `100.92.205.99`.

Objetivo de este documento: lista de errores reales encontrados, causa, impacto y qué falta cerrar con análisis previo (no improvisar en producción).

---

## Resumen ejecutivo

| # | Problema | Causa raíz | Severidad | Estado |
|---|----------|------------|-----------|--------|
| 1 | Red lenta / CPU alta | Suricata IPS con ~309k reglas SNI | Crítica | Mitigado (tope SNI + priorización); diseño IPS vs DNS pendiente |
| 2 | Navegación en vivo vacía | Offset SNI > tamaño de `eve.json` tras rotar log | Alta | Mitigado (reset + código); vigilar |
| 3 | YouTube/WhatsApp “bloqueados” sin grupo | DNS del cliente apuntaba a alias de grupo borrado | Crítica | Mitigado en código: al borrar → equipos a default + sync DNS/DHCP |
| 4 | Alias DNS de grupos huérfanos | `delete_group` no limpiaba IP/recursor/DNAT | Alta | Mitigado (cleanup en sync + move a default) |
| 5 | Bloqueo IP YouTube en Invitados | `EXTRA_BLOCKED_IPS` a cualquier blocklist | Alta | Corregido; GGC ampliado a `.72/24`+`.73/24` |
| 6 | Conflicto DHCP vs alias DNS | Pool solapaba IPs de grupos | Alta | Cerrado en **194**: subrango `.10–.19`, pool `.20+`, `dns_alias_ip` persistida |
| 7 | FINANCIERO en `.14` vs DNS alias `.14` | Misma IP: PC + alias | Alta | FINANCIERO → `.151`; alias restaurado en prod |
| 8 | Suricata IPS corta flujos | `exception-policy: auto` | Media | Versionado en `scripts/configure_suricata.py` (`ignore` + midstream) |
| 9 | Generador SNI prioriza malware alfabético | Tope 250 sin priorizar YouTube/DoH | Media | **Hecho** (`SNI_PRIORITY_MARKERS`) |
| 10 | Confusión de host (`.99` vs `.90` / `.194`) | Diagnóstico en máquina equivocada | Proceso | Anotado: verdad = `.194` |

---

## 1. Suricata saturado por reglas SNI (~309 000)

### Síntomas
- CPU Suricata ~237 %, RSS ~2 GB.
- Alerta RESOURCE_CPU ~93 %.
- LAN lenta / sensación de “toda la red lenta”.

### Causa
`SniBlockService` generaba **1 regla TLS + 1 QUIC por cada (IP de equipo × dominio del blocklist)**.  
Con categorías/malware globales → cientos de miles de PCRE en NFQUEUE.

### Mitigación hecha
- Archivo enorme respaldado; reglas reducidas.
- Generador: agregar IPs por dominio + `MAX_SNI_DOMAINS = 250` + `MAX_IPS_PER_SNI_RULE = 64`.
- En un momento se vació `stepad-sni.rules` para aliviar.

### Diseño definitivo (194)
- [x] SNI **solo** catálogo antievasión (`ips_evasion.py`), no blocklist DNS.
- [ ] Evaluar IDS (AF_PACKET) vs IPS (NFQUEUE) para reglas ET (~68k).
- [ ] Commit + despliegue a prod `.90`.

### Archivos
- `backend/groups/constants/ips_evasion.py` — catálogo DoH/YouTube/redes
- `backend/groups/services/sni_block_service.py`
- `/var/lib/suricata/rules/stepad-sni.rules`

---

## 2. Navegación en vivo vacía (ingesta SNI)

### Síntomas
- UI “Navegación en vivo” sin datos.
- DNS sí registraba consultas; `sni_logs` congelado desde ~23/08 05:28.

### Causa
`/etc/stepad/ips/sni_offset` quedó en ~3 GB con `eve.json` ~220 MB tras rotación/truncate.  
El ingest hacía `if size <= offset: return` y no leía nada.

### Mitigación hecha
- Reset del offset + reinicio backend.
- Código: si `size < offset`, reiniciar offset al final del fichero.
- Mismo patrón en alert ingest (`eve_offset`).

### Pendiente
- [ ] Asegurar que el fix está en el repo/`main` y en todos los appliances.
- [ ] Si se apaga Suricata para depurar, avisar: **sin Suricata no hay navegación en vivo**.
- [ ] Revisar rotación de `eve.json` (logrotate) y que el offset se resetee siempre.

### Archivos
- `backend/dns/logging/services/sni_log_ingest.py`
- `backend/ips/services/suricata_alert_ingest.py`
- `/etc/stepad/ips/sni_offset`

---

## 3. Cliente con DNS de grupo borrado (caso TQB-SVR `.73`)

### Síntomas
```
nslookup youtube.com
Servidor:  UnKnown
Address:  192.168.1.14
DNS request timed out.
```
- No YouTube, no WhatsApp, “parece bloqueo de grupo” aunque el grupo ya no exista.
- Captura en LAN: la PC **ni siquiera** abría HTTPS a Google; solo conexiones viejas / AnyDesk.

### Causa
1. El equipo recibió por DHCP `option 6 = 192.168.1.14` (alias DNS del grupo antiguo).
2. Al borrar grupos se quitó el alias del gateway.
3. Además **FINANCIERO** tenía lease/reserva en `.14` → ARP hacia un Windows sin DNS.
4. Resultado: timeout de DNS en el cliente.

### Mitigación hecha
- Restaurar `.14` (y `.12`/`.13`) en el gateway + listen en PowerDNS.
- Mover FINANCIERO a reserva `.151`.
- Override DHCP para MAC de TQB-SVR → DNS `192.168.1.1` (`/etc/stepad/dns/host_dns_fix.conf`).
- GARP de `.14`.

### Mitigación estructural (código en 194)
- Al borrar grupo: equipos → grupo default, sync DNS + SNI, `DhcpService.apply_config()`.
- Subrango de alias excluido del pool; reservas no pisan `dns_alias_ip`.
- IP de alias persistida; no se reasigna al borrar otros grupos.

### Pendiente
- [ ] Desplegar a prod `.90`.
- [ ] En clientes con lease viejo: `ipconfig /renew` + `flushdns` (o esperar renew).
- [ ] Decidir si alias legacy (`.12/.13/.14` sin grupo) se limpian en un one-shot de upgrade.

### Evidencia
- `nslookup` del usuario apuntando a `192.168.1.14`.
- `ip neigh`: `.14` → MAC FINANCIERO `2c:fd:a1:bf:38:55` (STALE) antes del fix.

---

## 4. Grupos borrados dejan alias / recursors / DNAT

### Síntomas
- Tras borrar grupos en UI, seguían IPs `.10/.12/.13/.14` y `pdns_recursor` de dirs `group-dns/3`, `/4`, `/5`.
- `groups_dns.conf` seguía con tags de grupos muertos hasta un sync forzado.

### Causa
`GroupService.delete_group` no llamaba a `group_dns_service.sync_all`.  
`_sync_all` no limpiaba huérfanos (solo recreaba los activos).

### Mitigación hecha
- Cleanup de dirs/recursors/alias en sync.
- `delete_group` dispara sync DNS + SNI.

### Pendiente
- [x] `delete_group` mueve equipos a default + sync + DHCP apply (194).
- [ ] Test manual: crear grupo → borrar → IP alias desaparece y no queda `pdns` huérfano.
- [ ] Decidir política: ¿el grupo default “Invitados” debe tener alias `.10` o basta `.1`?
- [ ] Commit + despliegue a `.90`.

### Archivos
- `backend/groups/services/group_dns_service.py`
- `backend/groups/services/group_service.py`

---

## 5. Bloqueo por IP (GGC YouTube) sin bloquear YouTube en el grupo

### Síntomas
- Equipo pasado a Invitados (sin regla YouTube) seguía sin video.
- DNS resolvía YouTube; nft dropeaba CDN del ISP.

### Causa
`_blocked_ips()` devolvía siempre `EXTRA_BLOCKED_IPS` si el grupo tenía **cualquier** blocklist (malware permanente, etc.).

### Mitigación hecha
- Solo aplicar `EXTRA_BLOCKED_IPS` si el blocklist incluye dominios YouTube/ecosistema.
- Se quitaron reglas `stepad-ipblock-*` de grupo 1 en prod.

### Pendiente
- [x] GGC ampliado a `45.162.72.0/24` + `45.162.73.0/24` (+ `162.43.190.0/24`).
- [ ] Commit + despliegue a `.90`.

### Archivos
- `backend/groups/services/sni_block_service.py` (`EXTRA_BLOCKED_IPS`, `_blocked_ips`)

---

## 6. Pool DHCP solapa alias DNS de grupos

### Norma (implementada en código)

Al definir el segmento / pool DHCP:

| Concepto | Valor |
|----------|--------|
| Subrango de grupos (config) | Default **10** IPs (`.10`–`.19` si gateway `.1`) |
| Claves YAML | `group_ip_start` / `group_ip_end` (o `group_ip_count`) |
| Persistencia | `device_groups.dns_alias_ip` (única, no se reasigna al borrar) |
| Mínimo para equipos en el pool | **20** |
| Total útil mínimo del segmento | **~30** hosts (10 grupos + 20 equipos) |

- El DHCP **excluye siempre** ese subrango (aunque el admin no lo liste).
- Al cambiar segmento LAN, el pool de equipos empieza justo después del subrango.
- No se escriben `dhcp-host` (reservas) sobre IPs del subrango de grupos.
- Si no hay IP libre en el subrango, **`create_group` responde 400**.
- Borrar un grupo **libera** su IP; los demás **conservan** la suya.

Código: `backend/groups/constants/group_dns_ip_reserve.py`

### Síntomas / riesgo (antes del fix)
- Alias: `.10`, `.12`, `.13`, `.14`…
- Pool prod antiguo: `192.168.1.2`–`192.168.1.150`, `excluded_ips: []`
- Conflicto real: FINANCIERO en `.14` + alias DNS `.14`

### Estado en 194 (fuente de verdad)
- [x] `group_ip_start/end` `.10–.19`, `pool_start` `.20`, exclusiones aplicadas, dnsmasq regenerado.
- [x] Migración `0013` + backfill `dns_alias_ip` (Invitados `.10`, Contabilidad `.11`).
- [x] Auditoría: 0 equipos en subrango de grupos.

### Pendiente en prod `.90`
- [ ] Aplicar mismo config + migración + regenerar dnsmasq (sin romper `port=0`).
- [ ] Auditoría de reservas dentro del subrango de grupos.

---

## 7. Suricata IPS y `stream_error` / exception-policy

### Síntomas
- Contadores: `ips.blocked` por `stream_error` / antes `flow_drop`.
- Flujos raros (p. ej. GGC puerto `22117`) degradados con IPS inline.

### Mitigación en prod (no necesariamente en git)
- `exception-policy: ignore`
- `stream.midstream: true`
- Backup: `/etc/suricata/suricata.yaml.BAK-20260824-yt`

### Pendiente
- [x] `exception-policy: ignore` + `stream.midstream: true` en `scripts/configure_suricata.py` (aplicado en 194).
- [ ] Decidir política oficial IPS vs IDS.
- [ ] Desplegar/reaplicar script en prod `.90`.
- [ ] Si se apaga Suricata para depurar: documentar impacto en navegación en vivo.

---

## 8. Proceso / operación

### Confusión `.99` vs `.90`
- Parte del diagnóstico de LAN USB / DHCP se hizo en `100.92.205.99`.
- Producción real: `100.97.46.90` con NICs PCI `enp2s0`/`enp3s0`.

### Checklist antes de tocar prod
1. Confirmar IP Tailscale / panel.
2. Confirmar `wan_interface` / `lan_interface` en `config.yaml`.
3. No asumir que el workspace local = el host en el que el usuario navega.

### Dependencias cruzadas
| Acción | Efecto colateral |
|--------|------------------|
| Apagar Suricata | Navegación en vivo vacía |
| Borrar grupos sin sync | Alias DNS huérfanos en clientes |
| Vaciar SNI rules | Menos CPU; menos bloqueo SNI (DNS/RPZ sigue) |
| Reinicios encadenados Suricata | Picos CPU (cooldown 90s ya existe) |

---

## Orden sugerido de resolución (con análisis previo)

Hecho en **194** (fuente de verdad): §3/§4 borrado de grupos, §5 GGC, §6 DHCP+`dns_alias_ip`, §8 Suricata yaml, §9 priorización SNI.

Siguiente:
1. **Commit** de este workspace y tag/version.
2. **Despliegue a prod `.90`** (migración 0013 + config DHCP + `configure_suricata.py` + restart).
3. **Política Suricata** — IPS ligero vs IDS (diseño; no improvisar).
4. **SNI solo DoH/YouTube** — reducir aún más el rol de Suricata frente a DNS/RPZ.

---

## Cambios locales relevantes (workspace) — verificar si ya están en `main`

- `backend/groups/services/sni_block_service.py` — tope SNI + `_blocked_ips` condicional  
- `backend/groups/services/group_dns_service.py` — cleanup huérfanos  
- `backend/groups/services/group_service.py` — sync al borrar grupo  
- `backend/dns/logging/services/sni_log_ingest.py` — reset offset si log rota  
- `backend/ips/services/suricata_alert_ingest.py` — igual para alertas  
- Frontend datetime / TopBar / Devices / Notifications (hilo paralelo; no son la causa de YouTube)

---

## Notas rápidas de verificación

```bash
# ¿DNS del cliente apunta a alias vivo?
# En Windows: nslookup youtube.com  → Server Address debe ser .1 / .10 / alias con pdns UP

# Alias en gateway
ip -4 addr show enp3s0

# Listeners DNS
ss -ulnp | grep ':53'

# Suricata / NFQUEUE
systemctl is-active suricata
nft list chain inet stepad forward | grep queue

# Ingesta live nav
# sni_logs últimos minutos + /etc/stepad/ips/sni_offset vs size eve.json
```

---

*Documento generado a partir del incidente del 24/08/2026. Actualizar estado al cerrar cada ítem.*
