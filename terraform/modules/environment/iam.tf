resource "oci_identity_policy" "workload" {
  compartment_id = oci_identity_compartment.this.id
  name           = "${local.name}-workload"
  description    = "Escrita de novos objetos; leitura somente dos secrets explicitamente autorizados"
  statements = concat([
    "Allow any-user to manage objects in compartment id ${oci_identity_compartment.this.id} where all {${local.workload_condition}, target.bucket.name = '${oci_objectstorage_bucket.conversations.name}', request.permission = 'OBJECT_CREATE'}"
    ], [for secret_id in var.settings.application_secret_ids :
    "Allow any-user to read secret-bundles in compartment id ${oci_identity_compartment.this.id} where all {${local.workload_condition}, target.secret.id = '${secret_id}'}"
  ])
}
