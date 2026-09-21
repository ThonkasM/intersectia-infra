#!/bin/bash
set -e
exec > >(tee /var/log/user-data.log) 2>&1
echo "=== IntersectIA setup (terraform) ==="

# Swap (ayuda a compilar imagenes en instancias chicas)
if [ ! -f /swapfile ]; then
  dd if=/dev/zero of=/swapfile bs=1M count=2048
  chmod 600 /swapfile; mkswap /swapfile; swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

dnf update -y
dnf install -y docker git jq
systemctl enable --now docker
usermod -aG docker ec2-user

curl -L "https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
(cd /tmp && unzip -q awscliv2.zip && ./aws/install && rm -rf aws awscliv2.zip)

APP_DIR=/home/ec2-user/intersectia
mkdir -p $APP_DIR && cd $APP_DIR

for r in intersectia-backend intersectia-frontend intersectia-ai; do
  [ -d "$r" ] || git clone --branch ${branch} https://github.com/ThonkasM/$r.git
done

DB_PASS=$(aws secretsmanager get-secret-value --secret-id ${db_secret_name} --region ${region} --query SecretString --output text | jq -r .password)
TOKEN=$(aws secretsmanager get-secret-value --secret-id ${token_secret_name} --region ${region} --query SecretString --output text | jq -r .token)
DB_PASS_ENC=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$DB_PASS")

cat > .env <<ENVFILE
DATABASE_URL=postgresql://${db_user}:$DB_PASS_ENC@${db_address}:5432/${db_name}?schema=public
INTERNAL_SERVICE_TOKEN=$TOKEN
AI_INTERNAL_SERVICE_TOKEN=$TOKEN
AI_AWS_REGION=${region}
AI_BEDROCK_MODEL_ID=${bedrock_model_id}
CORS_ORIGIN=${cors_origin}
ENVFILE
chmod 600 .env; chown ec2-user:ec2-user .env

cat > docker-compose.yml <<'EOF'
services:
  ai:
    build: ./intersectia-ai
    restart: unless-stopped
    env_file: .env
    logging:
      driver: awslogs
      options:
        awslogs-region: ${region}
        awslogs-group: /ec2/intersectia
        awslogs-stream-prefix: ai
        awslogs-create-group: "true"
  backend:
    build: ./intersectia-backend
    restart: unless-stopped
    env_file: .env
    environment:
      PORT: "3000"
      AI_SERVICE_URL: http://ai:8000
    command: sh -c "npx prisma migrate deploy && node dist/main"
    depends_on: [ai]
    logging:
      driver: awslogs
      options:
        awslogs-region: ${region}
        awslogs-group: /ec2/intersectia
        awslogs-stream-prefix: backend
        awslogs-create-group: "true"
  frontend:
    build: ./intersectia-frontend
    restart: unless-stopped
    depends_on: [backend]
    ports: ["80:80"]
    logging:
      driver: awslogs
      options:
        awslogs-region: ${region}
        awslogs-group: /ec2/intersectia
        awslogs-stream-prefix: frontend
        awslogs-create-group: "true"
EOF

su ec2-user -c "cd $APP_DIR && docker-compose up -d --build"
echo "=== Listo ==="
