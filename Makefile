# Operaciones de IntersectIA (stack de un solo host: Postgres + AI + backend + frontend)
.PHONY: up down logs ps rebuild migrate setup

up: ## Construye y levanta todo (frontend en :80)
	docker compose up -d --build

down: ## Detiene y elimina los contenedores
	docker compose down

logs: ## Sigue los logs
	docker compose logs -f

ps: ## Estado de los contenedores
	docker compose ps

rebuild: ## Reconstruye las imagenes sin cache
	docker compose build --no-cache

migrate: ## Aplica migraciones de Prisma en la base del compose
	docker compose exec backend npx prisma migrate deploy

setup: ## Aprovisiona en una VM/EC2 (Docker + repos + stack)
	bash deploy/ec2-setup.sh
