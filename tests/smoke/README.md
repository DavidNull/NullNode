# Smoke test

Lives in [`scripts/smoke.sh`](../../scripts/smoke.sh), not here, because it uses
the shared shell library and is part of the operator flow (`make smoke`).

It doesn't check that pods are up: it walks the full chain.

| Step | What it proves |
| --- | --- |
| `/health/liveliness` | Ingress, Traefik routing and the gateway process |
| `POST` unauthenticated | That authentication is actually applied |
| `/v1/models` | That the catalog rendered from the values loaded |
| `/v1/chat/completions` | Router, Ollama, weights on disk, GPU access |
| Repeat the same prompt | That the Redis cache is connected and used |
| `/metrics` | That the Prometheus callback is active |
| `s3://nullnode-model-vault/audit` | That the audit reaches LocalStack |

Run after `make up`, or in CI against an ephemeral cluster.
