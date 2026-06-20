#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/req_app}"
cd "$APP_DIR"

echo "==> Pull latest main..."
git fetch origin main
git reset --hard origin/main

echo "==> Build and start containers..."
docker compose -f docker-compose.prod.yml --env-file .env.production build
docker compose -f docker-compose.prod.yml --env-file .env.production up -d

echo "==> Wait for Rails..."
for i in $(seq 1 30); do
  if docker compose -f docker-compose.prod.yml --env-file .env.production exec -T rails curl -sf http://localhost:3000/up >/dev/null 2>&1; then
    echo "Rails is up."
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "Rails health check timed out — check logs:"
    docker compose -f docker-compose.prod.yml --env-file .env.production logs rails --tail 50
    exit 1
  fi
  sleep 5
done

echo "==> Database prepare..."
docker compose -f docker-compose.prod.yml --env-file .env.production exec -T rails ./bin/rails db:prepare

echo "==> Prune old images..."
docker image prune -f

echo "==> Deploy complete."
docker compose -f docker-compose.prod.yml --env-file .env.production ps
