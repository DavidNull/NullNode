locals {
  platform_namespace      = "nullnode-platform"
  observability_namespace = "nullnode-observability"

  common_labels = {
    "app.kubernetes.io/part-of"    = "nullnode"
    "app.kubernetes.io/managed-by" = "terraform"
  }
}

# ArgoCD could create these, but then the labels NetworkPolicies select on
# would not exist and the Secrets below would have nowhere to land.
resource "kubernetes_namespace_v1" "platform" {
  metadata {
    name   = local.platform_namespace
    labels = local.common_labels
  }
}

resource "kubernetes_namespace_v1" "observability" {
  metadata {
    name   = local.observability_namespace
    labels = local.common_labels
  }
}

resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name   = "argocd"
    labels = local.common_labels
  }
}
