# Deploy Fase 0 — Pre-vuelo + captura del flujo online (2 PCs)

Topología: server Debian `192.168.1.2` (Docker) + 2 PCs Windows en la misma LAN,
cada una con su username (Fase A multi-cuenta). Primero el **pre-vuelo** (0a:
identidad Blaze por persona + online visible), luego la **captura** (0b: solo
instrumentación, sin tocar matchmaking).

## 0a. Pre-vuelo

### 1. Identidad Blaze por persona (REQ-A1)

En el server, desplegar el cambio que mapea IP del cliente → persona y devuelve
el `player_id`/`display_name` correcto en OriginLogin/PostAuth/UserAdded
(guía de implementación detallada en `spec.md` → "Guía de implementación de
REQ-A1"; puntos de anclaje `probe.py:1617,1683-1684,1772,1911-1939`,
`local_identity.py:185-346,570-652,668`, admin endpoint `bind_client`). El
mapeo se registra **por el launcher** antes de lanzar el juego. Rebuild y
verificación:

```bash
cd /home/luisg595/fifa14-fut-server
./up.sh
docker compose logs -f fifa14-fut   # buscar blaze-request/response de OriginLogin por persona
```

Nota: el volumen de la DB se conserva; las cuentas existentes siguen mapeando a
las mismas personas (R8 multi-cuenta).

### 2. Verificación con 2 PCs (REQ-A3, SC-A1/SC-A2)

En **cada** PC, lanzar el juego con su username y entrar a FUT:

- El launcher registra la IP de esa PC en el server (`bind_client`) al pedir el
  username, antes de abrir el juego.
- **SC-A1**: cada conexión Blaze debe mostrar su `player_id`/`display_name`
  (verificar en los logs del server).
- **SC-A2**: el menú FUT debe ofrecer **Season Online** (visible/seleccionable).

Si **no** aparece el modo online, parar: documentar qué señal falta (OSDK /
`division_online` / entitlements / config de cliente) y aplicar la contingencia
H3 (parche de disco del cliente, analogía `patch_fifa14_fut_dynamic_route.py`)
**antes** de la captura.

## 0b. Captura

### 3. Server: habilitar `--debug`

Opción A (recomendada, reproducible): añadir `--debug` a `entrypoint.sh`:

```bash
exec python /app/server/probe.py \
  --host 0.0.0.0 \
  ...
  --admin-secret "${ADMIN_SECRET:?...}" \
  --debug
```

Opción B (sin tocar el repo, sesión puntual): arrancar `probe.py` a mano con el
mismo set de args de `entrypoint.sh` + `--debug`.

Rebuild y verificación:

```bash
cd /home/luisg595/fifa14-fut-server
./up.sh
docker compose logs -f fifa14-fut   # buscar eventos blaze-unhandled-command / easfc-command-debug
```

### 4. Clientes: preparación

En **cada** PC:

1. `config.local.psd1` con `ServerHost = '192.168.1.2'`, `ServerHttpPort = '8099'`
   y `AdminSecret` correcto.
2. `GIVE_100M_TEST_COINS.cmd` (opcional): da monedas a la cuenta activa de esa
   PC (`artifacts/fut-current-account.txt`).
3. Firewall de Windows: para la parte P2P (H2) puede hacer falta permitir el
   puerto del juego en **ambas** PCs (se confirma con la captura; el juego
   escucha como host en la PC del anfitrión).

### 5. Sesión de captura

En ambas PCs (mismo momento):

```powershell
.\RUN_REMOTE_FUT.cmd -Diagnose
```

- Escribir el username propio cuando lo pida (no hay cuenta default).
- Anotar timestamps y pantallas al entrar a **FUT → Season Online** (misma
  división), primero una sola, luego ambas en cola a la vez.
- Capturar red en paralelo (por PC):
  - Wireshark: filtro `ip.addr == 192.168.1.2 || ip.addr == 192.168.1.0/24`,
    guardar `.pcapng` durante la búsqueda/partida.
  - O `pktmon`:
    ```powershell
    pktmon start --capture --pkt-size 0 --file-name fut-online.etl
    # ... jugar / buscar partido ...
    pktmon stop
    pktmon etl2pcap fut-online.etl -o fut-online.pcapng
    ```

### 6. Logs a recoger

| Origen | Ruta / comando | Qué revela |
| --- | --- | --- |
| Server | `docker compose logs fifa14-fut > captura-server.log` | comandos Blaze no manejados (componente/command/payload), peticiones HTTP nuevas (`unmapped-fut-route-local-ack`) |
| PC1 | `artifacts\frida.log`, `.err.log`, `.out.log` | `client-connect-any`, `local-connect-redirect`, DNS, long-wait |
| PC2 | idem | idem |
| Red | `.pcapng` por PC | IPs/puertos P2P entre PCs (H2) y hacia el server |

### 7. Lectura de la captura

- En `captura-server.log`: los frames `blaze-request`/`blaze-response` con
  `fire_component`/`fire_command` que NO correspondan a Auth/Util/Stats/etc.
  (componentes conocidos: 1, 7, 9, 10, 11, 15, 21, 25, 28, 0x081C, 0x081D,
  2148, 2249, 2268, 0x7802) son los comandos de matchmaking a documentar (H1).
- En cada `frida.log`: eventos `client-connect-any` con `port`/`original_ip`
  distintos de 42127/44125/8099/8080/8306 apuntando a otra PC = conexión P2P
  (H2). `client-connect-result` con error = bloqueo (firewall/NAT).
- La respuesta a **F3** (dónde aparece la dirección del rival) y **F5** (mismo
  `/ut/game/fifa14/match`, sesiones ligadas) sale de correlacionar el momento en
  que el cliente intenta conectar con las respuestas HTTP/Blaze previas.
- Si **no aparece** el botón/modo online pese a 0a, anotarlo: es un bloqueo de
  configuración (H3) y la captura de matchmaking aún no aplica.

### 8. Regresión

Tras la captura, jugar un partido offline normal y confirmar que todo sigue
igual; si se usó la opción B (arranque manual) o se desea el modo normal, quitar
`--debug` y `./up.sh` de nuevo.

## 9. Resultado esperado

`specs/fut-match-remoto-2pc/findings.md` con: mapa componente→respuesta,
confirmación/refutación de H1-H4, **F1-F5** (modo online visible, comandos del
primer intento, origen de la dirección del rival, IPs/puertos P2P, flujo de
match/sesiones), y el veredicto de regresión. Eso define la Fase 1
(emparejamiento mínimo: cola de 2 + notificar la dirección del rival) y la
Fase 2 (partido P2P + reporting).