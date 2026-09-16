# The secrets bridge used to live here: read what cloud-mock generated, project
# it into Kubernetes Secrets. That job now belongs to External Secrets Operator,
# which reconciles the same Secrets Manager entry on an interval instead of only
# at `terraform apply`. See docs/adr/0007-external-secrets-operator.md.
#
# What stays is a read-only data source: the operator convenience outputs
# (`make key`, `make grafana-password`) still surface the generated values
# without a kubectl round-trip. Terraform no longer creates any Kubernetes
# Secret; the external-secrets-config chart owns them.

data "aws_secretsmanager_secret_version" "platform" {
  secret_id = var.platform_secret_name
}

locals {
  creds = jsondecode(data.aws_secretsmanager_secret_version.platform.secret_string)
}
