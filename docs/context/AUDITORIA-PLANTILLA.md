# Auditoría de la plantilla inicial

**Fecha:** 2026-08-26 · **Alcance:** commits `467c4b9` y `f985943`

El estado previo del repositorio describía seis fases completadas. La estructura
era razonable y la documentación coherente, pero el conjunto no arrancaba: había
errores que impiden un `terraform init`, referencias de GitOps inválidas y
componentes declarados como desplegados que no existían en ningún manifiesto.

Este documento deja constancia de qué estaba mal y qué se hizo, para que el
registro de avances no herede afirmaciones que no se sostienen.

## Bloqueantes

Cosas que fallan antes de desplegar nada.

| # | Dónde | Problema |
| --- | --- | --- |
| B1 | `terraform/main.tf` + `versions.tf` | Dos bloques `required_providers` en el mismo módulo. `terraform init` falla con *Duplicate required providers configuration*. |
| B2 | `terraform/main.tf` + `outputs.tf` | `cluster_name` declarado dos veces y `kubeconfig`/`kubeconfig_path` duplicando el mismo valor. Error de validación. |
| B3 | `terraform/` ↔ `k8s/platform/localstack/` | Interbloqueo: Terraform necesita LocalStack para crear el secreto, el secreto lo consume LiteLLM, LiteLLM lo despliega ArgoCD, y ArgoCD es quien despliega LocalStack. |
| B4 | `k8s/platform/argocd-apps.yaml` | `repoURL: ./` en dos Applications. No es una URL de repositorio válida. |
| B5 | `k8s/platform/argocd-apps.yaml` | `valueFiles: ['../../../k8s/platform/...']` apuntando fuera del árbol del chart. ArgoCD lo rechaza. |
| B6 | `k8s/platform/argocd-apps.yaml` | La Application `observability` apuntaba a un repositorio de GitHub sin `path` ni `chart`. |
| B7 | `scripts/up.sh` | `kubectl apply -f kustomization.yaml` aplica el fichero de kustomize como manifiesto. Hace falta `apply -k`. |
| B8 | `scripts/up.sh` | `export KUBECONFIG=$(terraform output -raw kubeconfig_path)` asigna el *contenido* del kubeconfig a una variable que espera una ruta. |
| B9 | `k8s/platform/localstack/templates/service.yaml` | `nodePort: 4566`, fuera del rango válido (30000-32767). El Service no se crea. |

## Componentes declarados pero inexistentes

`GOTO.md` marcaba las fases 3 a 5 como completadas. Faltaba:

- **Redis.** Referenciado por LiteLLM (`redis.platform.svc.cluster.local`) y por
  el trigger de KEDA. No existía ningún chart ni manifiesto que lo desplegara.
- **Postgres.** `DATABASE_URL` apuntaba a `postgres.platform.svc.cluster.local`.
  Tampoco existía. Sin él, las cuotas por departamento no son implementables:
  LiteLLM guarda equipos, claves y presupuestos en base de datos.
- **El operador de KEDA.** Había un `ScaledObject` pero nada que instalara el
  operador que lo interpreta. `argocd-apps.yaml` no incluía KEDA.
- **Prometheus y Grafana.** Había un `values.yaml`, pero la Application que lo
  consumía estaba mal formada (B6).
- **El dashboard de Grafana.** El JSON estaba en el repo sin conectar a nada, y
  el values de Grafana provisionaba `gnetId: 1`, un dashboard público ajeno.
- **OpenTelemetry.** Mencionado en `CONTEXT.md` y en el README como parte de la
  observabilidad. No aparecía en ningún fichero.

## Configuración incorrecta

| # | Dónde | Problema |
| --- | --- | --- |
| C1 | `litellm/values.yaml` | `generalSettings.drop_params: ["messages", "tools"]`. `drop_params` es un booleano; como lista con esos valores, descartaría el contenido de la petición. |
| C2 | `litellm/templates/configmap.yaml` | Bloque `security_settings` (`pii_masking`, `quota_management`...) inventado. LiteLLM no tiene esa clave: ignora el bloque y ninguna de esas protecciones se activa. |
| C3 | `litellm/values.yaml` | `model_list` sin el parámetro `model`. Con solo `model_name` y `api_base`, el router no sabe qué invocar. |
| C4 | `litellm/templates/deployment.yaml` | Probes contra `/health`, que exige autenticación. Los endpoints abiertos son `/health/liveliness` y `/health/readiness`. |
| C5 | `litellm/values.yaml` | Master key, salt key y contraseña de Postgres en claro y commiteadas, además duplicadas a mano en el Terraform. |
| C6 | `litellm/templates/*` | El ConfigMap se montaba pero no se pasaba `--config` al proceso, y sin anotación de checksum un cambio de configuración no reiniciaba los pods. |
| C7 | `ollama/values.yaml` | `nodeSelector: {accelerator: nvidia-tesla-k80}`. Ninguna estación de trabajo tiene ese label; el pod queda `Pending` indefinidamente. |
| C8 | `ollama/templates/deployment.yaml` | Deployment con PVC `ReadWriteOnce` y KEDA escalando a 5 réplicas. A partir de la segunda, los pods no arrancan. |
| C9 | `ollama/templates/deployment.yaml` | Descarga de modelos en un hook `postStart`, que corre en paralelo al arranque del servidor: `ollama pull` falla porque aún no hay servidor al que hablar. Y el pod se marca `Ready` sin modelos. |
| C10 | `keda/scaledobject.yaml` | Trigger de Redis sobre la lista `litellm:queue`, que no existe. LiteLLM no encola peticiones en Redis. El escalador leería 0 siempre. |
| C11 | `observability/grafana/dashboards/ai-metrics.json` | Métricas inexistentes (`litellm_request_duration_seconds_bucket`, `litellm_requests_total`, `litellm_tokens_generated_total`). |
| C12 | `observability/prometheus/values.yaml` | Sin desactivar los scrape targets del plano de control, que en k3s no exponen métricas: paneles de kube-* permanentemente rojos. |
| C13 | `.github/workflows/load-test.yaml` | `ab -p test-payload.json` con un fichero que no existe en el repo, sin autenticación y sin esperar a que el gateway responda. |
| C14 | `k8s/bootstrap/argo-cd/kustomization.yaml` | Parche que añade el puerto 4000 al Service de `argocd-server`, mezclando el gateway con la UI de ArgoCD. |

## Qué se hizo

- **Reconstruido:** los dos stacks de Terraform, el patrón app-of-apps, los
  charts de LiteLLM y Ollama, la observabilidad completa y los scripts de ciclo
  de vida.
- **Nuevo:** charts de Redis, Postgres y Presidio; instalación de KEDA,
  kube-prometheus-stack, OTel Collector, device plugin y DCGM exporter; Job de
  bootstrap de departamentos; tres dashboards contra métricas reales; reglas de
  grabación y alertas; suite de validación offline; test de humo end-to-end;
  perfil de carga con k6; runbook y ADRs.
- **Eliminado:** el chart de LocalStack in-cluster (ADR-0002) y el parche de
  kustomize sobre ArgoCD (ADR-0003).
- **Renombrado:** `ironnode` → `nullnode` en todo el árbol, alineado con el
  repositorio y el remoto.

## Lo que sigue sin verificarse

Nada de esto se ha ejecutado. En particular:

- Las versiones de los charts de terceros están pinneadas sin acceso a red:
  `make versions-check` antes del primer despliegue.
- Los nombres de las métricas de LiteLLM dependen de la versión pinneada
  (ADR-0006).
- `helm lint`, `helm template`, `terraform validate` y `shellcheck` están
  cableados en `make validate` y en CI, pero no se han corrido.
