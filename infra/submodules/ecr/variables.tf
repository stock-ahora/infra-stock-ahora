variable "project_name" {
  type    = string
  default = "stockahora"
}

# Nombres de repos (puedes cambiarlos)
variable "ecr_repositories" {
  type    = list(string)
  default = ["api-movement", "api-stock", "api-client", "api-notification"]
}

# KMS opcional (si quieres cifrado KMS en vez de AES256)
variable "kms_key_arn" {
  type      = string
  default   = "" # deja vacío para usar AES256
}