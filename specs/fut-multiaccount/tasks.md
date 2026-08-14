# Tasks — FUT Multi-cuenta (Fase A)

## 1. Migración `identity` multi-fila (REQ-2)

- [x] En `server/local_identity.py::_initialize`: tras el `executescript` de DDL, detectar esquema legacy (`PRAGMA table_info(identity)` con columna `singleton`).
- [x] Si es legacy: rebuild de `identity` keyed por `persona_id` (crear `identity_multi`, copiar fila existente, `DROP` + `RENAME`), resiliente ante crash a medio camino.
- [x] `local_accounts` creada en la DDL base (DBs frescas) e insertada para la persona default.
- [x] Actualizar `CREATE TABLE IF NOT EXISTS identity` para reflejar el esquema nuevo en DBs frescas.

## 2. Thread-local + `_identity()` por persona (REQ-1)

- [x] Añadir `_CLIENT_CONTEXT = threading.local()` a nivel de módulo en `local_identity.py`.
- [x] Funciones `set_client_persona(persona_id)`, `get_client_persona()`, `clear_client_persona()`.
- [x] Reescribir `_identity(connection)`: resolver `persona_id` (thread-local) → `SELECT * FROM identity WHERE persona_id = ?`; sin contexto → default `1_000_001`.

## 3. Tabla `local_accounts` + `resolve_persona()` (REQ-3)

- [x] `CREATE TABLE IF NOT EXISTS local_accounts (account_key TEXT PRIMARY KEY, persona_id INTEGER NOT NULL UNIQUE, created_at INTEGER NOT NULL)`.
- [x] `resolve_persona(account_key) -> int` (bajo `_lock`): cuenta existente → su persona; nueva → `persona_id = MAX(persona_id)+1`, insertar fila `identity` (persona_name `LocalFUT-<key>`), registrar en `local_accounts`, invocar `_provision_persona`.
- [x] Validar `account_key`: `[A-Za-z0-9_-]{1,63}`; vacío/sentinel `LOCAL-FIFA14-EASW-SESSION` → persona default.
- [x] `persona_id_for_sid(sid) -> int|None` (incluye fallback de `LOCAL-FIFA14-SID` legacy → default).

## 4. Helper seeds por persona nueva (REQ-4)

- [x] En `server/beta_identity.py`: extraído a `_seed_beta_persona_locked(connection, persona_id, now)` el bloque de seeds (beta_accounts + offline_seasons + offline_tournaments) de `_initialize_beta_schema`.
- [x] Llamado desde `_initialize_beta_schema` y desde el provisioning de persona nueva (`_provision_persona` → `ensure_beta_starter_club`).
- [x] Persona nueva recibe torneos/season listos y club starter (SC-2 verificado en smoke).

## 5. `start_session()` SID único + parse `EASW-Session` (REQ-5)

- [x] En `server/local_identity.py::start_session`: extraer `identification.EASW-Session` del body JSON.
- [x] Si es un nombre de cuenta válido → `resolve_persona` y fijar thread-local.
- [x] Generar SID `P<persona>-<rand>` (secrets.token_hex) y upsert en `sessions` con ese SID (ya no `DEFAULT_SID`).
- [x] Devolver el SID único (el cliente lo reenvía como `X-UT-SID`, R4).

## 6. `_handle()` HTTP thread-local desde `X-UT-SID` (REQ-6)

- [x] En `server/probe.py::_handle`: leer header `X-UT-SID`.
- [x] Si es SID conocido → `persona_id_for_sid` → `set_client_persona`; si no → default (`set_client_persona(None)` al inicio de cada request).
- [x] Cada request es un thread nuevo (`ThreadingHTTPServer`) → no requiere cleanup final.

## 7. `/ut/auth` resuelve cuenta → SID (REQ-7)

- [x] En `server/probe.py` handler `/ut/auth`: `start_session(body)` devuelve el SID único; `EASW-Session` del body llega al server (R5).
- [x] Emitir `fut-ut-auth-account` con `account_key`/`persona_id`/`sid` para diagnóstico.

## 8. Persona default en arranque (REQ-11)

- [x] `_initialize_beta_schema` / `ensure_beta_starter_club` corren sin contexto → default `1_000_001` (thread principal sin `set_client_persona`).
- [x] `admin/prepare_state.py` sin cambios (usa `existing` → persona default).
- [x] `validate_phishing_answer` corregido: `UPDATE identity SET trusted WHERE persona_id = ?` (ya no depende de `singleton`).

## 9. Cliente: prompt de cuenta (REQ-10)

- [x] En `run_fifa14_remote_beta.ps1`: `Read-Host` de cuenta (Enter = cuenta actual), validación `[A-Za-z0-9_-]{1,63}`.
- [x] Pasar `--account <nombre>` al helper Frida.
- [x] Si está vacío → omitir el flag (default).

## 10. Frida: `--account` → buffer EASW (REQ-10)

- [x] En `frida_pc_fut_nav_route_patch_trace.py`: nuevo arg `--account` (default `""`).
- [x] `build_agent(..., easw_session_value)` reemplaza `__EASW_SESSION_VALUE__`; al alocar `localEaswSessionPointer` usa el nombre de cuenta (≤63 chars, buffer 64B).
- [x] `read_local_record`/`read_local_badge` tolerantes al esquema nuevo (sin `singleton`).

## 11. Verificación

- [x] Smoke local: DB legacy migrada, dos cuentas, SIDs únicos, `accountinfo`/`squad` aislados por persona, sentinel default mapea a `1_000_001`.
- [ ] Guía de deploy en `specs/fut-multiaccount/deploy.md` → probar `./up.sh` en Debian.
- [ ] SC-1 a SC-7 en runtime real (ver `deploy.md`).