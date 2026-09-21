# Operaciones de IntersectIA.
# Local (docker-compose):  make up / down / logs / migrate
# AWS (CloudFormation):    make cloud-up / cloud-outputs / cloud-destroy
# Actualizar en la EC2:    make cloud-update ID=... S=frontend
.PHONY: up down logs ps rebuild migrate setup cloud-up cloud-status cloud-outputs cloud-destroy cloud-update

# --- Local / VM con docker-compose ---
up:
	docker compose up -d --build

down:
	docker compose down

logs:
	docker compose logs -f

ps:
	docker compose ps

rebuild:
	docker compose build --no-cache

migrate:
	docker compose exec backend npx prisma migrate deploy

setup:
	bash deploy/ec2-setup.sh

# --- AWS con CloudFormation (EC2 + RDS + CloudFront) ---
cloud-up:
	bash deploy/ec2-cfn.sh up

cloud-status:
	bash deploy/ec2-cfn.sh status

cloud-outputs:
	bash deploy/ec2-cfn.sh outputs

cloud-destroy:
	bash deploy/ec2-cfn.sh destroy

# make cloud-update ID=i-xxxx S=frontend   (S = frontend|backend|ai|all)
cloud-update:
	bash deploy/ec2-update.sh $(ID) $(S)
