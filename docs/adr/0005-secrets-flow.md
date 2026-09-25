# 0005 - Secrets flow: Terraform generates, Secrets Manager stores, Kubernetes consumes

**Status:** accepted · **Date:** 2026-08-26

> **Update (2026-09-17):** Kubernetes projection is no longer done by Terraform's `data source` but by External Secrets Operator, over the same Secrets Manager secret. The source and flow shape don't change. See [ADR-0007](0007-external-secrets-operator.md).

## Context

The template had this in `k8s/platform/litellm/values.yaml`, committed:

```yaml
environment:
  LITELLM_MASTER_KEY: "sk-ironnode-master-key-2024"
  LITELLM_SALT_KEY: "ironnode-salt-key-2024"
  DATABASE_URL: "postgresql://user:password@postgres..."
```

And the same value manually duplicated in the Secrets Manager secret. Two sources of truth, neither rotatable, both in git.

## Decision

Single direction of flow, no going back:

```bash
random_password (Terraform)
      │
      ▼
AWS Secrets Manager mocked          ← single source of truth
      │  (data source, read-only)
      ▼
Kubernetes Secret                  ← created by platform-bootstrap
      │  (secretKeyRef)
      ▼
Pod (LiteLLM / Postgres / Redis / Grafana)
```

Specifically:

- `infra/terraform/cloud-mock/secrets.tf` generates master key, salt key, and Postgres, Redis, and Grafana passwords with `random_password`, and stores them in `nullnode/platform/credentials`.
- `infra/terraform/platform-bootstrap/secrets.tf` reads them with a data source and creates Kubernetes Secrets.
- No chart generates passwords. All consume `existingSecret`.
- Department keys are minted by the bootstrap job in `nullnode/litellm/department-keys`. Terraform owns the secret, not its content (`lifecycle.ignore_changes`), so the job can rotate them.

## Consequences

### Pros

- Rotating the platform is `terraform taint` + `apply`.
- No credential-shaped value in the repository.
- This is the flow shape you'd use in real life: instead of the data source, External Secrets Operator over the same secret. One piece to replace.

### Cons

- Secrets are in clear in Terraform's local state. Acceptable in a lab, covered by `.gitignore`; in production requires encrypted remote backend.
- If the LocalStack container restarts, Terraform generates new values and invalidates re-issued department keys.
- Kubernetes Secrets are base64, not encrypted: no etcd encryption at rest here.
