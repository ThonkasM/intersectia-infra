#!/usr/bin/env bash
# Despliega/actualiza el stack de IntersectIA en AWS con CloudFormation
# (EC2 + RDS + CloudFront + Secrets + IAM/Bedrock). Un solo comando.
#
# Uso:
#   ./deploy/ec2-cfn.sh up        # crea o actualiza el stack y muestra la URL
#   ./deploy/ec2-cfn.sh status
#   ./deploy/ec2-cfn.sh outputs
#   ./deploy/ec2-cfn.sh destroy
#
# Variables: STACK, AWS_REGION, ENV_NAME, INSTANCE_TYPE, BRANCH, CORS_ORIGIN.
set -euo pipefail

STACK="${STACK:-intersectia}"
REGION="${AWS_REGION:-us-east-1}"
ENV_NAME="${ENV_NAME:-production}"
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.small}"
BRANCH="${BRANCH:-v2}"
CORS_ORIGIN="${CORS_ORIGIN:-*}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE="infrastructure/cloudformation-ec2.yaml"
cd "$ROOT"

case "${1:-up}" in
  up)
    echo "Desplegando stack '$STACK' en $REGION (EC2=$INSTANCE_TYPE, rama=$BRANCH)..."
    aws cloudformation deploy \
      --template-file "$TEMPLATE" \
      --stack-name "$STACK" \
      --capabilities CAPABILITY_IAM \
      --region "$REGION" \
      --parameter-overrides \
        EnvironmentName="$ENV_NAME" \
        InstanceType="$INSTANCE_TYPE" \
        GitBranch="$BRANCH" \
        AllowedCORSOrigin="$CORS_ORIGIN"
    echo "Stack listo. Salidas:"
    "$0" outputs
    ;;
  status)
    aws cloudformation describe-stacks --stack-name "$STACK" --region "$REGION" \
      --query "Stacks[0].StackStatus" --output text
    ;;
  outputs)
    aws cloudformation describe-stacks --stack-name "$STACK" --region "$REGION" \
      --query "Stacks[0].Outputs[].{Key:OutputKey,Value:OutputValue}" --output table
    ;;
  destroy)
    echo "Eliminando stack '$STACK'..."
    aws cloudformation delete-stack --stack-name "$STACK" --region "$REGION"
    aws cloudformation wait stack-delete-complete --stack-name "$STACK" --region "$REGION"
    echo "Eliminado."
    ;;
  *)
    echo "Uso: $0 [up|status|outputs|destroy]" >&2
    exit 1
    ;;
esac
