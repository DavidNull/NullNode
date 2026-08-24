output "cluster_name" {
  description = "Name of the created cluster"
  value       = k3d_cluster.ironnode.name
}

output "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  value       = k3d_cluster.ironnode.kubeconfig
}

output "api_endpoint" {
  description = "Kubernetes API endpoint"
  value       = "https://0.0.0.0:6443"
}

output "gateway_endpoint" {
  description = "AI Gateway endpoint"
  value       = "http://localhost:4000"
}

output "grafana_endpoint" {
  description = "Grafana dashboard endpoint"
  value       = "http://localhost:3000"
}

output "s3_bucket_name" {
  description = "S3 bucket name for model vault"
  value       = aws_s3_bucket.ironnode_model_vault.id
}

output "secrets_manager_endpoint" {
  description = "AWS Secrets Manager endpoint"
  value       = "http://localhost:4566"
}

output "localstack_endpoint" {
  description = "LocalStack endpoint"
  value       = "http://localhost:4566"
}
