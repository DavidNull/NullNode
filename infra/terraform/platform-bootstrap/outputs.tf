output "argocd_url" {
  description = "ArgoCD UI (add the host to /etc/hosts - see `make hosts`)."
  value       = "http://argocd.${var.host_suffix}:8080"
}

output "gateway_url" {
  description = "OpenAI-compatible endpoint of the AI gateway."
  value       = "http://gateway.${var.host_suffix}:8080"
}

output "grafana_url" {
  description = "Grafana UI."
  value       = "http://grafana.${var.host_suffix}:8080"
}

output "prometheus_url" {
  description = "Prometheus UI."
  value       = "http://prometheus.${var.host_suffix}:8080"
}

output "litellm_master_key" {
  description = "Master key for the gateway. Use department keys for anything else."
  value       = local.creds.master_key
  sensitive   = true
}

output "grafana_admin_password" {
  description = "Generated Grafana admin password."
  value       = local.creds.grafana_password
  sensitive   = true
}

output "argocd_admin_password_hint" {
  description = "Where to find the ArgoCD admin password."
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}
