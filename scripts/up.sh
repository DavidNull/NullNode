#!/bin/bash
set -e

# IronNode Platform Bootstrap Script
# This script provisions the local K3s cluster and deploys the complete platform

echo "🚀 IronNode Platform Bootstrap"
echo "================================"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
print_status "Checking prerequisites..."

# Check Docker
if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed. Please install Docker first."
    exit 1
fi
print_status "✓ Docker found: $(docker --version)"

# Check LocalStack
print_status "Checking LocalStack..."
if ! docker ps | grep -q localstack; then
    print_warning "LocalStack is not running. Starting LocalStack..."
    docker run -d \
      --name localstack \
      -p 4566:4566 \
      -e SERVICES=s3,secretsmanager \
      -e DEBUG=0 \
      -e DATA_DIR=/tmp/localstack/data \
      -e PERSISTENCE=1 \
      -v /tmp/localstack:/tmp/localstack \
      localstack/localstack:latest
    
    print_status "Waiting for LocalStack to be ready..."
    for i in {1..30}; do
      if curl -s http://localhost:4566/_localstack/health > /dev/null 2>&1; then
        print_status "✓ LocalStack is ready"
        break
      fi
      if [ $i -eq 30 ]; then
        print_error "LocalStack failed to start"
        exit 1
      fi
      sleep 2
    done
else
    print_status "✓ LocalStack is running"
    
    # Validate LocalStack health
    if ! curl -s http://localhost:4566/_localstack/health > /dev/null 2>&1; then
      print_error "LocalStack is not healthy"
      exit 1
    fi
    print_status "✓ LocalStack is healthy"
fi

# Check k3d
if ! command -v k3d &> /dev/null; then
    print_warning "k3d not found. Installing k3d..."
    curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | TAG=v5.6.0 bash
fi
print_status "✓ k3d found: $(k3d version)"

# Check kubectl
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed. Please install kubectl first."
    exit 1
fi
print_status "✓ kubectl found: $(kubectl version --client --short)"

# Check Terraform
if ! command -v terraform &> /dev/null; then
    print_error "Terraform is not installed. Please install Terraform first."
    exit 1
fi
print_status "✓ Terraform found: $(terraform --version | head -n1)"

# Check Helm
if ! command -v helm &> /dev/null; then
    print_error "Helm is not installed. Please install Helm first."
    exit 1
fi
print_status "✓ Helm found: $(helm version --short)"

# Navigate to terraform directory
cd "$(dirname "$0")/../terraform"

# Initialize Terraform
print_status "Initializing Terraform..."
terraform init

# Apply Terraform configuration
print_status "Provisioning K3d cluster with Terraform..."
terraform apply -auto-approve

# Get kubeconfig
print_status "Configuring kubectl..."
export KUBECONFIG=$(terraform output -raw kubeconfig_path)

# Wait for cluster to be ready
print_status "Waiting for cluster to be ready..."
kubectl wait --for=condition=ready nodes --all --timeout=300s

# Bootstrap ArgoCD
print_status "Bootstrapping ArgoCD..."
cd "$(dirname "$0")/../k8s/bootstrap/argo-cd"
kubectl apply -f kustomization.yaml

# Wait for ArgoCD to be ready
print_status "Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=available -n argocd deployment/argocd-server --timeout=300s

# Deploy platform applications
print_status "Deploying platform applications..."
cd "$(dirname "$0")/../k8s/platform"
kubectl apply -f argocd-apps.yaml

# Wait for applications to sync
print_status "Waiting for applications to sync..."
sleep 30

# Print endpoints
echo ""
echo "================================"
echo -e "${GREEN}✓ IronNode Platform is ready!${NC}"
echo "================================"
echo ""
echo "🎯 Available Endpoints:"
echo "  - AI Gateway (LiteLLM):     http://localhost:4000"
echo "  - Grafana Dashboard:        http://localhost:3000"
echo "  - Prometheus:               http://localhost:9090"
echo "  - ArgoCD UI:                http://localhost:8080"
echo "  - LocalStack (AWS Mock):    http://localhost:4566"
echo ""
echo "🔑 ArgoCD Credentials:"
echo "  Username: admin"
echo "  Password: $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)"
echo ""
echo "📊 To view all pods:"
echo "  kubectl get pods -A"
echo ""
echo "📝 To view logs:"
echo "  kubectl logs -f deployment/litellm -n platform"
echo ""
