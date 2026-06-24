terraform {
  required_version = ">= 1.15.6"

  required_providers {
    unifi = {
      source  = "ubiquiti-community/unifi"
      version = "~> 0.52"
    }
  }

  backend "s3" {
    bucket       = "terraform-xehos"
    key          = "genesis-unifi.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
