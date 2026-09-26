variable "environment" {
  description = "Ambiente isolado atendido por esta instancia do modulo."
  type        = string
  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "Use staging ou production."
  }
}

variable "settings" {
  description = "Parametros definidos pelo operador; capacidade, versoes e retencao nao sao requisitos da IRRAH. Os campos secret contêm somente OCIDs, nunca valores secretos."
  type = object({
    region                    = string
    tenancy_id                = string
    parent_compartment_id     = string
    name_prefix               = string
    vcn_cidr                  = string
    pods_cidr                 = string
    services_cidr             = string
    admin_cidrs               = set(string)
    kubernetes_version        = string
    node_image_id             = string
    node_shape                = string
    node_ocpus                = number
    node_memory_gbs           = number
    node_count                = number
    availability_domain       = string
    postgres_version          = string
    postgres_shape            = string
    postgres_ocpus            = number
    postgres_memory_gbs       = number
    postgres_instance_count   = number
    postgres_regional_storage = bool
    backup_retention_days     = number
    backup_start              = string
    maintenance_window        = string
    database_bootstrap_secret = optional(object({
      id      = string
      version = string
    }))
    application_secret_ids = optional(set(string), [])
  })
  nullable = false
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,23}$", var.settings.name_prefix))
    error_message = "name_prefix deve ter 2 a 24 caracteres minusculos, numeros ou hifens, iniciando por letra."
  }
  validation {
    condition     = alltrue([for cidr in concat([var.settings.vcn_cidr, var.settings.pods_cidr, var.settings.services_cidr], tolist(var.settings.admin_cidrs)) : can(cidrnetmask(cidr))]) && can(cidrsubnet(var.settings.vcn_cidr, 4, 2))
    error_message = "Use CIDRs IPv4 validos e uma VCN que permita subdivisao com quatro bits adicionais."
  }
  validation {
    condition = alltrue([for cidr in var.settings.admin_cidrs : try(
      (startswith(cidr, "10.") && tonumber(split("/", cidr)[1]) >= 8) ||
      (startswith(cidr, "192.168.") && tonumber(split("/", cidr)[1]) >= 16) ||
      (can(regex("^172\\.(1[6-9]|2[0-9]|3[01])\\.", cidr)) && tonumber(split("/", cidr)[1]) >= 12), false)
    ])
    error_message = "Origens administrativas devem ser redes privadas RFC1918, sem super-redes publicas."
  }
  validation {
    condition     = try(alltrue([for value in [var.settings.node_count, var.settings.postgres_instance_count, var.settings.backup_retention_days] : value > 0 && floor(value) == value]) && alltrue([for value in [var.settings.node_ocpus, var.settings.node_memory_gbs, var.settings.postgres_ocpus, var.settings.postgres_memory_gbs] : value > 0]), false)
    error_message = "Capacidades devem ser positivas; contagens e retencoes devem ser inteiros positivos."
  }
  validation {
    condition     = var.settings.database_bootstrap_secret == null ? true : !contains(var.settings.application_secret_ids, var.settings.database_bootstrap_secret.id)
    error_message = "A identidade da aplicacao nao pode ler a credencial administrativa do banco."
  }
}
