#!/usr/bin/env bash
# Opcion A+ con Terraform: EC2 (Docker Compose) + RDS + CloudFront + Secrets + IAM/Bedrock.
# Misma arquitectura que el template de CloudFormation, pero en HCL.
#
# Uso:
#   ./deploy/terraform-ec2.sh up       # crea/actualiza el stack y muestra la URL
#   ./deploy/terraform-ec2.sh plan
#   ./deploy/terraform-ec2.sh outputs
#   ./deploy/terraform-ec2.sh destroy
#
# Actualizar el codigo (sin cambios de infra) usa SSM:
#   ./deploy/ec2-update.sh <instance-id> backend|frontend|ai|all
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TF_DIR="$ROOT/terraform-ec2"
TF="${TERRAFORM:-terraform}"

tf() { (cd "$TF_DIR" && "$TF" "$@"); }

case "${1:-up}" in
  up)
    tf init -input=false
    tf apply -auto-approve -input=false
    echo "Salidas:"
    tf output
    ;;
  plan)
    tf init -input=false
    tf plan -input=false
    ;;
  outputs)
    tf output
    ;;
  destroy)
    tf destroy -auto-approve -input=false
    ;;
  *)
    echo "Uso: $0 [up|plan|outputs|destroy]" >&2
    exit 1
    ;;
esac
