output "infrastructure" {
  description = "Identificadores para operacao e bootstrap; nenhum valor secreto ou kubeconfig."
  value = {
    compartment_id       = oci_identity_compartment.this.id
    cluster_id           = oci_containerengine_cluster.this.id
    conversations_bucket = oci_objectstorage_bucket.conversations.name
    vault_id             = oci_kms_vault.this.id
    secrets_key_id       = oci_kms_key.secrets.id
    postgres_id          = one(oci_psql_db_system.this[*].id)
    namespace            = "ai-agents"
    service_account      = "ai-agent"
  }
}
