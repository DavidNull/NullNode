# NullNode — context and architecture vision

## What it is

An LLMOps platform that runs on a workstation. The goal isn't to have a local LLM: it's to have the control environment that surrounds an LLM in production, with the same pieces and the same trade-offs, on a machine where breaking it costs nothing.

Private models, governance via AI Gateway, prompt cache, auto-scaling on the right signal, and GenAI SRE observability (TTFT, tokens/s, hit rate, spend per team, VRAM). Cost: 0€, with AWS services mocked.

## Design principle

Look like production where it matters, and be explicit where it can't.

First: real GitOps (one root `Application`, everything else reconciles), secrets outside git, single entry point, pinned versions, dashboards against metrics that exist.

Second: write down where the lab deviates and why. LocalStack Community doesn't persist, a GPU can't be shared between pods, secrets are in clear in Terraform state. It's in the ADRs, not hidden.

From this a corollary: better absent and documented than present and non-functional. The previous version declared six complete phases over components that didn't exist; the record is in [AUDITORIA-PLANTILLA.md](AUDITORIA-PLANTILLA.md).

## Layers

### 1. Control and gateway — LiteLLM + Redis + PostgreSQL

All requests go through here. The gateway validates the virtual key, checks department budget and limits, applies PII guardrail, resolves by cache if it can, routes to the pool if not, and logs spend, trace, metric, and audit.

The three pieces are inseparable:

- **Redis** isn't just cache: the `least-busy` router and rate limit counters need shared state between replicas. Without it, each pod decides with its partial view and limits are wrong.
- **PostgreSQL** is what makes department quotas real. Teams, keys, and budgets live there, survive restarts, and change via API without redeployment.

### 2. Execution — Ollama

StatefulSet, not Deployment: the local `storageClass` only gives `ReadWriteOnce`, so each replica needs its own volume. Weights are downloaded in an initContainer, so `Ready` means "it already has its models".

### 3. Scaling — KEDA

Scales by requests per second at the gateway, not by CPU: a server blocked waiting for GPU can be at 15% CPU and saturated.

With a single GPU the ceiling is one replica, so here KEDA is worth it for scale-to-zero — freeing VRAM when there's no traffic — more than scaling to N ([ADR-0004](../adr/0004-scaling-signal.md)).

### 4. Observability — Prometheus, Grafana, OpenTelemetry, DCGM

Three dashboards, one per question:

- **Golden Signals**: Is it healthy? Rate, errors, TTFT, tokens/s, hit rate.
- **FinOps and governance**: Who consumes and how much budget do they have left?
- **Inference Runtime**: What's the pool doing? Replicas, KEDA decisions, VRAM.

Recording rules are the only definition of each signal, so panels and alerts can't contradict. OTLP traces feed a `spanmetrics` connector as a safety net if the Prometheus callback isn't available ([ADR-0006](../adr/0006-metrics-sources.md)).

### 5. GitOps — ArgoCD

One `AppProject` and one root `Application` is all the imperative. That root points to an app-of-apps chart where each template is another `Application`, ordered by sync waves: CRDs and operators, datastores, model runtime, gateway, dashboards.

Third-party charts aren't forked: they're consumed with the multi-source `$values` pattern, which allows versioning values here without touching the chart.

### 6. Infrastructure — Terraform + k3d

Two stacks with a clear boundary:

- **`cloud-mock`**: the simulated cloud provider. LocalStack container plus S3 and Secrets Manager resources. Lives outside the cluster because the cluster can't depend on something that needs to exist before it does ([ADR-0002](../adr/0002-localstack-outside-the-cluster.md)).
- **`platform-bootstrap`**: namespaces, the secrets bridge, ArgoCD and the root Application.

The cluster itself is created with k3d's declarative config file, not a Terraform provider ([ADR-0001](../adr/0001-k3d-declarative-config.md)).

### 7. Mocked cloud — LocalStack

Not decoration: this is where the platform's security comes from.

- **Secrets Manager** stores the credentials Terraform generates and the virtual keys from the bootstrap job. No chart generates passwords ([ADR-0005](../adr/0005-secrets-flow.md)).
- **S3** receives the audit of every request (`s3` callback), with lifecycle that expires logs after 30 days: these are the fastest-growing object class and nobody cleans them up.

## Hardware profiles

`PROFILE=gpu` (default) and `PROFILE=cpu` select the values file and the k3d node image. They change the model, resources, concurrency, and scaling limits; the rest is identical.
