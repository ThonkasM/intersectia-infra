# IntersectIA — Cómo bajarlo y correrlo (guía para el equipo)

Guía para clonar los proyectos, obtener la **última versión** y correrlos en tu máquina.

## 0. Antes de empezar
- **Repos** (5, independientes): `intersectia-backend`, `intersectia-frontend`, `intersectia-ai`, `intersectia-mobile`, `intersectia-infra`.
- **La última versión está en `main`** (y en `v2`, que apunta al mismo commit). Un `git clone` normal ya trae todo.
- **Requisitos**: Git, Node 22+ (probado en 24), Python 3.10+ (probado en 3.14), Docker (recomendado para la DB).

## 1. Clonar todo
```bash
mkdir intersectia && cd intersectia
for r in intersectia-backend intersectia-frontend intersectia-ai intersectia-mobile intersectia-infra; do
  git clone https://github.com/ThonkasM/$r.git
done
```
> `main` y `v2` apuntan al mismo commit en los 5 repos, así que un clon normal ya trae la última versión.

## 2. Base de datos (PostgreSQL)
Lo más simple (Docker, viene en el backend):
```bash
cd intersectia-backend
docker compose up -d          # Postgres en localhost:5434
```
> Alternativa: un Postgres local con usuario/DB `intersectia` en `localhost:5432`; en ese caso ajusta `DATABASE_URL` en `backend/.env`.

## 3. Backend (NestJS · puerto 3000)
```bash
cd intersectia-backend
cp .env.example .env
npm install
npx prisma generate
npx prisma migrate dev
npm run start:dev
```
- Verificar: <http://localhost:3000/> → `{"name":"IntersectIA Backend","status":"ok"}`
- Tests: `npm test` · e2e: `npm run test:e2e`
- `backend/.env` por defecto asume Postgres en **5434** (el `docker compose` del backend).

## 4. IA (FastAPI · puerto 8000)
```bash
cd intersectia-ai
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
cp .env.example .env
python -m app.policy.train            # genera data/trained_policy.json (gitignored)
uvicorn app.main:app --reload --port 8000
```
- Verificar: <http://localhost:8000/health> → `{"status":"ok"}`
- Tests: `pytest`
- El **token interno** debe coincidir: `backend INTERNAL_SERVICE_TOKEN` == `ai AI_INTERNAL_SERVICE_TOKEN` (ambos `dev-internal-token`).
- El chat usa Amazon Bedrock; sin credenciales AWS **degrada offline** (sigue respondiendo). Ver `docs/ia-en-cloud.md`.

## 5. Frontend (Next.js · puerto 3001 en dev)
```bash
cd intersectia-frontend
cp .env.example .env.local
npm install
npm run dev -- -p 3001
```
- Landing: <http://localhost:3001> · Demo 3D: <http://localhost:3001/demo>
- ⚠️ Backend y frontend usan **3000** por defecto → corre el frontend en **3001**; `.env.local` sigue apuntando al backend en 3000.
- Lint/build: `npm run lint` · `npm run build` (export estático a `out/`).
- En la demo, activa **managed**/**managed-ai** para conectarte al backend; en *Opciones* puedes activar **Giros** y **Colisiones**.

## 6. Mobile (Expo SDK 57)
```bash
cd intersectia-mobile
cp .env.example .env          # EXPO_PUBLIC_API_URL
npm install
npm start                     # o: npm run android / npm run ios
```
- **Android emulator**: `EXPO_PUBLIC_API_URL=http://10.0.2.2:3000` (el host es 10.0.2.2, no localhost).
- **Dispositivo físico** (misma Wi-Fi): usa la IP LAN de tu máquina, ej. `http://192.168.1.20:3000`.
- Checks: `npm run typecheck` · `npm run lint`.
- El chatbot necesita el **backend** corriendo (`POST {API_URL}/ai/chat`); no tiene lógica de simulación.

## 7. Infra (opcional): todo el stack con Docker en un comando
```bash
cd intersectia-infra
cp .env.example .env
docker compose up -d --build
# Todo por el puerto 80 → http://localhost/
```

## 8. Puertos y variables clave
| Servicio | Puerto | Variable principal |
|---|---|---|
| Backend | 3000 | `DATABASE_URL`, `INTERNAL_SERVICE_TOKEN`, `AI_SERVICE_URL` |
| IA | 8000 | `AI_INTERNAL_SERVICE_TOKEN` |
| Frontend | 3001 dev (3000 en prod estático) | `NEXT_PUBLIC_WS_URL`, `NEXT_PUBLIC_API_URL` |
| Mobile | Metro (8081) | `EXPO_PUBLIC_API_URL` |
| Postgres | 5434 (Docker del backend) / 5432 (local) | — |

## 9. Orden de arranque
**Postgres → IA (8000) → Backend (3000) → Frontend (3001) / Mobile**.
Recuerda: `INTERNAL_SERVICE_TOKEN` (backend) y `AI_INTERNAL_SERVICE_TOKEN` (IA) deben ser iguales.

## 10. Problemas comunes
- **`EADDRINUSE` en 3000**: estás corriendo frontend y backend en el mismo puerto → frontend con `-p 3001`.
- **403 en `/ai/chat` o decisiones sin IA**: el token interno no coincide entre backend e IA.
- **`The table public.SimulationSession does not exist`**: falta `npx prisma migrate dev` en el backend.
- **La IA responde siempre genérico**: falta `data/trained_policy.json` → `python -m app.policy.train`.
- **El mobile no conecta al backend**: revisa `EXPO_PUBLIC_API_URL` (10.0.2.2 en emulador Android, IP LAN en dispositivo).

## 11. Nota sobre ramas
`main` y `v2` están **sincronizadas** (mismo commit) en los 5 repos; un `git clone` normal trae la última versión.
