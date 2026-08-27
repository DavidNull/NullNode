# LocalStack runs on the host, not in the cluster: Terraform needs the bucket
# and secrets before the platform boots, and the platform is what would deploy
# LocalStack. See docs/adr/0002-localstack-outside-the-cluster.md

resource "docker_image" "localstack" {
  name         = var.localstack_image
  keep_locally = true
}

resource "docker_container" "localstack" {
  name         = "${local.name_prefix}-localstack"
  image        = docker_image.localstack.image_id
  restart      = "unless-stopped"
  must_run     = true
  network_mode = "bridge"

  # Not loopback-bound: pods reach this via host.k3d.internal, the host's
  # address on the Docker bridge. Cost: the mock answers on the LAN.
  ports {
    internal = 4566
    external = var.localstack_port
  }

  env = [
    "SERVICES=s3,secretsmanager",
    "DEBUG=0",
    "EAGER_SERVICE_LOADING=1",
    "DEFAULT_REGION=${var.aws_region}",
    # Persistence is a Pro feature. On community, restarting the container
    # drops the bucket and secrets; `make up` recreates them.
  ]

  healthcheck {
    test         = ["CMD-SHELL", "curl -sf http://localhost:4566/_localstack/health || exit 1"]
    interval     = "5s"
    timeout      = "5s"
    retries      = 20
    start_period = "10s"
  }

  labels {
    label = "io.nullnode.component"
    value = "cloud-mock"
  }
}

# "Running" is not "answering". Gate downstream resources on a health check.
resource "null_resource" "localstack_ready" {
  triggers = {
    container_id = docker_container.localstack.id
  }

  provisioner "local-exec" {
    interpreter = ["/bin/sh", "-c"]
    command     = <<-EOT
      for i in $(seq 1 60); do
        if curl -sf ${local.localstack_endpoint}/_localstack/health \
             | grep -q '"s3"'; then
          echo "localstack ready after $${i} attempt(s)"
          exit 0
        fi
        sleep 2
      done
      echo "localstack did not become healthy at ${local.localstack_endpoint}" >&2
      exit 1
    EOT
  }
}
