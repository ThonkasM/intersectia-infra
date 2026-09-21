#!/usr/bin/env bash
# Habilita Amazon Bedrock para el chat de la IA en una instancia EC2 (Opcion A).
# Crea un rol + instance profile con bedrock:InvokeModel, lo asocia a la instancia
# y sube el IMDS hop limit a 2 (el contenedor Docker agrega un salto).
#
# Ejecutar desde TU maquina (AWS CLI configurado con permisos), NO en la VM:
#   ./deploy/ec2-bedrock-iam.sh <instance-id> [region]
#
# Despues, en la VM:  docker compose restart ai
# (y habilita el acceso al modelo en la consola de Bedrock)
set -euo pipefail

INSTANCE_ID="${1:-}"
REGION="${2:-${AWS_REGION:-us-east-1}}"
ROLE_NAME="${ROLE_NAME:-intersectia-ec2-bedrock}"
PROFILE_NAME="${PROFILE_NAME:-intersectia-ec2-bedrock}"

if [ -z "$INSTANCE_ID" ]; then
  echo "Uso: $0 <instance-id> [region]" >&2
  exit 1
fi

TRUST_FILE="$(mktemp)"
POLICY_FILE="$(mktemp)"
trap 'rm -f "$TRUST_FILE" "$POLICY_FILE"' EXIT

cat > "$TRUST_FILE" <<'JSON'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}
JSON

cat > "$POLICY_FILE" <<'JSON'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["bedrock:InvokeModel","bedrock:InvokeModelWithResponseStream"],"Resource":"*"}]}
JSON

echo "[1/5] Rol IAM $ROLE_NAME"
aws iam create-role --role-name "$ROLE_NAME" \
  --assume-role-policy-document "file://$TRUST_FILE" >/dev/null 2>&1 || echo "  (ya existe)"

echo "[2/5] Politica de Bedrock"
aws iam put-role-policy --role-name "$ROLE_NAME" \
  --policy-name intersectia-bedrock --policy-document "file://$POLICY_FILE"

echo "[3/5] Instance profile $PROFILE_NAME"
aws iam create-instance-profile --instance-profile-name "$PROFILE_NAME" >/dev/null 2>&1 || echo "  (ya existe)"
aws iam add-role-to-instance-profile --instance-profile-name "$PROFILE_NAME" \
  --role-name "$ROLE_NAME" >/dev/null 2>&1 || echo "  (rol ya asociado)"

echo "[4/5] Asociando a $INSTANCE_ID (esperando propagacion de IAM)"
sleep 10
aws ec2 associate-iam-instance-profile --instance-id "$INSTANCE_ID" \
  --iam-instance-profile "Name=$PROFILE_NAME" --region "$REGION" >/dev/null \
  || echo "  (ya tiene instance profile)"

echo "[5/5] IMDS hop limit = 2 (accesible desde el contenedor)"
aws ec2 modify-instance-metadata-options --instance-id "$INSTANCE_ID" \
  --http-endpoint enabled --http-tokens optional \
  --http-put-response-hop-limit 2 --region "$REGION" >/dev/null

cat <<EOF

Listo. Pasos finales:
  1) Habilita el acceso al modelo en Bedrock (consola -> Model access) en $REGION.
  2) En la VM: docker compose restart ai
  3) Prueba: curl -s -X POST http://<IP>/ai/chat -H 'Content-Type: application/json' \\
       -d '{"message":"Explicame la comunicacion V2V"}'
EOF
