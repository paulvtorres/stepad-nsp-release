# Arquitectura de protección STEPAD NSP

Fuente de verdad: **192.168.100.194** → versionar → desplegar a **100.97.46.90**.

## Capas (orden de aplicación)

```
Cliente LAN
    │
    ▼
┌─────────────────────────────────────┐
│ 1. DNS forzado (nftables por MAC)   │  → redirige :53 al recursor del grupo
└─────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────┐
│ 2. DNS/RPZ por grupo (PowerDNS)     │  → blocklist COMPLETO (malware, cats)
└─────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────┐
│ 3. Suricata SNI (catálogo fijo)     │  → DoH, YouTube, redes (antievasión)
└─────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────┐
│ 4. nft GGC (solo si bloquea YT)     │  → caché de video del ISP
└─────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────┐
│ 5. Suricata ET (~68k firmas IPS)    │  → alertas/drop de exploits
└─────────────────────────────────────┘
```

## Reglas de diseño

| Recurso | Grupos | Equipos (DHCP) |
|---------|--------|----------------|
| Subrango LAN | `group_ip_start` … `group_ip_end` (UI Segmento) | `pool_start` … `pool_end` |
| Persistencia | `device_groups.dns_alias_ip` | reservas DHCP normales |

- **No mezclar** IPs de alias DNS con pool de equipos.
- **No generar** reglas Suricata desde el blocklist DNS (evita combinatoria IP×dominio).
- SNI solo desde `backend/groups/constants/ips_evasion.py`.
- Borrar grupo → equipos a Invitados + sync DNS/DHCP + liberar alias.

## Archivos clave

| Componente | Ruta |
|------------|------|
| Subrango grupos | `backend/groups/constants/group_dns_ip_reserve.py` |
| Catálogo antievasión IPS | `backend/groups/constants/ips_evasion.py` |
| DNS/RPZ por grupo | `backend/groups/services/group_dns_service.py` |
| SNI + GGC nft | `backend/groups/services/sni_block_service.py` |
| Suricata yaml | `scripts/configure_suricata.py` |
| UI segmento | `frontend/.../Interfaces/Interfaces.jsx` |

## Alertas

- **DNS seguridad**: consultas a malware/phishing bloqueadas (RPZ).
- **Suricata IPS**: `eve.json` → alertas de firmas ET (exploits, etc.).
- **Navegación en vivo**: eventos TLS SNI en `eve.json`.

Apagar Suricata no desactiva el bloqueo DNS; sí afecta alertas IPS y navegación en vivo.

## Borde WAN (ataques externos)

Con **deny-all** activo (`FirewallHardeningService` + `WanEdgeService`):

| Protección | Efecto |
|------------|--------|
| Policy drop desde WAN | Internet no entra a la LAN salvo allowlist |
| Rate-limit SSH/8443 | Solo RFC1918; máx. ~20 nuevas/min (anti fuerza bruta) |
| Port-forward controlado | DNAT + accept en harden-forward con tope de conexiones; tráfico inspeccionado por Suricata NFQUEUE |
| WireGuard / Tailscale | UDP 51820 / 41641 permitidos (VPN) |
| RustDesk (opcional) | Si *Acceso remoto* + “Exponer a Internet”: TCP 21115–21117 y UDP 21116 en WAN (rate-limit) |

No publicar RDP/SMB/bases de datos a Internet. DDoS masivo → ISP / CDN, no el NSP.

### Escritorio remoto (RustDesk)

Para teletrabajo tipo AnyDesk/TeamViewer use **Seguridad → Acceso remoto**:
servidor OSS `hbbs`/`hbbr` en el NSP. Los clientes apuntan ID/Relay + Key
del panel. El acceso administrativo al NSP sigue siendo VPN/Tailscale;
RustDesk es para escritorios de usuarios en la LAN.
