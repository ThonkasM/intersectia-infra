#!/usr/bin/env bash
# Limpia los restos que dejan los destroy de IntersectIA (Secrets Manager,
# CloudWatch log groups, snapshots de RDS y Elastic IPs con tag "intersectia").
#
# Uso:
#   ./deploy/nuke.sh --dry-run    # solo lista (no borra)
#   ./deploy/nuke.sh              # lista y pide confirmacion
#   ./deploy/nuke.sh --yes        # borra sin preguntar
#
# Variable: AWS_REGION (def. us-east-1), PATTERN (def. intersectia).
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
PATTERN="${PATTERN:-intersectia}"
MODE="interactive"
for arg in "$@"; do
  case "$arg" in
    --dry-run) MODE="dry" ;;
    --yes|-y)  MODE="yes" ;;
    *) echo "Argumento desconocido: $arg" >&2; exit 1 ;;
  esac
done

q() { aws --region "$REGION" "$@"; }

secrets=$(q secretsmanager list-secrets --query "SecretList[?contains(Name, '${PATTERN}')].ARN" --output text 2>/dev/null || true)
loggroups=$(q logs describe-log-groups --query "logGroups[?contains(logGroupName, '${PATTERN}')].logGroupName" --output text 2>/dev/null || true)
snapshots=$(q rds describe-db-snapshots --snapshot-type manual --query "DBSnapshots[?contains(DBSnapshotIdentifier, '${PATTERN}')].DBSnapshotIdentifier" --output text 2>/dev/null || true)
eips=$(q ec2 describe-addresses --query "Addresses[?Tags[?contains(Value, '${PATTERN}')]].AllocationId" --output text 2>/dev/null || true)

echo "== Restos en $REGION (patron '$PATTERN') =="
echo "Secrets:      ${secrets:-<ninguno>}"
echo "Log groups:   ${loggroups:-<ninguno>}"
echo "Snapshots:    ${snapshots:-<ninguno>}"
echo "Elastic IPs:  ${eips:-<ninguna>}"

if [ "$MODE" = "dry" ]; then
  echo "(dry-run: no se borro nada)"
  exit 0
fi

if [ "$MODE" = "interactive" ]; then
  read -r -p "¿Borrar estos recursos? Escribe 'borrar' para confirmar: " ok
  [ "$ok" = "borrar" ] || { echo "Cancelado."; exit 0; }
fi

for arn in $secrets; do
  echo "- secret $arn"
  q secretsmanager delete-secret --secret-id "$arn" --force-delete-without-recovery >/dev/null
done
for lg in $loggroups; do
  echo "- log group $lg"
  q logs delete-log-group --log-group-name "$lg" >/dev/null
done
for snap in $snapshots; do
  echo "- snapshot $snap"
  q rds delete-db-snapshot --db-snapshot-identifier "$snap" >/dev/null
done
for eip in $eips; do
  echo "- elastic ip $eip"
  q ec2 release-address --allocation-id "$eip" >/dev/null
done

echo "Limpieza completa."
