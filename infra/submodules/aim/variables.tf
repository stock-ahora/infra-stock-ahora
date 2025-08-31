variable "project_name" {
  type = string
  default = ""
}

variable "ecr_repo_arns" {
  type = map(string)
}