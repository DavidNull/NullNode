# NullNode <img src="docs/media/nullnode.png" alt="NullNode Logo" width="70" style="vertical-align: middle; margin-left: 10px;">

La idea nació de algo muy concreto: un grupo de gente en su casa que quiere tener su propia IA ligera (porque con recursos domésticos no da para más), sin pagar un euro, y con control real de quién gasta qué y a qué hora. Gobernanza, básicamente. 

<p align="center">
  <img src="https://img.shields.io/badge/K3s-Kubernetes-FFC61C?style=flat-square&logo=k3s&logoColor=white" alt="K3s">
  <img src="https://img.shields.io/badge/ArgoCD-GitOps-EF4444?style=flat-square&logo=argo&logoColor=white" alt="ArgoCD">
  <img src="https://img.shields.io/badge/Terraform-IaC-844FBA?style=flat-square&logo=terraform&logoColor=white" alt="Terraform">
  <img src="https://img.shields.io/badge/Helm-Package%20Manager-0F1689?style=flat-square&logo=helm&logoColor=white" alt="Helm">
  <img src="https://img.shields.io/badge/LiteLLM-Gateway-3B82F6?style=flat-square&logo=openai&logoColor=white" alt="LiteLLM">
  <img src="https://img.shields.io/badge/Ollama-Inference-000000?style=flat-square&logo=ollama&logoColor=white" alt="Ollama">
  <img src="https://img.shields.io/badge/Redis-Prompt%20Cache-DC2626?style=flat-square&logo=redis&logoColor=white" alt="Redis">
  <img src="https://img.shields.io/badge/KEDA-Autoscaling-FF9900?style=flat-square&logo=kubernetes&logoColor=white" alt="KEDA">
  <img src="https://img.shields.io/badge/PostgreSQL-Database-4169E1?style=flat-square&logo=postgresql&logoColor=white" alt="PostgreSQL">
  <img src="https://img.shields.io/badge/Prometheus-Metrics-E6522C?style=flat-square&logo=prometheus&logoColor=white" alt="Prometheus">
  <img src="https://img.shields.io/badge/Grafana-Dashboards-F46800?style=flat-square&logo=grafana&logoColor=white" alt="Grafana">
  <img src="https://img.shields.io/badge/OpenTelemetry-Tracing-000000?style=flat-square&logo=opentelemetry&logoColor=white" alt="OpenTelemetry">
  <img src="https://img.shields.io/badge/LocalStack-AWS%20Mock-000000?style=flat-square&logo=localstack&logoColor=white" alt="LocalStack">
</p>

Plataforma LLMOps enterprise local y privada sobre K3s. Implementa inferencia local de LLMs con escalado dinámico (KEDA), gateway con presupuestos y control de costes (LiteLLM), caché de prompts (Redis), observabilidad dedicada GenAI y despliegue automatizado 100% por GitOps con ArgoCD y Terraform.

Coste: 0 € (solo luz). Todo corre en tu hardware y los servicios de AWS están mockeados.

```bash
make up          # perfil GPU (por defecto)
PROFILE=cpu make up
make status
make smoke
```

<!-- despliegue en consola, `make up` de principio a fin -->
<p align="center">
  <img src="docs/media/deploy.gif" alt="Despliegue de NullNode en consola, make up de principio a fin" width="80%">
</p>

Todo mockeado: AWS, S3, Bedrock, etc.
<p align="center">
  <img src="docs/media/mockeado.png" alt="Servicios AWS mockeados en NullNode" width="80%">
</p>

---

## Antes de arrancar

### 1. Por defecto asume GPU NVIDIA

Necesitas: driver NVIDIA en el host (en Windows si usas WSL2, no en la distro),
`nvidia-container-toolkit` dentro de la distro con Docker reiniciado, la imagen
`make k3s-cuda-image` (una vez, los nodos de k3d son contenedores y la oficial
no trae el runtime), y el device plugin, que se instala solo con el perfil GPU.
El preflight de `make up` te dice cuál falta.

**Sin GPU:** `PROFILE=cpu make up`. Todo igual, solo más lento por respuesta.

### 2. Con una sola GPU no escales réplicas

El device plugin asigna la tarjeta en exclusiva, así que la segunda réplica se
queda `Pending`. La concurrencia se consigue con `OLLAMA_NUM_PARALLEL`. En
perfil CPU sí escala. Ver [ADR-0004](docs/adr/0004-scaling-signal.md).

### 3. Se reconcilia desde git, no desde tu copia local

Editar un fichero no hace nada hasta que lo pusheas a la revisión que ArgoCD
sigue. Para iterar sobre una rama:

```bash
terraform -chdir=infra/terraform/platform-bootstrap apply \
  -var gitops_target_revision=mi-rama
```

### 4. El primer arranque tarda 10-20 minutos

Se descargan la pila de observabilidad y los pesos de los modelos. `^C` es
seguro: ArgoCD sigue reconciliando por dentro.

### 5. No hay UI de chat

`make up` expone un endpoint compatible con OpenAI. Conéctate desde VS Code
con Continue o Cline: [docs/uso/CONECTAR.md](docs/uso/CONECTAR.md).

### 6. Versiones pinneadas sin verificar en red

Los charts de terceros están fijados a ciegas: pasa `make versions-check`
antes del primer despliegue. Las métricas de LiteLLM dependen de la versión
pinneada, y afectan a dashboards y al trigger de KEDA
([ADR-0006](docs/adr/0006-metrics-sources.md)).

---

## Arquitectura

<!-- diagrama de arquitectura (queda diseñarla) -->
<p align="center">
  <img src="docs/media/Arquitectura_NullNode.png" alt="Diagrama de arquitectura de NullNode" width="90%">
</p>

Una petición: entra por Traefik → LiteLLM valida la clave del departamento y su
presupuesto → consulta la caché en Redis → si es miss, enruta a Ollama →
registra gasto en Postgres, traza en el collector, métrica en Prometheus y la
petición completa en S3.

| Capa | Componente | Qué hace |
| --- | --- | --- |
| Gateway | LiteLLM | Endpoint compatible con OpenAI. Claves virtuales por departamento con presupuesto, TPM y RPM. Caché, guardrail de PII, auditoría. |
| Caché | Redis | Caché de prompts y estado compartido del router. |
| Gobierno | PostgreSQL | Equipos, claves y presupuestos. Sobreviven a un reinicio y se cambian por API. |
| Inferencia | Ollama | StatefulSet con caché de modelos por réplica y precarga de pesos. |
| Escalado | KEDA | Escala según peticiones por segundo, no según CPU. |
| Observabilidad | Prometheus, Grafana, OTel, DCGM | TTFT, tokens/s, hit rate, gasto por equipo, VRAM. |
| Guardrails | Presidio | Detección y enmascarado de PII. Opcional. |
| Cloud mock | LocalStack | S3 y Secrets Manager. De aquí salen los secretos. |
| GitOps | ArgoCD | App-of-apps con sync waves, un solo Application raíz. |
| IaC | Terraform, k3d | Dos stacks: cloud mockeado y bootstrap de la plataforma. |

<br>
<p align="center">
  <img src="docs/media/grafana.png" alt="Dashboards de Grafana: GenAI, gasto y VRAM" width="80%">
</p>

## Requisitos

Docker, `k3d` ≥ 5.6, `kubectl`, `Helm` ≥ 3.14, `Terraform` ≥ 1.6. El preflight
de `make up` los comprueba y enlaza la instalación de lo que falte.

También `make`, en una WSL2 recién instalada no lo trae🤓:
`sudo apt install make`. O usa `scripts/` directamente si pasas de instalaciones extra:

| `make` | equivalente |
| --- | --- |
| `make up` | `./scripts/up.sh` |
| `make down` | `./scripts/down.sh` |
| `make status` | `./scripts/status.sh` |
| `make smoke` | `./scripts/smoke.sh` |
| `make validate` | `./scripts/validate.sh` |
| `make security` | `./scripts/security.sh` |
| `PROFILE=cpu make up` | `PROFILE=cpu ./scripts/up.sh` |


## Documentación

[docs/](docs/) — arquitectura, decisiones, runbook, guía de conexión para devs.

---

<p align="center">
  <img src="docs/media/NullNode-mii.gif" alt="Mii de NullNode" width="10%">
  <img src="docs/media/NullNode-tepig.gif" alt="Tepig de NullNode" width="6%">
</p>

<p align="center">DavidNull 🐰</p>
