# FUT Multi-cuenta (Fase A)

## Objetivo

Que 2+ laptops se conecten al mismo `fifa14-fut-server` (Docker, Debian
`192.168.1.2`), cada una con **su propia cuenta**: persona, club, monedas,
items, torneos y récord separados. La cuenta actual (persona `1_000_001`) debe
quedar **intacta**.

## Restricciones verificadas (hechos del código)

- **R1.** `identity` es singleton: `singleton INTEGER PRIMARY KEY CHECK (singleton = 1)` — `server/local_identity.py:163`. **Imposible 2 personas sin migración de esquema.**
- **R2.** `_identity()` = `SELECT * FROM identity WHERE singleton = 1` (`server/local_identity.py:422-426`), usado en ~100 puntos (todos con `connection`, ninguno con contexto).
- **R3.** `sessions` upsert sobre `DEFAULT_SID` fijo (`server/local_identity.py:490-515`) → dos laptops se pisan la sesión.
- **R4.** El cliente **reenvía `X-UT-SID` en cada request** post-auth (verificado: `squad/list` → `X-UT-SID: LOCAL-FIFA14-SID`). El server controla el valor → puede emitir SIDs únicos.
- **R5.** El body `/ut/auth` incluye `identification.EASW-Session` (verificado), inyectado por Frida (`frida_pc_fut_nav_route_patch_trace.py:2631`) → canal natural para el nombre de cuenta.
- **R6.** `ThreadingHTTPServer` crea un thread por request → *thread-local* por request es seguro y no requiere cleanup.
- **R7.** `ensure_beta_starter_club` (`server/beta_identity.py:1162`) es idempotente **por persona** y provisiona club/squad/items/cosméticos para una persona nueva.
- **R8.** Los seeds de `beta_offline_seasons`/`beta_offline_tournaments`/`beta_accounts` corren **solo en `_initialize_beta_schema` para la persona del arranque** (`server/beta_identity.py:445-458`). **Una persona nueva no los tendría.**

## Requerimientos

- **REQ-1** `_identity()` resuelve la persona desde un *thread-local* `current_persona_id`; sin contexto → `1_000_001` (default). Ningún call-site cambia su firma.
- **REQ-2** Migración de `identity` a multi-fila keyed por `persona_id` (rebuild de tabla), **idempotente**, preservando la fila `1_000_001` existente.
- **REQ-3** Nueva tabla `local_accounts(account_key PK, persona_id UNIQUE, created_at)` con `resolve_persona(account_key)`: existente → su persona; nueva → allocate `persona_id = MAX+1`, insertar `identity` + `beta_accounts` + seeds + `ensure_beta_starter_club`.
- **REQ-4** Extraer los seeds por-persona (`beta_accounts`, `beta_offline_seasons`, `beta_offline_tournaments`) a un helper y llamarlo también para personas nuevas.
- **REQ-5** `start_session()` genera SID único `P<persona>-<rand>` y lo guarda en `sessions` (sin colisión entre laptops).
- **REQ-6** `_handle()` (HTTP) fija el thread-local desde `X-UT-SID` → `sessions.persona_id`.
- **REQ-7** `/ut/auth` extrae el nombre de cuenta del body (`identification.EASW-Session`) → `resolve_persona` → emite su SID.
- **REQ-8** `account_info()` devuelve solo la persona del contexto.
- **REQ-9** OriginLogin Blaze queda en default (`1_000_001`, cosmético para FUT) — limitación conocida, verificar en runtime.
- **REQ-10** Cliente: `run_fifa14_remote_beta.ps1` prompt "¿Con qué cuenta entras?" (vacío = cuenta actual) → `--account` al helper; helper escribe el nombre en el buffer `EASW-Session` (≤63 chars, buffer 64B).
- **REQ-11** Seeds de arranque (`_initialize_beta_schema`, `ensure_beta_starter_club`, `prepare_state.py`) usan persona default.

## Escenarios

- **SC-1** Login default → persona `1_000_001`, club/monedas intactos (regresión prohibida).
- **SC-2** Nueva cuenta (`--account laptop2`) → persona nueva `1_000_002`, club starter, 0 monedas, seeds de torneos/season presentes.
- **SC-3** Re-login misma cuenta → misma persona, no se duplica.
- **SC-4** Dos laptops simultáneas → SIDs distintos, ninguna derriba la otra; `accountinfo` distinto por SID.
- **SC-5** Reinicio server → `local_accounts` persiste (volumen), cuentas mapean a las mismas personas.
- **SC-6** Migración DB existente → fila `1_000_001` conservada, `sessions` con SID viejo migrado o reemplazado sin error.
- **SC-7** Comportamiento Blaze → partido/torneo siguen funcionando con default player_id.

## Riesgos residuales

- OriginLogin cosmético (SC-7): si el cliente valida `nuc` contra `accountinfo` en runtime, ajustar Blaze por conexión (verificar en pruebas).
- HUD W-D-L (`read_local_record`, `--identity-db`) es local/cosmético: en laptop B opcional apuntar a otra DB.
- Clave es el nombre de cuenta (string libre): limitar a `[A-Za-z0-9_-]{1,63}` para evitar colisiones/caracteres raros.