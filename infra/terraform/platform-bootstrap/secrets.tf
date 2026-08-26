# The secrets bridge: read what cloud-mock generated, project it into
# Kubernetes Secrets. No chart generates its own password, so one
# `terraform apply` rotates everything.
#
# In a real cluster this is where External Secrets Operator would go.
# See docs/adr/0005-secrets-flow.md

data "aws_secretsmanager_secret_version" "platform" {
  secret_id = var.platform_secret_name
}

locals {
  creds = jsondecode(data.aws_secretsmanager_secret_version.platform.secret_string)
}

resource "kubernetes_secret_v1" "litellm" {
  metadata {
    name      = "nullnode-litellm-credentials"
    namespace = kubernetes_namespace_v1.platform.metadata[0].name
    labels    = local.common_labels
  }

  data = {
    "master-key" = local.creds.master_key
    "salt-key"   = local.creds.salt_key
  }
}

resource "kubernetes_secret_v1" "postgres" {
  metadata {
    name      = "nullnode-postgres-auth"
    namespace = kubernetes_namespace_v1.platform.metadata[0].name
    labels    = local.common_labels
  }

  data = {
    "postgres-password" = local.creds.postgres_password
  }
}

resource "kubernetes_secret_v1" "redis" {
  metadata {
    name      = "nullnode-redis-auth"
    namespace = kubernetes_namespace_v1.platform.metadata[0].name
    labels    = local.common_labels
  }

  data = {
    "redis-password" = local.creds.redis_password
  }
}

# LocalStack ignores these, but the SDKs refuse to call without them.
resource "kubernetes_secret_v1" "aws" {
  metadata {
    name      = "nullnode-aws-credentials"
    namespace = kubernetes_namespace_v1.platform.metadata[0].name
    labels    = local.common_labels
  }

  data = {
    "access-key-id"     = "test"
    "secret-access-key" = "test"
  }
}

resource "kubernetes_secret_v1" "grafana_admin" {
  metadata {
    name      = "nullnode-grafana-admin"
    namespace = kubernetes_namespace_v1.observability.metadata[0].name
    labels    = local.common_labels
  }

  data = {
    "admin-user"     = "admin"
    "admin-password" = local.creds.grafana_password
  }
}
