# Pinned versions

Everything pinned on purpose: with `latest`, the environment changes between two
`make up` and a failure stops being reproducible.

## How to verify them

```bash
make versions-check
```

Confirms that each pinned version exists and warns about the latest available.
Do this before first deployment: these versions were chosen without network
access.

[Renovate](../../renovate.json) keeps pins up to date via PR, including those in
the app-of-apps `values.yaml` via a custom manager.

## Inventory

### Third-party charts — `k8s/platform/values.yaml`

| Chart | Version | Repository |
| --- | --- | --- |
| `external-secrets` | 2.10.0 | external-secrets |
| `reloader` | 1.0.67 | stakater |
| `kube-prometheus-stack` | 65.5.1 | prometheus-community |
| `keda` | 2.15.2 | kedacore |
| `tempo` | 1.11.0 | grafana |
| `opentelemetry-collector` | 0.108.1 | open-telemetry |
| `nvidia-device-plugin` | 0.17.0 | nvidia (GPU profile only) |
| `dcgm-exporter` | 3.6.1 | nvidia (GPU profile only) |

### Bootstrap — `infra/terraform/platform-bootstrap/variables.tf`

| Chart | Version |
| --- | --- |
| `argo-cd` | 7.7.11 |

### Container images

| Image | Tag | Where |
| --- | --- | --- |
| `ghcr.io/berriai/litellm-non_root` | `main-v1.72.6-stable` | litellm chart |
| `ollama/ollama` | `0.5.7` | ollama chart |
| `redis` | `7.4-alpine` | redis chart |
| `postgres` | `16.4-alpine` | postgres chart |
| `oliver006/redis_exporter` | `v1.66.0` | redis chart |
| `quay.io/prometheuscommunity/postgres-exporter` | `v0.15.0` | postgres chart |
| `mcr.microsoft.com/presidio-analyzer` | `2.2.355` | presidio chart |
| `mcr.microsoft.com/presidio-anonymizer` | `2.2.355` | presidio chart |
| `ghcr.io/open-webui/open-webui` | `v0.11.4` | open-webui chart (GPU profile) |
| `localstack/localstack` | `4.4.0` | cloud-mock |
| `rancher/k3s` | `v1.31.2-k3s1` | CPU profile / CUDA image base |
| `python` | `3.12-alpine` | bootstrap job |

### The `litellm-non_root` variant

The standard image assumes uid 0 and the pod runs with `runAsNonRoot: true`. With
the normal one it doesn't start.

### Updating LiteLLM

Mandatory step: metric names change between minor versions (ADR-0006).

```bash
kubectl -n nullnode-platform exec deploy/litellm -- \
  sh -c 'wget -qO- localhost:4000/metrics' | grep '^litellm_' | cut -d'{' -f1 | sort -u
```

Compare with the expressions in `k8s/charts/nullnode-observability/` (panels and
recording rules) and with the KEDA trigger in the Ollama values.

### LocalStack: why 4.x and not 3.8.1

The AWS provider (`~> 5.70`, which resolves to 5.100) waits for the S3 lifecycle
configuration to become "stable" before considering the resource created.
LocalStack 3.8.1 never reports that state, so
`aws_s3_bucket_lifecycle_configuration.vault` hangs and `terraform apply` fails
at 3 minutes — this was what took down the integration job in CI. With `4.4.0`
the resource is created in ~1 min. If you lower the LocalStack pin, you also need
to lower the provider to a version before that wait.
