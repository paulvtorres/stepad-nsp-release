# STEPAD NSP — Referencia Rapida

## Comandos de Emergencia

```bash
# Estado del sistema
systemctl status stepad-nsp.service
ss -tlnp | grep 8443
pgrep -a dnsmasq
systemctl is-active suricata

# Reiniciar todo
sudo systemctl restart stepad-nsp.service

# Ver errores
sudo journalctl -u stepad-nsp.service -n 30 --no-pager

# Ver alertas en DB
PGPASSWORD=$(grep DB_PASSWORD /etc/stepad/stepad.env | cut -d= -f2) \
  psql -h 127.0.0.1 -U stepad_app -d stepad_nsp \
  -c "SELECT id, severity, title, left(message,80) FROM alerts ORDER BY id DESC LIMIT 10"
```

## Si no hay internet (usuarios)

1. `systemctl is-active stepad-nsp.service` → debe decir "active"
2. `pgrep -a dnsmasq` → debe mostrar el proceso
3. `ss -ulnp | grep ":67"` → debe escuchar
4. Si no: `sudo systemctl restart stepad-nsp.service`

## Si no responde el panel web

1. `ss -tlnp | grep 8443` → debe escuchar
2. `systemctl is-active stepad-nsp.service` → debe decir "active"
3. Si no escucha: `sudo systemctl restart stepad-nsp.service`
4. Si falla: `sudo journalctl -u stepad-nsp.service -n 50`

## Si no funciona Suricata (IPS)

1. `systemctl status suricata` → debe estar "active"
2. Si no: `sudo systemctl start suricata`
3. Si falla: `suricata -T -c /etc/suricata/suricata.yaml`

## Archivos importantes

- Config: `/etc/stepad/stepad.env`
- Logs: `sudo journalctl -u stepad-nsp.service`
- Health: `grep "Health check" /home/paulan/stepad-nsp/logs/stepad.log`
- Version: `cat /etc/stepad/version`
- Docs: `https://github.com/paulvtorres/stepad-nsp-release/blob/main/OPERACIONES.md`

## Actualizar

```bash
curl -fsSL https://raw.githubusercontent.com/paulvtorres/stepad-nsp-release/main/get-stepad.sh | sudo bash
```
