# Troubleshooting

Frequent problems ordered by when they appear.

---

## During `make setup` / preflight

### "Docker not found" when running `make setup`

Docker is the only prerequisite that can't be installed from the Makefile.
Follow the installation guide for your system:
<https://docs.docker.com/engine/install/>

On WSL2, install Docker Desktop on Windows and enable integration with your
distro in Settings → Resources → WSL Integration.

### "the GPU profile is selected but Docker cannot reach an NVIDIA GPU"

The preflight tells you exactly which of the three steps is missing:

1. **NVIDIA driver** → install it on Windows (not WSL). Restart.

2. **nvidia-container-toolkit** → inside the WSL distro:

   ```bash
   curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
   curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
     | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
     | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
   sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
   sudo nvidia-ctk runtime configure --runtime=docker
   sudo systemctl restart docker
   ```

3. **k3s CUDA image** → `make k3s-cuda-image` (takes a few minutes, only once).

If you don't have a GPU, use `PROFILE=cpu make up`.

### "k3d X.Y.Z is too old"

```bash
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | TAG=v5.7.4 bash
```

---

## During `make up`

### Cluster already exists and `make up` fails creating it

```bash
k3d cluster delete nullnode
make up
```

Or if you want to preserve state: `make up --from cloud-mock` to skip the cluster
phase.

### LocalStack doesn't start / `terraform apply` fails in cloud-mock

LocalStack runs as a Docker container. Check:

```bash
docker ps -a | grep localstack
docker logs localstack
```

If the container exists but doesn't respond:

```bash
docker rm -f localstack
make up --from cloud-mock
```

If there's a port conflict error (`4566 already in use`):

```bash
lsof -i :4566
# kill the process occupying it, then:
make up --from cloud-mock
```

### ArgoCD doesn't sync / applications in `Unknown` or `OutOfSync`

ArgoCD reconciles from git, not from your local copy. If you just made changes,
make sure you pushed them:

```bash
git push
make sync
```

If the gitops revision doesn't match the branch you're working on:

```bash
terraform -chdir=infra/terraform/platform-bootstrap apply \
  -var gitops_target_revision=my-branch
```

### Pods in `Pending` (GPU profile)

Almost always the NVIDIA device plugin isn't ready yet or the pod requests the
GPU before the plugin registers it. Wait a minute and check:

```bash
kubectl get pods -n nullnode-platform -o wide
kubectl describe pod <pending-pod> -n nullnode-platform
```

If the event says `0/1 nodes have sufficient nvidia.com/gpu`, the device plugin
isn't ready yet:

```bash
kubectl rollout status ds/nvidia-device-plugin-daemonset -n kube-system
```

### Ollama takes a long time to start

Normal on first boot: it's downloading model weights. With `make logs-ollama`
you can see progress. For llama3.2 (3B) expect 5-15 minutes depending on your
connection.

---

## During `make smoke`

### "DNS resolution failed" for `gateway.nullnode.localhost`

The `/etc/hosts` entries aren't added. Run `make hosts` to see the exact line
and add it:

```bash
make hosts
# 127.0.0.1 gateway.nullnode.localhost grafana.nullnode.localhost ...
sudo tee -a /etc/hosts <<< "127.0.0.1 gateway.nullnode.localhost grafana.nullnode.localhost prometheus.nullnode.localhost argocd.nullnode.localhost"
```

On Windows, if accessing from the browser, add the same line to
`C:\Windows\System32\drivers\etc\hosts` (as administrator).

### "401 Unauthorized" in the smoke test

The master key didn't reach the LiteLLM pod. Check that the secret exists:

```bash
kubectl get secret litellm-master-key -n nullnode-platform
```

If it doesn't exist, the Terraform `platform-bootstrap` didn't finish well.
Check the output: `terraform -chdir=infra/terraform/platform-bootstrap output`.

### "cache miss on all repeated requests"

Redis isn't configured as cache backend in LiteLLM, or the Redis pod isn't Ready:

```bash
kubectl rollout status statefulset/redis -n nullnode-platform
kubectl -n nullnode-platform logs deployment/litellm | grep -i cache
```

### "no audit log in S3"

LiteLLM's S3 callback isn't reaching LocalStack. Check that LocalStack is still
alive:

```bash
curl http://127.0.0.1:4566/_localstack/health
```

If LocalStack died (happens if Docker restarts):

```bash
make up --from cloud-mock
```

---

## CI / GitHub Actions

### All CI jobs fail with "Permission denied"

Scripts in `scripts/` need execute permission. If you cloned the repo and
permissions weren't preserved:

```bash
chmod +x scripts/up.sh scripts/down.sh scripts/security.sh scripts/smoke.sh \
         scripts/status.sh scripts/validate.sh scripts/versions-check.sh
git update-index --chmod=+x scripts/up.sh scripts/down.sh scripts/security.sh
git commit -m "fix: restore execute permissions on scripts"
git push
```

### `markdownlint` fails with "conflict marker"

There are unresolved merge conflicts in some `.md`. Find them:

```bash
grep -r "^<<<<<<< " docs/
```

Resolve them manually and commit.

### Integration job times out (45 min)

The model didn't finish downloading. In CI only the CPU profile is used with a
1B model, but the runner might be saturated. Options:

- Re-run the job from the GitHub UI (Actions → Re-run failed jobs).
- If it fails repeatedly, check that the model configured for CPU is
  `llama3.2:1b` and not a larger one.

---

## Terraform

### "Error: No valid credential sources found"

Terraform is trying to connect to real AWS instead of LocalStack. Make sure the
mock environment variables are present:

```bash
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=eu-west-1
```

The `cloud-mock` stack injects them automatically when starting from `make up`,
but if you run Terraform directly you'll need to export them.

### "state lock" when re-running `make up`

If a previous `apply` was interrupted, a lock might remain. With LocalStack as
backend, deleting it is simple:

```bash
terraform -chdir=infra/terraform/cloud-mock force-unlock <lock-id>
```

The lock-id appears in the error message.

---

## Observability

### Empty Grafana panels

LiteLLM metrics depend on the pinned chart version
([ADR-0006](../adr/0006-metrics-sources.md)). If you updated LiteLLM, metric
names might have changed. Check:

```bash
curl -s http://gateway.nullnode.localhost:8080/metrics | grep litellm
```

And compare with the recording rules in
`k8s/charts/nullnode-observability/templates/`.

### "No data" in the VRAM panel (GPU profile only)

The DCGM exporter takes time to start. Wait 2-3 minutes after the first cluster
boot. If it still doesn't appear:

```bash
kubectl get pods -n kube-system | grep dcgm
kubectl logs -n kube-system <dcgm-pod>
```
