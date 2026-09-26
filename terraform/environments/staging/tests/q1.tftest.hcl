# Valores abaixo sao fixtures sinteticas de teste; nao dimensionam nenhum ambiente.
# command=plan com provider mock: nenhuma API OCI e chamada e nenhum recurso e criado.
mock_provider "oci" {}

override_data {
  target = data.oci_core_services.this
  values = {
    services = [{ id = "test-service", cidr_block = "test-services-cidr", name = "All TEST Services In Oracle Services Network" }]
  }
}

override_data {
  target = data.oci_objectstorage_namespace.this
  values = { namespace = "test-namespace" }
}

variables {
  environment = "staging"
  settings = {
    region                    = "test-region"
    tenancy_id                = "test-tenancy"
    parent_compartment_id     = "test-parent"
    name_prefix               = "test-q1"
    vcn_cidr                  = "10.0.0.0/16"
    pods_cidr                 = "10.244.0.0/16"
    services_cidr             = "10.96.0.0/16"
    admin_cidrs               = ["10.1.0.0/24"]
    kubernetes_version        = "v1.33.1"
    node_image_id             = "test-image"
    node_shape                = "VM.Standard.E4.Flex"
    node_ocpus                = 1
    node_memory_gbs           = 16
    node_count                = 1
    availability_domain       = "test-ad"
    postgres_version          = "14"
    postgres_shape            = "PostgreSQL.VM.Standard.E4.Flex"
    postgres_ocpus            = 2
    postgres_memory_gbs       = 32
    postgres_instance_count   = 1
    postgres_regional_storage = false
    backup_retention_days     = 7
    backup_start              = "02:00"
    maintenance_window        = "sun 03:00:00"
  }
}

run "foundation_without_database" {
  command = plan
  module {
    source = "../../modules/environment"
  }
  assert {
    condition     = length(oci_psql_db_system.this) == 0
    error_message = "A fase de fundacao nao deve criar o banco sem referencia ao secret."
  }
  assert {
    condition     = oci_objectstorage_bucket.conversations.access_type == "NoPublicAccess" && oci_containerengine_cluster.this.type == "ENHANCED_CLUSTER" && oci_containerengine_cluster.this.endpoint_config[0].is_public_ip_enabled == false
    error_message = "Bucket deve ser privado e OKE Enhanced deve ter endpoint sem IP publico."
  }
  assert {
    condition     = alltrue([for subnet in oci_core_subnet.this : subnet.prohibit_public_ip_on_vnic && subnet.prohibit_internet_ingress]) && length(oci_core_route_table.private.route_rules) == 1 && one(oci_core_route_table.private.route_rules).destination_type == "SERVICE_CIDR_BLOCK"
    error_message = "Subnets devem ser privadas e a unica rota externa deve ser para servicos OCI."
  }
  assert {
    condition     = oci_core_network_security_group_security_rule.this["database_from_workers"].tcp_options[0].destination_port_range[0].min == 5432 && oci_core_network_security_group_security_rule.this["database_from_workers"].source_type == "NETWORK_SECURITY_GROUP" && oci_core_network_security_group_security_rule.this["api_support"].tcp_options[0].destination_port_range[0].min == 9995
    error_message = "Banco deve aceitar PostgreSQL por NSG e OKE deve incluir o fluxo gerenciado 9995."
  }
}

run "database_from_secret_reference" {
  command = plan
  module {
    source = "../../modules/environment"
  }
  variables {
    environment = "production"
    settings = merge(var.settings, {
      database_bootstrap_secret = { id = "test-admin-secret", version = "1" }
      application_secret_ids    = ["test-app-secret", "test-ai-secret"]
    })
  }
  assert {
    condition     = length(oci_psql_db_system.this) == 1 && oci_psql_db_system.this[0].credentials[0].password_details[0].password_type == "VAULT_SECRET" && oci_psql_db_system.this[0].credentials[0].password_details[0].secret_id == "test-admin-secret" && oci_psql_db_system.this[0].credentials[0].password_details[0].secret_version == "1"
    error_message = "Banco deve existir e usar somente a referencia de bootstrap esperada."
  }
  assert {
    condition     = oci_identity_compartment.this.name == "test-q1-production" && oci_objectstorage_bucket.conversations.name == "test-q1-production-conversations" && oci_psql_db_system.this[0].display_name == "test-q1-production-postgresql" && oci_psql_db_system.this[0].management_policy[0].backup_policy[0].kind == "DAILY" && oci_psql_db_system.this[0].management_policy[0].backup_policy[0].retention_days == 7
    error_message = "Recursos devem refletir production e o backup informado pela fixture."
  }
}

run "reject_admin_secret_in_workload" {
  command = plan
  module {
    source = "../../modules/environment"
  }
  variables {
    settings = merge(var.settings, {
      database_bootstrap_secret = { id = "test-admin-secret", version = "1" }
      application_secret_ids    = ["test-admin-secret"]
    })
  }
  expect_failures = [var.settings]
}

run "reject_unrestricted_admin_network" {
  command = plan
  module {
    source = "../../modules/environment"
  }
  variables {
    settings = merge(var.settings, { admin_cidrs = ["0.0.0.0/0"] })
  }
  expect_failures = [var.settings]
}
