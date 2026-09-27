# Dados sinteticos compartilhados; nenhum lookup ou credencial OCI.
mock_data "oci_core_services" {
  defaults = {
    services = [{ id = "test-service", cidr_block = "test-services-cidr", name = "All TEST Services In Oracle Services Network" }]
  }
}

mock_data "oci_objectstorage_namespace" {
  defaults = { namespace = "test-namespace" }
}

# Somente atributos calculados: entradas de recursos continuam sendo avaliadas
# pelo Terraform. IDs estaveis permitem conferir referencias durante command=plan.
mock_resource "oci_identity_compartment" {
  override_during = plan
  defaults        = { id = "test-compartment" }
}

mock_resource "oci_containerengine_cluster" {
  override_during = plan
  defaults        = { id = "test-cluster" }
}

mock_resource "oci_kms_vault" {
  override_during = plan
  defaults        = { id = "test-vault" }
}

mock_resource "oci_kms_key" {
  override_during = plan
  defaults        = { id = "test-key" }
}

mock_resource "oci_psql_db_system" {
  override_during = plan
  defaults        = { id = "test-postgres" }
}

mock_resource "oci_core_route_table" {
  override_during = plan
  defaults        = { id = "test-route-table" }
}

mock_resource "oci_core_service_gateway" {
  override_during = plan
  defaults        = { id = "test-service-gateway" }
}
