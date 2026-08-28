#!/usr/bin/env bash
#
# Everything checkable without a cluster. Same checks CI runs.
#
#   ./scripts/validate.sh            # all checks
#   ./scripts/validate.sh helm       # one group: helm | terraform | shell | yaml
#
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
# Collect every failure instead of stopping at the first.
trap - ERR

GROUP="${1:-all}"
FAILURES=0

run() {
  local name="$1"; shift
  if "$@" >/tmp/nullnode-validate.log 2>&1; then
    ok "$name"
  else
    err "$name"
    sed 's/^/    /' /tmp/nullnode-validate.log | tail -n 30
    FAILURES=$((FAILURES + 1))
  fi
}

CHARTS=(
  "${REPO_ROOT}/k8s/charts/redis"
  "${REPO_ROOT}/k8s/charts/postgres"
  "${REPO_ROOT}/k8s/charts/ollama"
  "${REPO_ROOT}/k8s/charts/litellm"
  "${REPO_ROOT}/k8s/charts/presidio"
  "${REPO_ROOT}/k8s/charts/nullnode-observability"
  "${REPO_ROOT}/k8s/platform"
  "${REPO_ROOT}/k8s/bootstrap/root"
)

validate_helm() {
  phase "Helm"
  require_tool helm || { FAILURES=$((FAILURES + 1)); return; }

  local chart
  for chart in "${CHARTS[@]}"; do
    run "lint $(basename "$chart")" helm lint "$chart" --strict
  done

  # The check that matters: lint passes on templates that render invalid
  # YAML.
  for chart in "${CHARTS[@]}"; do
    run "template $(basename "$chart")" helm template validate "$chart"
  done

  # Both hardware profiles have to render.
  local profile
  for profile in gpu cpu; do
    run "template platform (${profile} profile)" \
      helm template validate "${REPO_ROOT}/k8s/platform" \
        -f "${REPO_ROOT}/k8s/platform/values.yaml" \
        -f "${REPO_ROOT}/k8s/platform/values-${profile}.yaml"
  done

  # Presidio changes the gateway config, so render both states.
  run "template litellm (guardrail on)" \
    helm template validate "${REPO_ROOT}/k8s/charts/litellm" \
      --set guardrails.pii.enabled=true

  if command -v kubeconform >/dev/null 2>&1; then
    for chart in "${CHARTS[@]}"; do
      # CRDs are not in the upstream schema set.
      run "kubeconform $(basename "$chart")" bash -c \
        "helm template validate '${chart}' | kubeconform -strict -summary \
           -ignore-missing-schemas \
           -skip ScaledObject,ServiceMonitor,PrometheusRule,Application,AppProject -"
    done
  else
    warn "kubeconform not installed; skipping schema validation"
    hint "https://github.com/yannh/kubeconform"
  fi
}

validate_terraform() {
  phase "Terraform"
  require_tool terraform || { FAILURES=$((FAILURES + 1)); return; }

  run "fmt" terraform fmt -check -recursive "${REPO_ROOT}/infra/terraform"

  local stack
  for stack in cloud-mock platform-bootstrap; do
    # -backend=false: never touch state.
    run "init ${stack}" tf "$stack" init -backend=false -input=false
    run "validate ${stack}" tf "$stack" validate
  done
}

validate_shell() {
  phase "Shell"
  if ! command -v shellcheck >/dev/null 2>&1; then
    warn "shellcheck not installed; skipping"
    hint "https://github.com/koalaman/shellcheck"
    return
  fi
  local script
  while IFS= read -r script; do
    run "shellcheck $(basename "$script")" \
      shellcheck -x -S warning "$script"
  done < <(find "${REPO_ROOT}/scripts" -name '*.sh' -type f | sort)
}

validate_yaml() {
  phase "YAML"
  if ! command -v yamllint >/dev/null 2>&1; then
    warn "yamllint not installed; skipping"
    return
  fi
  # Helm templates are not YAML until rendered.
  run "yamllint" yamllint -c "${REPO_ROOT}/.yamllint.yaml" \
    "${REPO_ROOT}/infra/k3d" \
    "${REPO_ROOT}/k8s/platform/values" \
    "${REPO_ROOT}/.github"
}

validate_python() {
  phase "Python"
  if ! command -v python3 >/dev/null 2>&1; then
    warn "python3 not installed; skipping"
    return
  fi
  run "compile bootstrap script" \
    python3 -m py_compile "${REPO_ROOT}/k8s/charts/litellm/files/bootstrap_departments.py"

  local dash
  for dash in "${REPO_ROOT}"/k8s/charts/nullnode-observability/dashboards/*.json; do
    run "json $(basename "$dash")" python3 -m json.tool "$dash" /dev/null
  done
}

case "$GROUP" in
  helm)      validate_helm ;;
  terraform) validate_terraform ;;
  shell)     validate_shell ;;
  yaml)      validate_yaml ;;
  python)    validate_python ;;
  all)
    validate_helm
    validate_terraform
    validate_shell
    validate_yaml
    validate_python
    ;;
  *) die "unknown group: ${GROUP} (helm|terraform|shell|yaml|python|all)" ;;
esac

printf '\n'
if (( FAILURES > 0 )); then
  die "${FAILURES} check(s) failed"
fi
ok "all checks passed"
