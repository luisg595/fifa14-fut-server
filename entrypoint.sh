#!/usr/bin/env bash
set -euo pipefail

mkdir -p /app/state /app/artifacts /app/certs

export PYTHONPATH=/app/server

python /app/admin/prepare_state.py --database /app/state/local-fut.sqlite3

exec python /app/server/probe.py \
  --host 0.0.0.0 \
  --main-blaze-host "${BLAZE_PUBLIC_HOST:?BLAZE_PUBLIC_HOST no está definido (revisa .env)}" \
  --blaze-port 42129 \
  --main-blaze-port 42128 \
  --http-port 8080 \
  --fut-http-port 8099 \
  --dynamic-http-port 8306 \
  --gosca-port 44125 \
  --enable-gosca --gosca-reply xml \
  --redirector-mode tls --redirector-reply local \
  --cert-hostname gosredirector.ea.com --cert-hash old-protossl \
  --cert-dir /app/certs \
  --identity-db /app/state/local-fut.sqlite3 \
  --beta-mode --fut-account-mode existing \
  --admin-secret "${ADMIN_SECRET:?ADMIN_SECRET no está definido (revisa .env)}"
