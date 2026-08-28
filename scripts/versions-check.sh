#!/usr/bin/env bash
#
# The chart versions are pinned by hand, so they can point at something that
# does not exist. Check them before a sync does.
#
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
trap - ERR

require_tool helm || die "helm is required"

# name|repo|chart|version - keep in step with k8s/platform/values.yaml
PINS=(
  "keda|https://kedacore.github.io/charts|keda|2.15.2"
  "kube-prometheus-stack|https://prometheus-community.github.io/helm-charts|kube-prometheus-stack|65.5.1"
  "otel-collector|https://open-telemetry.github.io/opentelemetry-helm-charts|opentelemetry-collector|0.108.1"
  "nvidia-device-plugin|https://nvidia.github.io/k8s-device-plugin|nvidia-device-plugin|0.17.0"
  "dcgm-exporter|https://nvidia.github.io/dcgm-exporter/helm-charts|dcgm-exporter|3.6.1"
  "argo-cd|https://argoproj.github.io/argo-helm|argo-cd|7.7.11"
)

FAILURES=0

phase "Pinned chart versions"
for pin in "${PINS[@]}"; do
  IFS='|' read -r name repo chart version <<<"$pin"
  helm repo add "nullnode-check-${name}" "$repo" >/dev/null 2>&1 || true
  helm repo update "nullnode-check-${name}" >/dev/null 2>&1 || true

  latest="$(helm search repo "nullnode-check-${name}/${chart}" --versions \
    -o json 2>/dev/null | sed -n 's/.*"version":"\([^"]*\)".*/\1/p' | head -n1)"

  if helm search repo "nullnode-check-${name}/${chart}" --version "$version" \
       -o json 2>/dev/null | grep -q '"version"'; then
    if [[ -n "$latest" && "$latest" != "$version" ]]; then
      ok "${name} ${version} exists (latest: ${latest})"
    else
      ok "${name} ${version} exists and is current"
    fi
  else
    err "${name} ${version} not found in ${repo}"
    [[ -n "$latest" ]] && hint "latest available: ${latest}"
    FAILURES=$((FAILURES + 1))
  fi
  helm repo remove "nullnode-check-${name}" >/dev/null 2>&1 || true
done

printf '\n'
if (( FAILURES > 0 )); then
  die "${FAILURES} pinned version(s) are wrong - fix k8s/platform/values.yaml"
fi
ok "every pinned chart version resolves"
