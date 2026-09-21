# Guion de demo (AWS)

## Pre-chequeos (5 min antes)

```bash
IP=<EC2_PUBLIC_IP>

# App y demo 3D
curl -s -o /dev/null -w "/: %{http_code}\n"     "http://$IP/"
curl -s -o /dev/null -w "/demo: %{http_code}\n" "http://$IP/demo"

# Backend + base de datos
curl -s "http://$IP/metrics/summary"

# Chat (respuesta exacta, sin LLM)
curl -s -X POST "http://$IP/ai/chat" -H 'Content-Type: application/json' -d '{"message":"¿Qué es IoT?"}'

# CloudFront habilitado? (salida AppURL: https://... o http://<IP>)
aws cloudformation describe-stacks --stack-name intersectia --region us-east-1 \
  --query "Stacks[0].Outputs[?OutputKey=='AppURL'].OutputValue" --output text

# Bedrock (LLM del chat) autorizado?
aws bedrock get-foundation-model-availability \
  --model-id meta.llama3-1-8b-instruct-v1:0 --region us-east-1
#   AUTHORIZED    -> el chat generará con el LLM
#   NOT_AUTHORIZED-> el chat responde offline (igual funciona). Requiere verificar la cuenta AWS.
```

## Demo (10–15 min)

1. **Landing** (`/`): qué es IoT, vehículos autónomos, niveles SAE, V2V/V2I, y la sección **Teoría**.
2. **Demo 3D** (`/demo`): el backend **simula** (fuente de verdad) y el frontend solo **interpola**.
3. **Modos**: `traditional` (prioridad a la derecha, local) → `managed` (FIFO) → `managed-ai` (política entrenada).
4. **Opciones**: activar **Giros** y **Colisiones**. Mostrar el árbol de giros y los guiñadores.
5. **Métricas (HUD)**: cruces, espera media, **throughput**, **p95** y **equidad** por dirección.
6. **Chat**: preguntar por IoT, V2V, o "¿cómo controlo la demo?". Fuera de tema → "no tengo información".
7. **(Opcional) Mobile**: `EXPO_PUBLIC_API_URL=http://$IP` y mostrar el mismo chatbot desde la app.

## Operación

```bash
cd intersectia-infra
ID=i-0e46bb692142a1e29

# Actualizar un servicio (git pull + rebuild en la EC2, por SSM)
./deploy/ec2-update.sh "$ID" frontend     # o backend | ai | all

# Ver logs (sin SSH)
aws ssm start-session --target "$ID" --region us-east-1
#   dentro: cd /home/ec2-user/intersectia && docker-compose logs -f

# Borrar todo (después del parcial)
./deploy/ec2-cfn.sh destroy && ./deploy/nuke.sh
```
