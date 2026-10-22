# Procedimiento de Configuración y Uso de la Red

**STEPAD NSP** · Revisión anual · Última revisión: 2026-08

Este documento describe formalmente cómo se configura y opera la red
gestionada por STEPAD NSP. Debe revisarse **al menos una vez al año** o
ante cualquier cambio relevante de la red (nueva tarjeta, nueva zona,
cambio de operador, publicación de un nuevo servicio).

---

## 1. Alcance

Aplica a toda la configuración de red del equipo NSP:

- Asignación de tarjetas (WAN/LAN) y su identidad.
- Zonas (segmentación / VLAN).
- Aislamiento entre zonas.
- Reenvío de puertos (DMZ).
- DHCP y DNS.

## 2. Roles y responsabilidades

| Rol | Responsabilidades |
|---|---|
| Administrador (ADMIN) | Configurar/crear zonas, interfaces, reenvíos, bloquear dominios, gestionar usuarios y MFA. |
| Operador (OPERATOR) | Solo lectura: consultar estado, dispositivos, logs y protección. No puede escribir configuración. |

## 3. Instalación inicial

1. Ejecutar el instalador. **No solicita datos**: genera las claves
   (JWT, contraseña de PostgreSQL) y las credenciales iniciales del
   administrador automáticamente y las muestra al final.
2. En el primer acceso, cambiar la contraseña inicial del administrador.
3. Activar MFA en la cuenta de administrador.
4. La **web de administración** se sirve desde el propio NSP por
   **HTTPS** (`https://<ip-del-nsp>:8443`, certificado autofirmado). Por
   defecto solo es accesible desde **LAN o VPN** (no desde la WAN).
5. El frontend se sirve compilado desde el backend; no hay dev server
   expuesto. SSH permanece abierto como canal de recuperación.

## 4. Identidad de tarjetas (WAN / LAN)

- Las tarjetas se identifican por **MAC** (no por nombre de Linux), de
  modo que el rol asignado sobrevive a reinicios, cambios de máquina o
  sustitución de tarjeta.
- Asignar rol **WAN** a la tarjeta con salida a Internet y rol **LAN** a
  la(s) tarjeta(s) interna(s).
- Si una tarjeta se cambia de puerto o se reemplaza, el sistema lo
  detecta; reasignar el rol en la pantalla de **Interfaces**.

## 5. Segmentación de red (zonas)

Dos modos de despliegue, no excluyentes:

- **Varias tarjetas LAN**: cada zona sobre su propia tarjeta física.
- **Switch administrable + VLAN**: cada zona con un VLAN ID crea una
  sub-interfaz 802.1Q sobre la tarjeta LAN (el puerto del switch debe
  estar en modo *trunk* con los VLAN etiquetados).

**Misma UI, distinto contexto:** las pantallas (Dispositivos, DHCP,
Zonas, etc.) no se duplican. En la barra superior se elige la
**tarjeta / red activa**; con 3.ª o 4.ª LAN el mismo selector escala.

Flujo recomendado:

1. Asignar la primera tarjeta como LAN → el sistema crea la **zona por
   defecto** a partir del segmento DHCP configurado.
2. Asignar otra tarjeta LAN (p. ej. libre hacia otro router) → crear
   zona eligiendo **Tarjeta completa** o **VLAN**, con CIDR/DHCP
   libres. No dejes dos DHCP en el mismo L2.
3. En la barra superior, cambiar de tarjeta para administrar cada
   segmento.

Procedimiento para crear una zona:

1. En **Zonas → Nueva zona**, indicar nombre, red (CIDR), gateway y
   pool DHCP.
2. Elegir si el enlace es **tarjeta completa** o **VLAN**, y la
   tarjeta LAN (MAC) para que la zona la siga.
3. Si se usa un switch, indicar el VLAN ID.
4. Marcar una zona como **default** (recibe los dispositivos nuevos).
5. Revisar que DHCP y DNS de la zona quedan activos.

### Aislamiento entre zonas

- Con **dos o más zonas**, el motor de aislamiento bloquea el tráfico
  directo entre zonas (movimiento lateral), permitiendo salida a
  Internet y el acceso a los servicios del propio equipo (DHCP/DNS).
- Ver estado en `Zonas → isolation` o en el panel de ajustes.
- Para redes tipo *invitados*, crear una zona dedicada y no asignar
  recursos internos en ella.

## 6. DMZ y reenvío de puertos

- Crear una zona **DMZ** para todo servicio publicado hacia Internet.
- En **Ajustes → Reenvío de puertos**, añadir cada servicio: protocolo,
  puerto externo (WAN), IP interna del host y puerto interno.
- Aplicar la regla y verificar el acceso desde Internet.

## 7. Políticas de seguridad (resumen)

- Contraseñas robustas, caducidad de 90 días y MFA.
- Bloqueo de cuenta tras 3 intentos fallidos (30 min).
- Sesión con timeout de inactividad de 15 min.
- Revocación inmediata al desvincular personal.
- Solo los administradores pueden escribir configuración.

## 7. Acceso remoto (VPN)

Todo acceso administrativo remoto debe realizarse a través de la **VPN
cifrada (WireGuard)**:

1. **Autorización previa**: en **VPN → Autorizar nuevo acceso remoto**,
   indicar nombre, motivo/justificación y, si es temporal, la fecha de
   caducidad. No se habilita acceso sin autorización documentada.
2. **Credenciales individuales**: cada persona/proveedor tiene su propio
   peer con su propia clave; nunca se comparten credenciales.
3. **Entrega del acceso**: al crearlo se muestra la configuración del
   cliente (clave privada) **una sola vez**; entregarla solo al
   autorizado.
4. **MFA**: el acceso a la web de administración sigue exigiendo
   usuario/contraseña y MFA aunque se entre por la VPN.
5. **Supervisión**: revisar **VPN → sesiones** (conexiones activas) y el
   log de auditoría (creación/revocación de peers) semanal o mensualmente.
6. **Revocación**: al terminar un trabajo contratado, **Revocar** el peer
   inmediatamente. Los accesos temporales se revocan automáticamente al
   cumplirse su fecha de caducidad.
7. **Política estricta (opcional)**: activar
   `STEPAD_VPN_REQUIRE_REMOTE_ADMIN` para limitar la web de
   administración a LAN/VPN desde la WAN (bloquea el puerto 8000). Por
   defecto está desactivada; el SSH del sistema nunca se bloquea.

## 8. Revisión periódica

- **Anual** (o ante cambios): revisar este procedimiento y el diagrama
  de red.
- Revisar usuarios y sus últimos accesos (pantalla **Usuarios**).
- Comprobar el estado de todos los componentes en el **Panel**.
- Verificar que el diagrama de red refleja la topología real.

## 9. Registro de cambios

| Fecha | Cambio | Autorizado por |
|---|---|---|
| 2026-08-06 | Creación del procedimiento. | — |
