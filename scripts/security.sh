#!/usr/bin/env bash
#
# Security and hygiene scans. Same tools CI runs, same configuration.
#
#   ./scripts/security.sh              # everything installed locally
#   ./scripts/security.sh iac          # one group
#
# Groups: iac | manifests | secrets | images | format | all
#
# Missing tools are skipped with a hint rather than failing the run: the point
# is that a partial local scan is better than none.
#
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

# Collect every failure instead of stopping at the first.
trap - ERR

GROUP="${1:-all}"
FAILURES=0
REPORTS="${REPO_ROOT}/reports"
RENDERED="${REPORTS}/rendered"

run() {
  local name="$1"
  shift
  if "$@" >"${REPORTS}/last.log" 2>&1; then
    ok "$name"
  else
    err "$name"
    sed 's/^/    /' "${REPORTS}/last.log" | tail -n 40
    FAILURES=$((FAILURES + 1))
  fi
}

have() {
  if command -v "$1" >/dev/null 2>&1; then
    return 0
  fi
  warn "$1 not installed; skipping"
  [[ -n "${2:-}" ]] && hint "$2"
  return 1
}

# The interesting security properties live in the rendered output, not in the
# templates: securityContext, resource limits, image tags, host mounts.
render_manifests() {
  have helm || return 1
  rm -rf "$RENDERED"
  mkdir -p "$RENDERED"

  local chart name
  for chart in "${REPO_ROOT}"/k8s/charts/*; do
    name="$(basename "$chart")"
    if ! helm template "$name" "$chart" >"${RENDERED}/${name}.yaml" 2>/dev/null; then
      err "could not render ${name}"
      FAILURES=$((FAILURES + 1))
      return 1
    fi
  done

  # Presidio enabled changes the gateway's config and env.
  helm template litellm "${REPO_ROOT}/k8s/charts/litellm" \
    --set guardrails.pii.enabled=true \
    >"${RENDERED}/litellm-guardrail.yaml" 2>/dev/null

  ok "rendered $(find "$RENDERED" -name '*.yaml' | wc -l | tr -d ' ') manifest set(s)"
}

# --------------------------------------------------------------------------
scan_iac() {
  phase "IaC misconfiguration"

  if have trivy "https://trivy.dev/latest/getting-started/installation/"; then
    run "trivy config (terraform)" \
      trivy config --config "${REPO_ROOT}/trivy.yaml" "${REPO_ROOT}/infra/terraform"
    run "trivy config (dockerfile)" \
      trivy config --config "${REPO_ROOT}/trivy.yaml" "${REPO_ROOT}/infra/k3d/cuda"
  fi

  # NOTE: tfsec is no longer developed on its own - Aqua folded it into Trivy,
  # and `trivy config` above runs the same rule set. Kept as an opt-in for
  # anyone whose pipeline still standardises on it.
  if [[ "${WITH_TFSEC:-false}" == "true" ]]; then
    if have tfsec "https://github.com/aquasecurity/tfsec"; then
      run "tfsec" tfsec "${REPO_ROOT}/infra/terraform" --concise-output
    fi
  fi

  if have checkov "pipx install checkov"; then
    run "checkov" checkov --config-file "${REPO_ROOT}/.checkov.yaml"
  fi
}

scan_manifests() {
  phase "Rendered manifests"
  render_manifests || return

  if have trivy; then
    run "trivy config (rendered charts)" \
      trivy config --config "${REPO_ROOT}/trivy.yaml" "$RENDERED"
  fi

  if have kube-linter "https://docs.kubelinter.io/#/?id=installing-kubelinter"; then
    run "kube-linter" kube-linter lint \
      --config "${REPO_ROOT}/.kube-linter.yaml" "$RENDERED"
  fi
}

scan_secrets() {
  phase "Secrets"

  if have gitleaks "https://github.com/gitleaks/gitleaks"; then
    # Working tree and full history: a rotated credential that is still in an
    # old commit is still a leaked credential.
    run "gitleaks (working tree)" gitleaks dir "$REPO_ROOT" \
      --config "${REPO_ROOT}/.gitleaks.toml" --no-banner --redact
    run "gitleaks (history)" gitleaks git "$REPO_ROOT" \
      --config "${REPO_ROOT}/.gitleaks.toml" --no-banner --redact
  fi

  if have trivy; then
    run "trivy fs (secret scan)" \
      trivy fs --scanners secret --config "${REPO_ROOT}/trivy.yaml" "$REPO_ROOT"
  fi
}

scan_images() {
  phase "Container images"
  have trivy || return

  # Informational: LiteLLM and Ollama images are several GiB and their CVE
  # count is dominated by the CUDA and Python base layers. Pulling them in a
  # gate would make the pipeline slow and permanently red.
  local images=(
    "redis:7.4-alpine"
    "postgres:16.4-alpine"
    "python:3.12-alpine"
    "localstack/localstack:3.8.1"
    "oliver006/redis_exporter:v1.66.0"
  )
  local image
  for image in "${images[@]}"; do
    log "scanning ${image}"
    trivy image --config "${REPO_ROOT}/trivy.yaml" --exit-code 0 \
      --scanners vuln "$image" 2>/dev/null | tail -n 20
  done
  ok "image scan complete (informational)"
}

check_format() {
  phase "Formatting"

  if have terraform; then
    run "terraform fmt" terraform fmt -check -recursive "${REPO_ROOT}/infra/terraform"
  fi

  if have shfmt "https://github.com/mvdan/sh"; then
    run "shfmt" shfmt -d -i 2 -ci "${REPO_ROOT}/scripts"
  fi

  if have actionlint "https://github.com/rhysd/actionlint"; then
    run "actionlint" actionlint
  fi

  if have markdownlint-cli2 "npm i -g markdownlint-cli2"; then
    run "markdownlint" markdownlint-cli2 \
      --config "${REPO_ROOT}/.markdownlint.yaml" "${REPO_ROOT}/**/*.md"
  fi

  if have hadolint "https://github.com/hadolint/hadolint"; then
    run "hadolint" hadolint "${REPO_ROOT}/infra/k3d/cuda/Dockerfile"
  fi
}

mkdir -p "$REPORTS"

case "$GROUP" in
  iac) scan_iac ;;
  manifests) scan_manifests ;;
  secrets) scan_secrets ;;
  images) scan_images ;;
  format) check_format ;;
  all)
    scan_iac
    scan_manifests
    scan_secrets
    check_format
    ;;
  *) die "unknown group: ${GROUP} (iac|manifests|secrets|images|format|all)" ;;
esac

rm -f "${REPORTS}/last.log"
printf '\n'
if ((FAILURES > 0)); then
  die "${FAILURES} scan(s) failed"
fi
ok "all scans passed"
