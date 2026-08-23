#!/bin/bash
set -e

# IronNode Platform Teardown Script
# This script destroys the local K3s cluster and all resources

echo "🛑 IronNode Platform Teardown"
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

# Check k3d
if ! command -v k3d &> /dev/null; then
    print_error "k3d is not installed."
    exit 1
fi

# Check Terraform
if ! command -v terraform &> /dev/null; then
    print_error "Terraform is not installed."
    exit 1
fi

# Navigate to terraform directory
cd "$(dirname "$0")/../terraform"

# Destroy Terraform infrastructure
print_warning "Destroying K3d cluster and all resources..."
terraform destroy -auto-approve

print_status "✓ IronNode Platform has been destroyed."
echo ""
echo "All resources have been cleaned up."
