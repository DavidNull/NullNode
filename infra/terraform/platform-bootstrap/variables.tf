variable "kubeconfig_path" {
  description = "Kubeconfig with the k3d cluster context."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "Context name k3d creates for the cluster."
  type        = string
  default     = "k3d-nullnode"
}

variable "localstack_endpoint" {
  description = "LocalStack edge endpoint as seen from the machine running Terraform."
  type        = string
  default     = "http://127.0.0.1:4566"
}

variable "aws_region" {
  description = "Region the mocked endpoints answer for."
  type        = string
  default     = "eu-west-1"
}

variable "platform_secret_name" {
  description = "Secrets Manager entry with the generated platform credentials."
  type        = string
  default     = "nullnode/platform/credentials"
}

variable "vault_bucket" {
  description = "S3 bucket used for the request audit log."
  type        = string
  default     = "nullnode-model-vault"
}

variable "argocd_chart_version" {
  description = "argo-cd Helm chart version. Pinned - see docs/ops/VERSIONS.md."
  type        = string
  default     = "7.7.11"
}

variable "gitops_repo_url" {
  description = "Repository ArgoCD reconciles the platform from."
  type        = string
  default     = "https://github.com/DavidNull/NullNode.git"
}

variable "gitops_target_revision" {
  description = "Branch, tag or commit ArgoCD tracks."
  type        = string
  default     = "main"
}

variable "hardware_profile" {
  description = "gpu | cpu - selects the platform values file layered on top."
  type        = string
  default     = "gpu"

  validation {
    condition     = contains(["gpu", "cpu"], var.hardware_profile)
    error_message = "hardware_profile must be either \"gpu\" or \"cpu\"."
  }
}

variable "host_suffix" {
  description = "DNS suffix for every platform Ingress."
  type        = string
  default     = "nullnode.localhost"
}
