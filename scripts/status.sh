#!/usr/bin/env bash
#
# Endpoints, credentials and anything unhealthy. Read-only.
#
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
# A half-up platform is the normal case here, not an error.
trap - ERR
set +e

printf '%sNullNode status%s\n' "$C_BLUE" "$C_RESET"

# --------------------------------------------------------------- infrastructure
phase "Infrastructure"
if cluster_exists; then
  ok "k3d cluster '${CLUSTER_NAME}' up"
else
  err "k3d cluster '${CLUSTER_NAME}' not found - run make up"
  exit 0
fi

if localstack_healthy; then
  ok "LocalStack healthy at ${LOCALSTACK_ENDPOINT}"
else
  err "LocalStack not answering at ${LOCALSTACK_ENDPOINT}"
  hint "the gateway's audit log and the secrets bridge both depend on it"
fi

# ------------------------------------------------------------------- workloads
phase "Workloads"
not_ready="$(kube get pods -A --no-headers 2>/dev/null |
  awk '$4 != "Running" && $4 != "Completed" {print "  " $1 "/" $2 " " $4}')"
if [[ -z "$not_ready" ]]; then
  ok "every pod is Running or Completed"
else
  warn "pods needing attention:"
  printf '%s\n' "$not_ready"
fi

phase "ArgoCD applications"
if kube get crd applications.argoproj.io >/dev/null 2>&1; then
  kube -n argocd get applications \
    -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status' \
    2>/dev/null | sed 's/^/  /'
else
  warn "ArgoCD CRDs not installed yet"
fi

phase "Autoscaling"
if kube get crd scaledobjects.keda.sh >/dev/null 2>&1; then
  kube -n nullnode-platform get scaledobject \
    -o custom-columns='NAME:.metadata.name,MIN:.spec.minReplicaCount,MAX:.spec.maxReplicaCount,READY:.status.conditions[?(@.type=="Ready")].status,ACTIVE:.status.conditions[?(@.type=="Active")].status' \
    2>/dev/null | sed 's/^/  /'
else
  warn "KEDA CRDs not installed yet"
fi

# ------------------------------------------------------------------- endpoints
phase "Endpoints"
for host in "${INGRESS_HOSTS[@]}"; do
  printf '  http://%s:8080\n' "$host"
done
printf '  %s (mocked AWS)\n' "$LOCALSTACK_ENDPOINT"

if ! grep -qs "gateway.${HOST_SUFFIX}" /etc/hosts; then
  warn "the *.${HOST_SUFFIX} names are not in /etc/hosts"
  hint "run 'make hosts' to print the line to add"
fi

# ----------------------------------------------------------------- credentials
phase "Credentials"
if [[ -f "${REPO_ROOT}/infra/terraform/platform-bootstrap/terraform.tfstate" ]]; then
  hint "gateway master key : make key"
  hint "grafana admin      : make grafana-password"
  hint "argocd admin       : make argocd-password"
  hint "department keys    : make department-keys"
else
  warn "platform not bootstrapped yet"
fi
printf '\n'
