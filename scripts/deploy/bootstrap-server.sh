#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/req_app}"
REPO_URL="${REPO_URL:-git@github.com:malikusman/req_app.git}"
DOMAIN="${DOMAIN:-req.pebbleintelligentsolutions.com}"

echo "==> Installing Docker (if needed)..."
if ! command -v docker >/dev/null 2>&1; then
  apt-get update
  apt-get install -y ca-certificates curl git ufw
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
fi

echo "==> Firewall..."
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

echo "==> App directory..."
mkdir -p "$APP_DIR"

if [ ! -d "$APP_DIR/.git" ]; then
  echo "==> Clone repo (requires deploy key at /root/.ssh/id_ed25519)..."
  git clone "$REPO_URL" "$APP_DIR"
else
  echo "==> Repo already cloned at $APP_DIR"
fi

cd "$APP_DIR"

if [ ! -f .env.production ]; then
  echo "==> Creating .env.production from example..."
  cp deploy/.env.production.example .env.production
  POSTGRES_PW=$(openssl rand -hex 24)
  MINIO_PW=$(openssl rand -hex 24)
  SECRET=$(openssl rand -hex 64)
  JWT=$(openssl rand -hex 32)
  TOKEN=$(openssl rand -hex 32)
  sed -i "s|^POSTGRES_PASSWORD=$|POSTGRES_PASSWORD=$POSTGRES_PW|" .env.production
  sed -i "s|^MINIO_SECRET_KEY=$|MINIO_SECRET_KEY=$MINIO_PW|" .env.production
  sed -i "s|^SECRET_KEY_BASE=$|SECRET_KEY_BASE=$SECRET|" .env.production
  sed -i "s|^JWT_SECRET=$|JWT_SECRET=$JWT|" .env.production
  sed -i "s|^INTERNAL_API_TOKEN=$|INTERNAL_API_TOKEN=$TOKEN|" .env.production
  echo ""
  echo "Created .env.production with generated secrets."
  echo "Edit $APP_DIR/.env.production and add OPENAI_API_KEY + META_* before going live."
fi

echo "==> Bootstrap complete."
echo "Next:"
echo "  1. Add server deploy key to GitHub repo (Settings → Deploy keys)"
echo "  2. Fill in .env.production secrets on server"
echo "  3. Run: cd $APP_DIR && bash scripts/deploy/deploy.sh"
echo "  4. Add GitHub Actions secrets: DEPLOY_HOST, DEPLOY_SSH_KEY"
