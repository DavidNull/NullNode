# 0002 - LocalStack runs outside the cluster

**Status:** accepted · **Date:** 2026-08-26

## Context

The template deployed LocalStack as a chart managed by ArgoCD, and at the same time Terraform created the bucket and secret against `http://localhost:4566`. That's a deadlock:

1. Terraform needs LocalStack to create the secret.
2. The secret is consumed by LiteLLM, which ArgoCD deploys.
3. ArgoCD is what deploys LocalStack.

Also the chart published the endpoint with a `NodePort: 4566`, outside the valid NodePort range (30000-32767), so it would never respond on the port Terraform was looking for.

## Decision

LocalStack is a Docker container on the host, managed by Terraform with the `kreuzwerker/docker` provider, published on port 4566. Pods reach it via `http://host.k3d.internal:4566`, the DNS name k3d injects in CoreDNS.

The `k8s/platform/localstack/` chart has been removed.

## Consequences

### Pros

- Breaks the cycle: LocalStack → AWS resources → cluster → platform.
- Charts are configured the same as against real AWS; only the endpoint changes.
- Survives `k3d cluster delete`.

### Cons

- One piece outside GitOps. Conscious compromise: it's the piece that *simulates* the provider, not part of the platform.
- The port is exposed on all interfaces because pods reach it via the host IP on Docker's bridge.
- LocalStack Community doesn't persist state: if the container restarts, bucket and secrets disappear. `make up` recreates them.
