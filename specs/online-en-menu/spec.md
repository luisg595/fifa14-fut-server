# Online en el menú FUT (integración del stash + verificación SC-A2)

## Objetivo

Que el menú FUT de ambas PCs muestre el **modo online** (indicador Online +
**Season Online** / **Partido Directo Online** visibles y seleccionables) al
conectarse al `fifa14-fut-server` (Docker, Debian `192.168.1.2`). Es el
prerrequisito (REQ-A2/SC-A2 de `specs/fut-match-remoto-2pc`) para poder jugar
online entre 2 PCs.

**El trabajo online ya existe pero NO está en ninguna rama**: vive solo en el
stash `stash@{0}` = `b38406e` de `fifa14-fut-server` (rama borrada
`feat/fase0a-identidad-blaze-por-persona`). Esta spec cubre:

1. **Integración**: la rama `feat/online-en-menu` sale de `main` (multi-squad);
   el trabajo online del stash se integra en ella como **un único commit**
   (`git merge --squash b38406e`) resolviendo conflictos y subiendo la rama a
   origin (el PR/merge final lo hace el usuario).
2. **Cliente**: registrar la IP de cada PC (`bind_client`) desde el launcher
   antes de abrir el juego, para que Blaze resuelva la identidad de cada persona.
3. **Verificación**: confirmar el conjunto de señales de "online" del backend
   (REQ-A2) y el escenario SC-A2 en ambas PCs con el juego real.

Alcance NO incluido (fases posteriores): emparejamiento activo
(`queue_size==2` → notificación PNET del rival, F3 parte 2), partido P2P y
reporting. Esa lógica queda implementada en el server desde el stash pero **no
se activa ni se prueba** en esta fase salvo que SC-A2 se cumpla.

## Restricciones verificadas (hechos del código)

- **R1.** El stash `b38406e` (rama `feat/fase0a-identidad-blaze-por-persona`
  borrada) contiene TODO el trabajo online:
  - `server/beta_identity.py` (+83): `_online_season_matches`,
    `_native_online_season_record` (type ONLINE, `trophyResourceId: 0` = E2),
    `online_seasons_list()` (división 11 provisional prepended = E1),
    `online_season_user()`.
  - `server/local_identity.py` (+61): tabla `client_ips(persona_id PK,
    client_ip UNIQUE, updated_at)`, `start_session(client_ip=...)` que hace
    bind redundante en `/ut/auth`, `bind_client_ip()`,
    `persona_id_for_client_ip()`, `persona_name_for_id()`.
  - `server/probe.py` (+374): `MATCHMAKING_COMPONENT = 4`, helpers
    `extract_matchmaking_key`/`extract_matchmaking_pnet`,
    `build_matchmaking_join_queue_response` (experimento cmd 13, R16),
    `purge_matchmaking_peer`, cola en memoria en `main_blaze`
    (`matchmaking_queue`/`matchmaking_lock`/`matchmaking_next_msid`), dispatch
    cmd 13 (join, `matchmaking-queue-join`) y cmd 14 (leave), admin endpoint
    `/__fifa14_local_fut_admin/bind_client`, resolución de identidad Blaze por
    IP en `BlazeProbe.handle` (player_id/display_name en OriginLogin/PostAuth/
    UserAuthenticated/UserAdded/UserExtendedData), dispatcher de `type` en
    `/ut/game/fifa14/season*` (online vs offline).
  - `entrypoint.sh` (+1): `--debug` añadido al `exec python probe.py`.
  - `specs/fut-match-remoto-2pc/{spec,tasks,deploy}.md` (spec completa de la
    Fase 0/1 con hallazgos R13-R16).
- **R2.** `main` = `52af29b` (multi-squad `feat(multi-squad)` #1). NO tiene el
  trabajo online. Contiene además `dev/summarize_fifa14_squad_requests.py` y
  `dev/verify_fifa14_multi_squad.py` que el stash no tiene.
- **R3.** `git merge-base main b38406e` = `f76e4fb`; `52af29b` NO es ancestro de
  `b38406e` ni `b38406e` de `main` → integración = merge real con conflictos.
  `git diff main b38406e` = +1499/−559 (9 archivos; `dev/*` se eliminarían si se
  tomara el stash tal cual → hay que conservarlos de main).
- **R4.** Punto de conflicto esperado: `server/beta_identity.py` (main trae
  multi-squad; stash trae seasons online). `probe.py`, `local_identity.py` y
  `entrypoint.sh` también tocan ambos lados en zonas distintas (bajo riesgo de
  conflicto, verificar al mergear).
- **R5.** Cliente (`fifa14-fut-client`, `main` = `ef68825`): el launcher
  `run_fifa14_remote_beta.ps1` pide username obligatorio (líneas 23-37), hace
  health check (líneas 50-77) y lanza el juego (línea 106+). **NO tiene** el
  POST de `bind_client` antes de lanzar el juego. Patrón de referencia:
  `tools/give_coins_remote.ps1:14,33` (POST a `/__fifa14_local_fut_admin/...`
  con header `X-Admin-Secret`).
- **R6.** Señales "online" ya anunciadas por el backend (REQ-A2): account
  `onlineAccess: True` (`probe.py:62`), config OSDK `FUT_ENABLE_MENU=1`,
  `FUT/IS_RETURNING_USER`, `FUT_SKIP_ICEBREAKER_FLOW` (`probe.py:944-969`),
  `division_online` del club (`local_identity.py:536`), entitlements
  `FIFA14PCFUTContentUnlocks` con persona. No hay un flag "online" único ni un
  flag "offline-only" que oculte el modo online → verificar el conjunto.
- **R7.** Hallazgo R13.1 (ya documentado en la spec del stash): servir
  `season/list?type=online` por sí solo NO desbloquea Season Online (el cliente
  sondea `/fut/items/pc/-1.json` en bucle y no llega al cmd 13). E1 (división
  11 provisional) + E2 (`trophyResourceId: 0`) están implementados pero la vía
  primaria es el **Partido Directo Online** (R14: alcanza `fire_component: 4`
  cmd 13 sin depender de `season/list`).
- **R8.** El server en producción corre en Debian `192.168.1.2`
  (`/home/luisg595/fifa14-fut-server`), volumen `docker` conserva la DB
  (`/app/state/local-fut.sqlite3`). `./up.sh` requiere `.env` con
  `BLAZE_PUBLIC_HOST` y `ADMIN_SECRET`. Health: `http://192.168.1.2:8099/
  __fifa14_local_fut_health` (valida `buildVersion == 2.41.1-beta2.25.9` en el
  launcher).

## Requerimientos

- **REQ-1** Rama `feat/online-en-menu` creada desde `main`. Integrar el trabajo
  online del stash (`b38406e`) como **un único commit** (`git merge --squash
  b38406e`), resolviendo conflictos y conservando **ambos** trabajos
  (multi-squad de main + online del stash) y **todos** los archivos `dev/*` de
  main.
- **REQ-2** Verificar que la rama integrada compila y arranca: `py_compile` de
  `server/*.py` + smoke `--beta-mode` que sirva offline seasons intactas,
  online seasons (11 records, división 11 provisional) y multi-squad sin
  regresiones.
- **REQ-3** Subir `feat/online-en-menu` a origin. El PR/merge a `main` lo hace
  el usuario después de las pruebas.
- **REQ-4** Cliente: en `run_fifa14_remote_beta.ps1`, tras leer el username y
  pasar el health check, y **antes** de lanzar el juego: POST a
  `http://${ServerHost}:${ServerHttpPort}/__fifa14_local_fut_admin/bind_client`
  con header `X-Admin-Secret` (patrón `give_coins_remote.ps1:33`) y body
  `{"account": $accountKey}`. Validar `bound: true` y anotar
  `persona_id`/`client_ip`.
- **REQ-5** Verificar el conjunto de señales online (REQ-A2): confirmar que
  ninguna de las respuestas del server fuerza modo offline (account
  `onlineAccess`, OSDK config, `division_online`, entitlements).
- **REQ-6** Deploy en el Debian: `git fetch && git checkout feat/online-en-menu
  && git pull && ./up.sh` (con `.env` correcto) y confirmar health.
- **REQ-7** SC-A2: en ambas PCs, entrar a FUT y confirmar que el menú ofrece el
  modo online (indicador Online + Season Online / Partido Directo Online
  visible y seleccionable). Verificar en logs: `blaze-identity` (cada PC en su
  persona), `fut-online-seasons-beta2`, `matchmaking-queue-join`.
- **REQ-8** Si SC-A2 falla → **contingencia H3**: documentar qué señal falta
  (OSDK / `division_online` / entitlements / config de cliente) y el plan del
  parche de disco del cliente (analogía `patch_fifa14_fut_dynamic_route.py`).
  No continuar al emparejamiento activo hasta resolverlo.

## Escenarios

- **SC-1** Rama `feat/online-en-menu` compila y el server arranca con el set de
  args de producción: offline seasons intactas, online seasons servidas por
  `type=online`, multi-squad operativo.
- **SC-2** El launcher de cada PC registra su IP (`bind_client` → `bound:
  true`, `persona_id` correcto por username) antes de abrir el juego.
- **SC-3** Cada conexión Blaze resuelve su persona por IP (log `blaze-identity`
  con `player_id`/`display_name` distintos por PC).
- **SC-4** (`SC-A2`) El menú FUT de ambas PCs ofrece el modo online visible y
  seleccionable (Partido Directo Online al menos; Season Online si E1/E2
  desbloquean la pantalla).
- **SC-5** Regresión offline: un partido offline (Season o Torneo) sigue
  funcionando sin cambios de comportamiento.
- **SC-6** Si SC-4 falla → H3: señal que falta identificada y parche de disco
  documentado.

## Riesgos residuales

- **Conflicto de merge** en `beta_identity.py` (multi-squad vs seasons online):
  mitigar resolviendo a mano y validando con smoke `--beta-mode`.
- **R13.1** (Season Online puede seguir sin desbloquearse con solo el server):
  vía primaria es Partido Directo Online (R14); E1/E2 quedan como vía
  secundaria, sin bloquear SC-A2.
- **Reachability**: si `192.168.1.2:8099` no responde al health check, el
  launcher aborta (timeout 60 s). Confirmar el server y el `.env` antes de
  probar SC-4.
- **`--debug` activo** en producción (del stash): añade logs ruidosos
  (`blaze-unhandled-command`, etc.); es intencional para esta fase de
  verificación, revisar si se quita en el PR final.
- **Bind redundante `/ut/auth`**: al añadir `client_ip` a `start_session`, el
  bind ocurre igual aunque el launcher no lo haya hecho (defensa extra, sin
  efecto lateral negativo conocido).
