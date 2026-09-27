# Executa o root staging real e seu modulo, sem override_module.
# O backend remoto nao participa destes planos mock; isolamento IAM exige OCI.
mock_provider "oci" {
  source          = "../../tests/fixtures"
  override_during = plan
}

variables {
  settings = jsondecode(file("../../tests/fixtures/environment.json"))
}

run "staging_root_contract" {
  command = plan

  assert {
    condition     = output.infrastructure.conversations_bucket == "test-q1-staging-conversations"
    error_message = "O root staging deve encaminhar staging ao modulo, sem nome de production."
  }
  assert {
    condition     = output.infrastructure.postgres_id == null && output.infrastructure.namespace == "ai-agents" && output.infrastructure.service_account == "ai-agent"
    error_message = "O root deve preservar defaults de identidade e a fase inicial sem banco."
  }
  assert {
    condition     = output.infrastructure == module.environment.infrastructure && toset(keys(output.infrastructure)) == toset(["compartment_id", "cluster_id", "conversations_bucket", "vault_id", "secrets_key_id", "postgres_id", "namespace", "service_account"])
    error_message = "O output publico deve encaminhar o contrato de identificadores do modulo, sem campos adicionais."
  }
}
