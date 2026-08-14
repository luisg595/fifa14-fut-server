#!/usr/bin/env bash
set -e

docker compose up -d --build --pull always

echo "Esperando a que el server responda en :8099 ..."
for i in $(seq 1 120); do
  if curl -fsS http://127.0.0.1:8099/__fifa14_local_fut_health >/dev/null 2>&1; then
    echo "Server listo tras ${i}s"
    break
  fi
  sleep 1
  if [ "$i" -eq 120 ]; then
    echo "Timeout esperando al healthcheck" >&2
    exit 1
  fi
done

server_host=$(hostname -I 2>/dev/null | awk '{print $1}')
if [ -n "$server_host" ]; then
  echo
  echo "ServerHost (pega en config.local.psd1 del cliente): $server_host"
fi
