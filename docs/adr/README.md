# Architecture Decisions

One ADR per decision that isn't obvious from reading the code. If something in the repo seems weird, the explanation is probably here.

Files are in English because code comments reference them by path; content is in Spanish, like the rest of the documentation.

| # | Decision | Status |
| --- | --- | --- |
| [0001](0001-k3d-declarative-config.md) | The cluster is created with k3d's declarative config, not a Terraform provider | Accepted |
| [0002](0002-localstack-outside-the-cluster.md) | LocalStack runs outside the cluster | Accepted |
| [0003](0003-single-entrypoint.md) | Single entry point via Ingress instead of one port per service | Accepted |
| [0004](0004-scaling-signal.md) | KEDA on Prometheus metrics for inference, HPA on CPU for gateway | Accepted |
| [0005](0005-secrets-flow.md) | Secrets are born in Terraform, live in Secrets Manager, and are projected to Kubernetes | Accepted |
| [0006](0006-metrics-sources.md) | LiteLLM metrics with fallback to OTel spanmetrics | Accepted |
| [0007](0007-external-secrets-operator.md) | External Secrets Operator replaces Terraform bridge: rotation without `apply` | Accepted |
