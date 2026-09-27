# Runbook

Diagnosis by symptom. Each alert points here by its anchor.

First command always: `make status` — endpoints, unhealthy pods, Applications and
ScaledObjects on one screen.

---

## Startup

### First `make up` takes a long time

Normal: ~1 GiB of observability images plus 2-5 GiB per model. 10-20 minutes.

`^C` is safe, ArgoCD keeps reconciling. Resume with `make status` or
`kubectl -n argocd get applications -w`.

### `PROFILE=gpu` fails in preflight

The message tells you which of the three checks failed:

1. **Docker doesn't see the GPU.** Driver on the host (in Windows, not WSL),
   `nvidia-container-toolkit` inside the WSL distro, Docker restarted after.
   Verify:
   `docker run --rm --gpus all nvidia/cuda:12.6.2-base-ubuntu24.04 nvidia-smi`
2. **Missing CUDA image.** `make k3s-cuda-image`.
3. No GPU: `PROFILE=cpu make up`.

### Applications stuck in `Unknown` or `ComparisonError`

Almost always ArgoCD can't read the repository. It reconciles from
`gitops.repoURL` at the configured revision, not from your local copy: without
push, changes don't exist for it.

```bash
kubectl -n argocd get application nullnode-root -o jsonpath='{.status.conditions}' | jq
kubectl -n argocd logs deploy/argocd-repo-server --tail=100
```

To iterate without pushing to `main`, point bootstrap to your branch:

```bash
terraform -chdir=infra/terraform/platform-bootstrap apply \
  -var gitops_target_revision=my-branch
```

---

## Alerts

### NullNodeGatewayDown

In order:

```bash
kubectl -n nullnode-platform get pods -l app.kubernetes.io/name=litellm
kubectl -n nullnode-platform logs deploy/litellm --tail=200
```

Common causes:

- **`CrashLoopBackOff` on startup:** Prisma migrations. Check that Postgres is
  `Ready` and that `nullnode-postgres-auth` exists. The initContainer covers
  this, so if you get here Postgres started and then crashed.
- **Invalid config:** a syntax error kills the process in a second.
  `kubectl -n nullnode-platform get cm litellm-config -o yaml`.
- **Missing secret:** `platform-bootstrap` didn't finish applying.
  `./scripts/up.sh --only platform`.

### NullNodeGatewayHighErrorRate

Separate by code: they mean opposite things.

```promql
sum by (status_code) (rate(litellm_proxy_failed_requests_metric_total[5m]))
```

- **429:** governance working. A team exhausted budget or their RPM/TPM.
  Business decision: raise the limit in `departments` or let it throttle.
- **401/403:** keys distributed wrong or revoked.
- **5xx:** the inference pool. Go to `NullNodeWorkerPoolEmpty`.
- **408/504:** timeouts. Model too big for the hardware, or
  `OLLAMA_NUM_PARALLEL` above what VRAM can handle.

### NullNodeTimeToFirstTokenDegraded

The only latency the user notices. In order of probability:

1. **Model evicted from VRAM.** `OLLAMA_KEEP_ALIVE` expired and every call
   reloads. Raise it in the profile values.
2. **More concurrency than `OLLAMA_NUM_PARALLEL`.** Requests queue inside
   Ollama without anything going up in Kubernetes. Compare gateway rps against
   the configured value.
3. **Pool scaled down with traffic.** "KEDA scaling decisions" panel.
4. **VRAM contention** with `OLLAMA_MAX_LOADED_MODELS > 1`: two models take
   turns and both perform worse.

```bash
kubectl -n nullnode-platform logs statefulset/ollama --tail=100 | grep -i "load\|memory"
```

### NullNodeCacheHitRateLow

Informational. Three causes, and the third is the one that matters:

1. The load is diverse. Nothing to fix.
2. `cache.ttlSeconds` too short for the usage pattern.
3. **Redis evicts under `maxmemory` pressure.** Raising TTL doesn't fix it.
   Check evictions first:

```promql
rate(redis_evicted_keys_total[5m])
```

If there are evictions, raise `config.maxmemory` before touching TTL.

### NullNodeTeamBudgetNearlyExhausted

At zero, the gateway returns 429 to that team's keys. That's by design.

```bash
KEY=$(make -s key)
curl -s http://gateway.nullnode.localhost:8080/team/list \
  -H "Authorization: Bearer $KEY" | jq '.[] | {team_alias, spend, max_budget}'
```

Raise budget without redeploy (teams live in Postgres):

```bash
curl -X POST http://gateway.nullnode.localhost:8080/team/update \
  -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
  -d '{"team_id":"<id>","max_budget":500}'
```

To make the change permanent, edit `departments` in the values and commit.

### NullNodeWorkerPoolEmpty

There's traffic and zero ready replicas.

```bash
kubectl -n nullnode-platform get pods -l app.kubernetes.io/name=ollama
kubectl -n nullnode-platform describe pod ollama-0
```

- **`Pending` / `Insufficient nvidia.com/gpu`:** the GPU is claimed. With one
  card, `maxReplicas` has to be 1 (ADR-0004). If there's an old pod terminating,
  wait.
- **`Pending` / `Insufficient memory`:** requests don't fit. Lower them or use
  a smaller model.
- **`Init:0/1` for a long time:** downloading weights.
  `kubectl -n nullnode-platform logs ollama-0 -c preload-models -f`
- **Zero replicas and everything healthy:** `scaleToZero` active and the pool
  sleeping.

### NullNodeWorkerPoolCrashLooping

Almost always OOM:

```bash
kubectl -n nullnode-platform get pod ollama-0 \
  -o jsonpath='{.status.containerStatuses[0].lastState}' | jq
```

`OOMKilled` means limit below the working set. A quantized 7B needs ~6 GiB of
container RAM even on GPU (KV cache, tokenizer, buffers). Raise
`resources.limits.memory` or drop to a smaller model.

### NullNodeGpuMemoryHigh

The next load will fail or evict a resident model.

```bash
kubectl -n nullnode-observability port-forward svc/dcgm-exporter 9400:9400
curl -s localhost:9400/metrics | grep DCGM_FI_DEV_FB
```

Lower `OLLAMA_MAX_LOADED_MODELS` to 1 or use more aggressive quantizations
(`:q4_0`).

---

## Problems without alerts

### `curl` doesn't resolve `gateway.nullnode.localhost`

glibc doesn't resolve `*.localhost` (browsers do).

```bash
make hosts   # prints the line for /etc/hosts
```

Or skip it: `curl --resolve gateway.nullnode.localhost:8080:127.0.0.1 ...`

### Department keys don't appear

`make department-keys` reads the Secrets Manager secret that the bootstrap job
writes. If it comes back empty or `_bootstrap: pending`:

```bash
kubectl -n nullnode-platform get jobs
kubectl -n nullnode-platform logs job/<litellm-bootstrap-...>
```

It's a PostSync hook: only runs if the `litellm` Application syncs properly.
Idempotent, and doesn't regenerate already registered keys.

### A Grafana panel is empty

Distinguish "no traffic" from "the metric was renamed":

```bash
KEY=$(make -s key)
curl -s http://gateway.nullnode.localhost:8080/metrics | grep '^litellm_' | cut -d'{' -f1 | sort -u
```

Compare with the panel expressions. Names change between LiteLLM minor versions:
ADR-0006.

### ArgoCD marks Ollama or LiteLLM as `OutOfSync` forever

Should be covered: `argocd.tf` configures `ignoreDifferences` on
`/spec/replicas`, because KEDA and the HPA own the field. If it reappears,
check that the ConfigMap maintains them:

```bash
kubectl -n argocd get cm argocd-cm -o yaml | grep -A3 ignoreDifferences
```

### Everything is weird after restarting Docker

LocalStack Community doesn't persist: on restart, bucket and secrets disappear
and pods fail S3 calls.

```bash
./scripts/up.sh --only cloud-mock   # recreates bucket and secrets
```

Watch out: Terraform generates new credentials, so the distributed department
keys stop working (ADR-0005).
