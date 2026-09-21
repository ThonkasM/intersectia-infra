# La IA en la nube

El servicio de IA tiene **dos caminos muy distintos**. En cloud se comportan así:

## 1) Decisión de cruce (`/decision`) — sin LLM, junto al backend

- Es una **política en memoria** (QTable cargada de `data/trained_policy.json`). Corre en **CPU**, sin
  red y sin GPU. Presupuesto **150 ms**; si falla o tarda, el backend cae al motor determinista.
- En cloud corre **en el mismo host que el backend** (misma task de ECS Fargate, o contenedor en la
  VM de la Opción A) y se llama por `http://localhost:8000`. Nunca se expone a Internet.
- El artefacto se **entrena en el build** de la imagen (`RUN python -m app.policy.train`), así no
  depende del archivo gitignored.
- **Reentrenar en la VM** (segundos): `docker compose exec ai python -m app.policy.train`.
  A mayor escala: **AWS Batch** o **SageMaker Training** con instancia CPU (el entrenamiento no usa GPU).
- Alternativa más flexible: guardar el artefacto en **S3 versionado** y bajarlo al arrancar, para
  cambiar la política sin reconstruir la imagen.

## 2) Chat (`/chat`) — RAG local + LLM con Amazon Bedrock

- El **retriever (TF-IDF) y la base de conocimiento** (`data/knowledge_base/*.md`) son **locales**: sin
  servicios externos ni coste.
- La generación usa **Amazon Bedrock** (`boto3 bedrock-runtime`). Para que funcione en cloud hacen falta:

| Requisito | Opción A (EC2) | Opción B (ECS Fargate) |
|---|---|---|
| Credenciales IAM | **Instance profile** con `bedrock:InvokeModel` | **Task role** con `bedrock:InvokeModel` (ya en el Terraform) |
| Acceso desde el contenedor | **IMDS hop limit = 2** (Docker agrega un salto) | Credenciales inyectadas por ECS |
| Acceso al modelo | Habilitar en la consola de **Bedrock → Model access** | Igual |
| Región | `AI_AWS_REGION` con el perfil de inferencia (`us-east-1`/`us-west-2`) | Igual |
| Salida a Internet | Subred pública + IGW (o NAT) | NAT Gateway (o VPC endpoints) |

- Si falta cualquiera de estos, el chat **degrada offline** con el `contextoResumen` del tema (no falla;
  ya lo verificamos localmente: sin credenciales responde sin LLM).
- Config: `AI_AWS_REGION`, `AI_BEDROCK_MODEL_ID` (por defecto `us.meta.llama3-1-8b-instruct-v1:0`).

## Seguridad

- El servicio de IA es **interno**: solo el backend lo llama con `X-Internal-Token`. No se expone al
  navegador ni al ALB.
- Las respuestas exactas (Q&A) y los saludos **no** llaman al LLM; solo las preguntas que requieren
  generación. Eso reduce coste y latencia.

## Coste

- `/decision`: **$0 extra** (usa la CPU del contenedor que ya corre).
- `/chat`: se paga por **tokens de Bedrock**, solo cuando se usa el LLM.

## Habilitar Bedrock en la Opción A (EC2)

```bash
# 1) Desde tu máquina (AWS CLI con permisos):
./deploy/ec2-bedrock-iam.sh <instance-id> us-east-1

# 2) Habilita el modelo en la consola de Bedrock (Model access) en esa región.

# 3) En la VM, reinicia la IA:
docker compose restart ai

# 4) Prueba (por el nginx/proxy):
curl -s -X POST http://<IP>/ai/chat -H 'Content-Type: application/json' \
  -d '{"message":"Explicame la comunicacion V2V"}'
```

Sin esos pasos, la demo funciona igual: el chat responde con la base de conocimiento (offline) y la
decisión de cruce usa la política entrenada con normalidad.

## Requisito de cuenta AWS (importante)

CloudFront **y** Bedrock dependen de que la **cuenta AWS esté verificada**:

- **CloudFront**: al crear una distribución, una cuenta no verificada devuelve
  `403 Your account must be verified before you can add new CloudFront resources`.
- **Bedrock**: con la cuenta sin verificar, `get-foundation-model-availability` muestra
  `authorizationStatus: NOT_AUTHORIZED` (para **todos** los modelos, no solo Meta) e `InvokeModel`
  devuelve `ValidationException: Operation not allowed`.

En ambos casos la app sigue funcionando (HTTP directo + chat offline). Una vez verificada la cuenta:

- CloudFront: `ENABLE_CLOUDFRONT=true ./deploy/ec2-cfn.sh up`.
- Bedrock: se **auto-habilita en la primera invocación** (el instance role ya tiene
  `bedrock:InvokeModel` y el **IMDS hop limit = 2** viene en el template, que es lo que permite al
  contenedor tomar las credenciales del rol). No requiere redeploy.

Comprobar el estado de Bedrock:
```bash
aws bedrock get-foundation-model-availability \
  --model-id meta.llama3-1-8b-instruct-v1:0 --region us-east-1
```
