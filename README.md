# NullNode

Plataforma LLMOps completa, privada y local. Un clúster K3s de un nodo sobre tu
máquina, con las piezas que tendría un despliegue enterprise: gateway con claves
y "presupuestos por departamento", caché de prompts, autoescalado del pool de
inferencia, observabilidad de GenAI y todo gestionado por GitOps.

Coste: 0 € (solo luz). Todo corre en tu hardware y los servicios de AWS están mockeados.

```bash
make up          # perfil GPU (por defecto)
PROFILE=cpu make up
make status
make smoke
```

<!-- despliegue en consola, `make up` de principio a fin -->
<p align="center">
  <img src="docs/media/deploy.gif"  width="80%">
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
  <img src="docs/media/Arquitectura_NullNode.png"  width="90%">
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

<!-- GIF: Grafana (GenAI, gasto, VRAM) 
<p align="center">
  <img src="docs/media/dashboards.gif" width="80%">
</p>
-->
## Requisitos

Docker, k3d ≥ 5.6, kubectl, Helm ≥ 3.14, Terraform ≥ 1.6. El preflight de
`make up` los comprueba y enlaza la instalación de lo que falte.

También `make`, que en una WSL2 recién instalada no viene:
`sudo apt install make`. Si prefieres no instalarlo, todos los targets son
envoltorios finos sobre `scripts/`:

| `make` | equivalente |
| --- | --- |
| `make up` | `./scripts/up.sh` |
| `make down` | `./scripts/down.sh` |
| `make status` | `./scripts/status.sh` |
| `make smoke` | `./scripts/smoke.sh` |
| `make validate` | `./scripts/validate.sh` |
| `make security` | `./scripts/security.sh` |
| `PROFILE=cpu make up` | `PROFILE=cpu ./scripts/up.sh` |

16 GiB de RAM y ~60 GiB de disco en perfil GPU; 8 GiB de RAM en CPU.

## Posibles mejoras

Lo que tiene sentido añadir sin cambiar la arquitectura base:

- **GPUs no-NVIDIA.** El runtime CUDA es el único punto que ata la plataforma
  a NVIDIA. Con ROCm (AMD) o CPU offloading (Apple Silicon vía GGML) el cambio
  es en la imagen de k3s y en el device plugin; el gateway, la caché y el
  resto no se tocan. Hoy no hay imagen k3s equivalente para ROCm, pero es
  cuestión de tiempo.

- **Proveedor hosted en el catálogo.** Con todo local el dashboard de FinOps es
  un ensayo. Un modelo de pago detrás de una variable convierte los
  presupuestos por departamento en un control real.

- **External Secrets Operator.** El flujo ya tiene la forma correcta: el
  operador leería el mismo Secrets Manager y mantendría los Secrets
  sincronizados con rotación sin tener que hacer `terraform apply`.

- **Open WebUI como componente opcional.** Hoy se documenta como un
  `docker run` de cliente. Meterlo en el app-of-apps con `enabled: false`
  daría chat con Ingress y clave de departamento sin pasos manuales.

- **Backend de trazas.** El collector ya recibe OTLP de LiteLLM y deriva
  spanmetrics. Añadir Tempo y su datasource en Grafana permitiría abrir una
  petición lenta y ver en qué paso se fue el tiempo.

- **Namespaces multi-tenant.** Ahora hay cuotas lógicas en el gateway pero no
  cuotas de recursos en Kubernetes. Un namespace por departamento con
  `ResourceQuota` cierra esa brecha.

## Documentación

[docs/](docs/) — arquitectura, decisiones, runbook, guía de conexión para devs.

---

<p align="center">
  <img src="docs/media/NullNode-mii.gif" width="10%">
  <img src="docs/media/NullNode-tepig.gif" width="6%">
</p>

<p align="center">DavidNull 🐰</p>
