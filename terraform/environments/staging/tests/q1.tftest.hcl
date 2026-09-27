# Fixtures sinteticas compartilhadas; nao dimensionam nenhum ambiente.
# command=plan com provider mock: nenhuma API OCI e chamada e nenhum recurso e criado.
mock_provider "oci" {
  source          = "../../tests/fixtures"
  override_during = plan
}

variables {
  environment = "staging"
  settings    = jsondecode(file("../../tests/fixtures/environment.json"))
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
    condition     = alltrue([for subnet in oci_core_subnet.this : subnet.prohibit_public_ip_on_vnic && subnet.prohibit_internet_ingress && subnet.route_table_id == oci_core_route_table.private.id]) && length(oci_core_route_table.private.route_rules) == 1 && one(oci_core_route_table.private.route_rules).destination_type == "SERVICE_CIDR_BLOCK" && one(oci_core_route_table.private.route_rules).destination == "test-services-cidr" && one(oci_core_route_table.private.route_rules).network_entity_id == oci_core_service_gateway.this.id
    error_message = "Subnets devem ser privadas e a unica rota externa deve ser para servicos OCI."
  }
  assert {
    condition = alltrue([for key in ["workers_mtu", "workers_mtu_out"] :
      oci_core_network_security_group_security_rule.this[key].protocol == "1" &&
      !oci_core_network_security_group_security_rule.this[key].stateless &&
      one(oci_core_network_security_group_security_rule.this[key].icmp_options).type == 3 &&
      one(oci_core_network_security_group_security_rule.this[key].icmp_options).code == 4
    ]) && oci_core_network_security_group_security_rule.this["workers_mtu"].direction == "INGRESS" && oci_core_network_security_group_security_rule.this["workers_mtu"].source_type == "CIDR_BLOCK" && oci_core_network_security_group_security_rule.this["workers_mtu"].source == "0.0.0.0/0" && oci_core_network_security_group_security_rule.this["workers_mtu_out"].direction == "EGRESS" && oci_core_network_security_group_security_rule.this["workers_mtu_out"].destination_type == "CIDR_BLOCK" && oci_core_network_security_group_security_rule.this["workers_mtu_out"].destination == "0.0.0.0/0"
    error_message = "ICMP amplo dos workers deve permitir somente PMTUD stateful tipo 3/codigo 4, nunca todo ICMP."
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
