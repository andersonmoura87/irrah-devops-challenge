variable "settings" {
  description = "Configuracao repassada ao modulo environment, que centraliza schema e validacoes. Veja modules/environment/variables.tf."
  type        = any
  nullable    = false
}