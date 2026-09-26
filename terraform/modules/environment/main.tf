locals {
  name               = "${var.settings.name_prefix}-${var.environment}"
  tags               = { environment = var.environment, scope = "q1" }
  workload_condition = "request.principal.type = 'workload', request.principal.cluster_id = '${oci_containerengine_cluster.this.id}', request.principal.namespace = 'ai-agents', request.principal.service_account = 'ai-agent'"
}

resource "oci_identity_compartment" "this" {
  compartment_id = var.settings.parent_compartment_id
  name           = local.name
  description    = "Q1: recursos isolados de ${var.environment}"
  enable_delete  = false
  freeform_tags  = local.tags
}

resource "oci_containerengine_cluster" "this" {
  compartment_id     = oci_identity_compartment.this.id
  name               = local.name
  kubernetes_version = var.settings.kubernetes_version
  vcn_id             = oci_core_vcn.this.id
  type               = "ENHANCED_CLUSTER"
  freeform_tags      = local.tags
  endpoint_config {
    is_public_ip_enabled = false
    subnet_id            = oci_core_subnet.this["api"].id
    nsg_ids              = [oci_core_network_security_group.this["api"].id]
  }
  cluster_pod_network_options {
    cni_type = "FLANNEL_OVERLAY"
  }
  options {
    kubernetes_network_config {
      pods_cidr     = var.settings.pods_cidr
      services_cidr = var.settings.services_cidr
    }
  }
  depends_on = [oci_core_network_security_group_security_rule.this]
}

resource "oci_containerengine_node_pool" "this" {
  compartment_id     = oci_identity_compartment.this.id
  cluster_id         = oci_containerengine_cluster.this.id
  name               = "${local.name}-workers"
  kubernetes_version = var.settings.kubernetes_version
  node_shape         = var.settings.node_shape
  freeform_tags      = local.tags
  node_shape_config {
    ocpus         = var.settings.node_ocpus
    memory_in_gbs = var.settings.node_memory_gbs
  }
  node_source_details {
    source_type = "IMAGE"
    image_id    = var.settings.node_image_id
  }
  node_config_details {
    size                                = var.settings.node_count
    nsg_ids                             = [oci_core_network_security_group.this["workers"].id]
    is_pv_encryption_in_transit_enabled = true
    placement_configs {
      availability_domain = var.settings.availability_domain
      subnet_id           = oci_core_subnet.this["workers"].id
    }
    node_pool_pod_network_option_details {
      cni_type = "FLANNEL_OVERLAY"
    }
  }
  depends_on = [oci_core_network_security_group_security_rule.this]
}

resource "oci_kms_vault" "this" {
  compartment_id = oci_identity_compartment.this.id
  display_name   = "${local.name}-secrets"
  vault_type     = "DEFAULT"
  freeform_tags  = local.tags
  lifecycle {
    prevent_destroy = true
  }
}

resource "oci_kms_key" "secrets" {
  compartment_id      = oci_identity_compartment.this.id
  display_name        = "${local.name}-secrets"
  management_endpoint = oci_kms_vault.this.management_endpoint
  protection_mode     = "SOFTWARE"
  key_shape {
    algorithm = "AES"
    length    = 32
  }
  lifecycle {
    prevent_destroy = true
  }
}

# Referencia imutavel de bootstrap: credentials tem ForceNew no provider 7.22.0.
# Rotacao operacional ocorre fora deste bloco; nao ignorar diff nem remover prevent_destroy.
resource "oci_psql_db_system" "this" {
  count                       = var.settings.database_bootstrap_secret == null ? 0 : 1
  compartment_id              = oci_identity_compartment.this.id
  display_name                = "${local.name}-postgresql"
  db_version                  = var.settings.postgres_version
  shape                       = var.settings.postgres_shape
  instance_count              = var.settings.postgres_instance_count
  instance_ocpu_count         = var.settings.postgres_ocpus
  instance_memory_size_in_gbs = var.settings.postgres_memory_gbs
  freeform_tags               = local.tags
  credentials {
    username = "q1_admin"
    password_details {
      password_type  = "VAULT_SECRET"
      secret_id      = var.settings.database_bootstrap_secret.id
      secret_version = var.settings.database_bootstrap_secret.version
    }
  }
  network_details {
    subnet_id                  = oci_core_subnet.this["database"].id
    nsg_ids                    = [oci_core_network_security_group.this["database"].id]
    is_reader_endpoint_enabled = false
  }
  storage_details {
    system_type           = "OCI_OPTIMIZED_STORAGE"
    is_regionally_durable = var.settings.postgres_regional_storage
    availability_domain   = var.settings.postgres_regional_storage ? null : var.settings.availability_domain
  }
  management_policy {
    maintenance_window_start = var.settings.maintenance_window
    backup_policy {
      kind           = "DAILY"
      backup_start   = var.settings.backup_start
      retention_days = var.settings.backup_retention_days
    }
  }
  lifecycle {
    prevent_destroy = true
  }
  depends_on = [oci_core_network_security_group_security_rule.this]
}

data "oci_objectstorage_namespace" "this" {
  compartment_id = var.settings.tenancy_id
}

resource "oci_objectstorage_bucket" "conversations" {
  compartment_id = oci_identity_compartment.this.id
  namespace      = data.oci_objectstorage_namespace.this.namespace
  name           = "${local.name}-conversations"
  access_type    = "NoPublicAccess"
  storage_tier   = "Standard"
  freeform_tags  = local.tags
  lifecycle {
    prevent_destroy = true
  }
}
