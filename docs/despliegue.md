# Guía de despliegue

Dos caminos: **VM única (barato)** o **AWS gestionado (Fargate + RDS)**.

## Prerrequisitos

- Docker y Docker Compose.
- Repos hermanos clonados: `intersectia-frontend`, `intersectia-backend`, `intersectia-ai`, `intersectia-infra`.
- (AWS gestionado) AWS CLI v2, Terraform ≥ 1.6 y una cuenta con permisos.

---

## Opción A — VM única (EC2 / Lightsail)

Ideal para una demo de taller: un solo host corre todo con Docker.

```bash
# En la VM, con los 4 repos clonados como hermanos:
cd intersectia-infra
cp .env.example .env
docker compose up -d --build
```

- Frontend: `http://<IP>:8080`
- Backend: `http://<IP>:3000`
- Postgres queda dentro de la red de Docker (no expuesto).

Puntos de atención:
- El `docker-compose.yml` construye las imágenes desde los repos locales, así que no necesita ECR.
- El backend ejecuta `npx prisma migrate deploy` al arrancar (crea las tablas).
- Para producción real, cambia `INTERNAL_SERVICE_TOKEN` y restringe `CORS_ORIGIN`.

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

## Rollback

El servicio ECS conserva revisiones previas de la task definition. Ante un fallo, actualiza el servicio a la revisión anterior:

```bash
aws ecs update-service --cluster intersectia --service backend --task-definition intersectia-backend:<revision-anterior>
```
