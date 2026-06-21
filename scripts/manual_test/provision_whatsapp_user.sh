#!/usr/bin/env bash
# Run on prod server from repo root (/opt/req_app).
#
#   PHONE=+971526187620 COMPANY=acme-corp ./scripts/manual_test/provision_whatsapp_user.sh
#
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/req_app}"
COMPOSE="docker compose -f docker-compose.prod.yml --env-file .env.production"

cd "$APP_DIR"

PHONE="${PHONE:-+971526187620}"
COMPANY="${COMPANY:-acme-corp}"
DEPARTMENT="${DEPARTMENT:-finance}"
SEND_WHATSAPP="${SEND_WHATSAPP:-true}"

$COMPOSE exec -T \
  -e "PHONE=${PHONE}" \
  -e "COMPANY=${COMPANY}" \
  -e "DEPARTMENT=${DEPARTMENT}" \
  -e "SEND_WHATSAPP=${SEND_WHATSAPP}" \
  rails ./bin/rails runner lib/manual_test/provision_whatsapp_user.rb
