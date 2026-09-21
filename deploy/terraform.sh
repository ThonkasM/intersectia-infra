#!/usr/bin/env bash
# Despliegue de IntersectIA con Terraform (Opcion B: S3+CloudFront + ECS Fargate + RDS).
# Flujo en dos fases (el servicio ECS necesita las imagenes ya en ECR).
#
# Uso:
#   ./deploy/terraform.sh up          # todo: infra + imagenes + servicio + frontend + migraciones
#   ./deploy/terraform.sh platform    # fase 1 (ECR, RDS, ALB, CloudFront, S3, Secrets)
#   ./deploy/terraform.sh images      # build+push backend y ai a ECR
#   ./deploy/terraform.sh services    # fase 2 (task definition + servicio ECS)
#   ./deploy/terraform.sh frontend    # build del frontend + sync a S3 + invalidacion
#   ./deploy/terraform.sh migrate     # prisma migrate deploy (task ECS one-off)
#   ./deploy/terraform.sh update-frontend | update-backend | update-ai
#   ./deploy/terraform.sh outputs | destroy
#
# Requiere: terraform, aws CLI, docker, y los repos de app como hermanos de intersectia-infra.
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_BASE="$(cd "$ROOT/.." && pwd)"
TF_DIR="$ROOT/terraform"
IMAGES_ENV="$TF_DIR/images.env"
TF="${TERRAFORM:-terraform}"

tf() { (cd "$TF_DIR" && "$TF" "$@"); }
out() { tf output -raw "$1"; }
account_id() { aws sts get-caller-identity --query Account --output text; }

ecr_login() {
  aws ecr get-login-password --region "$REGION" \
    | docker login --username AWS --password-stdin "$(account_id).dkr.ecr.$REGION.amazonaws.com"
}

build_push() { # $1=repo-name(local.name-suffix)  $2=app dir  $3=env var name
  local repo="$1" dir="$2"
  local url; url="$(out "$3")"
  local tag; tag="$(git -C "$dir" rev-parse --short HEAD)"
  local image="$url:$tag"
  echo "==> build $repo ($tag)"
  docker build -t "$image" "$dir"
  docker push "$image"
  echo "$image"
}

images() {
  ecr_login
  mkdir -p "$TF_DIR"
  local be ai
  be="$(build_push backend "$APP_BASE/intersectia-backend" ecr_backend)"
  ai="$(build_push ai "$APP_BASE/intersectia-ai" ecr_ai)"
  printf 'BACKEND_IMAGE=%s\nAI_IMAGE=%s\n' "$be" "$ai" > "$IMAGES_ENV"
  echo "Imagenes subidas. Guardado en $IMAGES_ENV"
}

load_images() {
  [ -f "$IMAGES_ENV" ] || { echo "Falta $IMAGES_ENV. Corre primero: $0 images" >&2; exit 1; }
  # shellcheck disable=SC1090
  source "$IMAGES_ENV"
}

platform() { tf init -input=false; tf apply -auto-approve -input=false; }

services() {
  load_images
  tf apply -auto-approve -input=false \
    -var "deploy_services=true" \
    -var "backend_image=${BACKEND_IMAGE}" \
    -var "ai_image=${AI_IMAGE}"
}

frontend() {
  local bucket; bucket="$(out frontend_bucket)"
  ( cd "$APP_BASE/intersectia-frontend" && npm ci && npm run build )
  aws s3 sync "$APP_BASE/intersectia-frontend/out/" "s3://$bucket/" --delete
  local dist; dist="$(tf output -raw cloudfront_domain)"
  aws cloudfront create-invalidation --distribution-id \
    "$(aws cloudfront list-distributions --query "DistributionList.Items[?DomainName=='$dist'].Id" --output text)" \
    --paths "/*"
  echo "Frontend publicado en https://$dist"
}

migrate() {
  local cluster; cluster="$(out ecs_cluster_name)"
  local sg; sg="$(out ecs_security_group_id)"
  local subnets; subnets="$(tf output -json default_subnet_ids | tr -d '[]" \n' )"
  local family; family="$(out backend_task_family)"
  aws ecs run-task \
    --cluster "$cluster" \
    --task-definition "$family" \
    --launch-type FARGATE \
    --region "$REGION" \
    --network-configuration "awsvpcConfiguration={subnets=[$subnets],securityGroups=[$sg],assignPublicIp=ENABLED}" \
    --overrides '{"containerOverrides":[{"name":"ai","command":["sh","-c","true"]},{"name":"backend","command":["npx","prisma","migrate","deploy"]}]}' \
    --query "tasks[0].taskArn" --output text
}

update_service() { # $1 = backend|ai
  local svc="$1"
  # reconstruye y sube SOLO esa imagen, y aplica con el otro tag ya guardado
  load_images
  ecr_login
  if [ "$svc" = backend ]; then
    BACKEND_IMAGE="$(build_push backend "$APP_BASE/intersectia-backend" ecr_backend)"
  else
    AI_IMAGE="$(build_push ai "$APP_BASE/intersectia-ai" ecr_ai)"
  fi
  printf 'BACKEND_IMAGE=%s\nAI_IMAGE=%s\n' "$BACKEND_IMAGE" "$AI_IMAGE" > "$IMAGES_ENV"
  services
}

case "${1:-up}" in
  up)        platform; images; services; frontend; migrate ;;
  platform)  platform ;;
  images)    images ;;
  services)  services ;;
  frontend|update-frontend) frontend ;;
  migrate)   migrate ;;
  update-backend) update_service backend ;;
  update-ai)      update_service ai ;;
  outputs)   tf output ;;
  destroy)   tf destroy -auto-approve -input=false ;;
  *) echo "Uso: $0 [up|platform|images|services|frontend|migrate|update-backend|update-ai|outputs|destroy]" >&2; exit 1 ;;
esac
