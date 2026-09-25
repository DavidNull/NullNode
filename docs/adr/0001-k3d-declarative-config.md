# 0001 - The cluster is created with k3d's declarative config

**Status:** accepted · **Date:** 2026-08-26

## Context

The template used the `pvotal-tech/k3d` provider. Consistent with the role: if everything is IaC, the cluster should be too.

In practice it's a community provider with little maintenance, lags behind k3d's schema, and doesn't cover necessary options here (`options.runtime.gpuRequest`, node filters on volumes, registry). It's a fragile dependency in the layer that has to work before everything else.

## Decision

The cluster is created with `k3d cluster create --config infra/k3d/nullnode-<profile>.yaml`.

Terraform remains the IaC engine for everything else:

- `infra/terraform/cloud-mock` → LocalStack container and AWS resources.
- `infra/terraform/platform-bootstrap` → namespaces, secrets, ArgoCD and the root Application.

## Consequences

### Pros

- The k3d config file is declarative and versioned: we don't lose IaC.
- All k3d options available, including GPU.
- One less dependency at startup.

### Cons

- The cluster isn't in Terraform state, so `up.sh` checks if it exists (`cluster_exists()`).
- Two tools at startup instead of one.

## Discarded alternatives

- **kind:** doesn't expose GPU as easily and we'd lose the load balancer k3d mounts for Ingress.
- **`null_resource` with `local-exec`:** puts the cluster in state without the guarantees of a real resource.
