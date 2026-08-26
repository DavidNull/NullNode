provider "docker" {
  host = var.docker_host
}

# Every AWS call here is answered by LocalStack. Fake credentials, and the
# validation calls (STS, IMDS) skipped so the provider never reaches real AWS.
provider "aws" {
  region     = var.aws_region
  access_key = "test"
  secret_key = "test"

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    s3             = local.localstack_endpoint
    secretsmanager = local.localstack_endpoint
    sts            = local.localstack_endpoint
  }

  default_tags {
    tags = {
      Project   = "nullnode"
      ManagedBy = "terraform"
      Mock      = "localstack"
    }
  }
}
