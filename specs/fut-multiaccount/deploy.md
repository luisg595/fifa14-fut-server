# Deploy Fase A — FUT Multi-cuenta

## 1. Subir los cambios al Debian

Solo 3 archivos del server cambiaron:

- `server/local_identity.py`
- `server/beta_identity.py`
- `server/probe.py`

Subir a `/home/luisg595/fifa14-fut-server/` (mantener estructura `server/...`).

## 2. Rebuild del contenedor

```bash
cd /home/luisg595/fifa14-fut-server
./up.sh
```

El volumen con la DB (`/app/state/local-fut.sqlite3`) se conserva; `_initialize`
detecta el esquema legacy (`singleton`) y lo migra a multi-fila de forma
idempotente, preservando la fila `1_000_001`.

## 3. Verificación en server

```bash
docker compose exec fifa14-fut sh -c 'python -c "from probe import *"'  # o importar BetaIdentityStore si es Python en el contenedor
```

Comandos recomendados (dentro del contenedor, con la DB de producción):

```bash
# 1) La tabla identity ya no tiene 'singleton'
sqlite3 /app/state/local-fut.sqlite3 "PRAGMA table_info(identity);"
# 2) Debe existir local_accounts con la fila default (account_key='', persona_id=1000001)
sqlite3 /app/state/local-fut.sqlite3 "SELECT * FROM local_accounts;"
# 3) La persona 1000001 sigue con su club/monedas
sqlite3 /app/state/local-fut.sqlite3 "SELECT persona_id,club_name,coins FROM clubs WHERE persona_id=1000001;"
```

## 4. Prueba en las laptops

En la laptop **cuenta actual**: ejecutar `RUN_REMOTE_FUT.cmd` y pulsar Enter en el
prompt (cuenta default). Debe entrar en la misma cuenta de siempre (SC-1).

En la **segunda laptop** (o la misma, sin tocar la primera): ejecutar y escribir
un nombre de cuenta, p. ej. `laptop2`. Debe crear la persona `1_000_002` con club
starter, 0 monedas y torneos/season presentes (SC-2). Re-login con el mismo nombre
no duplica (SC-3).

## 5. Logs de diagnóstico

Tras un `/ut/auth`, buscar en `docker compose logs` (o `frida.log` en el cliente)
el evento `fut-ut-auth-account` con `account_key` y `persona_id`, que confirma qué
cuenta resolvió cada login. En cada request el server re-resuelve la persona desde
`X-UT-SID` (REQ-6); dos laptops simultáneas usan SIDs distintos (SC-4).

## 6. Regresión

Confirmar SC-5 (reinicio del server conserva las cuentas) y SC-7 (el partido/torneo
sigue funcionando con el default player_id en Blaze).