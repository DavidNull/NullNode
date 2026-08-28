# The one thing ArgoCD cannot install. Everything after this comes from git.
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name

  # CRDs plus the initial reconcile loop take a while on a cold cluster.
  timeout = 900
  wait    = true

  values = [yamlencode({
    global = {
      domain = "argocd.${var.host_suffix}"
    }

    configs = {
      params = {
        # Traefik terminates TLS; ArgoCD's own TLS behind it means redirect
        # loops for no gain.
        "server.insecure" = true
        # Faster than the 3-minute default while iterating on charts.
        "timeout.reconciliation" = "60s"
      }
      cm = {
        "application.resourceTrackingMethod" = "annotation"
        # KEDA and the HPA own replica counts. Without this, self-heal
        # fights the autoscaler and the app never reports Synced.
        "resource.customizations.ignoreDifferences.apps_StatefulSet" = yamlencode({
          jsonPointers = ["/spec/replicas"]
        })
        "resource.customizations.ignoreDifferences.apps_Deployment" = yamlencode({
          jsonPointers = ["/spec/replicas"]
        })
      }
    }

    server = {
      ingress = {
        enabled          = true
        ingressClassName = "traefik"
        hostname         = "argocd.${var.host_suffix}"
        path             = "/"
        pathType         = "Prefix"
      }
      resources = {
        requests = { cpu = "50m", memory = "128Mi" }
        limits   = { memory = "512Mi" }
      }
    }

    repoServer = {
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { memory = "1Gi" }
      }
    }

    controller = {
      resources = {
        requests = { cpu = "150m", memory = "512Mi" }
        limits   = { memory = "1536Mi" }
      }
      metrics = {
        enabled = true
        serviceMonitor = {
          enabled          = true
          additionalLabels = { release = "kube-prometheus-stack" }
        }
      }
    }

    dex = {
      # No SSO locally.
      enabled = false
    }

    notifications  = { enabled = false }
    applicationSet = { enabled = false }

    redis = {
      resources = {
        requests = { cpu = "50m", memory = "64Mi" }
        limits   = { memory = "256Mi" }
      }
    }
  })]
}

# GitOps entrypoint: one AppProject, one root Application. From here the
# platform is whatever is committed to the tracked revision.
resource "helm_release" "nullnode_root" {
  name      = "nullnode-root"
  chart     = "${path.module}/../../../k8s/bootstrap/root"
  namespace = kubernetes_namespace_v1.argocd.metadata[0].name

  # ArgoCD CRDs must exist before these manifests validate.
  depends_on = [
    helm_release.argocd,
    kubernetes_secret_v1.litellm,
    kubernetes_secret_v1.postgres,
    kubernetes_secret_v1.redis,
    kubernetes_secret_v1.aws,
    kubernetes_secret_v1.grafana_admin,
  ]

  values = [yamlencode({
    gitops = {
      repoURL        = var.gitops_repo_url
      targetRevision = var.gitops_target_revision
      path           = "k8s/platform"
    }
    platform = {
      profile    = var.hardware_profile
      hostSuffix = var.host_suffix
    }
    argocd = {
      namespace = kubernetes_namespace_v1.argocd.metadata[0].name
    }
  })]
}
