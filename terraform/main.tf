terraform {
  required_version = ">= 1.5.0"
  required_providers {
    k3d = {
      source  = "pvotal-tech/k3d"
      version = ">= 0.0.1"
    }
  }
}

provider "k3d" {
  # K3d provider configuration
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
