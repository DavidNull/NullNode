# Action plan

## Now: validate

None of this has been executed. Check order:

- [ ] `make versions-check` — third-party chart versions are pinned without
      network access. If any doesn't resolve, fix `k8s/platform/values.yaml` and
      `infra/terraform/platform-bootstrap/variables.tf`.
- [ ] `make validate` — helm lint and render on both profiles, terraform validate,
      shellcheck, yamllint. Same as what CI runs.
- [ ] Push to `main` (or point bootstrap to a branch with
      `-var gitops_target_revision=...`). ArgoCD reconciles from git, not from
      the working tree.
- [ ] `PROFILE=cpu make up` first: rules out GPU from diagnosis and takes less
      time.
- [ ] `make smoke`.
- [ ] `PROFILE=gpu make up` once the CPU profile converges.
- [ ] Verify LiteLLM metric names against the pinned version (ADR-0006). Affects
      the three dashboards, recording rules and KEDA trigger. Command in
      `../ops/VERSIONS.md`.

## Next: close what's half-done

- [ ] **Pin scanner versions in CI.** `trivy`, `shellcheck` and `checkov` are
      installed as *latest* (apt/pip) in the workflows. Every new release can
      introduce rules that put the gate in red without touching a line of code —
      already happened with KSV-0014/0109, DS-0002 and AWS-0132 when Trivy was
      upgraded. Pinning them (as already done with images) makes the pipeline
      deterministic.
- [ ] **Confirm the integration test in CI.** The blocker was the mock:
      LocalStack 3.8.1 hung on `aws_s3_bucket_lifecycle_configuration` against
      the AWS 5.100 provider. Upgraded to 4.4.0 (see VERSIONS.md), the `apply`
      passes locally. Still need to see it green in CI after the push — remember
      that ArgoCD reconciles from the pushed SHA, not from the working tree.
- [x] **Trace backend.** The collector receives OTLP and derives spanmetrics,
      but traces die in the `debug` exporter. Added Tempo and its datasource in
      Grafana to open a slow request and see where the time went as part of
      v0.5.0.
- [x] **PII guardrail by default.** Presidio is wired and disabled by RAM.
      Enabled in GPU profile as part of v0.4.0. Need to measure latency and
      memory impact after deployment to confirm it's acceptable.
- [x] **NetworkPolicies.** Written and disabled. Enabled progressively on Redis,
      Postgres, LiteLLM and Ollama as part of v0.4.0. Verified with helm lint and
      template validation.
- [ ] **Scale-to-zero.** Implemented and disabled. Measure how long the pool takes
      to wake up and whether `num_retries` is enough to not lose the first request.
- [ ] **Per-user budgets in addition to per-team.** LiteLLM supports it; right now
      there are only department teams.
- [x] **Open WebUI as a platform component.** Previously documented as
      `docker run` (client, not infrastructure). Now in the app-of-apps, on by
      default in the GPU profile and off in CPU. Ingress, key and session key
      come from the Secret; state sits on its own PVC. Raising `replicaCount`
      still needs a shared `DATABASE_URL` first — see below.
- [ ] **Tempo query UI behind an Ingress.** The v0.5.1 notes announced one at
      `tempo.nullnode.localhost`; it was never written. Traces are reachable
      today only through the Grafana datasource. Same for the Tempo and Reloader
      NetworkPolicies those notes claimed.
- [ ] **Open WebUI beyond one replica.** Its state is a SQLite file on a
      ReadWriteOnce volume, so the chart is pinned to one replica. Pointing
      `DATABASE_URL` at the existing Postgres would lift that.
- [ ] **Scanning large images at the gate.** LiteLLM and Ollama are excluded because
      their CVEs come from CUDA and Python base layers. With an allowlist by base
      layer they'd be actionable.

## After: what's needed to look like production

- [x] **External Secrets Operator** instead of the data source. Installed in wave
      -20 with a `ClusterSecretStore` against the same Secrets Manager and one
      `ExternalSecret` per credential; Terraform no longer projects Secrets.
      Rotating is changing the value at the source and waiting for the
      `refreshInterval`, no `terraform apply` needed
      ([ADR-0007](../adr/0007-external-secrets-operator.md)). Reloader closes
      the loop in wave -15: `secretKeyRef` via env doesn't reload hot, so the
      gateway and the chat UI carry its annotations and restart on rotation.
- [ ] **A hosted model in the catalog.** With everything local spend is zero and
      the FinOps dashboard is a rehearsal. A paid provider behind a variable
      turns budgets into real control.
- [ ] **Model fallbacks.** `router_settings` supports fallback chains. With a
      single model per profile there's nothing to test.
- [ ] **Etcd encryption at rest** and image signing. Right now Kubernetes Secrets
      are just base64.
- [ ] **Continuous evaluation.** A periodic job with a set of reference prompts
      that publishes quality metrics, to detect that a model change or
      quantization made responses worse.
- [ ] **Prompt versioning in the bucket.** The `prompts/` prefix exists and bucket
      versioning is enabled, but nothing writes there yet.
- [ ] **Real multi-tenant.** One namespace per department with resource quotas,
      not just logical quotas in the gateway.

## Ideas without commitment

- Custom admin interface. LiteLLM already has a UI; a layer with the FinOps view
  by department would make sense if this is used by a team.
- `vLLM` as an alternative to Ollama to measure throughput with continuous batching.
- Semantic cache by embeddings instead of exact. LiteLLM supports it and would
  increase hit rate with paraphrased prompts.
- Chaos testing: kill the pool under load and verify that the gateway degrades
  instead of hanging.

---

## Completed phases

All were redone on 2026-08-26 on the audited base. Details in
[PROGRESS.md](PROGRESS.md) and reasons for each change in
[the ADRs](../adr/).

- [x] **Phase 1 — Infrastructure and IaC.** Declarative cluster with k3d in two
      profiles, CUDA k3s image, two Terraform stacks, idempotent lifecycle scripts
      with phases.
- [x] **Phase 2 — GitOps.** ArgoCD via Helm from Terraform, one `AppProject` and one
      root `Application`, app-of-apps with sync waves and multi-source pattern
      `$values` for third-party charts.
- [x] **Phase 3 — Gateway and cache.** LiteLLM with virtual keys, budgets and
      limits per department, Redis cache, router with shared state. Redis and
      PostgreSQL charts, which didn't exist before.
- [x] **Phase 4 — Inference pool and autoscaling.** Ollama as StatefulSet with
      per-replica volume and model preloading, KEDA (operator included) on
      Prometheus metric.
- [x] **Phase 5 — Observability.** kube-prometheus-stack, OTel Collector with
      spanmetrics, DCGM in GPU profile, three dashboards against real metrics,
      recording rules and eight alerts with runbook.
- [x] **Phase 6 — Mocked cloud.** LocalStack outside the cluster, S3 with request
      auditing and lifecycle, Secrets Manager as single credential source.
- [x] **Phase 7 — Security, guardrails and tooling.** Secrets flow with nothing in
      git, restricted `securityContext`, Presidio wired, NetworkPolicies written,
      offline validation suite, end-to-end smoke test, k6 load profile, full CI,
      runbook and ADRs.
