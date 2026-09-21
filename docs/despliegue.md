# Guía de despliegue

Dos caminos: **VM única (barato)** o **AWS gestionado (Fargate + RDS)**.

## Prerrequisitos

- Docker y Docker Compose.
- Repos hermanos clonados: `intersectia-frontend`, `intersectia-backend`, `intersectia-ai`, `intersectia-infra`.
- (AWS gestionado) AWS CLI v2, Terraform ≥ 1.6 y una cuenta con permisos.

---

## Opción A — VM única (EC2 / Lightsail) — la más barata

Un solo host corre **todo** con Docker: Frontend (nginx) + Backend + IA + Postgres.
**Un único puerto público (80)**; nginx sirve el frontend y hace de proxy de `/socket.io`,
`/ai` y `/metrics` hacia el backend. Al ser **mismo origen**, no hay CORS ni *mixed content*,
y no hace falta hornear URLs en el build del frontend.

```
Navegador -> :80 (nginx)
              ├── /            -> frontend estático (out/)
              ├── /socket.io/  -> backend:3000
              ├── /ai/         -> backend:3000
              └── /metrics/    -> backend:3000
                                   └── backend:3000 -> ai:8000 (localhost de la task) y db:5432
```

### Deploy en un comando (recomendado)

El script `deploy/ec2-setup.sh` hace todo: instala Docker, clona/actualiza los repos, genera el
`.env` con un token aleatorio y levanta el stack.

```bash
# Opción 1: copia el repo de infra a la VM
scp -r intersectia-infra usuario@<IP>:~/
ssh usuario@<IP> '~/intersectia-infra/deploy/ec2-setup.sh'

# Opción 2: si intersectia-infra tiene remoto
INFRA_REPO_URL=https://github.com/tu-usuario/intersectia-infra.git ./deploy/ec2-setup.sh
```

Variables opcionales: `BRANCH=v2`, `BACKEND_REPO_URL`, `FRONTEND_REPO_URL`, `AI_REPO_URL`.

Operación diaria (desde `intersectia-infra/`): `make up` · `make logs` · `make migrate` · `make down`.

### Pasos manuales

1. **Crear la VM**: EC2 **t3.small** (Ubuntu 22.04) o Lightsail. En el Security Group abre
   **solo el puerto 80** (y el 22 para SSH). t3.small (2 GB) es lo mínimo cómodo; t3.micro
   puede quedar justo al compilar.
2. **Instalar Docker** en la VM:
   ```bash
   curl -fsSL https://get.docker.com | sh
   sudo usermod -aG docker $USER && newgrp docker
   ```
3. **Llevar los 4 repos** a la VM, clonados **como hermanos**:
   ```bash
   mkdir -p ~/intersectia && cd ~/intersectia
   git clone https://github.com/ThonkasM/intersectia-backend.git
   git clone https://github.com/ThonkasM/intersectia-frontend.git
   git clone https://github.com/ThonkasM/intersectia-ai.git
   # intersectia-infra no tiene remoto: súbelo a GitHub o cópialo por scp:
   scp -r ./intersectia-infra usuario@<IP>:~/intersectia/
   ```
4. **Levantar todo**:
   ```bash
   cd ~/intersectia/intersectia-infra
   cp .env.example .env      # cambia INTERNAL_SERVICE_TOKEN
   docker compose up -d --build
   ```
5. **Abrir** `http://<IP>/` (landing) y `http://<IP>/demo`. En la demo, cambia a **managed** o
   **managed-ai** para conectar.

### Puntos de atención
- El `docker-compose.yml` construye las imágenes desde los repos locales (no usa ECR).
- El backend corre `npx prisma migrate deploy` al arrancar (crea las tablas en el Postgres del compose).
- La IA **entrena su política en el build** de la imagen (`RUN python -m app.policy.train`), así el
  artefacto (gitignored) queda dentro del contenedor.
- Cambia `INTERNAL_SERVICE_TOKEN` en `.env` (debe coincidir backend ↔ IA; el compose ya lo unifica).
- `restart: unless-stopped` reinicia los contenedores si la VM se reinicia.
- Logs: `docker compose logs -f` · Detener: `docker compose down` · Rebuild: `docker compose up -d --build`.

---

## Opción B — AWS gestionado (recomendado para la nube)

### 1. Imágenes en ECR

```bash
aws ecr create-repository --repository-name intersectia-backend
aws ecr create-repository --repository-name intersectia-ai
aws ecr create-repository --repository-name intersectia-frontend

# Login y push (tag inmutable = commit SHA)
aws ecr get-login-password | docker login --username AWS --password-stdin <account>.dkr.ecr.<region>.amazonaws.com
docker build -t <account>.dkr.ecr.<region>.amazonaws.com/intersectia-backend:$(git -C ../intersectia-backend rev-parse --short HEAD) ../intersectia-backend
docker push <account>.dkr.ecr.<region>.amazonaws.com/intersectia-backend:<tag>
```

### 2. Infraestructura con Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # ajusta región, cuenta, etc.
terraform init
terraform plan
terraform apply
```

Crea VPC/subredes, ECR, Secrets Manager, RDS, el clúster y servicio ECS, el ALB y el bucket + CloudFront del frontend.

### 3. Frontend estático a S3

```bash
cd ../intersectia-frontend
NEXT_PUBLIC_WS_URL="https://<alb-dns>" NEXT_PUBLIC_API_URL="https://<alb-dns>" npm run build
aws s3 sync out/ s3://<bucket-frontend>/ --delete
aws cloudfront create-invalidation --distribution-id <id> --paths "/*"
```

### 4. Migraciones de base de datos

No se corren en el contenedor de producción que atiende tráfico. Usa una **task ECS one-off** con la misma task definition y security group:

```bash
aws ecs run-task --cluster intersectia --task-definition intersectia-backend \
  --launch-type FARGATE --network-configuration '...' \
  --overrides '{"containerOverrides":[{"name":"backend","command":["npx","prisma","migrate","deploy"]}]}'
```

### 5. CI/CD con GitHub Actions + OIDC

Cada repo incluye un workflow que, al hacer push a `main`:

1. corre lint y tests,
2. construye y publica la imagen con tag = SHA,
3. registra una nueva revisión de la task definition,
4. actualiza el servicio ECS y espera estabilidad,
5. invalida CloudFront (frontend).

La autenticación usa **OIDC** (`permissions: id-token: write`), sin claves de AWS de larga duración. El rol IAM de Terraform confía solo en el repositorio y la rama indicados.

---

## Verificación post-despliegue

- `GET http://<alb-dns>/` → `{"name":"IntersectIA Backend","status":"ok"}`
- `GET http://<alb-dns>/metrics/summary` → JSON con métricas.
- Abrir la URL de CloudFront → landing; ir a `/demo` y comprobar que el HUD muestra "conectado".
- `curl http://<alb-dns>/ai/chat/topics` → lista de temas.
- Chat: `curl -s -X POST http://<IP>/ai/chat -H 'Content-Type: application/json' -d '{"message":"¿Qué es IoT?"}'`
  (funciona offline; para usar el LLM de Bedrock ver `docs/ia-en-cloud.md`).

## Rollback

El servicio ECS conserva revisiones previas de la task definition. Ante un fallo, actualiza el servicio a la revisión anterior:

```bash
aws ecs update-service --cluster intersectia --service backend --task-definition intersectia-backend:<revision-anterior>
```
