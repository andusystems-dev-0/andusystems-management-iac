terraform {
    required_version = ">= 1.5.0"

    backend "s3" {
        bucket         = "andusystems-management-tf-state"
        key            = "layer-1-terraform.tfstate"
        region         = "us-east-1"
        use_lockfile   = true
        encrypt        = true
    }
    
    required_providers {
      proxmox = {
        source  = "bpg/proxmox"
        version = "~> 0.93"
      }
      kubernetes = {
        source  = "hashicorp/kubernetes"
        version = "~> 2.35"
      }
      helm = {
        source  = "hashicorp/helm"
        version = "~> 2.17"
      }
      kubectl = {
        source  = "gavinbunney/kubectl"
        version = ">= 1.14.0"
      }
      http = {
        source  = "hashicorp/http"
        version = ">= 3.0.0"
      }
      aws = {
        source  = "hashicorp/aws"
        version = "~> 6.0"
      }
    }
}
