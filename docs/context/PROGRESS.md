# Progress log

## [2026-09-17] — External Secrets Operator replaces Terraform bridge

### Motivation

Kubernetes Secrets were created by `platform-bootstrap` reading Secrets Manager
with a `data source`. A `data source` only re-evaluates on a `terraform apply`,
so rotating a credential at the source wouldn't reach the cluster until the next
apply. ADR-0005 already anticipated replacing it with External Secrets Operator;
this makes it happen.

### What was done

- **Operator** (`k8s/platform/values/external-secrets.yaml`, component
  `externalSecrets`): `external-secrets` chart 2.10.0 as an `Application` in wave
  -20, before datastores and gateway. ESO's AWS provider has no endpoint field,
  so it points to LocalStack with `AWS_SECRETSMANAGER_ENDPOINT` /
  `AWS_STS_ENDPOINT` in the controller.
- **Wiring** (`k8s/charts/external-secrets-config`, component
  `externalSecretsConfig`, wave -5): a `ClusterSecretStore` against the mocked
  Secrets Manager and one `ExternalSecret` per credential. Each one creates the
  same Secret and the same keys that Terraform projected, so no consumer chart
  changes. The static Secret `nullnode-aws-credentials` (test/test) moves here;
  both pods and the store itself use it to authenticate.
- **Terraform**: `platform-bootstrap/secrets.tf` loses the five
  `kubernetes_secret_v1`; only the read-only `data source` remains, which feeds
  `make key` / `make grafana-password`. Cleaned up the `depends_on` from the
  root `Application` and the comment in `namespaces.tf`.
- **GitOps**: the `AppProject` adds the `charts.external-secrets.io` repo and the
  `external-secrets` namespace to its destinations. The `nullnode.localApp`
  helper gains `extraSyncOptions` (parity with `upstreamApp`) so the config chart
  can declare `SkipDryRunOnMissingResource` against the CRD order.
- **CI**: ESO pin added to `versions-check.sh`. New ADR-0007; ADR-0005,
  GOTO.md and the ADR index updated.

### Verification (offline, no cluster)

`helm lint`/`template` of the new chart and the app-of-apps on both profiles,
kube-linter and `trivy config` on the project's charts (clean; the
`access-to-secrets` findings are from the upstream chart, which the pipeline
doesn't scan), `terraform fmt`/`validate` of `platform-bootstrap`, and render of
the controller confirming the injected endpoint. The platform hasn't been
raised.

### Pending

- **Reloader**: `secretKeyRef` via env doesn't reload hot, so end-to-end rotation
  still requires a rollout. A Reloader that watches the Secret and restarts the
  Deployment closes the loop.
- **Per-department keys**: the bootstrap job publishes them to Secrets Manager
  but nothing reads them back to a Secret. Another `ExternalSecret` would let
  Open WebUI use a scoped key instead of the master key.

## [2026-09-03] — Fixing bugs in the CI integration pipeline

### Observed symptoms

- The integration pipeline (`CI / CPU-profile integration`) hung indefinitely at
  the PostgreSQL step until the job's 60 min timeout.
- `nullnode-root` showed status `Unknown` (or not synced) in ArgoCD.
- The `push → main` trigger was temporarily disabled as a workaround.

### Root cause identified

**Critical bug in `scripts/up.sh` (`phase_verify`):** the 60-attempt loop that
waits for `nullnode-root` to become `Synced` ended up calling `err "..."` instead
of `die "..."`. The `err` function only prints a message; `die` aborts the script.
By not aborting, the script continued to the next phase: `wait_for
"application/postgres to exist" 300 10`, which waits 300 × 10 s = 50 minutes if
the ArgoCD Application doesn't exist (exact situation when `nullnode-root`
didn't sync). With the CI timeout at 60 min, the job always exploded during that
wait.

The `Unknown` status of `nullnode-root` was a consequence of the first sync on
a cold cluster (images not in cache, ArgoCD repo-server's first `git clone`):
with 60 attempts × 10 s = 10 min margin, a slow startup exceeded the threshold.

### Problems found and fixed

| # | File | Problem | Fix |
|---|------|---------|-----|
| 1 | `k8s/bootstrap/root/templates/project.yaml` | **Root cause.** The `nullnode` AppProject didn't list `argocd` in `destinations`. `nullnode-root` deploys child Application CRDs to the `argocd` namespace. ArgoCD validates the destination against the AppProject before syncing → rejects the sync → `nullnode-root` stays in `Unknown` state with error `destination {... argocd} is not permitted in project nullnode` → child apps are never created | Add `namespace: argocd` to `destinations` using `{{ .Values.argocd.namespace }}` so it's not hardcoded |
| 2 | `scripts/up.sh:213` | `err` instead of `die` on timeout — the script **didn't abort** and continued to the 50 min PostgreSQL wait (visible symptom of the failure) | Restructure with `synced` flag + `die` at the end if it didn't sync |
| 3 | `scripts/up.sh:200` | Sync timeout too short: 60 × 10 s = 10 min. Insufficient margin for first startup (ArgoCD startup + first git clone) | Increased to 90 × 10 s = **15 min** |
| 4 | `scripts/up.sh:220` | `wait_for "application/postgres to exist" 300 10` = **50 min per app** — caused the visible "infinite wait" | Reduced to 60 × 10 s = **10 min** |
| 5 | `scripts/security.sh:138` | LocalStack version hardcoded: `3.8.1`. The deployment uses `4.4.0`. The 3.8.1 pin hangs `terraform apply` at 3 min (AWS provider `~> 5.70` expects S3 stability that 3.x never reports) | Updated to `4.4.0` |
| 6 | `.github/workflows/ci.yaml` | `push → main` trigger disabled as workaround | Re-enabled |

### CI restructuring: light core vs. full manual

The `integration` job raised the **full** platform (ollama asks for 2 CPU, plus
the observability stack): ~4 CPU of `requests`, too much for a standard GitHub
runner. Split into two:

- **`core-integration`** (runs on `push`/`pull_request`): deploys only cluster +
  LocalStack + ArgoCD + PostgreSQL + Redis via the new `CORE_ONLY=true` flag.
  Validates the entire GitOps machinery —including the `nullnode-root` sync fix—
  with <1 CPU. Fits in any runner.
- **`integration`** (full e2e with ollama + gateway + smoke test): moves to
  `if: github.event_name == 'workflow_dispatch'`, i.e., **manual** from the
  "Run workflow" button. Ideal to run on a self-hosted runner with GPU.

The `CORE_ONLY` flag propagates: CI env → `scripts/up.sh` →
`-var core_only` (Terraform) → `platform.coreOnly` value of the bootstrap chart
→ ArgoCD Helm parameters on `nullnode-root` that disable `keda`,
`observabilityStack`, `otelCollector`, `ollama`, `litellm`, `presidio`,
`observability` and `global.monitoring` (the last removes ServiceMonitors,
which otherwise would depend on the Prometheus operator CRDs). Compatible with
GitOps: no repo values are touched, it's overridden in the Application.

### Pending problems / identified technical debt

- **Inconsistent version pinning:** `security.sh` hardcoded the LocalStack image
  independently of the Terraform pin. If a pin is updated, the scan has to be
  updated manually. Future improvement: read the version from the Terraform
  variable.
- **No real verification of first startup end:** the ArgoCD `wait_for` checks
  that the `Application` object exists, but doesn't wait for the repo-server to
  complete the first clone. On very slow clusters (restrictive networks, GitHub
  throttling) it could still fail. Future improvement: poll `status.reconciledAt`
  or `status.conditions`.
- **Timeout diagram:** the `wait_for` values in `phase_verify` aren't documented.
  Add a table in the RUNBOOK with the deadlines and why they were chosen.

---

## [2026-08-26] — Platform audit and rebuild

Repository review against what `GOTO.md` and `AVANCES.md` declared. The structure
was reasonable, but the whole thing didn't start: nine blocking defects (two
prevent a `terraform init`), six components marked as deployed that didn't exist,
and fourteen configuration errors. Inventory in
[TEMPLATE-AUDIT.md](TEMPLATE-AUDIT.md).

Phases 1-6 are redone. Previous entries remain at the end of the file as history,
but they don't describe the current state.

### Renaming

`ironnode` → `nullnode` throughout the tree: cluster, namespaces, charts, bucket,
secrets and documentation. Consistent with the repository and the remote.

### Infrastructure

- Cluster with declarative k3d config in two profiles
  (`infra/k3d/nullnode-{gpu,cpu}.yaml`), removing the community Terraform
  provider. ADR-0001.
- `Dockerfile` for the k3s image with NVIDIA runtime, needed so a k3d node
  (which is a container) can see the GPU.
- Terraform split in two stacks with explicit boundary: `cloud-mock` (LocalStack
  - S3 - Secrets Manager) and `platform-bootstrap` (namespaces, secrets, ArgoCD,
  root Application).
- LocalStack becomes a container on the host, resolving the previous version's
  deadlock. ADR-0002.
- Single entry point: Traefik with host routing on 8080, instead of one host
  port per service. ADR-0003.

### Security and governance

- Unidirectional secrets flow: `random_password` → mocked Secrets Manager →
  Kubernetes Secret → pod. No chart generates passwords. ADR-0005.
- Department bootstrap job: creates teams with budget, TPM and RPM, mints a key
  per department and publishes them to Secrets Manager. Doesn't regenerate an
  already registered key: LiteLLM stores hashes and recreating it would invalidate
  it.
- PII guardrail with Presidio, wired and disabled by memory. The gateway flag
  is derived from the component, so they can't diverge.
- Auditing of every request to the mocked S3 bucket, with lifecycle rule that
  expires logs after 30 days.
- Restricted `securityContext` in all project charts. LiteLLM uses the
  `litellm-non_root` image variant, which exists precisely for that.
- NetworkPolicies written for datastores, disabled by default.

### Missing components

- **Redis** (new chart): prompt cache and router state, with exporter. Configured
  as cache: bounded memory, LRU, no persistence.
- **PostgreSQL** (new chart): teams, virtual keys, budgets and spend history.
  Without this, per-department quotas aren't implementable: LiteLLM stores teams,
  keys and budgets in a database.
- **KEDA**: the operator, which wasn't installed anywhere before.
- **kube-prometheus-stack**: well-formed Application, with k3s control plane
  targets disabled so they don't stay permanently red.
- **OpenTelemetry Collector**: documented before, absent from the repository.
  Receives OTLP from LiteLLM and derives RED metrics with `spanmetrics`.
- **NVIDIA device plugin** and **DCGM exporter** in the GPU profile. The second is
  the only real source of VRAM.

### Gateway and inference

- LiteLLM chart rewritten: `model_list` with the missing `model` parameter,
  Redis cache, router with shared state, Prometheus, OTel and S3 callbacks,
  probes against real endpoints (`/health/liveliness`,
  `/health/readiness`), `--config` passed to the process, ConfigMap checksum so a
  config change restarts pods, and initContainer that waits for Postgres before
  migrations.
- Removed the invented `security_settings` block and `drop_params` as a list,
  which would discard request content.
- Ollama chart rewritten: StatefulSet with per-replica volume, preloading in
  initContainer (the previous `postStart` couldn't work, no server yet) and
  without the `nodeSelector` to a Tesla K80 that left the pod `Pending`.
- KEDA trigger on Prometheus metric instead of a Redis list that LiteLLM never
  writes. ADR-0004.
- ArgoCD ignores `/spec/replicas`: without that, self-heal and the autoscaler
  fight over the field indefinitely.

### Observability

- Three new dashboards against metrics that exist, provisioned by Grafana
  sidecar. The previous one graphed three invented metrics and wasn't connected
  to anything.
- Recording rules as the single definition of each signal, so panels and alerts
  can't contradict each other.
- Eight alerts anchored to the runbook, including team budget almost exhausted
  and high VRAM.
- Cache hit rate derived from the Redis exporter, legitimate because the gateway
  is the only client of that instance.

### Tooling and CI

- `Makefile` as operator interface, with `make help`.
- `scripts/up.sh` rewritten: strict mode, error trap with line and command,
  phases with `--only` and `--from`, preflight with version check and specific
  GPU diagnosis, waits on real conditions.
- `status.sh`, `smoke.sh` (end-to-end: ingress → auth → model → cache → audit,
  including that an unauthenticated request is rejected), `validate.sh` (everything
  verifiable without cluster) and `versions-check.sh`.
- CI rebuilt: helm lint and render on both profiles, kubeconform, Terraform fmt
  and validate, shellcheck, yamllint, and an integration job that raises the full
  CPU profile and passes the smoke test.
- k6 load profile: measures TTFT via `waiting` with `stream:true` and compares
  unique prompts against repeated ones. Replaces an `ab -p test-payload.json`
  whose file didn't exist.
- `renovate.json` with custom manager for the app-of-apps pins.
- Security pipeline (`security.yaml`, `make security`): Trivy on Terraform and
  Dockerfile, Trivy and kube-linter on rendered manifests, Checkov, gitleaks
  against tree and history, and image CVEs as informational. Scans the render,
  not the templates: `securityContext`, limits and tags only exist after
  templating.
- Format pipeline (`format.yaml`, `make fmt-check`): `terraform fmt`, shfmt,
  actionlint, hadolint and markdownlint.
- `make check` as the single PR gate. Accepted findings documented with their
  reason in `.trivyignore` and `.checkov.yaml`; almost all are controls without
  meaning against a mock (KMS, replication, access logging).
- tfsec remains opt-in (`WITH_TFSEC=true`): Aqua integrated it into Trivy and
  `trivy config` runs the same rules, so by default it would duplicate findings.

### Documentation

- README rewritten, with the GPU reality explained upfront.
- `docs/usage/CONNECT.md`: guide for the dev consuming the platform. VS Code with
  Continue and Cline as the main path, Open WebUI and SDKs after, and the name
  resolution table depending on where you call from (Windows browser, WSL
  extension, distro `curl`, another container), which is the usual source of
  "won't connect".
- `../ops/RUNBOOK.md`: diagnosis by symptom and by alert.
- `../ops/VERSIONS.md`: inventory of pins and LiteLLM update checklist.
- `../adr/`: six ADRs with the decisions and their trade-offs.
- `TEMPLATE-AUDIT.md`: what was broken and what was done.

### Unverified

None of this has been executed. Third-party chart versions are pinned without
network access (`make versions-check` before first deployment) and LiteLLM
metric names depend on the pinned version (ADR-0006).

---

## Historical log

> The following entries are from the initial scaffold. Kept for traceability;
> they describe intentions and not the repository state. The detail of what of
> this wasn't true is in [TEMPLATE-AUDIT.md](TEMPLATE-AUDIT.md).

### [2026-08-23] Project initialization

- Full tech stack definition.
- Base directory structure and governance files.

### [2026-08-23] Phases 1-5

- `terraform/` with k3d provider, variables and outputs.
- `up.sh` and `down.sh` scripts.
- ArgoCD bootstrap via kustomize and app-of-apps pattern.
- LiteLLM and Ollama charts, KEDA `ScaledObject`.
- Prometheus/Grafana values and an AI metrics dashboard.
- Lint and load test workflows.

### [2026-08-24] Phase 6 — Cloud mocking with LocalStack

- AWS provider in Terraform pointing to LocalStack.
- S3 bucket `ironnode-model-vault` and secret `ironnode/litellm-master-key`.
- LocalStack chart in-cluster and integration in the app-of-apps.
- LocalStack health validation in `up.sh`.
