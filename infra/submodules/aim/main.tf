# -------- Usuario IAM --------
resource "aws_iam_user" "ecr_ci" {
  name = "ecr-ci-user"
  tags = {
    Project = var.project_name
  }
}

# -------- Access Keys --------
resource "aws_iam_access_key" "ecr_ci" {
  user = aws_iam_user.ecr_ci.name
}

output "ecr_ci_access_key_id" {
  value     = aws_iam_access_key.ecr_ci.id
  sensitive = false
}

output "ecr_ci_secret_access_key" {
  value     = aws_iam_access_key.ecr_ci.secret
  sensitive = true
}

# -------- Política IAM personalizada --------
data "aws_caller_identity" "current" {}

resource "aws_iam_policy" "ecr_push_pull" {
  name        = "ECRPushPullPolicy"
  description = "Permite push/pull a los repos ECR del proyecto"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:BatchGetImage",
          "ecr:DescribeRepositories",
          "ecr:DescribeImages",
          "ecr:ListImages"
        ]
        Resource = values(var.ecr_repo_arns)  # 👈 aquí va directo la lista de ARNs
      }
    ]
  })
}

# -------- Adjuntar política al usuario --------
resource "aws_iam_user_policy_attachment" "ecr_ci_attach" {
  user       = aws_iam_user.ecr_ci.name
  policy_arn = aws_iam_policy.ecr_push_pull.arn
}