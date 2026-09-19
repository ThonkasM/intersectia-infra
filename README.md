# IntersectIA Infra

Repositorio de infraestructura y despliegue de IntersectIA. No contiene código de aplicación: describe cómo se empaquetan (Docker), cómo se despliegan en AWS y documenta la arquitectura, los casos de uso y las decisiones de operación.

## Contenido

- `docker-compose.yml` — stack completo (Postgres + backend + AI + frontend) para correr en local o en una VM (EC2/Lightsail) sin AWS gestionado.
- `terraform/` — infraestructura mínima en AWS (S3 + CloudFront, ECR, ECS Fargate, RDS, Secrets Manager, IAM).
- `docs/` — arquitectura, despliegue, seguridad/costos, casos de uso y diagramas Mermaid.
- `.github/workflows/` — pipeline de ejemplo (OIDC → ECR → ECS).

## Proyectos

| Repo | Rol | Puerto | Dockerfile |
|---|---|---|---|
| `intersectia-frontend` | Next.js 16 estático (Three.js) | 3000 dev / 80 nginx | `Dockerfile` |
| `intersectia-backend` | NestJS + Prisma + socket.io (fuente de verdad) | 3000 | `Dockerfile` |
| `intersectia-ai` | FastAPI (`/decision`, `/chat`) | 8000 | `Dockerfile` |

Los repos deben clonarse como hermanos de `intersectia-infra` para que los `build context` de `docker-compose.yml` y Terraform funcionen.

## Arranque rápido local (Docker)

```bash
cp .env.example .env
docker compose up -d --build
# Frontend: http://localhost:8080
# Backend:  http://localhost:3000
# AI:       http://localhost:8000/health
```

## Despliegue AWS (resumen)

Arquitectura mínima pensada para una demo de taller universitario:

- Frontend estático → **S3 + CloudFront** (Origin Access Control).
- Backend + AI → **un servicio ECS Fargate** con dos contenedores en la misma task (AI accesible por `localhost:8000`), detrás de un **ALB**.
- Base de datos → **RDS PostgreSQL** (`db.t4g.micro`), en subred privada.
- Secretos → **AWS Secrets Manager**.
- Imágenes → **ECR** (tags inmutables por commit).
- CI/CD → **GitHub Actions con OIDC** (sin credenciales de larga duración).

Ver `docs/arquitectura-aws.md` y `docs/despliegue.md`.
