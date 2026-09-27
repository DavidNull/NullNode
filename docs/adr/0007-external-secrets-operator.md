# 0007 - External Secrets Operator replaces Terraform bridge

**Status:** accepted · **Date:** 2026-09-17

## Context

[ADR-0005](0005-secrets-flow.md) left the flow with the right shape but with a
lab piece: `platform-bootstrap` read `nullnode/platform/credentials` from
Secrets Manager with a `data source` and created Kubernetes Secrets with
`kubernetes_secret_v1`. A `data source` only re-evaluates on a `terraform apply`,
so rotating a credential at the source wouldn't reach the cluster until the next
apply. ADR-0005 itself anticipated this:

> This is the real-world shape of the flow: instead of the data source, External
> Secrets Operator on the same secret. You replace one piece.

## Decision

That piece is replaced. The source (Terraform → mocked Secrets Manager) doesn't
change; what changes is who projects to Kubernetes:

```bash
random_password (Terraform)
      │
      ▼
AWS Secrets Manager mocked          ← single source of truth, no changes
      │
      ▼
External Secrets Operator             ← reconciles every refreshInterval
      │  (ClusterSecretStore + ExternalSecret)
      ▼
Kubernetes Secret                     ← same name and same keys as before
      │  (secretKeyRef)
      ▼
Pod (LiteLLM / Postgres / Redis / Grafana)
```

Specifically:

- The operator is the `external-secrets` chart
  (`k8s/platform/values/external-secrets.yaml`), another `Application` in the
  app-of-apps in wave -20: it installs before the datastores and the gateway,
  which consume what it syncs.
- ESO's AWS provider has no endpoint field, so it points to LocalStack with
  `AWS_SECRETSMANAGER_ENDPOINT` / `AWS_STS_ENDPOINT` in the controller, the
  same `host.k3d.internal:4566` address that pods use.
- `k8s/charts/external-secrets-config` has a `ClusterSecretStore` against that
  Secrets Manager and one `ExternalSecret` per credential. Each one creates
  exactly the same Secret and the same keys that Terraform projected
  (`nullnode-litellm-credentials`, `nullnode-postgres-auth`,
  `nullnode-redis-auth`, `nullnode-grafana-admin`), so no consumer chart changes.
- `platform-bootstrap/secrets.tf` loses the five `kubernetes_secret_v1`. Only
  the read-only `data source` remains, which still feeds the convenience
  outputs (`make key`, `make grafana-password`). Terraform no longer creates any
  Kubernetes Secret.
- The static Secret `nullnode-aws-credentials` (the `test`/`test` keys that
  LocalStack ignores) moves from Terraform to `external-secrets-config`: both
  pods use it to talk to the mock and the `ClusterSecretStore` to authenticate.
  It has no credential form and was already in git in the providers.

## Consequences

### Pros

- Rotating no longer needs `terraform apply` on `platform-bootstrap`: you change
  the value at the source and ESO propagates it to the Secret within
  `refreshInterval` (1 h). In real life, the source would be AWS Secrets
  Manager itself.
- Single source of truth and single Secret owner. Before Terraform wrote the
  Secret; now it's `Owner` of the `ExternalSecret`, without two systems fighting
  over the same object.
- This is the production topology: the same operator, the same type of
  `SecretStore`, changing only the auth backend (IRSA/role instead of
  `test`/`test`) and the endpoint.

### Cons

- ESO updates the Secret, but a pod that reads the credential via `env`
  (`secretKeyRef`) doesn't reload it until restarted. Fully automatic
  *end-to-end* rotation asks for a Reloader that restarts the Deployment when the
  Secret changes; without it, rotating still requires a rollout. It's not a
  regression: it didn't reload before either. Noted as the next step.
- The controller has, by design, read/write RBAC over cluster `secrets`.
  kube-linter flags it (`access-to-secrets`); it's inherent to the operator and
  doesn't apply to the project's own charts, which the pipeline does scan.
- In a migration on an existing cluster, the Secrets that Terraform created don't
  have ESO's owner-reference, so you have to delete them once for the operator
  to readopt them. On a fresh `make up` this doesn't happen.
- ADR-0005 still stands: values are in clear text in Terraform's local state and
  Kubernetes Secrets are base64, not encrypted in etcd.
