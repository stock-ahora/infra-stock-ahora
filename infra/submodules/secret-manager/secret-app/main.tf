resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_secretsmanager_secret" "app" {
  name                    = "${var.name}-true-stock-${random_id.suffix.hex}"
  description             = "Credenciales DB para ${var.name}"
  recovery_window_in_days = 0
  # kms_key_id            = aws_kms_key.sm.arn # si usas KMS propio
}

# Guarda la primera versión del secreto (string)
resource "aws_secretsmanager_secret_version" "app_v1" {
  secret_id     = aws_secretsmanager_secret.app.id
  secret_string = jsonencode({
    username = "app_user"
    password = "S3guro#2025!"
    host     = "db.internal"
    port     = 5432
  })
}

data "aws_secretsmanager_secret" "app" {
  name = "${var.name}-true-stock-${random_id.suffix.hex}"

  depends_on = [aws_secretsmanager_secret.app]
}

# Política mínima para leer el secreto en runtime
data "aws_iam_policy_document" "task_can_get_secret" {
  statement {
    sid     = "ReadSecretAtRuntime"
    effect  = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [
      data.aws_secretsmanager_secret.app.arn,
      "${data.aws_secretsmanager_secret.app.arn}*"  # versiones del secreto
    ]
  }
}

resource "aws_iam_policy" "task_can_get_secret" {
  name   = "${var.name}-task-can-get-secret"
  policy = data.aws_iam_policy_document.task_can_get_secret.json
}

resource "aws_iam_role_policy_attachment" "attach_task_can_get_secret" {
  role       = var.task_app_name
  policy_arn = aws_iam_policy.task_can_get_secret.arn
}