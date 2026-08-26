# Versiones pinneadas

Todo pinneado a propósito: con `latest`, el entorno cambia entre dos `make up`
y un fallo deja de ser reproducible.

## Cómo verificarlas

```bash
make versions-check
```

Confirma que cada versión pinneada existe y avisa de la última disponible.
Hazlo antes del primer despliegue: estas versiones se eligieron sin acceso a
red.

[Renovate](../../renovate.json) mantiene los pins al día vía PR, incluidos los del
`values.yaml` del app-of-apps mediante un custom manager.

## Inventario

### Charts de terceros — `k8s/platform/values.yaml`

| Chart | Versión | Repositorio |
| --- | --- | --- |
| `kube-prometheus-stack` | 65.5.1 | prometheus-community |
| `keda` | 2.15.2 | kedacore |
| `opentelemetry-collector` | 0.108.1 | open-telemetry |
| `nvidia-device-plugin` | 0.17.0 | nvidia (solo perfil GPU) |
| `dcgm-exporter` | 3.6.1 | nvidia (solo perfil GPU) |

### Bootstrap — `infra/terraform/platform-bootstrap/variables.tf`

| Chart | Versión |
| --- | --- |
| `argo-cd` | 7.7.11 |

### Imágenes de contenedor

| Imagen | Tag | Dónde |
| --- | --- | --- |
| `ghcr.io/berriai/litellm-non_root` | `main-v1.72.6-stable` | chart litellm |
| `ollama/ollama` | `0.5.7` | chart ollama |
| `redis` | `7.4-alpine` | chart redis |
| `postgres` | `16.4-alpine` | chart postgres |
| `oliver006/redis_exporter` | `v1.66.0` | chart redis |
| `quay.io/prometheuscommunity/postgres-exporter` | `v0.15.0` | chart postgres |
| `mcr.microsoft.com/presidio-analyzer` | `2.2.355` | chart presidio |
| `mcr.microsoft.com/presidio-anonymizer` | `2.2.355` | chart presidio |
| `localstack/localstack` | `3.8.1` | cloud-mock |
| `rancher/k3s` | `v1.31.2-k3s1` | perfil CPU / base de la imagen CUDA |
| `python` | `3.12-alpine` | Job de bootstrap |

### La variante `litellm-non_root`

La imagen estándar asume uid 0 y el pod corre con `runAsNonRoot: true`. Con la
normal no arranca.

### Actualizar LiteLLM

Paso obligatorio: los nombres de las métricas cambian entre versiones menores
(ADR-0006).

```bash
kubectl -n nullnode-platform exec deploy/litellm -- \
  sh -c 'wget -qO- localhost:4000/metrics' | grep '^litellm_' | cut -d'{' -f1 | sort -u
```

Comparar con las expresiones de `k8s/charts/nullnode-observability/` (paneles y
reglas de grabación) y con el trigger de KEDA en el values de Ollama.
