# NullNode - operator entrypoint. `make help` lists everything.
# PROFILE=gpu|cpu selects the hardware profile.

SHELL := /bin/bash
.DEFAULT_GOAL := help

PROFILE     ?= gpu
HOST_SUFFIX ?= nullnode.localhost
CLUSTER     ?= nullnode
NS          ?= nullnode-platform
K3S_TAG     ?= v1.31.2-k3s1
CUDA_IMAGE  ?= nullnode/k3s-cuda:$(K3S_TAG)

export PROFILE HOST_SUFFIX
CLUSTER_NAME := $(CLUSTER)
export CLUSTER_NAME

TF_PLATFORM := terraform -chdir=infra/terraform/platform-bootstrap
KUBECTL     := kubectl --context k3d-$(CLUSTER)

.PHONY: help
help: ## Show this help
	@printf '\033[0;34mNullNode\033[0m - local LLMOps platform\n\n'
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "} {printf "  \033[0;32m%-22s\033[0m %s\n", $$1, $$2}'
	@printf '\nCurrent profile: \033[0;33m%s\033[0m (override with PROFILE=cpu)\n' '$(PROFILE)'

# --------------------------------------------------------------- lifecycle
.PHONY: up
up: ## Bring the whole platform up
	@./scripts/up.sh

.PHONY: down
down: ## Tear down cluster and cloud mock, keep model weights
	@./scripts/down.sh

.PHONY: purge
purge: ## Tear down everything including the downloaded models
	@./scripts/down.sh --purge

.PHONY: restart
restart: down up ## Full rebuild

.PHONY: status
status: ## Endpoints, credentials and anything unhealthy
	@./scripts/status.sh

.PHONY: smoke
smoke: ## End-to-end test: ingress -> auth -> model -> cache -> audit log
	@./scripts/smoke.sh

# --------------------------------------------------------------- validation
.PHONY: validate
validate: ## Run every offline check (same as CI)
	@./scripts/validate.sh

.PHONY: lint
lint: ## Helm lint + template only
	@./scripts/validate.sh helm

.PHONY: fmt
fmt: ## Format Terraform in place
	@terraform fmt -recursive infra/terraform

.PHONY: versions-check
versions-check: ## Verify the pinned upstream chart versions still exist
	@./scripts/versions-check.sh

.PHONY: security
security: ## Trivy, Checkov, kube-linter and gitleaks (skips what is not installed)
	@./scripts/security.sh

.PHONY: fmt-check
fmt-check: ## Formatting only: terraform, shfmt, actionlint, hadolint, markdownlint
	@./scripts/security.sh format

.PHONY: check
check: validate security ## Everything a PR has to pass
# --------------------------------------------------------------- images
.PHONY: k3s-cuda-image
k3s-cuda-image: ## Build the CUDA-enabled k3s node image (GPU profile only)
	@printf 'building %s (this takes a few minutes)\n' '$(CUDA_IMAGE)'
	@docker build \
	  --build-arg K3S_TAG=$(K3S_TAG) \
	  -t $(CUDA_IMAGE) \
	  infra/k3d/cuda

# --------------------------------------------------------------- credentials
.PHONY: key
key: ## Print the gateway master key
	@$(TF_PLATFORM) output -raw litellm_master_key; echo

.PHONY: grafana-password
grafana-password: ## Print the generated Grafana admin password
	@$(TF_PLATFORM) output -raw grafana_admin_password; echo

.PHONY: argocd-password
argocd-password: ## Print the ArgoCD admin password
	@$(KUBECTL) -n argocd get secret argocd-initial-admin-secret \
	  -o jsonpath='{.data.password}' | base64 -d; echo

.PHONY: department-keys
department-keys: ## Print the per-department virtual keys from the mocked Secrets Manager
	@curl -sS -X POST http://127.0.0.1:4566/ \
	  -H 'Content-Type: application/x-amz-json-1.1' \
	  -H 'X-Amz-Target: secretsmanager.GetSecretValue' \
	  -H 'Authorization: AWS4-HMAC-SHA256 Credential=test/20240101/eu-west-1/secretsmanager/aws4_request, SignedHeaders=host, Signature=mock' \
	  -d '{"SecretId":"nullnode/litellm/department-keys"}' \
	  | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["SecretString"])'

# --------------------------------------------------------------- day two
.PHONY: hosts
hosts: ## Print the /etc/hosts line the Ingress hostnames need
	@printf '# NullNode - add to /etc/hosts\n'
	@printf '127.0.0.1 gateway.%s grafana.%s prometheus.%s argocd.%s\n' \
	  '$(HOST_SUFFIX)' '$(HOST_SUFFIX)' '$(HOST_SUFFIX)' '$(HOST_SUFFIX)'

.PHONY: logs
logs: ## Follow the gateway logs
	@$(KUBECTL) -n $(NS) logs -f deployment/litellm --tail=100

.PHONY: logs-ollama
logs-ollama: ## Follow the inference logs
	@$(KUBECTL) -n $(NS) logs -f statefulset/ollama --tail=100

.PHONY: sync
sync: ## Force ArgoCD to re-reconcile every application now
	@$(KUBECTL) -n argocd annotate applications --all --overwrite \
	  argocd.argoproj.io/refresh=hard

.PHONY: netpol-on
netpol-on: ## Enable the datastore NetworkPolicies (off by default)
	@printf 'set components.redis.values.networkPolicy.enabled and\n'
	@printf 'components.postgres.values.networkPolicy.enabled to true in\n'
	@printf 'k8s/platform/values.yaml, then commit and push - ArgoCD applies it.\n'

.PHONY: load-test
load-test: ## Run the k6 load test against the gateway
	@k6 run tests/load/chat-completions.js \
	  -e GATEWAY=http://gateway.$(HOST_SUFFIX):8080 \
	  -e API_KEY="$$($(TF_PLATFORM) output -raw litellm_master_key)"
