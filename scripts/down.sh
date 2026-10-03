#!/usr/bin/env bash
#
# Tear NullNode down. Keeps the model weights by default - re-downloading them
# is the slowest part of a rebuild.
#
#   ./scripts/down.sh            # cluster + LocalStack, keep model volume
#   ./scripts/down.sh --purge    # also delete the model weights
#   ./scripts/down.sh --keep-cloud-mock
#
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

PURGE=false
KEEP_CLOUD_MOCK=false
PLATFORM_DESTROYED=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --purge)
      PURGE=true
      shift
      ;;
    --keep-cloud-mock)
      KEEP_CLOUD_MOCK=true
      shift
      ;;
    -h | --help)
      sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) die "unknown flag: $1 (try --help)" ;;
  esac
done

# ArgoCD stamps `resources-finalizer.argocd.argoproj.io` on every Application
# and on the AppProject. Uninstalling the controller before those are cleared
# leaves objects nothing can finalize, and deleting the argocd namespace then
# blocks forever - taking the cluster and LocalStack teardown down with it.
# The cluster is about to be deleted wholesale, so orphaning what ArgoCD
# manages costs nothing.
release_argocd_finalizers() {
  kube get crd applications.argoproj.io >/dev/null 2>&1 || return 0
  log "clearing ArgoCD finalizers"
  local kind
  for kind in applications appprojects; do
    kube -n argocd patch "$kind" --all --type merge \
      -p '{"metadata":{"finalizers":null}}' >/dev/null 2>&1 || true
  done
  ok "finalizers cleared"
}

phase "Platform state"
# Destroy in-cluster resources first: killing the cluster under a live state
# file leaves it describing things that are gone, and the next apply fails.
if [[ -f "${REPO_ROOT}/infra/terraform/platform-bootstrap/terraform.tfstate" ]]; then
  if cluster_exists; then
    release_argocd_finalizers
    log "terraform destroy (platform-bootstrap)"
    tf_limited 600 platform-bootstrap destroy -input=false -auto-approve || {
      PLATFORM_DESTROYED=false
      warn "destroy did not finish; the cluster removal below makes it moot"
    }
  else
    warn "cluster already gone; discarding stale platform state"
    rm -f "${REPO_ROOT}/infra/terraform/platform-bootstrap/terraform.tfstate"*
  fi
else
  ok "no platform state to remove"
fi

phase "Cluster"
if cluster_exists; then
  log "deleting k3d cluster '${CLUSTER_NAME}'"
  k3d cluster delete "$CLUSTER_NAME" || warn "k3d reported an error; sweeping below"
  ok "cluster deleted"
  # Every resource in that state - two helm releases and three namespaces -
  # lived inside the cluster. Keeping a half-destroyed state file only makes
  # the next `make up` fail against resources that no longer exist.
  if [[ "$PLATFORM_DESTROYED" != true ]]; then
    warn "discarding the incomplete platform state"
    rm -f "${REPO_ROOT}/infra/terraform/platform-bootstrap/terraform.tfstate"*
  fi
else
  ok "cluster '${CLUSTER_NAME}' not present"
fi

phase "Cloud mock"
if [[ "$KEEP_CLOUD_MOCK" == true ]]; then
  ok "keeping LocalStack running (--keep-cloud-mock)"
else
  if [[ -f "${REPO_ROOT}/infra/terraform/cloud-mock/terraform.tfstate" ]]; then
    log "terraform destroy (cloud-mock)"
    tf_limited 300 cloud-mock destroy -input=false -auto-approve ||
      warn "destroy did not finish; the sweep below removes the container"
  else
    ok "no cloud-mock state to remove"
  fi
fi

phase "Volumes"
if [[ "$PURGE" == true ]]; then
  warn "removing the model volume - the next boot re-downloads every model"
  docker volume rm nullnode-storage >/dev/null 2>&1 &&
    ok "volume nullnode-storage removed" ||
    ok "volume nullnode-storage was not present"
else
  if docker volume inspect nullnode-storage >/dev/null 2>&1; then
    ok "model volume kept (use --purge to delete it)"
  fi
fi

# Nothing above is guaranteed to have run to completion - a failed destroy is
# warned about, not fatal. Without this, `make down` can report success while
# containers keep running and the next `make up` trips over the port bindings.
phase "Leftovers"
sweep() {
  local description="$1" name_filter="$2" ids
  ids="$(docker ps -aq --filter "name=${name_filter}" 2>/dev/null || true)"
  if [[ -z "$ids" ]]; then
    ok "no ${description} left"
    return 0
  fi
  warn "removing ${description} the teardown left behind:"
  printf '%s\n' "$ids" | sed 's/^/    /'
  printf '%s\n' "$ids" | xargs -r docker rm -f >/dev/null 2>&1 || true
}

# k3d prefixes every node, the load balancer and the managed registry with
# k3d-<cluster>-. LocalStack is named by the cloud-mock stack.
sweep "k3d containers" "^k3d-${CLUSTER_NAME}"
sweep "the LocalStack container" "^${CLUSTER_NAME}-localstack\$"

if docker network inspect "k3d-${CLUSTER_NAME}" >/dev/null 2>&1; then
  docker network rm "k3d-${CLUSTER_NAME}" >/dev/null 2>&1 &&
    ok "network k3d-${CLUSTER_NAME} removed" ||
    warn "network k3d-${CLUSTER_NAME} still in use"
else
  ok "no cluster network left"
fi

printf '\n'
ok "NullNode torn down"
