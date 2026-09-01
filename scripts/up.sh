#!/usr/bin/env bash
#
# Bring NullNode up. Idempotent, and each phase can run on its own.
#
#   ./scripts/up.sh                       # everything, GPU profile
#   PROFILE=cpu ./scripts/up.sh           # everything, CPU profile
#   ./scripts/up.sh --only cloud-mock     # single phase
#   ./scripts/up.sh --from platform       # this phase onwards
#   ./scripts/up.sh --no-wait             # do not block on ArgoCD syncing
#
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

PHASES=(preflight cluster cloud-mock platform verify)
FROM=""
ONLY=""
WAIT=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --only)
      ONLY="${2:-}"
      shift 2
      ;;
    --from)
      FROM="${2:-}"
      shift 2
      ;;
    --no-wait)
      WAIT=false
      shift
      ;;
    -h | --help)
      sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) die "unknown flag: $1 (try --help)" ;;
  esac
done

should_run() {
  local phase="$1"
  if [[ -n "$ONLY" ]]; then
    [[ "$phase" == "$ONLY" ]]
    return
  fi
  if [[ -n "$FROM" ]]; then
    local seen=false p
    for p in "${PHASES[@]}"; do
      [[ "$p" == "$FROM" ]] && seen=true
      [[ "$p" == "$phase" ]] && {
        [[ "$seen" == true ]]
        return
      }
    done
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
phase_preflight() {
  phase "Preflight"

  local missing=0
  require_tool docker "https://docs.docker.com/engine/install/" || missing=1
  require_tool k3d "https://k3d.io/#installation" || missing=1
  require_tool kubectl "https://kubernetes.io/docs/tasks/tools/" || missing=1
  require_tool helm "https://helm.sh/docs/intro/install/" || missing=1
  require_tool terraform "https://developer.hashicorp.com/terraform/install" || missing=1
  require_tool curl "" || missing=1
  ((missing == 0)) || die "install the missing tools and re-run"

  docker info >/dev/null 2>&1 || die "the Docker daemon is not reachable"
  ok "docker daemon reachable"

  local k3d_version
  k3d_version="$(k3d version | awk '/k3d version/ {gsub(/^v/, "", $3); print $3}')"
  if [[ -n "$k3d_version" ]] && ! version_at_least "$k3d_version" "5.6.0"; then
    die "k3d ${k3d_version} is too old; the config schema used here needs >= 5.6.0"
  fi
  ok "k3d ${k3d_version:-unknown}"

  local tf_version
  tf_version="$(terraform version -json 2>/dev/null | sed -n 's/.*"terraform_version": *"\([^"]*\)".*/\1/p' | head -n1)"
  if [[ -n "$tf_version" ]] && ! version_at_least "$tf_version" "1.6.0"; then
    die "terraform ${tf_version} is too old; needs >= 1.6.0"
  fi
  ok "terraform ${tf_version:-unknown}"

  case "$PROFILE" in
    gpu)
      if ! docker run --rm --gpus all nvidia/cuda:12.6.2-base-ubuntu24.04 \
        nvidia-smi >/dev/null 2>&1; then
        err "the GPU profile is selected but Docker cannot reach an NVIDIA GPU"
        hint "checklist:"
        hint "  1. NVIDIA driver installed on the host (on Windows, not in WSL)"
        hint "  2. nvidia-container-toolkit installed inside the WSL distro"
        hint "  3. Docker restarted after step 2"
        hint "no GPU available? run with PROFILE=cpu instead"
        exit 1
      fi
      ok "GPU visible from Docker"

      if ! docker image inspect nullnode/k3s-cuda:v1.31.2-k3s1 >/dev/null 2>&1; then
        err "the CUDA-enabled k3s image is missing"
        hint "build it once with: make k3s-cuda-image  (takes a few minutes)"
        exit 1
      fi
      ok "CUDA k3s image present"
      ;;
    cpu)
      warn "CPU profile: inference will be slow. Keep the models small."
      ;;
    *)
      die "PROFILE must be gpu or cpu (got: ${PROFILE})"
      ;;
  esac
}

# ---------------------------------------------------------------------------
phase_cluster() {
  phase "Cluster"

  if cluster_exists; then
    ok "k3d cluster '${CLUSTER_NAME}' already exists"
  else
    log "creating k3d cluster from infra/k3d/${CLUSTER_NAME}-${PROFILE}.yaml"
    k3d cluster create --config "${REPO_ROOT}/infra/k3d/${CLUSTER_NAME}-${PROFILE}.yaml"
    ok "cluster created"
  fi

  kubectl config use-context "$KUBE_CONTEXT" >/dev/null
  wait_for "nodes to be Ready" 60 5 \
    kube wait --for=condition=Ready nodes --all --timeout=10s

  # k3s installs Traefik asynchronously; the Ingresses are dead until it
  # exists.
  wait_for "traefik to be available" 60 5 \
    kube -n kube-system rollout status deployment/traefik --timeout=10s
}

# ---------------------------------------------------------------------------
phase_cloud_mock() {
  phase "Cloud mock (LocalStack + S3 + Secrets Manager)"

  log "terraform init"
  tf cloud-mock init -input=false -upgrade >/dev/null

  log "terraform apply"
  tf cloud-mock apply -input=false -auto-approve \
    -var "aws_region=${AWS_REGION:-eu-west-1}"

  localstack_healthy &&
    ok "LocalStack answering at ${LOCALSTACK_ENDPOINT}" ||
    die "LocalStack applied but not healthy"

  local bucket
  bucket="$(tf cloud-mock output -raw vault_bucket)"
  ok "vault bucket: ${bucket}"
}

# ---------------------------------------------------------------------------
phase_platform() {
  phase "Platform bootstrap (ArgoCD + GitOps root)"

  localstack_healthy ||
    die "LocalStack is not up; run './scripts/up.sh --only cloud-mock' first"

  log "terraform init"
  tf platform-bootstrap init -input=false -upgrade >/dev/null

  log "terraform apply"
  tf platform-bootstrap apply -input=false -auto-approve \
    -var "hardware_profile=${PROFILE}" \
    -var "host_suffix=${HOST_SUFFIX}" \
    -var "kube_context=${KUBE_CONTEXT}"

  ok "ArgoCD installed and the root Application is registered"
}

# ---------------------------------------------------------------------------
phase_verify() {
  phase "Convergence"

  if [[ "$WAIT" != true ]]; then
    warn "--no-wait given; skipping convergence checks"
    return 0
  fi

  # The first sync pulls several GiB of images and model weights.
  log "waiting for ArgoCD to reconcile (first run pulls images and models,"
  log "so 10-20 minutes is normal - ^C is safe, sync continues in-cluster)"

  wait_for "argocd applications to be registered" 60 5 \
    kube -n argocd get application nullnode-root

  local app
  for app in postgres redis ollama litellm; do
    wait_for "application/${app} to exist" 60 10 \
      kube -n argocd get "application/${app}"
  done

  wait_for "postgres to be ready" 60 10 \
    kube -n nullnode-platform rollout status statefulset/postgres --timeout=10s
  wait_for "redis to be ready" 60 10 \
    kube -n nullnode-platform rollout status statefulset/redis --timeout=10s
  wait_for "ollama to pull models and start" 180 10 \
    kube -n nullnode-platform rollout status statefulset/ollama --timeout=10s
  wait_for "the gateway to be ready" 120 10 \
    kube -n nullnode-platform rollout status deployment/litellm --timeout=10s

  ok "platform converged"
}

# ---------------------------------------------------------------------------
main() {
  printf '%sNullNode%s - local LLMOps platform (profile: %s)\n' \
    "$C_BLUE" "$C_RESET" "$PROFILE"

  # `if`, not `&&`: a false should_run in an && list trips set -e.
  if should_run preflight; then phase_preflight; fi
  if should_run cluster; then phase_cluster; fi
  if should_run cloud-mock; then phase_cloud_mock; fi
  if should_run platform; then phase_platform; fi
  if should_run verify; then phase_verify; fi

  printf '\n'
  "${REPO_ROOT}/scripts/status.sh" || true
}

main "$@"
