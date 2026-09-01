variable "docker_host" {
  description = "Docker daemon socket used to run the LocalStack container."
  type        = string
  default     = "unix:///var/run/docker.sock"
}

variable "aws_region" {
  description = "Region reported by the mocked AWS endpoints."
  type        = string
  default     = "eu-west-1"
}

variable "localstack_image" {
  # 4.x is required: the AWS provider (~> 5.70 resolves to 5.100) waits for the
  # S3 lifecycle configuration to stabilise, and LocalStack 3.8.1 never reports
  # it ready, so `terraform apply` hangs and fails. See docs/ops/VERSIONS.md.
  description = "LocalStack image. Pinned on purpose - see docs/ops/VERSIONS.md."
  type        = string
  default     = "localstack/localstack:4.4.0"
}

variable "localstack_port" {
  description = "Host port for the LocalStack edge endpoint."
  type        = number
  default     = 4566
}

variable "audit_log_retention_days" {
  description = "Days before LLM request logs expire in the mocked S3 bucket."
  type        = number
  default     = 30
}
