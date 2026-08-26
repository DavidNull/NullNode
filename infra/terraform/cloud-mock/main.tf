locals {
  localstack_endpoint = "http://127.0.0.1:${var.localstack_port}"

  # Pods resolve the host through the DNS entry k3d injects into CoreDNS.
  # This is the value the platform charts consume as AWS_ENDPOINT_URL.
  in_cluster_endpoint = "http://host.k3d.internal:${var.localstack_port}"

  name_prefix = "nullnode"
}
