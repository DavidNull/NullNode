# NullNode <img src="docs/media/nullnode.png" alt="NullNode Logo" width="70" style="vertical-align: middle; margin-left: 10px;">

**Everything a real platform has, but on your own hardware.**

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
  <img src="https://img.shields.io/badge/External%20Secrets-Rotation-5B4FC0?style=flat-square&logo=kubernetes&logoColor=white" alt="External Secrets Operator">
</p>

The idea came from something pretty specific: a group of people at home who want their own lightweight AI (because with home resources you can't do much more), without paying a cent, and with real control over who spends what and when. Governance, basically.

Local and private enterprise LLMOps platform on K3s. Implements local LLM inference with dynamic scaling (KEDA), gateway with budgets and cost control (LiteLLM), prompt cache (Redis), dedicated GenAI observability, and 100% automated GitOps deployment with ArgoCD and Terraform.

Cost: 0€ (just electricity). Everything runs on your hardware and AWS services are mocked.

```bash
make up          # GPU profile (default)
PROFILE=cpu make up
make status
make smoke
```

<!-- console deployment, `make up` from start to finish -->
<p align="center">
  <img src="docs/media/deploy.gif" alt="NullNode deployment in console, make up from start to finish" width="80%">
</p>

Everything mocked: AWS, S3, Bedrock, etc.
<p align="center">
  <img src="docs/media/mockeado.png" alt="AWS services mocked in NullNode" width="80%">
</p>

---

## Before you start

### 1. Defaults to NVIDIA GPU

You need: NVIDIA driver on the host (on Windows if you use WSL2, not in the distro),
`nvidia-container-toolkit` inside the distro with Docker restarted, the
`make k3s-cuda-image` image (once, k3d nodes are containers and the official one
doesn't bring the runtime), and the device plugin, which installs automatically
with the GPU profile. The `make up` preflight tells you what's missing.

**No GPU:** `PROFILE=cpu make up`. Same thing, just slower responses.

### 2. With a single GPU don't scale replicas

The device plugin assigns the card exclusively, so the second replica stays
`Pending`. Concurrency is achieved with `OLLAMA_NUM_PARALLEL`. CPU profile
does scale. See [ADR-0004](docs/adr/0004-scaling-signal.md).

### 3. Reconciles from git, not from your local copy

Editing a file does nothing until you push it to the revision ArgoCD follows.
To iterate on a branch:

```bash
terraform -chdir=infra/terraform/platform-bootstrap apply \
  -var gitops_target_revision=my-branch
```

### 4. First boot takes 10-20 minutes

The observability stack and model weights get downloaded. `^C` is safe:
ArgoCD keeps reconciling in the background.

### 5. No chat UI

`make up` exposes an OpenAI-compatible endpoint. Connect from VS Code with
Continue or Cline: [docs/uso/CONECTAR.md](docs/uso/CONECTAR.md).

### 6. Pinned versions without network verification

Third-party charts are pinned blindly: run `make versions-check` before the
first deployment. LiteLLM metrics depend on the pinned version and affect
dashboards and the KEDA trigger ([ADR-0006](docs/adr/0006-metrics-sources.md)).

---

## Architecture

<!-- architecture diagram (needs to be designed) -->
<p align="center">
  <img src="docs/media/Arquitectura_NullNode.png" alt="NullNode architecture diagram" width="90%">
</p>

<small>📝 Note: The diagram shows the base architecture v0.1.0. Recent versions include additional components like Open WebUI (optional chat interface) and External Secrets Operator (automatic secret rotation). Check the components table for the complete current architecture.</small>

A request: goes through Traefik → LiteLLM validates the department key and budget
→ checks cache in Redis → if miss, routes to Ollama → logs spend in Postgres,
trace in collector, metric in Prometheus and the full request in S3.

| Layer | Component | What it does |
| --- | --- | --- |
| Gateway | LiteLLM | OpenAI-compatible endpoint. Virtual keys per department with budget, TPM and RPM. Cache, PII guardrail, audit. |
| Cache | Redis | Prompt cache and shared router state. |
| Governance | PostgreSQL | Teams, keys and budgets. Survives restarts and changes via API. |
| Inference | Ollama | StatefulSet with model cache per replica and weight preloading. |
| Scaling | KEDA | Scales by requests per second, not by CPU. |
| Observability | Prometheus, Grafana, OTel, DCGM | TTFT, tokens/s, hit rate, spend per team, VRAM. |
| Guardrails | Presidio | PII detection and masking. Optional. |
| Cloud mock | LocalStack | S3 (request audit) and Secrets Manager (credentials source). |
| Secrets | External Secrets Operator | Syncs credentials from Secrets Manager to Kubernetes Secrets. Rotating is changing the source, no `terraform apply` ([ADR-0007](docs/adr/0007-external-secrets-operator.md)). |
| GitOps | ArgoCD | App-of-apps with sync waves, single root Application. |
| IaC | Terraform, k3d | Two stacks: mocked cloud and platform bootstrap. |

<br>
<p align="center">
  <img src="docs/media/grafana.png" alt="Grafana dashboards: GenAI, spend and VRAM" width="80%">
</p>

## Requirements

Docker, `k3d` ≥ 5.6, `kubectl`, `Helm` ≥ 3.14, `Terraform` ≥ 1.6. The `make up`
preflight checks them and links installation for what's missing.

Also `make`, a fresh WSL2 install doesn't have it🤓:
`sudo apt install make`. Or use `scripts/` directly if you don't want extra installs:

| `make` | equivalent |
| --- | --- |
| `make up` | `./scripts/up.sh` |
| `make down` | `./scripts/down.sh` |
| `make status` | `./scripts/status.sh` |
| `make smoke` | `./scripts/smoke.sh` |
| `make validate` | `./scripts/validate.sh` |
| `make security` | `./scripts/security.sh` |
| `PROFILE=cpu make up` | `PROFILE=cpu ./scripts/up.sh` |

## Documentation

[docs/](docs/) — architecture, decisions, runbook, dev connection guide.

## Recent Versions

**v0.5.1** - Tempo UI + better security
**v0.5.0** - Complete observability with Tempo
**v0.4.0** - NetworkPolicies + Reloader + Presidio
**v0.3.1** - Open WebUI + license

## License

NullNode is open source. It started as my personal lab to learn and play with LLMOps, and I publish it because it might be useful to someone else.

**The idea is to keep it open.** Feel free to fork it, send an improvement, fix something, or just propose an idea :)

And if it helps you, a ⭐ is more than enough.

<p align="center">
  <img src="docs/media/NullNode-mii.gif" alt="NullNode Mii" width="10%">
  <img src="docs/media/NullNode-tepig.gif" alt="NullNode Tepig" width="6%">
</p>

<p align="center">DavidNull 🐰</p>
