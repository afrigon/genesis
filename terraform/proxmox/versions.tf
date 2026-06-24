terraform {
  required_version = ">= 1.15.6"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.109.0"
    }
  }

  backend "s3" {
    bucket       = "terraform-xehos"
    key          = "genesis-proxmox.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
