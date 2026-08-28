#!/usr/bin/env bash
# Shared plumbing for the lifecycle scripts. Sourced, not executed.

set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly REPO_ROOT

CLUSTER_NAME="${CLUSTER_NAME:-nullnode}"
PROFILE="${PROFILE:-gpu}"
HOST_SUFFIX="${HOST_SUFFIX:-nullnode.localhost}"
KUBE_CONTEXT="k3d-${CLUSTER_NAME}"
LOCALSTACK_ENDPOINT="${LOCALSTACK_ENDPOINT:-http://127.0.0.1:4566}"
readonly CLUSTER_NAME PROFILE HOST_SUFFIX KUBE_CONTEXT LOCALSTACK_ENDPOINT

INGRESS_HOSTS=(
  "gateway.${HOST_SUFFIX}"
  "grafana.${HOST_SUFFIX}"
  "prometheus.${HOST_SUFFIX}"
  "argocd.${HOST_SUFFIX}"
)
readonly INGRESS_HOSTS
# shellcheck disable=SC2034
# INGRESS_HOSTS is used by status.sh but defined here for sharing

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_RED=$'\033[0;31m'; C_GREEN=$'\033[0;32m'
  C_YELLOW=$'\033[0;33m'; C_BLUE=$'\033[0;34m'; C_DIM=$'\033[2m'
else
  C_RESET=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_DIM=''
fi
readonly C_RESET C_RED C_GREEN C_YELLOW C_BLUE C_DIM

log()   { printf '%s==>%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()    { printf '%s  ok%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn()  { printf '%swarn%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()   { printf '%s fail%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
hint()  { printf '%s     %s%s\n' "$C_DIM" "$*" "$C_RESET"; }
die()   { err "$*"; exit 1; }

phase() {
  printf '\n%s┌─ %s%s\n' "$C_BLUE" "$*" "$C_RESET"
}

# Report the failing line and command instead of exiting silently.
_on_error() {
  local exit_code=$?
  err "aborted at ${BASH_SOURCE[1]:-?}:${BASH_LINENO[0]:-?} -> ${BASH_COMMAND}"
  exit "$exit_code"
}
trap _on_error ERR

require_tool() {
  local tool="$1" install_hint="${2:-}"
  if ! command -v "$tool" >/dev/null 2>&1; then
    err "$tool not found on PATH"
    [[ -n "$install_hint" ]] && hint "$install_hint"
    return 1
  fi
  return 0
}

# Dotted version compare, without depending on sort -V.
version_at_least() {
  local have="$1" want="$2"
  [[ "$(printf '%s\n%s\n' "$want" "$have" | sort -t. -k1,1n -k2,2n -k3,3n | head -n1)" == "$want" ]]
}

cluster_exists() {
  k3d cluster list -o json 2>/dev/null | grep -q "\"name\":\"${CLUSTER_NAME}\""
}

kube() {
  kubectl --context "$KUBE_CONTEXT" "$@"
}

# Keeps -chdir consistent across callers.
tf() {
  local stack="$1"; shift
  TF_IN_AUTOMATION=1 terraform -chdir="${REPO_ROOT}/infra/terraform/${stack}" "$@"
}

localstack_healthy() {
  curl -fsS --max-time 5 "${LOCALSTACK_ENDPOINT}/_localstack/health" 2>/dev/null \
    | grep -q '"s3"'
}

# Poll a command until it succeeds.
wait_for() {
  local description="$1" attempts="$2" delay="$3"; shift 3
  local i
  for ((i = 1; i <= attempts; i++)); do
    if "$@" >/dev/null 2>&1; then
      ok "$description"
      return 0
    fi
    printf '\r%s  ..%s waiting for %s (%d/%d)' \
      "$C_DIM" "$C_RESET" "$description" "$i" "$attempts"
    sleep "$delay"
  done
  printf '\n'
  err "timed out waiting for ${description}"
  return 1
}
