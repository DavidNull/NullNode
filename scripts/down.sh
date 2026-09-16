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

phase "Platform state"
# Destroy in-cluster resources first: killing the cluster under a live state
# file leaves it describing things that are gone, and the next apply fails.
if [[ -f "${REPO_ROOT}/infra/terraform/platform-bootstrap/terraform.tfstate" ]]; then
  if cluster_exists; then
    log "terraform destroy (platform-bootstrap)"
    tf platform-bootstrap destroy -input=false -auto-approve ||
      warn "destroy failed; the cluster removal below makes it moot"
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
  k3d cluster delete "$CLUSTER_NAME"
  ok "cluster deleted"
else
  ok "cluster '${CLUSTER_NAME}' not present"
fi

phase "Cloud mock"
if [[ "$KEEP_CLOUD_MOCK" == true ]]; then
  ok "keeping LocalStack running (--keep-cloud-mock)"
else
  if [[ -f "${REPO_ROOT}/infra/terraform/cloud-mock/terraform.tfstate" ]]; then
    log "terraform destroy (cloud-mock)"
    tf cloud-mock destroy -input=false -auto-approve ||
      warn "destroy failed; remove the container by hand: docker rm -f nullnode-localstack"
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

printf '\n'
ok "NullNode torn down"
