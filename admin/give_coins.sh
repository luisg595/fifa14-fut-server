#!/usr/bin/env bash
set -euo pipefail

: "${ADMIN_SECRET:?ADMIN_SECRET no está definido (revisa .env)}"

coins="${1:-100000000}"

curl -s -X POST "http://127.0.0.1:8099/__fifa14_local_fut_admin/give_coins" \
  -H "X-Admin-Secret: ${ADMIN_SECRET}" \
  -H "Content-Type: application/json" \
  -d "{\"coins\": ${coins}}"
echo
