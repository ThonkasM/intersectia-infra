# Guía de despliegue

Tres caminos **alternativos** (elige UNO; no los corras a la vez):

- **A** — VM única con `docker-compose` (Postgres en contenedor). El más barato.
- **A+** — **CloudFormation**: EC2 + RDS + CloudFront + IAM/Bedrock. HTTPS sin dominio, reproducible.
- **B** — **Terraform**: S3+CloudFront (front) + ECS Fargate (backend+IA) + RDS + ALB. Para producción/escala.

> ⚠️ **A+ y B son excluyentes.** Si corres ambos en la misma cuenta/región tendrás recursos
> duplicados (dos RDS, dos CloudFront, dos cómputos) y doble costo. Usa uno solo y, si cambias,
> destruye el anterior primero (`./deploy/ec2-cfn.sh destroy` o `terraform destroy`).

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

## Opción A+ — CloudFormation (EC2 + RDS + CloudFront) — recomendada con AWS

Igual que la Opción A (una EC2, un puerto 80), pero **aprovisionada con CloudFormation** y con
**RDS gestionado + CloudFront (HTTPS sin dominio) + IAM con Bedrock**. Es el patrón que usa el
proyecto Homy y deja el despliegue reproducible.

Plantilla: `infrastructure/cloudformation-ec2.yaml`. Crea: VPC + subredes, **EC2** (Amazon Linux
2023, con swap), **RDS PostgreSQL** privado, **Secrets Manager** (contraseña de DB y token interno),
**IAM instance role** (Secrets, CloudWatch, SSM y **Bedrock `bedrock:InvokeModel`** acotado al
inference-profile), **Elastic IP** y **CloudFront** (viewer HTTPS → origin HTTP en :80).

La EC2 (user-data) instala Docker + compose, clona los 3 repos (rama `v2`), genera el `.env` desde
Secrets Manager, escribe un `docker-compose.yml` (backend + IA + frontend, usando RDS) y compila/levanta.

Un solo comando (crea o actualiza y muestra la URL):

```bash
cd intersectia-infra
./deploy/ec2-cfn.sh up        # crea/actualiza el stack (EC2 + RDS + CloudFront)
./deploy/ec2-cfn.sh outputs   # ver salidas (URL de CloudFront, instance id)
./deploy/ec2-cfn.sh status
./deploy/ec2-cfn.sh destroy   # eliminar todo
```

Actualizar **solo** un servicio en la instancia (por SSM, sin SSH):

```bash
ID=$(aws cloudformation describe-stacks --stack-name intersectia --region us-east-1 \
  --query "Stacks[0].Outputs[?OutputKey=='EC2InstanceId'].OutputValue" --output text)

./deploy/ec2-update.sh "$ID" frontend
./deploy/ec2-update.sh "$ID" backend
./deploy/ec2-update.sh "$ID" ai
./deploy/ec2-update.sh "$ID"             # all
```

Con `make`: `make cloud-up` · `make cloud-outputs` · `make cloud-update ID=i-xxxx S=frontend` · `make cloud-destroy`.

- Usar la URL de **CloudFront** (HTTPS) → evita *mixed content* sin dominio propio.
- Tras el primer deploy, poner `AllowedCORSOrigin` = dominio de CloudFront y actualizar el stack.
- Acceso a la VM **sin SSH**: `aws ssm start-session --target <InstanceId>`.
- **Bedrock**: habilitar el modelo en la consola (Model access); si no, el chat degrada offline.
- **Requisito de compilación**: las imágenes se compilan **en la instancia** (por eso `t3.small` + swap).
- Costo: como la Opción A **+ RDS** (~$13/mes) **+ CloudFront** (centavos). Para el mínimo absoluto,
  usar el `docker-compose.yml` de la Opción A (Postgres en contenedor, sin RDS/CloudFront).

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

### Estado y limitaciones de la Opción B (Terraform)

El Terraform es un **esqueleto funcional** (no listo para producción sin completar esto):

- **HTTPS / mixed content**: el frontend (CloudFront HTTPS) apunta al ALB **HTTP**; el navegador
  bloquea `http://…` desde una página HTTPS. Falta **HTTPS en el ALB (ACM + dominio)** o **enrutar
  la API/WebSocket por CloudFront** al ALB.
- **Apply en dos fases**: el servicio ECS necesita que las imágenes ya existan en ECR → aplicar con
  `deploy_services=false`, subir imágenes y volver a aplicar.
- **Migraciones**: correr `prisma migrate deploy` como **task ECS one-off** (no en el contenedor que sirve).
- **Env del frontend**: `NEXT_PUBLIC_*` se hornean **antes** de `npm run build` y deben apuntar al
  dominio de CloudFront/ALB.
- **Sticky sessions**: con `desired_count > 1`, activar **stickiness** (cada task guarda sesiones en memoria).
- **VPC/red**: usa la **VPC por defecto**; para producción, VPC propia y subredes privadas + NAT.
- **Logs**: el Terraform no configura CloudWatch.

> En resumen: **A+ (CloudFormation) es la ruta lista y recomendada**; **B (Terraform)** es el camino
> “producción” a completar. No mezclar ambas.

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
