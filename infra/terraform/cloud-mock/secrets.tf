# Terraform generates the credentials, stores them in the mocked Secrets
# Manager, and platform-bootstrap reads them back into Kubernetes Secrets.
# Nothing credential-shaped reaches git. See docs/adr/0005-secrets-flow.md

resource "random_password" "litellm_master_key" {
  length  = 40
  special = false
}

resource "random_password" "litellm_salt_key" {
  length  = 40
  special = false
}

resource "random_password" "postgres_password" {
  length  = 32
  special = false
}

resource "random_password" "redis_password" {
  length  = 32
  special = false
}

resource "random_password" "grafana_password" {
  length  = 24
  special = false
}

resource "aws_secretsmanager_secret" "litellm" {
  name                    = "${local.name_prefix}/platform/credentials"
  description             = "Platform credentials: gateway keys, datastore and Grafana passwords"
  recovery_window_in_days = 0

  depends_on = [null_resource.localstack_ready]
}

resource "aws_secretsmanager_secret_version" "litellm" {
  secret_id = aws_secretsmanager_secret.litellm.id

  secret_string = jsonencode({
    # LiteLLM requires the "sk-" prefix.
    master_key        = "sk-${random_password.litellm_master_key.result}"
    salt_key          = random_password.litellm_salt_key.result
    postgres_password = random_password.postgres_password.result
    redis_password    = random_password.redis_password.result
    grafana_password  = random_password.grafana_password.result
  })
}

# Virtual keys are minted at runtime by the LiteLLM bootstrap Job. Terraform
# owns the secret, not its contents, so the Job can rotate them freely.
resource "aws_secretsmanager_secret" "department_keys" {
  name                    = "${local.name_prefix}/litellm/department-keys"
  description             = "Virtual API keys per department, written by the LiteLLM bootstrap Job"
  recovery_window_in_days = 0

  depends_on = [null_resource.localstack_ready]
}

resource "aws_secretsmanager_secret_version" "department_keys_placeholder" {
  secret_id     = aws_secretsmanager_secret.department_keys.id
  secret_string = jsonencode({ _bootstrap = "pending" })

  lifecycle {
    ignore_changes = [secret_string]
  }
}
