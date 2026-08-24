terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    k3d = {
      source  = "pvotal-tech/k3d"
      version = ">= 0.0.1"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
  }
  
  backend "local" {
    path = "./terraform.tfstate"
  }
}
