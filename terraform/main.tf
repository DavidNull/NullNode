terraform {
  required_version = ">= 1.5.0"
  required_providers {
    k3d = {
      source  = "pvotal-tech/k3d"
      version = ">= 0.0.1"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
  }
}

provider "k3d" {
  # K3d provider configuration
}

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  
  endpoints {
    s3          = "http://localhost:4566"
    secretsmanager = "http://localhost:4566"
  }
  
  s3_use_path_style           = true
}

resource "k3d_cluster" "ironnode" {
  name = "ironnode"
  
  servers = 1
  agents  = 1

  kube_api {
    host_ip = "0.0.0.0"
    port    = 6443
  }

  ports {
    host_port      = "4000"
    container_port = "4000"
    node_filters   = ["loadbalancer"]
  }

  ports {
    host_port      = "3000"
    container_port = "3000"
    node_filters   = ["loadbalancer"]
  }

  ports {
    host_port      = "8080"
    container_port = "8080"
    node_filters   = ["loadbalancer"]
  }

  volumes {
    host_path      = "/tmp/k3d-storage"
    node_filters   = ["all"]
    volume_path    = "/var/lib/rancher/k3s/storage"
  }

  registries {
    create = true
    host   = "0.0.0.0"
    port   = 5000
  }

  labels {
    node_filters = ["all"]
    key          = "platform"
    value        = "ironnode"
  }
}

output "kubeconfig" {
  value     = k3d_cluster.ironnode.kubeconfig
  sensitive = true
}

output "cluster_name" {
  value = k3d_cluster.ironnode.name
}

# LocalStack Resources
resource "aws_s3_bucket" "ironnode_model_vault" {
  bucket = "ironnode-model-vault"
  
  tags = {
    Name        = "IronNode Model Vault"
    Environment = "local"
    ManagedBy   = "localstack"
  }
}

resource "aws_s3_bucket_versioning" "ironnode_model_vault" {
  bucket = aws_s3_bucket.ironnode_model_vault.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ironnode_model_vault" {
  bucket = aws_s3_bucket.ironnode_model_vault.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_secretsmanager_secret" "litellm_master_key" {
  name = "ironnode/litellm-master-key"
  
  tags = {
    Name        = "LiteLLM Master Key"
    Environment = "local"
    ManagedBy   = "localstack"
  }
}

resource "aws_secretsmanager_secret_version" "litellm_master_key" {
  secret_id = aws_secretsmanager_secret.litellm_master_key.id
  secret_string = jsonencode({
    master_key = "sk-ironnode-master-key-2024"
    created_at = timestamp()
    environment = "local"
  })
}
