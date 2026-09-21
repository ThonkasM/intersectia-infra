#!/usr/bin/env bash
# Actualiza uno o todos los servicios en la EC2 del stack, por SSM (sin SSH):
# hace git pull de los repos y reconstruye solo lo necesario.
#
# Uso:
#   ./deploy/ec2-update.sh <instance-id> frontend
#   ./deploy/ec2-update.sh <instance-id> backend
#   ./deploy/ec2-update.sh <instance-id> ai
#   ./deploy/ec2-update.sh <instance-id>            # all
#
# Obtener el instance-id:
#   aws cloudformation describe-stacks --stack-name intersectia --region us-east-1 \
#     --query "Stacks[0].Outputs[?OutputKey=='EC2InstanceId'].OutputValue" --output text
set -euo pipefail

INSTANCE_ID="${1:-}"
TARGET="${2:-all}"
REGION="${AWS_REGION:-us-east-1}"
APP_DIR="/home/ec2-user/intersectia"

if [ -z "$INSTANCE_ID" ]; then
  echo "Uso: $0 <instance-id> [frontend|backend|ai|all]" >&2
  exit 1
fi

case "$TARGET" in
  frontend|backend|ai) SERVICES="$TARGET" ;;
  all) SERVICES="frontend backend ai" ;;
  *) echo "Servicio invalido: $TARGET" >&2; exit 1 ;;
esac

CMD="cd $APP_DIR"
for s in $SERVICES; do
  CMD="$CMD && git -c safe.directory='*' -C intersectia-$s pull --ff-only"
done
CMD="$CMD && docker-compose up -d --build $SERVICES"

echo "Actualizando [$SERVICES] en $INSTANCE_ID ..."
COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --region "$REGION" \
  --comment "intersectia update $TARGET" \
  --parameters "commands=[\"$CMD\"]" \
  --query "Command.CommandId" --output text)

echo "CommandId: $COMMAND_ID (esperando...)"
aws ssm wait command-executed --command-id "$COMMAND_ID" --instance-id "$INSTANCE_ID" --region "$REGION" || true
aws ssm get-command-invocation --command-id "$COMMAND_ID" --instance-id "$INSTANCE_ID" --region "$REGION" \
  --query "{Status:Status,Output:StandardOutputContent,Error:StandardErrorContent}" --output text
