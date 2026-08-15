# Diagnóstico: lag/pegado en el split remoto (client + server)

## Objetivo

El all-in-one local (`FIFA-14-Local-FUT`, todo en un solo PC, `127.0.0.1`) no
presentaba lag ni congelamientos; tras el split en `fifa14-fut-client`
(Windows/Frida) + `fifa14-fut-server` (Debian/Docker `192.168.1.2`) el juego
se pega y hace lag. Esta spec documenta el **análisis** de las diferencias
verificadas por código y logs, más la **solución de paridad con local**
(sección *Solución*): el remoto debe comportarse como el all-in-one local que
no lageaba. Los fixes se aplican y commitean **por repositorio separado**
(`fifa14-fut-client` y `fifa14-fut-server`).

## Restricciones verificadas (hechos del código)

- **R1.** El helper Frida del cliente reactiva el match-bridge trace que en
  local estaba desactivado por rendimiento: `MATCH_BRIDGE_TRACE_ENABLED = true`
  (`fifa14-fut-client/tools/frida_pc_fut_nav_route_patch_trace.py:52`) hace que
  `if (MATCH_BRIDGE_TRACE_ENABLED) installMatchBridgeTrace(module, reason)`
  (`:2667`) **sí** se ejecute. En local, `RUNTIME_PERFORMANCE_MODE = true`
  (`FIFA-14-Local-FUT/tools/frida_pc_fut_nav_route_patch_trace.py:44`) mantenía
  el gate `if (!RUNTIME_PERFORMANCE_MODE) installMatchBridgeTrace(...)` (`:2590`)
  y el trace **no** se instalaba. El comentario del propio código, junto a la
  declaración de `RUNTIME_PERFORMANCE_MODE` (`:43-45`), describe el motivo
  original: *"Store + ResetMatch paths were firing dozens of
  times per second and stalling the render thread while packs were being
  browsed"*.
- **R2.** El cliente añadió y dejó **siempre activos** (sin gate por
  `RUNTIME_PERFORMANCE_MODE`) varios hooks de diagnóstico: per-socket I/O
  (`hookSend`/`hookWSASend`/`hookRecv`/`hookWSARecv`), `hookLongWaits`
  (Sleep/SleepEx/WaitForSingleObject/select/WSAPoll) y los emits
  `client-connect-any`/`client-connect-result`/`client-dns-any` en cada
  connect/DNS de cualquier thread.
- **R3.** Topología de red: el juego conecta a `127.0.0.1:8099` (HTTP FUT),
  `127.0.0.1:42127` (redirector TLS) y `127.0.0.1:44125` (GOSCA); Frida
  reescribe el `sockaddr` con `__SERVER_IP_BYTES__` (`REDIRECT_PORTS =
  {42127, 44125, 8099, 8080}`) hacia `192.168.1.2`. El socket Blaze main es
  directo a `192.168.1.2:42128`.
- **R4.** `entrypoint.sh` remoto no difiere en los delays de login: los defaults
  de `probe.py` son `--origin-login-delay-ms 100` y `--login-notification-delay-ms
  1500` (`fifa14-fut-server/server/probe.py:5046-5057`), igual que el trace
  local. Diferencias reales: `--host 0.0.0.0`, `--main-blaze-host 192.168.1.2`,
  `--redirector-mode tls`, `--cert-hostname/hash/dir`, `--admin-secret`,
  `--identity-db`, y la ausencia de los verifiers de arranque que corre el
  launcher local (`verify_fifa14_v237_install.py`, `verify_fifa14_beta2.py`,
  `verify_fifa14_postmatch_beta2259.py`, `verify_fifa14_consumables_beta224.py`,
  `verify_fifa14_pack_ui_performance_beta2250.py`,
  `verify_fifa14_market_beta2250.py`, `verify_fifa14_regressions_beta2258.py`;
  `run_fifa14_local_beta.ps1:143-219` aborta el launch si alguno falla).
- **R5.** `probe.py` es compartido (diff solo en logging/endpoints admin); la
  respuesta `empty-success-observation` para comandos UTIL/EASFC no manejados es
  **idéntica** en local y remoto. Los handlers UTIL_COMPONENT 4/10 se añadieron
  (`4971408`) y se revirtieron por romper el login (`28b32f2`). Estado actual:
  revertidos, con debug logging (EASFC/`blaze-unhandled-command`) presente.
- **R6.** Match-assets con fallback hardcodeado: si falta el reporte
  `fifa14-match-assets-v2411-beta222.json`, `_resolved_match_assets()` devuelve
  kit/stadium fijos (Town Park) (`fifa14-fut-server/server/beta_identity.py:40,43-85`)
  → sin freeze, solo visual incorrecto.

## Hipótesis priorizadas

- **H1 (alta).** La instrumentación Frida dejada encendida en el cliente
  (R1+R2) estalla en los hilos de render/red: cada CreateMatch/MatchReady/
  ResetMatch hace `Interceptor` onEnter/onLeave con `pointerProbe` + `stackArgs` +
  backtrace + emit JSON; cada Sleep/WaitForSingleObject de cualquier thread paga
  JS extra. Efecto: stall/pegado del frente de juego, exactamente el síntoma.
- **H2 (media).** Pack purchase gap ~17-19 s: el server responde
  `empty-success-observation` a comandos UTIL/EASFC de la compra; el cliente
  espera una notificación Blaze que no llega. Diagnóstico del cliente: los gaps
  tienen **cero connects y cero DNS** (commit `763b621`). Freeze puntual, fix a
  medias (revertido).
- **H3 (media/baja).** RTT real de LAN + Nagle/delayed-ACK en frames Blaze
  pequeños y conexiones HTTP nuevas por request → lag perceptible, no freeze duro.

## Evidencia (logs del cliente)

- `artifacts/frida.log` (v2.40.10): `cards-match-bridge-enter-beta222` 193
  eventos; `client-long-wait` **491** (señal dominante tras el cap, umbral ≥2 s);
  waits largos `WaitForSingleObjectEx` 48056 ms (tid 11664) y
  56360 ms (tid 2620), `Sleep` 15000 ms; `client-connect-result` con
  `result -1 errno 0`; **0** eventos `client-dns-any`; `fifa14-native-exception-
  beta222` 1000 (cap) en `KERNELBASE.dll 0x75b9a2b4` (aparentemente benigno).
- `artifacts/frida.matchloop-22h29.bak.log`: `cards-match-bridge-enter/leave`
  alcanzan el cap de 1000.

## Solución (paridad con local)

La paridad se cierra en los puntos donde el split difiere del local. El lag
continuo (H1) es del **lado cliente**; H3 y el logging son del **lado server**.

- **PARITY-1 (cliente, H1).** En
  `fifa14-fut-client/tools/frida_pc_fut_nav_route_patch_trace.py`:
  `MATCH_BRIDGE_TRACE_ENABLED = false` por defecto (`:52`) → `installMatchBridgeTrace`
  no se instala en juego normal (comportamiento idéntico al gate
  `!RUNTIME_PERFORMANCE_MODE` del local, `:2590`). Nuevo flag `--diagnose`
  (default off) que gatea los hooks siempre-activos: `hookLongWaits` (umbral
  ≥2 s), per-socket I/O (`client-socket-io`) y los emits `client-connect-any`/
  `client-connect-result`/`client-dns-any`. El rewrite funcional de `connect()`
  (`REDIRECT_PORTS`, `:1048`) **queda siempre activo** (no es diagnóstico).
- **PARITY-3 (server, H3).** En `fifa14-fut-server/server/probe.py`: añadir
  `TCP_NODELAY` a los sockets aceptados (Blaze/redirector TLS/HTTP). Hoy solo
  se usan `SO_EXCLUSIVEADDRUSE` y `settimeout`; en loopback el sistema no aplica
  Nagle/delayed-ACK igual que en la NIC real, por eso la paridad exige
  `TCP_NODELAY` explícito.
- **PARITY-4 (server, logs/overhead).** Gatear los emits
  `easfc-command-debug` (`probe.py:1778`) y `blaze-unhandled-command`
  (`probe.py:1803`) tras un flag `--debug` (default off), igualando el logging
  del local y reduciendo el volumen/overhead por comando no manejado.
- **PARITY-2 (server, pack purchase — diferido).** Hipótesis revisada: el gap de
  17-19 s se resuelve al quitar el overhead (PARITY-1/3/4). **Si persiste** tras
  esos fixes, el siguiente paso es capturar las respuestas retail reales de
  UTIL 9/4 y 9/10 (SC-2) y reintroducir los handlers con el **TDF correcto**,
  reemplazando el intento `4971408` que rompió el login ("need proper TDF
  structures", revertido en `28b32f2`).

## Escenarios de verificación (sin tocar código)

- **SC-1.** Correlacionar en `frida.log` los bursts de `cards-match-bridge-*` con
  las ventanas donde el juego se pega (timestamps).
- **SC-2.** Correlacionar el gap de 17-19 s de una compra con los eventos
  `blaze-unhandled-command`/`easfc-command-debug` en `docker compose logs` del
  server: confirmar qué comando espera el cliente.
- **SC-3.** Medir latencia por request HTTP/Blaze en local vs remoto (timestamps
  de `frida.log` y RTT hacia `192.168.1.2:8099/42128`) para cuantificar H3.

## Riesgos residuales

- H2 requiere eventualmente un fix (fuera de alcance de esta spec): reintroducir
  UTIL 4/10 sin romper el login.
- H1 queda resuelto por PARITY-1 (trace off por defecto); el diagnóstico sigue
  disponible vía `--diagnose` cuando se necesite una sesión de telemetría.
- `fifa14-fut-server/.env` no existe en el repo (solo `.env.example`); confirmar
  en el despliegue real que `BLAZE_PUBLIC_HOST`/`ADMIN_SECRET` están definidos.