terraform {
  required_version = ">= 1.12.0, < 2.0.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 7.22.0"
    }
  }
  # O bucket bootstrap deve existir antes do init; criar/importar conforme o runbook.
  backend "oci" {}
}

provider "oci" {
  region = var.region
}

variable "region" {
  description = "Regiao OCI unica da Q1."
  type        = string
}

variable "parent_compartment_id" {
  description = "OCID do compartment pai previamente autorizado para o bootstrap."
  type        = string
}

variable "tenancy_id" {
  description = "OCID da tenancy para obter o namespace do Object Storage."
  type        = string
}

variable "name_prefix" {
  description = "Prefixo exclusivo dos buckets de state nesta tenancy."
  type        = string
}

variable "state_group_ids" {
  description = "Grupos IAM preexistentes e distintos: bootstrap, staging e production. Cada grupo acessa somente seu bucket."
  type = object({
    bootstrap  = string
    staging    = string
    production = string
  })
  validation {
    condition     = length(toset(values(var.state_group_ids))) == 3
    error_message = "Os tres grupos de state devem ser distintos."
  }
}

resource "oci_identity_compartment" "state" {
  compartment_id = var.parent_compartment_id
  name           = "${var.name_prefix}-terraform-state"
  description    = "State Q1 separado da infraestrutura da aplicacao"
  enable_delete  = false
}

data "oci_objectstorage_namespace" "this" {
  compartment_id = var.tenancy_id
}

resource "oci_objectstorage_bucket" "state" {
  for_each       = var.state_group_ids
  compartment_id = oci_identity_compartment.state.id
  namespace      = data.oci_objectstorage_namespace.this.namespace
  name           = "${var.name_prefix}-tfstate-${each.key}"
  access_type    = "NoPublicAccess"
  versioning     = "Enabled"
  lifecycle {
    prevent_destroy = true
  }
}

resource "oci_identity_policy" "state" {
  compartment_id = oci_identity_compartment.state.id
  name           = "${var.name_prefix}-state-access"
  description    = "Permissoes do backend OCI, limitadas ao bucket de cada grupo"
  statements = flatten([for environment, group_id in var.state_group_ids : [
    "Allow group id ${group_id} to read buckets in compartment id ${oci_identity_compartment.state.id} where target.bucket.name = '${oci_objectstorage_bucket.state[environment].name}'",
    "Allow group id ${group_id} to manage objects in compartment id ${oci_identity_compartment.state.id} where all {target.bucket.name = '${oci_objectstorage_bucket.state[environment].name}', any {request.permission = 'OBJECT_INSPECT', request.permission = 'OBJECT_READ', request.permission = 'OBJECT_CREATE', request.permission = 'OBJECT_OVERWRITE', request.permission = 'OBJECT_DELETE'}}"
  ]])
}

output "backend_locations" {
  description = "Localizacao dos backends; nao inclui credenciais."
  value = { for environment, bucket in oci_objectstorage_bucket.state : environment => {
    namespace = bucket.namespace
    bucket    = bucket.name
    key       = "${environment}/terraform.tfstate"
    region    = var.region
  } }
}
