terraform {
  required_version = ">= 1.12.0, < 2.0.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 7.22.0"
    }
  }
  backend "oci" {}
}

provider "oci" {
  region = var.settings.region
}

module "environment" {
  source      = "../../modules/environment"
  environment = "staging"
  settings    = var.settings
}

output "infrastructure" {
  description = "Identificadores nao secretos do ambiente."
  value       = module.environment.infrastructure
}