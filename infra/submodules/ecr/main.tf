locals {
  repo_map = { for r in var.ecr_repositories : r => {
    name = "${var.project_name}/${r}"
  }}
}

resource "aws_ecr_repository" "this" {
  for_each             = local.repo_map
  name                 = each.value.name
  image_tag_mutability = "IMMUTABLE"

  encryption_configuration {
    encryption_type = var.kms_key_arn == "" ? "AES256" : "KMS"
    kms_key         = var.kms_key_arn == "" ? null : var.kms_key_arn
  }

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Project = var.project_name
    Service = each.key
  }
}

# ------- Lifecycle: limpiar imágenes antiguas/untagged -------
resource "aws_ecr_lifecycle_policy" "solo_tagged" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Mantener máx. 2 imágenes con tag (cualquier tag)"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 2
        }
        action = { type = "expire" }
      }
    ]
  })
}

# ------- (Opcional) Política de repo para permitir pull a tu cuenta/roles -------
# Normalmente NO es necesario si tus tareas ECS usan el AmazonECSTaskExecutionRolePolicy.
# Si quieres permitir a otra cuenta/role, añade aquí su ARN.
variable "allow_pull_principals" {
  type    = list(string)
  default = [] # e.g. ["arn:aws:iam::123456789012:role/ci-cd"]
}

data "aws_iam_policy_document" "repo_policy" {
  count = length(var.allow_pull_principals) > 0 ? 1 : 0

  statement {
    sid     = "AllowPullFromPrincipals"
    effect  = "Allow"
    actions = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"]

    principals {
      type        = "AWS"
      identifiers = var.allow_pull_principals
    }
  }
}

resource "aws_ecr_repository_policy" "this" {
  for_each   = length(var.allow_pull_principals) > 0 ? aws_ecr_repository.this : {}
  repository = each.value.name
  policy     = data.aws_iam_policy_document.repo_policy[0].json
}