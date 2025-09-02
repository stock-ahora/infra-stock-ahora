# ---------- API Gateway (REST) ----------
resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.name}-api"
  description = "API para encender/apagar servicios"
}

# /on
resource "aws_api_gateway_resource" "on" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "on"
}

resource "aws_api_gateway_method" "on_post" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.on.id
  http_method   = "POST"
  authorization = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_integration" "on_post_lambda" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.on.id
  http_method             = aws_api_gateway_method.on_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_arn
}

# /off
resource "aws_api_gateway_resource" "off" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "off"
}

resource "aws_api_gateway_method" "off_post" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.off.id
  http_method   = "POST"
  authorization = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_integration" "off_post_lambda" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.off.id
  http_method             = aws_api_gateway_method.off_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_arn

}

# Permisos para que API GW invoque la Lambda
resource "aws_lambda_permission" "allow_apigw_on" {
  statement_id  = "AllowAPIGWInvokeOn"
  action        = "lambda:InvokeFunction"
  function_name = var.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/POST/on"
}

resource "aws_lambda_permission" "allow_apigw_off" {
  statement_id  = "AllowAPIGWInvokeOff"
  action        = "lambda:InvokeFunction"
  function_name = var.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/POST/off"
}

# Deploy + Stage
resource "aws_api_gateway_deployment" "dep" {
  rest_api_id = aws_api_gateway_rest_api.api.id

  triggers = {
    redeploy_hash = sha1(jsonencode({
      on  = aws_api_gateway_integration.on_post_lambda.id
      off = aws_api_gateway_integration.off_post_lambda.id
    }))
  }

  lifecycle { create_before_destroy = true }
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.dep.id
  stage_name    = "prod"
}


resource "random_password" "api_key_value" {
  length  = 40
  special = false
}

resource "aws_api_gateway_api_key" "ops" {
  name    = "${var.name}-ops-key"
  enabled = true
  value   = random_password.api_key_value.result
}

resource "aws_api_gateway_usage_plan" "plan" {
  name = "${var.name}-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_stage.prod.stage_name
  }

  throttle_settings {
    burst_limit = 20
    rate_limit  = 10
  }

}

resource "aws_api_gateway_usage_plan_key" "attach" {
  key_id        = aws_api_gateway_api_key.ops.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.plan.id
}


