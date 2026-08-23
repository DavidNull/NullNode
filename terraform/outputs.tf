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
