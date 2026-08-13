# fifa14-fut-server

Servidor local persistente del split remoto de **FIFA 14 Local FUT** (v2.41.1 BETA 2.25.9).
Se despliega en Debian/Docker y lo consume el proyecto Windows `fifa14-fut-client`.

## Puesta en marcha

```bash
cp .env.example .env
# Editar .env: BLAZE_PUBLIC_HOST = IP-LAN de este host; ADMIN_SECRET = secreto compartido
./up.sh
```

`up.sh` construye, levanta el contenedor y espera al healthcheck. `down.sh` lo detiene.

La IP-LAN del host se imprime al final de `up.sh`; ese valor es el `ServerHost` que el cliente
pega en `config.local.psd1`.

## Orden recomendado

1. `./up.sh` (inicia el server; el report de match-assets aún no existe → warning en stderr).
2. En el cliente Windows: `INSTALL_GAME_PATCHES.cmd` (sube el report de match-assets).
3. Primera sesión de juego desde el cliente.

## Endpoints HTTP (puerto 8099)

- `GET /__fifa14_local_fut_health` — health con `buildVersion`, `hasClub`, `profileKind`, `samplePlayer`.
- `GET /__fifa14_local_fut_ca` — descarga `old-protossl-otg3-ca.pem` (cert-dir persistente).
- `POST /__fifa14_local_fut_upload_match_assets` — `X-Admin-Secret`; escribe el report en `artifacts/`.
- `POST /__fifa14_local_fut_admin/give_coins` — `X-Admin-Secret`; body `{"coins": N}`; fija el balance (idempotente).

## Admin manual

```bash
./admin/give_coins.sh 100000000
python admin/prepare_state.py --database /app/state/local-fut.sqlite3
```

## Contenido

- `server/` — `probe.py` + identidades + catálogos + `sitecustomize.py` (contrato DNF/QUIT→LOSS).
- `admin/` — init de estado y utilidad de monedas.
- `dev/` — verifiers y herramientas experimentales del repo de referencia (no entran en la imagen).
