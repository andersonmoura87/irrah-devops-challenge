# Plano do root bootstrap real. Nao executa seed/import, acesso OCI ou locking.
mock_provider "oci" {
  source          = "../tests/fixtures"
  override_during = plan
}

variables {
  region                = "test-region"
  tenancy_id            = "test-tenancy"
  parent_compartment_id = "test-parent"
  name_prefix           = "test-q1"
  state_group_ids = {
    bootstrap  = "test-group-bootstrap"
    staging    = "test-group-staging"
    production = "test-group-production"
  }
}

run "isolated_backend_contract" {
  command = plan

  assert {
    condition     = toset(keys(oci_objectstorage_bucket.state)) == toset(["bootstrap", "staging", "production"]) && alltrue([for bucket in oci_objectstorage_bucket.state : bucket.access_type == "NoPublicAccess" && bucket.versioning == "Enabled" && bucket.compartment_id == oci_identity_compartment.state.id])
    error_message = "Bootstrap deve criar tres buckets privados/versionados no compartment de state."
  }
  assert {
    condition = alltrue([for environment, location in output.backend_locations :
      location.bucket == "test-q1-tfstate-${environment}" && location.key == "${environment}/terraform.tfstate" && location.namespace == "test-namespace" && location.region == "test-region"
    ]) && toset(keys(output.backend_locations)) == toset(["bootstrap", "staging", "production"]) && length(toset([for location in values(output.backend_locations) : location.bucket])) == 3 && length(toset([for location in values(output.backend_locations) : location.key])) == 3
    error_message = "Outputs devem identificar destinos de backend distintos e completos para os tres roots."
  }
  assert {
    condition     = oci_identity_policy.state.compartment_id == oci_identity_compartment.state.id
    error_message = "Policy do backend deve ficar no compartment de state, nao na raiz da tenancy."
  }
  assert {
    condition = toset(oci_identity_policy.state.statements) == toset(flatten([for environment, group_id in var.state_group_ids : [
      "Allow group id ${group_id} to read buckets in compartment id ${oci_identity_compartment.state.id} where target.bucket.name = 'test-q1-tfstate-${environment}'",
      "Allow group id ${group_id} to manage objects in compartment id ${oci_identity_compartment.state.id} where all {target.bucket.name = 'test-q1-tfstate-${environment}', any {request.permission = 'OBJECT_INSPECT', request.permission = 'OBJECT_READ', request.permission = 'OBJECT_CREATE', request.permission = 'OBJECT_OVERWRITE', request.permission = 'OBJECT_DELETE'}}"
    ]]))
    error_message = "Cada grupo deve receber somente acesso ao seu bucket e operacoes de state/lock, sem grants extras."
  }
}

run "reject_shared_state_group" {
  command = plan
  variables {
    state_group_ids = {
      bootstrap  = "test-group-bootstrap"
      staging    = "test-group-shared"
      production = "test-group-shared"
    }
  }
  expect_failures = [var.state_group_ids]
}
