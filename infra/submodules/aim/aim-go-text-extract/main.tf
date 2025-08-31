data "aws_iam_policy_document" "assume_role_ec2" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "task_app" {
  name               = "${var.name}-textract-client-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role_ec2.json
  description        = "Permite a la app Go invocar Textract y acceder al bucket S3 ${var.bucket_name}"
}

# Permisos mínimos para:
# - Subir/leer/delete objetos en el bucket (solo dentro de los prefijos configurados)
# - Llamar Textract Sync y Async
data "aws_iam_policy_document" "textract_policy" {
  statement {
    sid    = "S3Access"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      var.arn-docs,
      "${var.arn-docs}/*"
    ]
  }

  statement {
    sid    = "TextractSyncAndAsync"
    effect = "Allow"
    actions = [
      # Síncronas (útil para imágenes sueltas)
      "textract:DetectDocumentText",
      "textract:AnalyzeDocument",
      "textract:AnalyzeExpense",         # por si procesas facturas
      # Asíncronas (PDFs / multi-páginas)
      "textract:StartDocumentTextDetection",
      "textract:GetDocumentTextDetection",
      "textract:StartDocumentAnalysis",
      "textract:GetDocumentAnalysis",
      "textract:StartExpenseAnalysis",
      "textract:GetExpenseAnalysis"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "textract_policy" {
  name        = "${var.name}-textract-policy"
  description = "Acceso a S3 y Textract para la app Go"
  policy      = data.aws_iam_policy_document.textract_policy.json
}

resource "aws_iam_role_policy_attachment" "attach_textract_policy" {
  role       = aws_iam_role.task_app.name
  policy_arn = aws_iam_policy.textract_policy.arn
}

# Instance profile (si corres en EC2)
resource "aws_iam_instance_profile" "textract_client_profile" {
  name = "${var.name}-textract-client-profile"
  role = aws_iam_role.task_app.name
}


