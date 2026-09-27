# Executa o root production real; os testes detalhados do modulo nao sao duplicados.
# IDs calculados sao sinteticos. Isto nao valida backend remoto nem IAM efetivo.
mock_provider "oci" {
  source          = "../../tests/fixtures"
  override_during = plan
}

variables {
  settings = merge(jsondecode(file("../../tests/fixtures/environment.json")), {
    database_bootstrap_secret = { id = "test-admin-secret", version = "1" }
    application_secret_ids    = ["test-app-secret"]
  })
}

run "production_root_contract" {
  command = plan

  assert {
    condition     = output.infrastructure.conversations_bucket == "test-q1-production-conversations"
    error_message = "O root production deve encaminhar production ao modulo, separado do nome de staging."
  }
  assert {
    condition     = output.infrastructure.postgres_id != null && output.infrastructure.namespace == "ai-agents" && output.infrastructure.service_account == "ai-agent"
    error_message = "O root deve preservar referencia de bootstrap do banco e contrato de identidade."
  }
  assert {
    condition     = output.infrastructure == module.environment.infrastructure && toset(keys(output.infrastructure)) == toset(["compartment_id", "cluster_id", "conversations_bucket", "vault_id", "secrets_key_id", "postgres_id", "namespace", "service_account"])
    error_message = "O output publico deve encaminhar o contrato de identificadores do modulo, sem campos adicionais."
  }
}
