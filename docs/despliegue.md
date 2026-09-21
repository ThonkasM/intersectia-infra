# Guía de despliegue

Tres caminos **alternativos** (elige UNO; no los corras a la vez):

- **A** — VM única con `docker-compose` (Postgres en contenedor). El más barato.
- **A+** — **CloudFormation**: EC2 + RDS + CloudFront + IAM/Bedrock. HTTPS sin dominio, reproducible.
- **B** — **Terraform**: S3+CloudFront (front) + ECS Fargate (backend+IA) + RDS + ALB. Para producción/escala.

> ⚠️ **A+ y B son excluyentes.** Si corres ambos en la misma cuenta/región tendrás recursos
> duplicados (dos RDS, dos CloudFront, dos cómputos) y doble costo. Usa uno solo y, si cambias,
> destruye el anterior primero (`./deploy/ec2-cfn.sh destroy` o `terraform destroy`).

### IaC: CloudFormation vs Terraform (misma arquitectura, distinta herramienta)

- **Terraform**: el más usado en la industria; **multi-cloud** (AWS/GCP/Azure), `plan`/`apply`,
  **estado** (`.tfstate`) y módulos. Vos gestionás el estado (local o backend remoto con lock).
  En este repo: `terraform-ec2/` (A+) y `terraform/` (B).
- **CloudFormation**: **nativo de AWS**, el estado lo gestiona AWS (no hay archivos), integrado con
  consola/IAM. En este repo: `infrastructure/cloudformation-ec2.yaml` (A+).

La **arquitectura es idéntica**; cambia la herramienta. Si te interesa lo de industria → Terraform.

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

## Opción A+ — EC2 + RDS + CloudFront (CloudFormation o Terraform)

Igual que la Opción A (una EC2, un puerto 80), pero con **RDS gestionado + CloudFront (HTTPS sin
dominio) + IAM con Bedrock**. Misma arquitectura, dos herramientas de IaC: **CloudFormation** o
**Terraform** (elegí una; no las corras a la vez).

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

### Variante con Terraform (misma arquitectura)

El mismo stack (EC2 + RDS + CloudFront + Secrets + IAM/Bedrock) en HCL, en `terraform-ec2/`:

```bash
./deploy/terraform-ec2.sh up        # crea/actualiza y muestra la URL de CloudFront
./deploy/terraform-ec2.sh plan
./deploy/terraform-ec2.sh outputs
./deploy/terraform-ec2.sh destroy
```
(`make tf-ec2-up` · `make tf-ec2-destroy`). Para actualizar código: `./deploy/ec2-update.sh <instance-id> backend`.

> **Estado del state**: Terraform guarda el estado en `terraform-ec2/terraform.tfstate` (local). Cuidalo; para trabajo en equipo usá un backend remoto (S3 + DynamoDB) — ver comentario en `terraform-ec2/versions.tf`.

- Usar la URL de **CloudFront** (HTTPS) → evita *mixed content* sin dominio propio.
- Tras el primer deploy, poner `AllowedCORSOrigin` = dominio de CloudFront y actualizar el stack.
- Acceso a la VM **sin SSH**: `aws ssm start-session --target <InstanceId>`.
- **Bedrock**: habilitar el modelo en la consola (Model access); si no, el chat degrada offline.
- **Requisito de compilación**: las imágenes se compilan **en la instancia** (por eso `t3.small` + swap).
- Costo: como la Opción A **+ RDS** (~$13/mes) **+ CloudFront** (centavos). Para el mínimo absoluto,
  usar el `docker-compose.yml` de la Opción A (Postgres en contenedor, sin RDS/CloudFront).

---

## Opción B — AWS gestionado (Terraform: S3+CloudFront + ECS Fargate + RDS)

### Deploy en un comando

```bash
cd intersectia-infra
./deploy/terraform.sh up        # infra + imagenes (ECR) + servicio ECS + frontend (S3) + migraciones
./deploy/terraform.sh outputs   # ver salidas (URL de CloudFront, etc.)
./deploy/terraform.sh destroy   # eliminar todo
```

Actualizar solo una parte (sin tocar el resto):

```bash
./deploy/terraform.sh update-frontend   # rebuild frontend + sync a S3 + invalidacion
./deploy/terraform.sh update-backend    # rebuild backend + nuevo deployment ECS
./deploy/terraform.sh update-ai         # idem IA
```

Pasos internos (por si se corren por separado): `platform` (fase 1: ECR/RDS/ALB/CloudFront/S3/Secrets),
`images` (build+push a ECR), `services` (fase 2: task definition + servicio ECS), `frontend`, `migrate`.

### Cómo queda la red / HTTPS

CloudFront sirve el frontend desde S3 y **enruta `/socket.io/*`, `/ai/*` y `/metrics/*` al ALB**
(origen HTTP). El frontend usa **URLs relativas** (mismo origen) → **sin mixed content y sin dominio
propio**. Una función de CloudFront reescribe `/demo` → `/demo.html` (export estático de Next).

### CI/CD con GitHub Actions + OIDC (opcional)

Cada repo trae un workflow de ejemplo que, al hacer push, corre tests, publica la imagen con tag =
SHA, registra una nueva revisión de la task definition, actualiza el servicio ECS e invalida CloudFront.
La autenticación usa **OIDC** (`permissions: id-token: write`), sin claves de AWS de larga duración.

---

### Estado de la Opción B (Terraform)

- **HTTPS / mixed content**: **resuelto** — CloudFront enruta la API/WebSocket al ALB y el frontend
  usa URLs relativas (mismo origen).
- **Apply en dos fases**: **automatizado** por `deploy/terraform.sh up` (variable `deploy_services`).
- **Migraciones**: **automatizado** (`migrate`, task ECS one-off; la IA se overridea para que la task termine).
- **Sticky sessions**: configurada en el target group (soporta `desired_count > 1`).
- **Frontend**: build con URLs relativas → no hay que hornear dominios.

Pendiente para **producción real** (opcional): VPC propia + subredes privadas + NAT; HA
(Multi-AZ / `desired_count`); logs a CloudWatch (el Terraform no los configura, a diferencia del path
de EC2); backend remoto de Terraform con lock; HTTPS con dominio propio (ACM + ALB 443).

> En resumen: **A+ (CloudFormation)** es la ruta mínima y recomendada; **B (Terraform)** queda lista
> para escala/producción. No mezclar ambas.

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

---

## Eliminar el stack (teardown)

Elige según la opción desplegada. Después de borrar, corre `nuke.sh` para limpiar restos.

### Opción A+ (CloudFormation)
```bash
./deploy/ec2-cfn.sh destroy     # borra EC2, RDS, CloudFront, EIP, SG, IAM
./deploy/nuke.sh                # limpia Secrets, log group /ec2/intersectia, snapshots, EIPs
```
(`make cloud-destroy` · `make nuke`)

### Opción B (Terraform)
```bash
./deploy/terraform.sh destroy   # ECR con force_delete, S3 force_destroy, RDS sin snapshot
./deploy/nuke.sh
```
(`make tf-destroy` · `make nuke`)

> Si pierdes el `.tfstate`, `terraform destroy` no sabrá qué borrar: usa `nuke.sh` y elimina a mano lo que quede.

### Opción A (docker-compose en una EC2 manual)
```bash
# en la VM:
docker compose down -v          # -v borra el volumen de Postgres
# en AWS: terminar la EC2, liberar la Elastic IP y borrar el Security Group
```

### Verificar que no quede nada
```bash
aws resourcegroupstaggingapi get-resources --region us-east-1 \
  --resource-type-filters ec2:instance,rds:db,cloudfront:distribution,elasticloadbalancing:loadbalancer,ecr:repository \
  --query "ResourceTagMappingList[].ResourceARN" --output table
```
`./deploy/nuke.sh --dry-run` lista los restos sin borrar (Secrets Manager, log groups, snapshots, EIPs).

### Por qué podría quedar algo
- **Secrets Manager**: ventana de recuperación de 7 días (A+); `nuke.sh` los fuerza.
- **Log group `/ec2/intersectia`**: lo crea `awslogs` en runtime, no lo gestiona CloudFormation.
- **Snapshots de RDS**: A+ usa `Delete` y B `skip_final_snapshot` (no deberían quedar).
- **`.tfstate` local de Terraform**: sin él, `destroy` no sabe qué borrar.
