#!/usr/bin/env bash
# Aprovisiona IntersectIA en una VM (Ubuntu 22.04+) con Docker Compose.
# Un solo puerto publico: 80. nginx sirve el frontend y hace de proxy de
# /socket.io, /ai y /metrics al backend (mismo origen: sin CORS ni mixed content).
#
# Uso (copia el repo de infra a la VM y ejecuta el script):
#   scp -r intersectia-infra usuario@<IP>:~/
#   ssh usuario@<IP> '~/intersectia-infra/deploy/ec2-setup.sh'
#
# O si intersectia-infra ya tiene remoto:
#   INFRA_REPO_URL=https://github.com/tu-usuario/intersectia-infra.git ./ec2-setup.sh
#
# Variables: BRANCH (def. v2), BACKEND_REPO_URL, FRONTEND_REPO_URL, AI_REPO_URL.
set -euo pipefail

BRANCH="${BRANCH:-v2}"
BACKEND_REPO_URL="${BACKEND_REPO_URL:-https://github.com/ThonkasM/intersectia-backend.git}"
FRONTEND_REPO_URL="${FRONTEND_REPO_URL:-https://github.com/ThonkasM/intersectia-frontend.git}"
AI_REPO_URL="${AI_REPO_URL:-https://github.com/ThonkasM/intersectia-ai.git}"

log() { printf '\n[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

# 1) Docker
if ! command -v docker >/dev/null 2>&1; then
  log "Instalando Docker (get.docker.com)..."
  curl -fsSL https://get.docker.com | sh
fi
DOCKER="docker"
if ! docker info >/dev/null 2>&1; then
  DOCKER="sudo docker"
fi

# 2) Ubicar el repo de infraestructura (este script)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
if [ ! -f "$INFRA_DIR/docker-compose.yml" ]; then
  if [ -z "${INFRA_REPO_URL:-}" ]; then
    echo "ERROR: no encuentro docker-compose.yml y no definiste INFRA_REPO_URL." >&2
    exit 1
  fi
  INFRA_DIR="$HOME/intersectia/intersectia-infra"
  log "Clonando intersectia-infra en $INFRA_DIR"
  rm -rf "$INFRA_DIR"
  git clone --branch "$BRANCH" "$INFRA_REPO_URL" "$INFRA_DIR"
fi

# 3) Clonar/actualizar las apps como hermanas de infraestructura
REPO_BASE="$(cd "$INFRA_DIR/.." && pwd)"
clone_or_pull() {
  url="$1"; dir="$2"
  if [ -d "$dir/.git" ]; then
    log "Actualizando $(basename "$dir") (rama $BRANCH)"
    git -C "$dir" fetch --all --quiet
    git -C "$dir" checkout "$BRANCH" --quiet
    git -C "$dir" pull --ff-only --quiet
  else
    log "Clonando $(basename "$dir") (rama $BRANCH)"
    git clone --branch "$BRANCH" "$url" "$dir"
  fi
}
mkdir -p "$REPO_BASE"
clone_or_pull "$BACKEND_REPO_URL" "$REPO_BASE/intersectia-backend"
clone_or_pull "$FRONTEND_REPO_URL" "$REPO_BASE/intersectia-frontend"
clone_or_pull "$AI_REPO_URL" "$REPO_BASE/intersectia-ai"

# 4) .env con token interno aleatorio (backend e IA deben coincidir)
cd "$INFRA_DIR"
if [ ! -f .env ]; then
  log "Creando .env con INTERNAL_SERVICE_TOKEN aleatorio"
  TOKEN="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)"
  awk -v t="$TOKEN" '{ if ($0 ~ /^INTERNAL_SERVICE_TOKEN=/) print "INTERNAL_SERVICE_TOKEN=" t; else print }' .env.example > .env
fi

# 5) Construir y levantar
log "Construyendo y levantando el stack (puede tardar varios minutos)..."
$DOCKER compose up -d --build

IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
cat <<EOF

IntersectIA desplegado.
  Frontend:  http://${IP:-<IP-publica>}/
  Demo:      http://${IP:-<IP-publica>}/demo
  Logs:      $DOCKER compose logs -f
  Detener:   $DOCKER compose down

Recuerda abrir el puerto 80 en el Security Group de la instancia.
EOF
