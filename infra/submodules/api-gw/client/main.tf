############################
# API Gateway (REST) + VPC Link → NLB
############################

# REST API pública (puedes cambiar a PRIVATE si quieres que sea privada)
resource "aws_api_gateway_rest_api" "gw" {
  name = "${var.name}-rest"
  endpoint_configuration {
    types = ["REGIONAL"] # cambia a ["PRIVATE"] si quieres API privada
  }
}

# VPC Link apuntando al NLB interno
resource "aws_api_gateway_vpc_link" "link" {
  name        = "${var.name}-vpc-link"
  target_arns = [var.aws_lb_nlb_arn]
}

# Reutilizamos tus puertos
# locals.api_ports = { movement=8081, stock=8082, client=8083, notification=8084 }

# /{service}
resource "aws_api_gateway_resource" "svc" {
  for_each    = var.api_ports
  rest_api_id = aws_api_gateway_rest_api.gw.id
  parent_id   = aws_api_gateway_rest_api.gw.root_resource_id
  path_part   = each.key
}

# /{service}/{proxy+} (greedy)
resource "aws_api_gateway_resource" "proxy" {
  for_each    = var.api_ports
  rest_api_id = aws_api_gateway_rest_api.gw.id
  parent_id   = aws_api_gateway_resource.svc[each.key].id
  path_part   = "{proxy+}"
}

# ANY sobre /{service}
resource "aws_api_gateway_method" "svc_any" {
  for_each           = var.api_ports
  rest_api_id        = aws_api_gateway_rest_api.gw.id
  resource_id        = aws_api_gateway_resource.svc[each.key].id
  http_method        = "ANY"
  authorization      = "NONE"
}

# Integración HTTP_PROXY → NLB:puerto (raíz)
resource "aws_api_gateway_integration" "svc_any" {
  for_each                = var.api_ports
  rest_api_id             = aws_api_gateway_rest_api.gw.id
  resource_id             = aws_api_gateway_resource.svc[each.key].id
  http_method             = aws_api_gateway_method.svc_any[each.key].http_method
  type                    = "HTTP_PROXY"
  integration_http_method = "ANY"
  connection_type         = "VPC_LINK"
  connection_id           = aws_api_gateway_vpc_link.link.id
  uri                     = "http://${var.dns_name}:${each.value}"
}

# ANY sobre /{service}/{proxy+}
resource "aws_api_gateway_method" "proxy_any" {
  for_each      = var.api_ports
  rest_api_id   = aws_api_gateway_rest_api.gw.id
  resource_id   = aws_api_gateway_resource.proxy[each.key].id
  http_method   = "ANY"
  authorization = "NONE"

  # Necesario para mapear {proxy}
  request_parameters = {
    "method.request.path.proxy" = true
  }
}

# Integración HTTP_PROXY → NLB:puerto/{proxy}
resource "aws_api_gateway_integration" "proxy_any" {
  for_each                = var.api_ports
  rest_api_id             = aws_api_gateway_rest_api.gw.id
  resource_id             = aws_api_gateway_resource.proxy[each.key].id
  http_method             = aws_api_gateway_method.proxy_any[each.key].http_method
  type                    = "HTTP_PROXY"
  integration_http_method = "ANY"
  connection_type         = "VPC_LINK"
  connection_id           = aws_api_gateway_vpc_link.link.id
  uri                     = "http://${var.dns_name}:${each.value}/{proxy}"

  request_parameters = {
    "integration.request.path.proxy" = "method.request.path.proxy"
  }
}

resource "aws_api_gateway_deployment" "dep" {
  rest_api_id = aws_api_gateway_rest_api.gw.id

  triggers = {
    redeploy_hash = sha1(jsonencode({
      svc_resources   = keys(aws_api_gateway_resource.svc)
      proxy_resources = keys(aws_api_gateway_resource.proxy)
      svc_methods     = keys(aws_api_gateway_method.svc_any)
      proxy_methods   = keys(aws_api_gateway_method.proxy_any)
    }))
  }

  depends_on = [
    aws_api_gateway_integration.svc_any,
    aws_api_gateway_integration.proxy_any,
  ]
}

resource "aws_api_gateway_stage" "prod" {
rest_api_id   = aws_api_gateway_rest_api.gw.id
deployment_id = aws_api_gateway_deployment.dep.id
stage_name    = "prod"
}

