# Deploy — Online en el menú FUT (integración stash + verificación SC-A2)

Topología: server Debian `192.168.1.2` (Docker, `/home/luisg595/fifa14-fut-server`)
+ 2 PCs Windows en la misma LAN, cada una con su username. Primero la
integración del stash a una rama, luego el despliegue del server y del launcher,
y finalmente la verificación SC-A2.

## 1. Rama de integración (en la máquina de desarrollo)

La rama `feat/online-en-menu` sale de `main` (multi-squad); el trabajo online
del stash se integra como un único commit:

```bash
cd /path/to/fifa14-fut-server
git merge --squash b38406e    # integra el trabajo online del stash (1 commit)
# resolver conflictos conservando ambos trabajos + dev/* de main
# py_compile server/*.py + smoke --beta-mode
git commit
git push -u origin feat/online-en-menu
```

El PR/merge final a `main` lo hace el usuario tras las pruebas.

## 2. Server (Debian 192.168.1.2)

```bash
cd /home/luisg595/fifa14-fut-server
git fetch
git checkout feat/online-en-menu
git pull
# revisar .env: BLAZE_PUBLIC_HOST + ADMIN_SECRET
./up.sh
curl http://192.168.1.2:8099/__fifa14_local_fut_health
docker compose logs -f fifa14-fut   # confirmar --debug activo
```

La DB (`/app/state/local-fut.sqlite3`) se conserva (volumen); las cuentas
existentes siguen mapeando a las mismas personas (multi-cuenta R8). Al primer
arranque se crea la tabla `client_ips` (idempotente).

## 3. Cliente (cada PC)

- Pull de `fifa14-fut-client` con el cambio de `bind_client` en
  `tools/run_fifa14_remote_beta.ps1`.
- Verificar `config.local.psd1`: `ServerHost=192.168.1.2`,
  `ServerHttpPort=8099`, `AdminSecret` correcto.

## 4. Verificación (SC-A1 / SC-A2)

En cada PC, con su username: `RUN_REMOTE_FUT.cmd -Diagnose`.

- **SC-2**: el launcher registra la IP (`bind_client` → `bound: true`,
  `persona_id` correcto) antes de abrir el juego.
- **SC-3**: en los logs del server, cada conexión Blaze muestra su
  `player_id`/`display_name` (emit `blaze-identity` por conexión).
- **SC-4 (SC-A2)**: el menú FUT ofrece el modo online (indicador Online +
  Partido Directo Online / Season Online visible y seleccionable).

Evidencia a guardar: `docker compose logs` (grep `blaze-identity`,
`fut-online-seasons-beta2`, `matchmaking-queue-join`), `artifacts/frida.log`
de cada PC, capturas de pantalla del menú.

## 5. Si SC-A2 falla (H3)

Parar. Documentar qué señal falta (OSDK / `division_online` / entitlements /
config de cliente) y el plan del parche del cliente (analogía
`patch_fifa14_fut_dynamic_route.py`). No continuar al emparejamiento activo.

**Estado verificado (2026-08-19):** SC-A2 falló. Los 3 experimentos de la
Fase 1 (`persona_status=1` en `bddc524`, `lastOnlineTime=now` en `3432927`,
claves `EASW/ENABLED`+`OSDK_EASW_*_URL` en `a5be17c`) fueron desplegados por
el usuario y todos negativos: el indicador sigue "sin conexión a EAS FC" y el
juego nunca dialó EASW (no hay `easw-http-request` en `docker compose logs`).
El indicador lo decide la capa EASW del shell (sesión null) y `fifa14.exe`
está empaquetado/cifrado, así que el plan del cliente es un hook Frida en
runtime sobre el imagen descifrado que fuerce `EASW_STATE=CONNECTED`. Detalle
en `spec.md` §H3.

## 6. Regresión offline

Un partido offline (Season o Torneo) debe seguir funcionando (SC-5).
