# Initial template audit

**Date:** 2026-08-26 · **Scope:** commits `467c4b9` and `f985943`

The previous repository state described six completed phases. The structure was
reasonable and the documentation coherent, but the whole thing didn't start: there
were errors that prevent a `terraform init`, invalid GitOps references, and
components declared as deployed that didn't exist in any manifest.

This document records what was wrong and what was done, so the progress log
doesn't inherit claims that don't hold up.

## Blockers

Things that fail before deploying anything.

| # | Where | Problem |
| --- | --- | --- |
| B1 | `terraform/main.tf` + `versions.tf` | Two `required_providers` blocks in the same module. `terraform init` fails with *Duplicate required providers configuration*. |
| B2 | `terraform/main.tf` + `outputs.tf` | `cluster_name` declared twice and `kubeconfig`/`kubeconfig_path` duplicating the same value. Validation error. |
| B3 | `terraform/` ↔ `k8s/platform/localstack/` | Deadlock: Terraform needs LocalStack to create the secret, the secret is consumed by LiteLLM, LiteLLM is deployed by ArgoCD, and ArgoCD is what deploys LocalStack. |
| B4 | `k8s/platform/argocd-apps.yaml` | `repoURL: ./` in two Applications. Not a valid repository URL. |
| B5 | `k8s/platform/argocd-apps.yaml` | `valueFiles: ['../../../k8s/platform/...']` pointing outside the chart tree. ArgoCD rejects it. |
| B6 | `k8s/platform/argocd-apps.yaml` | The `observability` Application pointed to a GitHub repo without `path` or `chart`. |
| B7 | `scripts/up.sh` | `kubectl apply -f kustomization.yaml` applies the kustomize file as a manifest. Needs `apply -k`. |
| B8 | `scripts/up.sh` | `export KUBECONFIG=$(terraform output -raw kubeconfig_path)` assigns the kubeconfig *content* to a variable that expects a path. |
| B9 | `k8s/platform/localstack/templates/service.yaml` | `nodePort: 4566`, outside the valid range (30000-32767). The Service isn't created. |

## Components declared but non-existent

`GOTO.md` marked phases 3 to 5 as completed. Missing:

- **Redis.** Referenced by LiteLLM (`redis.platform.svc.cluster.local`) and by the
  KEDA trigger. No chart or manifest existed that deployed it.
- **Postgres.** `DATABASE_URL` pointed to `postgres.platform.svc.cluster.local`.
  Also didn't exist. Without it, per-department quotas aren't implementable:
  LiteLLM stores teams, keys and budgets in a database.
- **The KEDA operator.** There was a `ScaledObject` but nothing that installed the
  operator that interprets it. `argocd-apps.yaml` didn't include KEDA.
- **Prometheus and Grafana.** There was a `values.yaml`, but the Application that
  consumed it was malformed (B6).
- **The Grafana dashboard.** The JSON was in the repo without connecting to
  anything, and the Grafana values provisioned `gnetId: 1`, a random public
  dashboard.
- **OpenTelemetry.** Mentioned in `CONTEXT.md` and in the README as part of
  observability. Didn't appear in any file.

## Incorrect configuration

| # | Where | Problem |
| --- | --- | --- |
| C1 | `litellm/values.yaml` | `generalSettings.drop_params: ["messages", "tools"]`. `drop_params` is a boolean; as a list with those values, it would discard request content. |
| C2 | `litellm/templates/configmap.yaml` | Invented `security_settings` block (`pii_masking`, `quota_management`...). LiteLLM doesn't have that key: ignores the block and none of those protections activate. |
| C3 | `litellm/values.yaml` | `model_list` without the `model` parameter. With only `model_name` and `api_base`, the router doesn't know what to invoke. |
| C4 | `litellm/templates/deployment.yaml` | Probes against `/health`, which requires auth. The open endpoints are `/health/liveliness` and `/health/readiness`. |
| C5 | `litellm/values.yaml` | Master key, salt key and Postgres password in clear and committed, plus duplicated manually in Terraform. |
| C6 | `litellm/templates/*` | The ConfigMap was mounted but `--config` wasn't passed to the process, and without a checksum annotation a config change wouldn't restart pods. |
| C7 | `ollama/values.yaml` | `nodeSelector: {accelerator: nvidia-tesla-k80}`. No workstation has that label; the pod stays `Pending` indefinitely. |
| C8 | `ollama/templates/deployment.yaml` | Deployment with `ReadWriteOnce` PVC and KEDA scaling to 5 replicas. From the second one, pods don't start. |
| C9 | `ollama/templates/deployment.yaml` | Model download in a `postStart` hook, which runs in parallel to server startup: `ollama pull` fails because there's no server to talk to yet. And the pod is marked `Ready` without models. |
| C10 | `keda/scaledobject.yaml` | Redis trigger on the `litellm:queue` list, which doesn't exist. LiteLLM doesn't enqueue requests in Redis. The scaler would always read 0. |
| C11 | `observability/grafana/dashboards/ai-metrics.json` | Non-existent metrics (`litellm_request_duration_seconds_bucket`, `litellm_requests_total`, `litellm_tokens_generated_total`). |
| C12 | `observability/prometheus/values.yaml` | Without disabling control plane scrape targets, which in k3s don't expose metrics: kube-* panels permanently red. |
| C13 | `.github/workflows/load-test.yaml` | `ab -p test-payload.json` with a file that doesn't exist in the repo, without auth and without waiting for the gateway to respond. |
| C14 | `k8s/bootstrap/argo-cd/kustomization.yaml` | Patch adding port 4000 to the `argocd-server` Service, mixing the gateway with the ArgoCD UI. |

## What was done

- **Rebuilt:** the two Terraform stacks, the app-of-apps pattern, the LiteLLM and
  Ollama charts, the full observability and the lifecycle scripts.
- **New:** Redis, Postgres and Presidio charts; KEDA, kube-prometheus-stack,
  OTel Collector, device plugin and DCGM exporter installation; department
  bootstrap job; three dashboards against real metrics; recording rules and
  alerts; offline validation suite; end-to-end smoke test; k6 load profile;
  runbook and ADRs.
- **Removed:** the in-cluster LocalStack chart (ADR-0002) and the kustomize patch
  on ArgoCD (ADR-0003).
- **Renamed:** `ironnode` → `nullnode` throughout the tree, aligned with the
  repository and the remote.

## What remains unverified

None of this has been executed. In particular:

- Third-party chart versions are pinned without network access:
  `make versions-check` before first deployment.
- LiteLLM metric names depend on the pinned version (ADR-0006).
- `helm lint`, `helm template`, `terraform validate` and `shellcheck` are wired
  in `make validate` and in CI, but haven't been run.
