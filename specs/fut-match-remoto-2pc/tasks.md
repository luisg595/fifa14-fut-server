# Tasks — FUT Match remoto 2 PCs (Fase 0: pre-vuelo + captura)

> Orden sugerido. Cada paso produce evidencia para `findings.md`. La Fase 0a es
> implementable sin captura y es prerrequisito de la 0b.

## 0a. Pre-vuelo

### 1. Identidad Blaze por persona (REQ-A1)

**Servidor:**
- [ ] **Añadir tabla IP→persona**: `client_ips(persona_id INTEGER PRIMARY KEY, client_ip TEXT NOT NULL UNIQUE, updated_at INTEGER NOT NULL)` en `LocalIdentityStore.__init__` (`local_identity.py:185-346`, patrón `CREATE TABLE IF NOT EXISTS` + migración `PRAGMA table_info` de `:348-352`). Nota: `persona_id` como PK → 1 persona = 1 PC; si cambia de PC, `UPDATE` (no insert).
- [ ] **Admin endpoint** `/__fifa14_local_fut_admin/bind_client` (patrón `X-Admin-Secret`, `probe.py:2507-2562`): recibe `{"account": ...}`, resuelve `resolve_persona(account)` (crea la persona si no existe, NO `lookup_account`) y graba `self.client_address[0] → persona_id` (patrón handler `probe.py:2584-2601`).
- [ ] **Nuevo método** `persona_id_for_client_ip(ip)` en `LocalIdentityStore` (copiar patrón de `persona_id_for_sid`, `local_identity.py:668`) y opcional `persona_name_for_id(persona_id)`.
- [ ] **Complementario `/ut/auth`**: grabar `self.client_address[0] → persona_id` en `start_session`/`resolve_persona` (`local_identity.py:570-652`) como redundancia.
- [ ] **Resolver en Blaze**: en `BlazeProbe.handle` (`probe.py:1617`) resolver `persona_id = persona_id_for_client_ip(self.client_address[0])` y usarlo en `build_origin_login_body` (`probe.py:1683-1684`), `build_post_auth_body` (`probe.py:1772`), `build_user_authenticated_body` (`probe.py:1911-1916`), `build_user_added_body` (`probe.py:1924-1931`), `build_user_extended_data_body` (`probe.py:1939`). Fallback a `1_000_001`.
- [ ] **Setear persona thread-local en Blaze**: tras resolver, `set_client_persona(persona_id)` en `BlazeProbe.handle` (hoy solo se setea en el hilo HTTP, `probe.py:2424-2432`/`:2601`; el hilo Blaze lo necesita para `has_club()` en `build_fetch_config_body` `probe.py:1741-1743` y `division_online` de REQ-A2).
- [ ] **Entitlements con persona (opcional)**: pasar `persona_id` (resuelto / `get_client_persona()`) a `build_entitlements_body` vía `build_shared_blaze_bootstrap_response` (`probe.py:1352`), que codifica `PID` default `1_000_001` (`probe.py:1305`) y corre en el hilo de Blaze (`probe.py:1795`).
- [ ] **Emit `blaze-identity`**: al resolver en `BlazeProbe.handle`, emitir `blaze-identity` (peer, persona_id, display_name) para que SC-A1 se verifique en los logs sin decodificar hex.

**Cliente (launcher-bind, decisión):**
- [ ] En `run_fifa14_remote_beta.ps1`, tras leer el username (`:23-36`), antes de lanzar el juego: POST a `http://${ServerHost}:${ServerHttpPort}/__fifa14_local_fut_admin/bind_client` con header `X-Admin-Secret` (patrón `give_coins_remote.ps1:32-33`) y body `{"account": $accountKey}`.
- [ ] **SC-A1**: 2 PCs con su username → verificar en `docker compose logs` que cada conexión Blaze (OriginLogin/PostAuth) usa su `player_id`/`display_name` (emit `blaze-identity`).

### 2. Advertir online (REQ-A2)

- [ ] Revisar el conjunto de señales: OSDK config (`probe.py:944-969`), account
      `onlineAccess` (`probe.py:62`), club `division_online`
      (`local_identity.py:536`), entitlements.
- [ ] Verificar que no hay un flag "offline-only" que oculte el modo online.
- [ ] **SC-A2**: confirmar que el menú FUT de ambas PCs ofrece **Season Online**
      visible y seleccionable (requiere el despliegue real con el juego en las 2
      PCs; depende de R11/H3). Si no aparece → contingencia H3 (punto 3).

### 3. Contingencia H3 (si SC-A2 falla)

- [ ] Documentar qué señal falta (OSDK/`division_online`/entitlements/config de
      cliente) y el plan de **parche de disco del cliente** (ruta NAV/estado,
      analogía `patch_fifa14_fut_dynamic_route.py`).
- [ ] NO continuar a la captura de matchmaking hasta resolver el bloqueo (si se
      resuelve por server, volver a SC-A2; si no, parche de disco).

## 0b. Captura

### 4. Habilitar `--debug` en el server (REQ-1)

- [ ] En `fifa14-fut-server/entrypoint.sh` (líneas 10-25), añadir `--debug` al
      `exec python /app/server/probe.py \` final.
- [ ] Rebuild: `./up.sh` en el Debian y verificar que los logs muestran
      `blaze-request` por frame (ya ocurre sin `--debug`; con él aparecen los
      eventos nuevos).

### 5. Preparar ambas PCs (REQ-2, R9)

- [ ] Confirmar `config.local.psd1` en cada PC: `ServerHost=192.168.1.2`,
      `ServerHttpPort=8099`, `AdminSecret` correcto.
- [ ] Confirmar que cada PC tiene su username y que `GIVE_100M_TEST_COINS.cmd`
      apunta a la cuenta correcta (`artifacts/fut-current-account.txt`).
- [ ] (Opcional) Instalar Wireshark o tener `pktmon` listo en cada PC para la
      captura de tráfico (REQ-4).

### 6. Sesión de captura (SC-1 → SC-3)

- [ ] **SC-1**: lanzar `RUN_REMOTE_FUT.cmd -Diagnose` en PC1 y PC2 (cada una con
      su username), entrar a FUT y verificar que cada una está en su persona.
- [ ] **SC-2**: en PC1 entrar a **Season Online** y anotar (timestamps):
      pantallas, botones, spinner de búsqueda, errores. Repetir en PC2.
- [ ] **SC-3**: con ambas en la cola a la vez, anotar si algún cliente intenta
      conectar al otro PC (evento `client-connect-any`/`local-connect-redirect`
      hacia `192.168.1.x` en `frida.log`, o tráfico en la captura).
- [ ] Guardar los logs: `docker compose logs` del server (con `--debug`),
      `artifacts/frida.log` + `.err/.out` de cada PC, y la captura de red.

### 7. Correlacionar y documentar (REQ-5, findings F1-F5)

- [ ] **F1**: ¿aparece "Season Online"? (si no, es bloqueo H3, no matchmaking).
- [ ] **F2**: comandos Blaze no manejados + peticiones HTTP nuevas al entrar a
      Season Online (componente/command/payload; buscar `blaze-unhandled-command`,
      `easfc-command-debug`, `unmapped-fut-route-local-ack`, `probe.py:4479-4499`).
- [ ] **F3**: dónde aprende cada cliente la dirección del rival (respuesta HTTP
      de matchmaking, notificación Blaze, o descubrimiento directo).
- [ ] **F4**: IP/puerto de la conexión P2P y quién hostea (H2).
- [ ] **F5**: ¿el partido online usa el mismo `/ut/game/fifa14/match`? ¿cómo se
      ligan las 2 sesiones (`beta_identity.py:1600-1628`)?
- [ ] Escribir `specs/fut-match-remoto-2pc/findings.md` con el mapa
      componente→respuesta, la línea de tiempo de la búsqueda y F1-F5.

## 8. Regresión offline (SC-4)

- [ ] Jugar un partido offline (Season o Torneo) tras la captura y confirmar que
      sigue funcionando (sin cambios en el server; solo `--debug`).
- [ ] (Opcional) Volver a `entrypoint.sh` sin `--debug` para el modo normal.

## 9. Cierre

- [ ] Commit de la spec + `findings.md` en `fifa14-fut-server`.
- [ ] Actualizar los riesgos de esta spec con los hallazgos reales y decidir el
      alcance de la **Fase 1** (emparejamiento mínimo: cola de 2 + notificar la
      dirección del rival según F2/F3) y la **Fase 2** (partido P2P + reporting
      según F5).

## Fase 1 — Emparejamiento mínimo (en curso)

### 10. Paso 1 — Decodificar el request de matchmaking (HECHO)

- [x] Capturar el payload completo de `component=4, command=13` (JoinQueue) en
      ambas PCs: `docker logs fifa14-fut --since 30m | grep '"kind":
      "blaze-request"' | grep -E '"fire_component": 4' | grep '"fire_command":
      13'` → campo `hex` (1682 B, idéntico salvo `futTeamOVR`, `matchSimilar` y
      el tail `PNET`). `command=14` = leave cola (`MSID=0`).
- [x] Decodificar con decoder TDF tolerante (type `0x09` = mapa): estructura
      completa en `spec.md` → "Análisis del request de matchmaking (Paso 1)".
- [x] Hallazgo F4: el request trae `PNET` con la IP LAN/puerto propio del
      cliente (PC1 `192.168.1.3:3659`) → el server ya dispone de la dirección
      del rival para emparejar.

### 10.5. Paso 1.5 — Desbloquear Season Online (hallazgo R13, vía secundaria)

- [x] **Bloqueo encontrado en el deploy 3a:** el cliente de Season Online pide
      `season/list?type=online` y el server responde solo seasons `OFFLINE`
      (`probe.py:4413-4443` ignora el query string) → "no pudo recuperar la
      temporada" y nunca emite `fire_component: 4`/`cmd 13` (grep vacío en la
      sesión del 2026-08-15).
- [x] Implementar `online_seasons_list()`/`online_season_user()` en
      `beta_identity.py` (mismo esquema nativo `_native_season_record` pero
      `"type": "ONLINE"`, divisiones 10→1, `matches` sin rival IA: `teamId: 0`,
      `difficulty: 0`) y dispatcher de `type` en el handler de
      `/ut/game/fifa14/season*`: `type=online` → online, resto → offline.
- [x] **Deploy + re-test 2026-08-15 17:38 (hallazgo R13.1):** el fix ONLINE se
      sirve a ambas PCs (`fut-online-seasons-beta2`, 15090 B, `"type": "ONLINE"`),
      pero el cliente **se comporta idéntico** al fallo OFFLINE: sondea
      `/fut/items/pc/-1.json` en bucle y nunca llega a `season/user` ni al
      componente 4. El `type` solo no desbloquea la pantalla.
- [x] **E1 + E2 implementados y pusheados (commit `81fa615`,
      `feat/fase0a-identidad-blaze-por-persona`), validados localmente:
      `py_compile` + smoke `--beta-mode` (ONLINE con 11 records, división 11
      provisional id 1, `trophyResourceId: 0`; OFFLINE intacto; `season/user`
      despacha por `type`).**
      - E1: `online_seasons_list()` antepone record provisional `divisionId: 11`
        (cubre `divisionList=11`); `online_season_user()` devuelve `divisionId: 11`.
      - E2: `_native_online_season_record()` usa `trophyResourceId: 0` (el
        cliente pide `0.json`, patrón OFFLINE aceptado, en vez de `-1.json`).
- [ ] **En pausa (vía secundaria):** el **Partido Directo Online** alcanza el
      `cmd 13` sin depender de `season/list` (R14, tarea 10.7), así que el
      emparejamiento mínimo no necesita E1/E2. Si se reactiva Season Online:
      deploy, re-test ambas PCs esperando avanzar tras `season/list` y llegar al
      `cmd 13`; si aún falla → frida para capturar los keys reales del parser.

### 10.7. Hallazgo partido directo online (R14) — HECHO 2026-08-15 18:21

- [x] **Captura con ambas PCs en Partido Directo Online** (grep en
      `docker logs fifa14-fut`):
      - `blaze-request`: 18:21:23 ambas PCs `fire_component: 4`,
        `fire_command: 13` (JoinQueue, `fire_length: 1682`) — el cmd 13 se
        alcanza **sin** `season/list`.
      - `http-probe`: 18:21:07/08 `POST /ut/game/fifa14/match`
        `{"squadId":N,"type":"ONLINE","customData1":-863122704}` (CreateMatch
        HTTP) precede al cmd 13 (F5: el directo usa el mismo `/match`).
      - `matchmaking-queue-join`: PC2 (brimar, persona 1000005) msid=1
        queue_size=1; PC1 (luisg595, persona 1000003) msid=2 queue_size=2;
        **misma `queue_key` `[3, 1039, "qa-only-day45", 1]`**. Después solo
        pings (componente 9 cmd 2) cada 30 s → el server responde `b""` al
        cmd 13 (F3 pendiente).
      - **PNET en este modo `ip: 0, port: 0`** (a diferencia de Season Online,
        que traía la IP LAN) → el cliente no se auto-bindea; el server debe
        entregar la dirección del rival en la respuesta/notificación (F3).
- [x] Documentado en `spec.md`: R14; H1/F2/F5 resueltos; Paso 3a deploy
      verificado; Paso 1.5b (E1/E2) degradado a vía secundaria.
- [ ] **Vía primaria confirmada:** el emparejamiento mínimo (Fase 1) se ataca por
      el **Partido Directo Online**, no por Season Online.

### 11. Paso 2 — Determinar el esquema de respuesta esperado (F3, hook frida)

- [x] Ampliar la captura del socket Blaze del redirector (42129) en
      `frida_pc_fut_nav_route_patch_trace.py` para frames `component==4` de
      forma persistente (hoy `hookRecv`/`hookWSARecv` solo capturan dentro de
      `TRUSTED_WINDOW_MS` = 180 s post-login; el matchmaking ocurre después y
      quedó fuera del log). Implementado: `consumeBlazeFrames()` (reensamblador
      FIRE por socket, emite `blaze-matchmaking-frame-recv` con hex completo +
      backtrace) conectado en `hookRecv` (onLeave) y `hookWSARecv` (onLeave,
      solo completación síncrona `retval >= 0` por ser overlapped) +
      `scanMatchmakingResponseTags()` (xrefs de tags TDF de respuesta en
      secciones ejecutables de `fifa14.exe` y `CardsDLLzf.dll`, emite
      `blaze-matchmaking-tag-xref`). Todo gated por `--diagnose`. `py_compile`
      OK, balance JS OK.
- [x] Correr sesión `--diagnose` en PC1 (`run_fifa14_remote_beta.ps1
      -Diagnose`) y entrar a **Partido Directo Online** (no Season Online,
      R14). **HECHO 2026-08-15 (R15):** capturó **1 frame** componente 4 — la
      respuesta del server al cmd 13 con `length: 0` (el `b""`), `seq 43`,
      `type 1`, socket 4116 → `192.168.1.2:42128`, backtrace fifa14.exe
      `0xd94b42 → 0xd9a389 → 0xf58194 → 0xf5b32a → 0xf5c63f → 0xf61886 →
      0xf61bc4 → 0x409df → 0x47c56 → 0x1e98ca`. Tras el frame, solo polls
      WSARecv + `client-long-wait` (Sleep 2 s) → cliente en spinner, sin cmd 14
      ni frames nuevos. **Conclusión:** el cliente no parsea la respuesta vacía
      → no se puede observar el esquema esperado sin enviar antes un cuerpo TDF.
- [x] **BUG detectado en el scan (R15):** 18/21 tags de
      `MATCHMAKING_RESPONSE_TAGS` no coinciden con `tdf_tag(name,0)[0..2]` del
      server (solo `TID`/`DUR`/`UED` correctos). Los "hits" de `BTPL`
      (`0x2647dc`/`0x1ae5e7c`/`0x4875074`) son falsos positivos (patrón malo
      `8b 4c 00` = opcode x86 común). El único xref confiable es `TID` rva
      `0x478c006`. Corregir los 18 tags antes de reusar el scan.
- [x] **Decisión F3 (R15):** dado que el cliente no parsea la respuesta vacía,
      abordar F3 por el **experimento de respuesta del cmd 13** (backup) en vez
      de cazar el parser a ciegas: responder al `cmd 13` con el esquema inferido
      de raíz (`TID`, `QCAP`, `NTOP`, `PNET`, `RNFO`) y observar qué comandos
      nuevos envía el cliente (`blaze-unhandled-command`/`blaze-response`).
- [x] **Resultado del experimento 3b (R16, 2026-08-15 19:13):** el server sirvió
      `matchmaking-join-queue-experiment` (80 B frame = 68 B body) y el cliente
      **aceptó** la respuesta: sin error, sin `cmd 14` (leave), sin retry, sin
      crash; tras el join solo `util-ping` (comp 9 cmd 2) cada ~30 s → queda
      **esperando rival** en la cola (`queue_size==1`, solo PC1). **F3 parte 1
      resuelta** (la respuesta del `cmd 13` se acepta); **F3 parte 2 abierta**
      (emparejamiento requiere notificación Blaze con el PNET del rival cuando
      `queue_size==2`).
- [ ] Localizar el RVA del parser de la respuesta TDF de matchmaking (análogo a
      `AUTH_RESPONSE_PARSER`/`CREATE_MATCH_RESPONSE_PARSER`, patrón
      `frida_pc_fut_nav_route_patch_trace.py:2726-2756`). **Lead (R16):** el scan
      corregido solo da xref para `GNAM` (rva `0xa549fe`, sección ejecutable);
      `TID@0x478c006` era falso positivo (hook no instalado, `executable()`
      falso). Hookear los hits **ejecutables** del scan e **identificar por
      timestamp** si `GNAM@0xa549fe` es el serializador del request (dispara al
      enviar cmd 13) o el parser de la respuesta (dispara al procesar la de 68 B)
      → volcar qué campos lee → esquema esperado (F3).
- [x] (Backup) Si el parser no aparece, responder al `cmd 13` con el esquema
      inferido (eco de raíz: `TID`, `QCAP`, `NTOP`, `PNET`, `RNFO`) y observar
      qué comandos nuevos envía el cliente en logs del server. **SELECCIONADO
      como vía principal (R15), EJECUTADO (R16).**
- [ ] **F3 parte 2:** confirmar que la IP del rival llega en una **notificación
      Blaze posterior** (cuando `queue_size==2`) y no en la respuesta del
      `cmd 13` (F3 resuelto).

### 12. Paso 3 — Implementar handler de matchmaking en `probe.py`

- [x] **3a (infraestructura, sin F3):** `MATCHMAKING_COMPONENT = 4`; cola en
      memoria por `(MODE`/`GSET`/`GVER`/`fifaMatchupHash)` con lock + MSID en
      `main_blaze`; helpers tolerantes `extract_matchmaking_key`/
      `extract_matchmaking_pnet`; dispatch `cmd 13` (join, responde `b""`,
      `matchmaking-join-queue-observed`) y `cmd 14` (leave); `purge_matchmaking_peer`
      en `blaze-session-ended`. Emit `matchmaking-queue-join`/`-leave`.
      Validado: `py_compile`, test de extractores OK, smoke OK.
- [x] **3a deploy (HECHO 2026-08-15 18:21):** commit/push + `git pull` +
      `./up.sh` en Debian; `matchmaking-queue-join` observado con ambas PCs en
      Partido Directo Online: misma `queue_key` `[3, 1039, "qa-only-day45", 1]`,
      queue_size 1→2 (R14). La cola, PNET y clave funcionan en producción.
- [x] **3b (RESULTADO R16 — experimento de respuesta cmd 13, backup R15):**
      `body = b""` sustituido por `build_matchmaking_join_queue_response()` (eco
      de raíz `TID`/`QCAP`/`NTOP`/`PNET`/`RNFO` más `BTPL`/`DUR`, decodifica OK
      con `decode_tdf_document`). **Deploy + verificado en producción
      2026-08-15 19:13:** el cliente recibe y acepta la respuesta de 68 B (sin
      error/leave/retry, esperando rival). F3 parte 1 resuelta. Pendiente:
      hookear hits ejecutables del scan (lead `GNAM@0xa549fe`, discriminar
      serializador vs parser) + emparejamiento activo (`queue_size==2` →
      notificar PNET del rival según F3) + deploy + re-test (Paso 4).

### 13. Paso 4 — SC-3 (emparejamiento de 2 PCs)

- [ ] Ambas PCs en **Partido Directo Online** a la vez → emparejar con la
      dirección del rival (según F3) y notificar (según F3).
- [ ] Verificar que el cliente intenta conectar al otro PC (P2P LAN, H2/F4:
      `client-connect-any`/`local-connect-redirect` en `frida.log`).

### 14. Paso 5 — Regresión y cierre

- [ ] **SC-4**: partido offline intacto.
- [ ] Escribir `specs/fut-match-remoto-2pc/findings.md` (mapa componente→respuesta
      + F1-F5 + esquema F3).
- [ ] Commit de spec/tasks/findings.