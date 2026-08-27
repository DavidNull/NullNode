output "localstack_endpoint" {
  description = "LocalStack edge endpoint as seen from the host."
  value       = local.localstack_endpoint
}

output "localstack_endpoint_in_cluster" {
  description = "LocalStack edge endpoint as seen from a pod."
  value       = local.in_cluster_endpoint
}

output "aws_region" {
  description = "Region the mocked endpoints answer for."
  value       = var.aws_region
}

output "vault_bucket" {
  description = "S3 bucket holding audit logs, prompts and artifacts."
  value       = aws_s3_bucket.vault.id
}

output "platform_secret_name" {
  description = "Secrets Manager entry holding the generated platform credentials."
  value       = aws_secretsmanager_secret.litellm.name
}

output "department_keys_secret_name" {
  description = "Secrets Manager entry the bootstrap Job writes virtual keys to."
  value       = aws_secretsmanager_secret.department_keys.name
}
