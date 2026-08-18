# Tasks — Online en el menú FUT

> Orden sugerido. Evidencia por paso en los logs/`py_compile`/smoke.

## 1. Integración (fifa14-fut-server)

### 1.1. Integrar el trabajo online (rama ya sale de main)

- [ ] Rama `feat/online-en-menu` ya creada desde `main` (52af29b) + spec.
- [ ] `git merge --squash b38406e` → integra el trabajo online del stash como
      **un único commit** (sin la historia de 14 commits). Resolver conflictos
      conservando:
      - de `main`: multi-squad (`dev/verify_fifa14_multi_squad.py`,
        `dev/summarize_fifa14_squad_requests.py`, cambios multi-squad de
        `beta_identity.py`).
      - del stash: seasons online, tabla `client_ips`, `bind_client`, identidad
        Blaze por IP, cola matchmaking cmd 13/14, `--debug`.
- [ ] `py_compile` de `server/*.py` OK.
- [ ] Smoke `--beta-mode`: servir offline seasons intactas + online seasons
      (`type=online`, 11 records, división 11 provisional) + multi-squad sin
      regresión.
- [ ] Commit del merge resuelto.

### 1.2. Subir la rama

- [ ] `git push -u origin feat/online-en-menu` (el PR/merge a main lo hace el
      usuario tras las pruebas).

## 2. Cliente (fifa14-fut-client)

### 2.1. `bind_client` en el launcher

- [ ] En `tools/run_fifa14_remote_beta.ps1`, tras el health check OK y antes de
      lanzar el juego: POST a
      `http://${ServerHost}:${ServerHttpPort}/__fifa14_local_fut_admin/bind_client`
      con header `X-Admin-Secret` (patrón `give_coins_remote.ps1:33`) y body
      `{"account": $accountKey}`.
- [ ] Validar respuesta `bound: true` y escribir `persona_id`/`client_ip` en el
      log del launcher.
- [ ] Regresión: si el POST falla (server viejo sin el endpoint), el launcher
      debe **avisar pero no bloquear** el arranque (fallback degradado), o
      bloquear según decisión. Documentar la elección.

## 3. Verificación REQ-A2 (señales online)

- [ ] Confirmar en el server integrado que el conjunto anuncia online: account
      `onlineAccess: True`, OSDK `FUT_ENABLE_MENU=1`, `division_online` del
      club, entitlements con persona. Sin flag "offline-only".
- [ ] Registrar la lista de respuestas/emits que evidencian online
      (`blaze-identity`, `fut-online-seasons-beta2`, `matchmaking-queue-join`).

## 4. Deploy (Debian 192.168.1.2)

- [ ] En `/home/luisg595/fifa14-fut-server`:
      `git fetch && git checkout feat/online-en-menu && git pull`.
- [ ] Confirmar `.env` con `BLAZE_PUBLIC_HOST` y `ADMIN_SECRET`.
- [ ] `./up.sh` y confirmar health en
      `http://192.168.1.2:8099/__fifa14_local_fut_health`.
- [ ] Verificar en `docker compose logs` que arrancó con `--debug` y que la DB
      migró/convive con las cuentas existentes.

## 5. Verificación SC-A2 (ambas PCs)

- [ ] PC1 y PC2 con su username: `RUN_REMOTE_FUT.cmd -Diagnose`.
- [ ] Confirmar `bind_client` OK en cada PC (SC-2).
- [ ] Confirmar `blaze-identity` con persona/display_name por PC en los logs
      (SC-3).
- [ ] Entrar a FUT en cada PC y confirmar que el menú ofrece el modo online:
      indicador Online + **Partido Directo Online** (vía primaria, R14) y
      **Season Online** (vía secundaria, E1/E2) — SC-4/SC-A2.
- [ ] Regresión offline: un partido offline funciona (SC-5).
- [ ] Guardar evidencias: `docker compose logs`, `artifacts/frida.log` de cada
      PC, capturas de pantalla del menú.

## 6. Contingencia H3 (si SC-A2 falla)

- [ ] Documentar qué señal falta (OSDK / `division_online` / entitlements /
      config de cliente) y el plan del parche de disco del cliente (analogía
      `patch_fifa14_fut_dynamic_route.py`).
- [ ] NO continuar al emparejamiento activo hasta resolver el bloqueo.

## 7. Cierre

- [ ] Actualizar esta spec/tasks con los hallazgos reales y los logs de
      evidencia.
- [ ] Commit en `feat/online-en-menu` (spec + hallazgos) y push.
- [ ] Si todo OK: el usuario crea el PR y mergea a `main`.
