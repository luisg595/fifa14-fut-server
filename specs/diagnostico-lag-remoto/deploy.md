# Deploy — Paridad de rendimiento (split remoto)

Los cambios viven en **dos repos separados**; se despliegan por separado.

## 1. Server (Debian `192.168.1.2`)

```bash
cd /home/luisg595/fifa14-fut-server
git pull
./up.sh
```

- `up.sh` hace `docker compose up -d --build --pull always` y espera el
  healthcheck en `:8099`.
- El volumen `fifa14-state` (DB `/app/state/local-fut.sqlite3`) se conserva; la
  migración multi-cuenta es idempotente.

## 2. Cliente (laptop 2 con FIFA 14)

```bash
cd <ruta>/fifa14-fut-client
git pull
```

- Verificar `config.local.psd1` (ServerHost `192.168.1.2`, ServerHttpPort
  `8099`).
- Ejecutar como siempre `RUN_REMOTE_FUT.cmd` (o
  `tools\run_fifa14_remote_beta.ps1`).
- Juego normal: trace pesado **off** por defecto (paridad con local).
- Si se necesita telemetría: pasar `-Diagnose` (runner) o `--diagnose` (helper).

## 3. Verificación post-deploy

- [ ] Login completo e intacto (regresión prohibida).
- [ ] Navegación de FUT fluida (sin pegado), browsing de packs sin
      `cards-match-bridge-*` en `artifacts\frida.log`.
- [ ] Compra de packs sin gap de 17-19 s; si persiste, seguir `tasks.md` §5.

## 4. Opcional — sesión de diagnóstico

```bash
# Cliente, con telemetría activa:
.\tools\run_fifa14_remote_beta.ps1 -Diagnose
# Server, logs de comandos Blaze no manejados:
docker compose exec fifa14-fut python /app/server/probe.py --help  # --debug en args
docker compose logs -f fifa14-fut
```