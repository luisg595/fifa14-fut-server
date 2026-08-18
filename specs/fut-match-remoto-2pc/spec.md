# FUT Match remoto 2 PCs (Fase 0 — pre-vuelo + análisis y captura)

## Objetivo

Que 2 PCs (cada una con su username, Fase A multi-cuenta ya desplegada) puedan
**jugar un partido FUT online** contra el mismo `fifa14-fut-server` (Docker,
Debian `192.168.1.2`). Esta spec cubre la **Fase 0**, dividida en:

- **Fase 0a (pre-vuelo, implementable sin captura):** identidad Blaze por
  persona + señales de "online" en el backend, para que el menú FUT ofrezca el
  modo online.
- **Fase 0b (análisis y captura):** documentar exactamente qué pide el cliente
  al entrar a un modo online, para diseñar el emparejamiento en las fases
  siguientes (borradores de diseño al final).

Modo objetivo priorizado: **FUT Season Online** (división), porque reutiliza la
infraestructura de seasons/división que ya existe offline
(`beta_offline_seasons`) y el emparejamiento entre 2 jugadores es una cola
simple. La captura puede revelar que otro modo (Amistoso/`friendlyseason`) es
más alcanzable; se documenta y se ajusta.

## Restricciones verificadas (hechos del código)

- **R1.** El server Blaze no maneja matchmaking: todo comando no ruteado recibe
  `empty-success-observation` (`server/probe.py:1800-1802`). No hay componente
  GameManager/Matchmaking, ni endpoints FUT de matchmaking.
- **R2.** `--debug` gatea `blaze-unhandled-command` (`probe.py:1803`) y
  `easfc-command-debug` (`probe.py:1778`), ambos con `payload_hex` de los
  primeros bytes. **NO está cableado en `entrypoint.sh`** (los args actuales no
  lo pasan) → hay que habilitarlo para la captura.
- **R3.** El cliente ya soporta telemetría: `run_fifa14_remote_beta.ps1` tiene
  `param([switch]$Diagnose)` y pasa `--diagnose` al helper Frida
  (`run_fifa14_remote_beta.ps1:132-135`), que reactiva match-bridge
  (CreateMatch/MatchReady/DestroyMatch/PlayGame/ResetMatch/UpdateTournament) +
  socket/DNS/long-wait.
- **R4.** Identidad Blaze singleton: `build_origin_login_body(player_id=1_000_001)`
  fijo (`probe.py:1033`, usado en `:1683-1684`) y `build_post_auth_body`
  default `1_000_001` (`probe.py:991`). Blaze no distingue qué persona es cada
  conexión → el matchmaking necesita bindear la conexión a la persona (candidato
  natural: `self.client_address`, IP LAN única por PC).
- **R5.** El hook de Frida reescribe `connect()` solo para
  `REDIRECT_PORTS = {42127, 44125, 8099, 8080}` + el fallback dinámico `8306`
  (`tools/frida_pc_fut_nav_route_patch_trace.py:71,1046-1058`). Una conexión
  P2P al IP del rival en un puerto de juego **no** se reescribe → en LAN debería
  pasar directo, salvo firewall.
- **R6.** `friendlyseason/user` devuelve `{"userInfo": []}` (`probe.py:4244-4258`);
  Messaging (15) y AssociationLists (25) responden listas vacías → la lista de
  amigos está vacía (relevante solo para el modo Amistoso).
- **R7.** El partido FUT (offline) ya resuelve sesión por persona:
  `beta_match_sessions` keyed por `persona_id`, handlers
  `create_match`/`match_ready`/`settle_match`/`settle_match_end`/`reset_match`
  (`server/beta_identity.py:1600-1706,1808,2295`) + contrato DNF/QUIT→LOSS en
  `sitecustomize.py`. Si el cliente usa el mismo flujo HTTP para online, la base
  ya está.
- **R8.** Multi-cuenta verificado (SC-4 de `specs/fut-multiaccount`): 2 laptops
  simultáneas con SIDs únicos, cuentas/clubes/monedas aislados por persona; el
  server ya convive con 2 conexiones Blaze + 2 sesiones HTTP a la vez.
- **R9.** El launcher exige username obligatorio (`run_fifa14_remote_beta.ps1:24-37`)
  y el server devuelve `401 account-key-required` sin él (`f76e4fb`). Cada PC
  entra con su cuenta.
- **R10.** Todo `/ut/` no mapeado responde `{}` (200) con emit
  `unmapped-fut-route-local-ack` (`probe.py:4479-4499`) → la captura verá
  peticiones HTTP de matchmaking aunque no existan handlers.
- **R11.** El backend ya anuncia señales de online: account `onlineAccess: True`
  (`probe.py:62`), config OSDK `FUT/IS_RETURNING_USER`, `FUT_SKIP_ICEBREAKER_FLOW`
  (`probe.py:944-969`), `division_online` del club (`local_identity.py:536`),
  entitlements `FIFA14PCFUTContentUnlocks` (`probe.py:1350`). No hay un flag
  "online" único; hay que verificar el conjunto para que el modo online sea
  seleccionable.
- **R12.** No hay documentación pública del protocolo de matchmaking de FIFA 14
  (servidores EA cerrados en 2017; referencias Pocket Relay / New-Blaze-Emulator /
  BFP4F cubren otros títulos o generaciones). La única fuente fiable es la
  captura local del cliente.
- **R13.** El handler de `/ut/game/fifa14/season*` ignora el query string y
  responde siempre el payload de seasons **OFFLINE**
  (`probe.py:4413-4443` → `identity_store.offline_seasons_list()`). El cliente
  de Season Online pide `GET /ut/game/fifa14/season/list?active=true&count=99&
  divisionList=11&type=online`; al recibir solo `"type": "OFFLINE"` muestra
  **"no pudo recuperar la temporada"** y aborta **antes** de emitir
  `fire_component: 4`/`cmd 13` (verificado en la sesión del 2026-08-15, ambas
  PCs `192.168.1.3`/`192.168.1.15`). El modo offline también pasa por
  `season/list`, así que el fix debe despachar por `type` y mantener el payload
  OFFLINE para `type=offline`/sin `type`.
- **R13.1 (re-test 2026-08-15 17:38).** El fix de dispatch por `type` se
  desplegó y verificó en producción: ambas PCs reciben `fut-online-seasons-beta2`
  (15090 B, `"type": "ONLINE"`, `matches` con `teamId: 0`/`difficulty: 0`),
  pero el cliente **se comporta idéntico** al fallo OFFLINE: tras `season/list`
  sondea `/fut/items/pc/-1.json` en bucle (~40 s), pide
  `/fut/items/images/trophies/pc/item.big`, y nunca llega a `season/user` ni
  emite `fire_component: 4`/`cmd 13` (grep `matchmaking-queue-` vacío). El
  `type` solo no desbloquea la pantalla; el payload ONLINE sigue rechazado en el
  parseo o en un paso posterior.
- **H-A (alta, vía secundaria).** El pedido lleva `divisionList=11`; la lista
  ONLINE devuelve divisiones 10→1 (`OFFLINE_SEASON_DIVISIONS`), **sin la
  división 11**. El cliente busca la temporada de su división actual (11,
  provisional de arranque de Season Online) y, al no encontrarla, aborta con
  "no pudo recuperar la temporada". El flujo OFFLINE sí funciona porque la
  división offline del club (10) está en la lista. **E1:** anteponer un record
  provisional `divisionId: 11` (id 1) en `online_seasons_list()` y
  `divisionId: 11` en `online_season_user()`.
- **H-B (media, vía secundaria).** En el flujo OFFLINE que funciona, el cliente
  pide `/fut/items/pc/0.json` por división y acepta el sentinel `{}` (BETA 2.3,
  `probe.py:3068-3070`). En ONLINE pide `/fut/items/pc/-1.json`
  (`trophyResourceId: -1` literal) en bucle → el parser ONLINE usa
  `trophyResourceId` como id de ítem y no mapea "sin trofeo" → 0. **E2:**
  `trophyResourceId: 0` en los records ONLINE para alinear con el patrón
  OFFLINE conocido y aceptado.
- **R14 (hallazgo 2026-08-15 18:21 UTC, partido directo online).** El modo
  **Partido Directo Online** llega al matchmaking **sin pasar por
  `season/list`**: el flujo es `POST /ut/game/fifa14/match` con
  `{"squadId":N,"type":"ONLINE","customData1":-863122704}` (CreateMatch,
  `beta_identity.py:1654`, mode "ONLINE") seguido de
  `fire_component: 4`/`fire_command: 13` (JoinQueue, `fire_length: 1682`) en
  ambas PCs. Verificado en producción con `matchmaking-queue-join`: PC2
  (brimar, persona 1000005, msid=1, queue_size=1) y PC1 (luisg595, persona
  1000003, msid=2, queue_size=2) registrados en la **misma** `queue_key`
  `[3, 1039, "qa-only-day45", 1]`. Tras el join solo hay pings (componente 9
  cmd 2) cada 30 s porque el server responde `b""` al cmd 13 (F3 sin resolver).
  En este modo el `PNET` del request trae `ip: 0, port: 0` (`active_member=2`),
  a diferencia de Season Online donde trae la IP LAN → **el cliente no se
  auto-bindea**: la dirección del rival debe venir en la respuesta/notificación
  del server (F3). El partido directo online pasa por el **mismo**
  `/ut/game/fifa14/match` que el offline (F5) y dispara el matchmaking sin
  depender de la temporada → es la vía primaria; Season Online (E1/E2) queda
  como vía secundaria.
- **R15 (hallazgo 2026-08-15, captura frida `--diagnose` en PC1, game pid
  22048).** Evidencia del estado real de F3: `consumeBlazeFrames` capturó **un
  solo frame componente 4** — la respuesta del server al `cmd 13` con
  `length: 0` (el `b""` actual), `seq 43`, `type 1` (respuesta FIRE), socket
  4116 → `192.168.1.2:42128`, con backtrace por fifa14.exe offsets `0xd94b42 →
  0xd9a389 → 0xf58194 → 0xf5b32a → 0xf5c63f → 0xf61886 → 0xf61bc4 → 0x409df →
  0x47c56 → 0x1e98ca`. Tras el frame solo hay polls WSARecv + `client-long-wait`
  (Sleep 2 s) → el cliente **queda en el spinner de búsqueda**; sin cmd 14
  (leave) ni frames nuevos. **Conclusión:** con la respuesta vacía el cliente no
  parsea la respuesta, así que no hay forma de observar el esquema esperado sin
  enviar antes un cuerpo TDF real. `scanMatchmakingResponseTags` dio un único
  xref confiable: `TID` en rva `0x478c006` (los 3 "hits" de `BTPL` en rvas
  `0x2647dc`/`0x1ae5e7c`/`0x4875074` son **falsos positivos**: el tag del scan
  estaba mal codificado y `8b 4c 00` es un opcode x86 común). **Además se
  detectó un bug del propio scan:** 18 de 21 tags de `MATCHMAKING_RESPONSE_TAGS`
  (`frida_pc_fut_nav_route_patch_trace.py`) no coinciden con `tdf_tag(name,0)`
  del server (solo `TID`, `DUR`, `UED` son correctos); hay que corregirlos antes
  de que el scan vuelva a servir. Con esta evidencia, F3 se aborda por el
  **experimento de respuesta del cmd 13** (backup de la spec) en vez de cazar el
  parser RVA: responder con el esquema inferido de raíz para que el cliente
  **parsee de verdad** y con el scan corregido + hook en `TID@0x478c006` capturar
  qué campos lee.
- **R16 (hallazgo 2026-08-15, experimento 3b — respuesta del cmd 13 con cuerpo,
  sesión frida PC1 pid 20248, logs del server 19:13:30–19:16:00 UTC).** El server
  sirvió `matchmaking-join-queue-experiment` (80 B frame = 68 B body TDF, eco de
  raíz `TID`/`QCAP`/`NTOP`/`DUR`/`BTPL`/`RNFO`/`PNET`) al `cmd 13` de PC1
  (`matchmaking-queue-join` 19:13:29.886, persona 1000003, msid 1,
  `queue_size: 1`). El cliente **recibió y aceptó** la respuesta
  (`blaze-matchmaking-frame-recv` socket 8068, `length: 68`, `seq 43`, type 1):
  **no** hubo frame de error, **no** `cmd 14` (leave), **no** retry, **no**
  crash → tras el join solo `util-ping` (componente 9 cmd 2) cada ~30 s. El
  cliente queda **esperando rival en la cola**. **Conclusión F3 parte 1:** el
  esquema de respuesta del `cmd 13` se acepta (la respuesta ya no es el
  bloqueo). **F3 parte 2 (abierta):** el emparejamiento requiere la
  **notificación Blaze con el PNET del rival** cuando `queue_size==2`; en esta
  ventana `queue_size` se quedó en 1 (solo PC1 en Partido Directo Online), así
  que no hubo nada que notificar. **Duda abierta sobre el parser:** el scan
  corregido solo da xref para `GNAM` (rva `0xa549fe`, sección ejecutable); el
  hook de `TID@0x478c006` nunca se instaló (`executable()` falso → falso
  positivo R15) y no se volcaron campos leídos → el xref de `GNAM` puede ser el
  **serializador del request** (el request trae `GNAM=""` en raíz, ver arriba) y
  no el parser de la respuesta. No hay evidencia directa aún de qué campos lee
  el parser (solo de que la respuesta no se rechaza). Próximo paso: hookear los
  hits ejecutables del scan (incluido `GNAM@0xa549fe`) y discriminar por
  timestamp si dispara al enviar el request o al procesar la respuesta de 68 B.

## Hipótesis a validar

- **H1 (RESUELTO 2026-08-15 18:21).** Al entrar a un modo online, el cliente
  emite comandos Blaze de matchmaking: el **Partido Directo Online** dispara
  `fire_component: 4, fire_command: 13` (JoinQueue) en ambas PCs sin pasar por
  `season/list` (R14). El juego se queda en spinner de búsqueda porque el
  server responde `b""` al cmd 13 (F3 pendiente).
- **H2 (alta).** El gameplay online es **P2P** (host entre las 2 PCs). Al
  emparejarse, los clientes conectarán entre sí por IPs LAN `192.168.1.x` en
  puertos fuera de `REDIRECT_PORTS` (confirmado por conectividad en la captura;
  FIFA 14 online es peer-to-peer).
- **H3 (media, elevada a pre-vuelo).** El modo online puede no estar
  **habilitado/habilitable** hasta que el backend anuncie online (R11). Se
  resuelve en Fase 0a **antes** de la captura; si el botón "Season Online" no
  aparece tras 0a, la contingencia es un **parche de disco del cliente** (ruta
  NAV/estado), no más captura.
- **H4 (media).** La identidad Blaze debe ser distinta por PC para que el
  emparejamiento distinga jugadores; se resolverá por IP LAN del cliente
  (`client_address`), no por SID (Blaze no lleva `X-UT-SID`).

## Fase 0a — Pre-vuelo (implementable ahora, sin captura)

### Requerimientos

- **REQ-A1** Identidad Blaze por persona: en `BlazeProbe`, resolver la persona
  desde `client_address` (IP LAN única por PC) y devolver `player_id`/
  `display_name` correctos en `OriginLogin` (`probe.py:1033`), `PostAuth`
  (`probe.py:991`) y `UserAdded` (`probe.py:1088`). Sin IP conocida → persona
  default. Requiere un mapa IP→persona en el server (se puede poblar durante
  `/ut/auth`, donde ya se conoce el `account_key` + `client_address`).
- **REQ-A2** Advertir online (R11): revisar/ajustar el conjunto de señales
  (config OSDK, account, club `division_online`, entitlements) para que el
  cliente ofrezca "Season Online". Verificar que no hay un flag "offline-only"
  que oculte el modo.
- **REQ-A3** Verificación con 2 PCs: cada PC entra a FUT con su cuenta; el menú
  debe ofrecer el modo online. Si no aparece → contingencia H3 (parche de disco
  del cliente; definir en `tasks.md` como siguiente paso).

Nota: REQ-A1 es prerrequisito de **cualquier** flujo online (el emparejamiento
debe distinguir jugadores) y no depende del TDF de matchmaking.

### Guía de implementación de REQ-A1 (identidad Blaze por persona)

La identidad se resuelve por **IP LAN del cliente**. Para que funcione desde el
**primer arranque** de cada PC (el cliente conecta Blaze OriginLogin al abrir el
juego, antes/igual que el auth HTTP), el mapeo `IP → persona` se registra **por
el launcher** antes de lanzar el juego (decisión: bind por launcher), con
`/ut/auth` como mecanismo complementario/redundante.

Puntos de anclaje verificados en el código:

- **Nueva tabla** `client_ips(persona_id INTEGER PRIMARY KEY, client_ip TEXT NOT
  NULL UNIQUE, updated_at INTEGER NOT NULL)` en `LocalIdentityStore.__init__`
  (`local_identity.py:185-346`, patrón `CREATE TABLE IF NOT EXISTS`; seguir el
  patrón de migración con `PRAGMA table_info` de `local_identity.py:348-352`).
  Asume **1 persona = 1 PC**: `persona_id` como PK → si una persona cambia de PC
  hay que `UPDATE` la fila (no insertar); anotarlo en el comentario del esquema.
- **Nuevo admin endpoint** `/__fifa14_local_fut_admin/bind_client` (patrón de
  `X-Admin-Secret`, `probe.py:2507-2562`): recibe `{"account": "<username>"}` en
  el body, resuelve `persona_id = identity_store.resolve_persona(account)` y
  graba `self.client_address[0] → persona_id`. Punto de anclaje del handler de
  give_coins (`probe.py:2584-2601`) y del `/ut/auth` (`probe.py:2907-2970`).
  **Usar `resolve_persona` (crea la persona si no existe), NO `lookup_account`
  (da 404)**: el launcher corre antes del primer login, y la primera vez que se
  entra con un username aún no hay persona creada.
- **Launcher (`cliente`):** en `run_fifa14_remote_beta.ps1`, tras leer el
  username (`:23-36`), antes de lanzar el juego: POST a
  `http://${ServerHost}:${ServerHttpPort}/__fifa14_local_fut_admin/bind_client`
  con header `X-Admin-Secret` (patrón `give_coins_remote.ps1:32-33`) y body
  `{"account": $accountKey}`. Así la IP de esa PC queda mapeada antes del
  OriginLogin.
- **Complementario `/ut/auth`:** en el handler HTTP de `/ut/auth`
  (`probe.py:2907-2970`) ya se tiene `self.client_address` (usado en
  `probe.py:2408`) y `account_key` (del body `EASW-Session`, `probe.py:2960`).
  Grabar `ip → persona_id` en `start_session` / `resolve_persona`
  (`local_identity.py:570-652`) como redundancia (cubre reintentos/PCs sin
  launcher actualizado).
- **Nuevo método en `LocalIdentityStore`:** `persona_id_for_client_ip(ip)`
  (consulta inversa a la guardada; `persona_id_for_sid` en
  `local_identity.py:668` es el patrón a copiar) y opcional
  `persona_name_for_id(persona_id)` para el `display_name` (hoy fijo
  `"LocalFUT"` en `probe.py:1036,1176`; conviene enviar el real de la cuenta,
  `identity.persona_name`).
- **Resolver la persona por IP del cliente en Blaze:** en `BlazeProbe.handle`
  (`probe.py:1617`) ya existe `self.client_address` (IP LAN del PC). Añadir al
  inicio del handler una resolución `persona_id = persona_id_for_client_ip(
  self.client_address[0])` y usar ese id donde hoy está hardcodeado:
  - `build_origin_login_body(player_id=1_000_001, ...)` (`probe.py:1683-1684`),
  - `build_post_auth_body()` (`probe.py:1772`, default `player_id=1_000_001`
    en `probe.py:991`),
  - notificaciones `build_user_authenticated_body(player_id=1_000_001, ...)`
    (`probe.py:1911-1916`), `build_user_added_body(player_id=1_000_001, ...)`
    (`probe.py:1924-1931`) y `build_user_extended_data_body(user_id=1_000_001)`
    (`probe.py:1939`).
  - Fallback: sin IP conocida → `1_000_001` (comportamiento actual).
- **Setear la persona thread-local en el hilo de Blaze:** además de pasar el id
  a los builders, hacer `set_client_persona(persona_id)` tras resolver en
  `BlazeProbe.handle`. El hilo de Blaze hoy nunca setea la persona
  (`set_client_persona` solo ocurre en el hilo HTTP, `probe.py:2424-2432`,
  `:2601`, y en `start_session`, `local_identity.py:609`). Sin esto, las
  llamadas al store dentro del hilo Blaze (p. ej. `has_club()` en
  `build_fetch_config_body`, `probe.py:1741-1743`; `_identity()` usa
  `get_client_persona()`, `local_identity.py:493-506`) caen a la persona
  `1_000_001`, y REQ-A2 (OSDK `returning_user`/`IS_RETURNING_USER`,
  `division_online` del club) miraría la cuenta equivocada.
- **Emit `blaze-identity` (verificación SC-A1):** los emits actuales
  (`blaze-response`, `origin-login-variant`) no incluyen el `player_id`
  resuelto, solo `response_name` + hex. Añadir en `BlazeProbe.handle`, al
  resolver, un `emit("blaze-identity", peer=self.client_address,
  persona_id=persona_id, display_name=display_name)` para que SC-A1 se
  verifique de un vistazo en los logs.
- **Entitlements con el `persona_id` (opcional, consistencia):**
  `build_entitlements_body` codifica `PID` con default `1_000_001`
  (`probe.py:1305`) y se llama desde `build_shared_blaze_bootstrap_response`
  (`probe.py:1352`), que se ejecuta en el hilo de Blaze (`probe.py:1795`).
  Ahora que el hilo setea `set_client_persona`, pasar `persona_id=get_client_persona()`
  (o el resuelto) a esa llamada para que el grant de online access (TYPE 1,
  `FIFA14PCFUTContentUnlocks`) quede asociado a la persona correcta. No es
  necesario para SC-A1 ni bloquea REQ-A2.

### Guía de implementación de REQ-1 (`--debug` en el server)

- `--debug` ya existe como flag de argparse (`probe.py:5016-5019`, gatea
  `easfc-command-debug` y `blaze-unhandled-command` en `probe.py:1778,1803`).
- Falta cablearlo en `entrypoint.sh` (línea 10-25): añadir `--debug` al
  `exec python /app/server/probe.py \` final.
- Para la sesión de captura se usa el despliegue con `--debug`; para el modo
  normal se quita (ver `deploy.md`).

### Escenarios de pre-vuelo

- **SC-A1.** Ambos PCs entran a FUT con su cuenta → cada conexión Blaze
  (OriginLogin/PostAuth) muestra el `player_id`/`display_name` de su persona
  (verificado en `blaze-request`/`blaze-response` de los logs).
- **SC-A2.** El menú FUT de ambas PCs ofrece el modo online (Season Online
  visible y seleccionable). Nota: no es verificable sin el despliegue real con
  el juego en las 2 PCs; depende de la señal R11 (H3).

## Fase 0b — Captura del flujo online

### Requerimientos (solo instrumentación/observación)

- **REQ-1** Server: habilitar `--debug` en el despliegue de captura (ver
  `deploy.md`) para registrar todo comando Blaze no manejado con `payload_hex`.
- **REQ-2** Cliente: ambas PCs ejecutan `RUN_REMOTE_FUT.cmd -Diagnose` con su
  username (no hay cuenta default, R9).
- **REQ-3** Registro manual del flujo en cada PC: entrar a FUT → Season Online
  (misma división), anotar pantallas, botones visibles, spinner, errores,
  timestamps.
- **REQ-4** Recolección de logs: `docker compose logs` del server (con `--debug`),
  `artifacts/frida.log` de cada cliente, y una captura de tráfico por PC
  (Wireshark o `pktmon`) enfocada en el tráfico de juego (IPs 192.168.1.2 y
  192.168.1.x).
- **REQ-5** Documentar el mapa `componente/command → respuesta observada` y la
  línea de tiempo de la búsqueda de partido (qué se envió, qué se respondió,
  a qué IP/puerto conectó el cliente).

### Findings obligatorios (entrada de la Fase 1-2)

- **F1.** ¿Aparece "Season Online"? Si no, el hallazgo es un bloqueo de cliente
  (H3), no de matchmaking. **Hallazgo:** el modo **Partido Directo Online**
  aparece y es seleccionable (R14); Season Online aparece pero aborta antes del
  cmd 13 (R13.1). El directo online es la vía primaria.
- **F2.** Componente/command/petición HTTP + payload del primer intento de
  matchmaking (H1). **RESUELTO:** `POST /ut/game/fifa14/match` con
  `type=ONLINE` + `fire_component: 4, fire_command: 13` (JoinQueue, 1682 B);
  estructura completa decodificada en "Análisis del request de matchmaking".
- **F3.** ¿Dónde aprende cada cliente la **dirección del rival**? (respuesta
  HTTP de matchmaking, notificación Blaze, o descubrimiento directo). Dato de
  diseño decisivo para la Fase 1. **EN ANÁLISIS** (Paso 2 frida, R15). La captura
  con `--diagnose` probó que el cliente recibe la respuesta vacía (`b""`) del
  cmd 13 y **nunca alcanza el parser** (R15); el único xref confiable es
  `TID` rva `0x478c006`. Decisión: **experimento de respuesta del cmd 13**
  (backup de la spec, R15/Paso 3b) en vez de seguir cazando el parser a ciegas.
- **F4.** IP/puerto de la conexión P2P y quién es host (H2). **Pendiente**
  (depende de F3); en el request del directo el `PNET` va `ip:0/port:0`, el
  server debe entregar la dirección del rival.
- **F5.** ¿El partido online usa el mismo `/ut/game/fifa14/match`? **RESUELTO:**
  sí (R14); el handler `create_match` (`beta_identity.py:1654`) ya persiste por
  persona con `mode="ONLINE"`. Falta ligar las 2 sesiones de
  `beta_match_sessions` en una fila de partido (Fase 2).

### Escenarios

- **SC-1.** Ambos PCs entran a FUT con su cuenta → login OK, cada uno en su
  persona, sin pisarse (regresión multi-cuenta, R8).
- **SC-2.** PC1 entra a Season Online → registrar los comandos Blaze/HTTP nuevos
  (H1) y la pantalla resultante (spinner infinito, error, regreso al menú, o
  partida iniciada).
- **SC-3.** Ambos en cola a la vez → registrar si el cliente intenta conectar al
  otro PC (H2: conexión P2P a IP LAN, F4) o si falla antes (bloqueo F1/F3).
- **SC-4.** Regresión: tras la captura, un partido offline (Season/Torneo) sigue
  funcionando sin cambios (R7 intacto).

## Análisis del request de matchmaking (Paso 1 — decodificado)

El payload completo de `component=4, command=13` (JoinQueue, `fire_length:
1682`) se decodificó con un decoder TDF tolerante (type `0x09` = mapa, mismo
formato que `0x05`). Los payloads de PC1 y PC2 son casi idénticos; diferencias:
`futTeamOVR` (61 vs 60), `matchSimilar` (1 vs 0) y el tail PNET
(IP/puerto LAN propio). `command=14` = leave cola (`MSID=0`).

Estructura raíz (`probe.py` debe responder con este esquema, ver Fase 1):

- `BTPL` (mapa `0x09`, vacío) — playlist/tournament battle.
- `CRIT` (grupo) — criterios de búsqueda, con sub-grupos: `AGAM`, `APLR`,
  `CUST`, `DNF` (=101), `FRES` (`MAXS`=65535, `MINS`=0), `GEO`/`GNAM`/`NAT`
  (THLD string vacío), `MODR` (`ISEN`/`MODS`), `PCNT` (`ISSG`, `PCAP`, `PCNT`,
  `PMIN`=2, `THLD`=`OSDK_matchRelax`), `PCTF` (`DESP`/`MAXP`/`MINP`/`THLD`),
  `PPLR` (`PSET` mapa, `REQP`), `PSR` (`THLD`=`OSDK_matchRelax`), `RANK`
  (`THLD`=`OSDK_matchExact`, `VALU`=1), `REP` (`REPR`), `RLST` (lista de
  criterios NAME/THLD/VALU: `OSDK_gameMode`="81", `OSDK_coop`="1",
  `OSDK_arenaChallengeId`="0", `fifaTeamLevel`=0, `fifaHalfLength`=4,
  `fifaCustomController`=0, `fifaGameSpeed`=1, `fifaGKControl`=1,
  `fifaClubNumPlayers`=0, `fifaClubLeague`=16, `fifaMatchupHash`=1684366964,
  `OSDK_clubId`=0, `futNewUser`=1, `futTeamOVR`="61", `OSDK_sponsoredEventId`=0,
  `OSDK_roomId`=0, `OSDK_categoryId`=0, `OSDK_rosterVersion`=1), `RSZR`
  (`PCAP`=65535, `PMIN`=0), `SIZE` (`PCNT`/`PCAP`/`PMIN`=1), `TBR` (`SDIF`,
  `THLD`), `TCNR` (`TCNT`=0), `TEAM` (`PCAP`/`PCNT`/`PMIN`/`SDIF`, `TID`=65535),
  `TMSR` (`PCNT`=0), `TOTS` (`DESS`/`MAXS`/`MINS`=2, `THLD`=`OSDK_matchRelax`),
  `UED` (mapa `0x05` string→grupo: `futSkillRating` con `CVAL`/`NAME`/`OVAL`/
  `THLD`=`OSDK_matchRelax`), `VIAB` (`THLD`=`OSDK_connUnlikely`), `VIRT`
  (`THLD` vacío, `VALU`=1).
- Raíz: `DUR`=60000, `ECRI` (mapa `0x05` string→string:
  `OSDK_maxDNF`→`stats_dnf <= 100`), `GENT`=0, `GNAM`="", `GSET`=1039,
  `GVER`=`qa-only-day45`, `IGNO`=1, `MODE`=3, `NTOP`=130, `PMAX`=0,
  `PNET` (unión tipo 2: `EXIP`/`INIP` con `IP`/`MACI`/`PORT` — **trae la IP LAN
  y puerto propio del cliente**, PC1 `IP=3232235779`=`192.168.1.3`,
  `PORT=3659`), `PRES`=1, `QCAP`=0, `RNFO` (grupo vacío), `TID`=65534, `VOIP`=0.

Hallazgo clave: el request ya transporta el `PNET` (IP LAN + puerto) de cada
jugador → el server dispone de la dirección del rival para emparejar y
notificarla (F3/F4), sin descubrimiento adicional.

## Fase 1 — Emparejamiento mínimo (plan aprobado)

Decisión de estrategia para descubrir el esquema de respuesta F3: **hook frida
al parser de respuestas de matchmaking del cliente** (recomendado), con
referencias públicas (Pocket Relay / New-Blaze-Emulator) como respaldo.

Pasos:

- **Paso 1 (hecho).** Decodificar el payload completo del `cmd 13` con decoder
  TDF tolerante (arriba) para definir la clave de cola (modo/división, `MODE`,
  `GSET`, `GVER`, `fifaMatchupHash`) y el formato de los campos. Falta la
  respuesta/notificación que el cliente espera (F3).
- **Paso 1.5 (HECHO, hallazgo R13).** Bloqueo descubierto en el deploy 3a:
  el cliente de Season Online no llega al `cmd 13` porque el server responde
  seasons `OFFLINE` a `season/list?type=online` → "no pudo recuperar la
  temporada". Fix: `online_seasons_list()`/`online_season_user()` en
  `beta_identity.py` (mismo esquema nativo de `_native_season_record` pero
  `"type": "ONLINE"`, divisiones 10→1, `matches` sin rival IA: `teamId: 0`,
  `difficulty: 0`) y dispatcher de `type` en el handler de `/ut/game/fifa14/season*`
  (`probe.py:4413-4443`): `type=online` → online; resto → offline (regresión
  R7 intacta). Validado localmente (`py_compile` + smoke `--beta-mode`:
  `type=online` → `"type": "ONLINE"`, `type=offline` → OFFLINE, `season/user`
  intacto). **Deploy + re-test 2026-08-15 17:38:** el fix ONLINE se sirve
  correctamente a ambas PCs (R13.1), pero el cliente sigue abortando → pasar a
  **Paso 1.5b**.
- **Paso 1.5b (EN PAUSA, vía secundaria — Season Online; E1/E2).** El `type`
  solo no desbloquea la pantalla de Season Online, pero el **Partido Directo
  Online** alcanza el cmd 13 sin depender de la temporada (R14), así que el
  emparejamiento mínimo no necesita E1/E2. Se mantienen implementados y
  pusheados (commit `81fa615`, rama `feat/fase0a-identidad-blaze-por-persona`)
  para desbloquear Season Online más adelante:
  - **E1 (H-A):** en `online_seasons_list()` anteponer un record provisional
    `divisionId: 11` (id 1) para cubrir `divisionList=11`; en
    `online_season_user()` devolver `divisionId: 11`.
  - **E2 (H-B):** en `_native_online_season_record()` usar `trophyResourceId: 0`
    para que el cliente pida `/fut/items/pc/0.json` (patrón OFFLINE aceptado)
    en vez de `-1.json`.
  - No tocar el payload OFFLINE (regresión R7 intacta). Validado local
    (`py_compile` + smoke `--beta-mode`) y pusheado; **pendiente de deploy**.
    Si más adelante se reactiva Season Online: deploy y re-test esperando que el
    cliente avance tras `season/list`; si aún falla, capturar los keys reales
    del parser con frida (Paso 2).
- **Paso 2.** Determinar el esquema de respuesta esperado (F3). **HECHO
  2026-08-15 (R15):** la sesión `--diagnose` capturó la respuesta vacía del
  cmd 13 (un solo frame componente 4, `length 0`, backtrace RVAs) y probó que el
  cliente **no llega al parser** con `b""`. El único xref confiable es
  `TID` rva `0x478c006`. **Se detectó además un bug en el propio scan:** 18/21
  tags de `MATCHMAKING_RESPONSE_TAGS` están mal codificados (solo `TID`/`DUR`/
  `UED` coinciden con `tdf_tag(name,0)`); los "hits" de BTPL eran falsos
  positivos. Decisión: dado que el cliente nunca parsea la respuesta vacía, la
  vía eficaz es el **experimento de respuesta** (backup, abajo) y NO seguir
  cazando el parser a ciegas. Se conserva el hook al parser como paso de
  verificación opcional tras el experimento:
  - `hookRecv`/`hookWSARecv` hoy solo capturan dentro de la "trusted window"
    (180 s tras login, `TRUSTED_WINDOW_MS`); el intento de matchmaking ocurre
    después y quedó fuera del log. Ampliar la captura del socket Blaze del
    redirector (42129) para que capture frames `component==4` de forma
    persistente (no solo en ventana), con hex completo + `Thread.backtrace` al
    recibir, para localizar el parser nativo de la respuesta TDF del componente
    4 en el módulo Blaze del cliente (análogo a `AUTH_RESPONSE_PARSER` /
    `CREATE_MATCH_RESPONSE_PARSER` de CardsDLL).
  - **Instrumentación lista (build):** en `frida_pc_fut_nav_route_patch_trace.py`:
    - `consumeBlazeFrames(fd, data, source, context)` — reensamblador por socket
      de frames FIRE (`>HHHHBBH`, 12 B header) que emite
      `blaze-matchmaking-frame-recv` (hex completo + backtrace normalizado) para
      cada frame `component==4`, request y response. Correr siempre que
      `--diagnose` está activo (fuera de la trusted window).
    - Conectado en `hookRecv` (onLeave, bytes completos) y `hookWSARecv`
      (onLeave; WSARecv es overlapped en el socket Blaze, así que solo se
      consume la cadena WSABUF en completación síncrona `retval >= 0` — el
      `retval -1` overlapped deja `bytesPointer` sin valor válido y produciría
      bytes basura).
    - `scanMatchmakingResponseTags(module, source)` — al resolver
      `fifa14.exe` y `CardsDLLzf.dll`, escanea las secciones ejecutables por las
      constantes inmediatas de los tags TDF de respuesta esperados (TID, QCAP,
      NTOP, PNET, RNFO, MODE, GSET, GVER, PMAX, PRES, DUR, VOIP, GENT, GNAM,
      IGNO, BTPL, ECRI, MSID, PCNT, RLST, UED), cada una como `tag 3B + 0x00`
      (tipo 0), y emite `blaze-matchmaking-tag-xref` con RVAs candidatos del
      parser. El backtrace de `blaze-matchmaking-frame-recv` discrimina el
      parser real de usos no relacionados.
    - **BUG (R15):** `MATCHMAKING_RESPONSE_TAGS` tiene **18/21 tags mal
      codificados** — los 3 bytes no son `tdf_tag(name,0)[0..2]` (p. ej. BTPL
      debe ser `[0x8b, 0x4c, 0x2c]`, no `[0x8b, 0x4c, 0x00]`). Corregir antes de
      reusar el scan. Verificado contra `probe.tdf_tag` el 2026-08-15.
  - **Sesión de captura (PC1, partido directo online):** correr en PC1
    (`run_fifa14_remote_beta.ps1 -Diagnose`) y entrar a **Partido Directo
    Online** (no Season Online, R14) → capturar frames componente 4 (request
    cmd 13 + la respuesta `b""` actual) con backtrace → RVA del parser.
    **HECHO (R15):** 1 frame (la respuesta vacía), backtrace obtenido, parser
    no alcanzado por el cliente.
  - Una vez localizado el parser, hookear su RVA (patrón
    `cards-create-match-response-parser-beta222`, `frida_pc_fut_nav_route_patch_trace.py:2726-2756`)
    para volcar qué campos TDF lee la respuesta (esquema esperado) → responde
    F3 (¿la IP del rival viene en la respuesta del cmd 13 o en una notificación
    posterior?).
  - **Alternativa/backup — SELECCIONADA (R15):** el cliente no parsea la
    respuesta vacía, así que en vez de cazar el parser a ciegas se **responde al
    `cmd 13` con el esquema inferido** (eco de raíz: `TID`, `QCAP`, `NTOP`,
    `PNET`, `RNFO`) y se observa qué comandos nuevos envía el cliente
    (`blaze-unhandled-command` / `blaze-response` en logs del server). Con el
    scan corregido + hook en `TID@0x478c006` se vuelcan los campos que el parser
    lee al procesar nuestra respuesta → esquema real (Paso 3b).
- **Paso 3 (desglosado en 3a/3b).**
  - **Paso 3a (HECHO): infraestructura de cola + observación, sin tocar la
    respuesta del `cmd 13`.** Implementado en `probe.py`:
    - `MATCHMAKING_COMPONENT = 4`.
    - Estado en `main_blaze`: `matchmaking_queue` (dict por clave
      `(MODE, GSET, GVER, fifaMatchupHash)`), `matchmaking_lock`,
      `matchmaking_next_msid`.
    - Helpers tolerantes `extract_matchmaking_key` (MODE/GSET/GVER/`fifaMatchupHash`
      dentro de `RLST`) y `extract_matchmaking_pnet` (unión `PNET` → `IP`/`PORT`);
      necesarios porque `decode_tdf_document` falla en la raíz type `0x09`
      (`BTPL`). Validados contra payload sintético que replica el esquema real
      (PC1: IP=3232235779=`192.168.1.3`, PORT=3659).
    - Dispatch `cmd 13` (JoinQueue): registra al jugador con `persona_id`,
      `peer`, `PNET` y `msid`; `emit("matchmaking-queue-join", ...)` con el
      estado de la cola; **responde `b""`** (`matchmaking-join-queue-observed`)
      — idéntico al comportamiento actual, F3 intacto. `cmd 14` (LeaveQueue):
      quita por MSID o persona; `emit("matchmaking-queue-leave", ...)`.
    - `purge_matchmaking_peer` en la desconexión (`blaze-session-ended`).
    - Verificado: `py_compile`, test de extractores OK, smoke de arranque OK.
    - **Deploy + verificado en producción 2026-08-15 18:21:** con ambas PCs en
      Partido Directo Online, `matchmaking-queue-join` registró a las dos en la
      misma `queue_key` `[3, 1039, "qa-only-day45", 1]` (queue_size 1→2) — la
      cola, el PNET y la clave funcionan en el despliegue real (R14).
  - **Paso 3b (RESULTADO R16 — experimento de respuesta cmd 13, backup R15).**
    Sustituir `body = b""` por una respuesta TDF eco del esquema inferido de
    raíz (`TID`, `QCAP`, `NTOP`, `PNET`, `RNFO`, más `BTPL`/`DUR` del request),
    de modo que el cliente **parsee de verdad** la respuesta. **HECHO:** el
    cliente acepta la respuesta (sin error/leave/retry, esperando rival, R16);
    **F3 parte 1 resuelta** (respuesta del cmd 13 aceptada). Con el scan
    corregido, hookear los hits **ejecutables** (incluido `GNAM@0xa549fe`) y
    discriminar por timestamp serializador vs parser para volcar qué campos lee
    → esquema real. Luego, emparejamiento activo (cola `queue_size==2` →
    notificar PNET del rival según F3). El handler `cmd 13` (cola, MSID) y
    `cmd 14` (leave) ya están construidos; falta el cuerpo de respuesta y el
    emparejamiento.
- **Paso 4.** SC-3: ambas PCs en **Partido Directo Online** a la vez →
  emparejar con la dirección del rival (según F3) y notificar (según F3).
  Verificar que el cliente intenta conectar al otro PC (P2P LAN, H2/F4).
- **Paso 5.** Regresión SC-4: partido offline intacto; documentar en
  `findings.md`.

## Riesgos residuales

- El modo online puede depender de parches de disco o assets del cliente (no
  solo del server); si el botón no aparece tras 0a, el siguiente paso es un
  **parche de disco** (ruta NAV/estado), no más captura (contingencia H3).
- La conexión P2P entre PCs puede estar bloqueada por el firewall de Windows de
  cada PC (el juego escucha como host); habrá que abrir el puerto del juego en
  ambas (punto 0 de la captura de conectividad).
- El matchmaking retail de EA no es observable (servidores cerrados en 2017);
  la captura local + referencias públicas (Pocket Relay, New-Blaze-Emulator) son
  la única fuente para deducir componentes/TDF (R12).
- La captura con `--debug` + `--diagnose` añade overhead; si apareciera lag, la
  Fase 0 se corre igualmente (es una sesión de telemetría puntual, no el modo de
  juego normal).
- Ligar las sesiones del partido online (F5) puede requerir cambios en
  `beta_match_sessions` (una fila por partido, no una por persona).

## Definición de "hecho"

La Fase 0 está completa cuando:

- **0a**: SC-A1 y SC-A2 pasan (identidad Blaze por persona + modo online
  visible). Si no es visible, el hallazgo de bloqueo (H3) y el plan de parche de
  disco quedan documentados en `findings.md`.
- **0b**: `specs/fut-match-remoto-2pc/findings.md` documenta **F1-F5** (o el
  hallazgo de bloqueo H3) con el mapa componente→respuesta y la línea de tiempo
  de la búsqueda de partido.

Con eso se diseña la Fase 1 y la Fase 2 (borradores abajo).

## Fases siguientes (borrador de diseño)

- **Fase 1 — Emparejamiento mínimo.** Servidor: cola en memoria de jugadores
  buscando partido (por modo/división). Al haber 2 en la cola, emparejarlos y
  emitir la/s notificación/es Blaze o la respuesta HTTP que el cliente espera
  (según F2/F3). La notificación debe incluir la dirección del rival (F3/F4: en
  LAN, IP del otro PC + puerto del host).
- **Fase 2 — Partido P2P + reporting.** Confirmar el flujo `/ut/game/fifa14/match`
  online (F5): ligar las sesiones de ambos jugadores en una fila de match,
  registrar W/D/L por persona, season online (divisiones), EASFC (componente
  0x081D, `record_easfc_signal`, `beta_identity.py:2637`) y contrato
  DNF/QUIT→LOSS (`sitecustomize.py`). Abrir el puerto P2P en ambos firewalls y
  validar el gameplay directo entre PCs.