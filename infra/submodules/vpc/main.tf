locals {
  name = "stockahora"
}

#------------------ VPC + IGW ------------------
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "${local.name}-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${local.name}-igw" }
}

#------------------ SUBNETS ------------------
# Mapeamos AZ -> index para elegir el CIDR correcto
locals {
  az_index = { for idx, az in var.azs : az => idx }
}

resource "aws_subnet" "public" {
  for_each                = toset(var.azs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnets[local.az_index[each.key]]
  availability_zone       = each.key
  map_public_ip_on_launch = true
  tags = {
    Name = "${local.name}-public-${each.key}"
    Tier = "public"
  }
}

resource "aws_subnet" "private_app" {
  for_each          = toset(var.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_app_subnets[local.az_index[each.key]]
  availability_zone = each.key
  tags = {
    Name = "${local.name}-private-app-${each.key}"
    Tier = "private-app"
  }
}

resource "aws_subnet" "private_data" {
  for_each          = toset(var.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_data_subnets[local.az_index[each.key]]
  availability_zone = each.key
  tags = {
    Name = "${local.name}-private-data-${each.key}"
    Tier = "private-data"
  }
}

#------------------ ROUTE TABLES ------------------
# Pública: 0.0.0.0/0 -> IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${local.name}-rt-public" }
}

resource "aws_route" "public_igw" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_assoc" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# NAT(s): en subred pública(s)
resource "aws_eip" "nat" {
  for_each = var.nat_per_az ? aws_subnet.public : { first = values(aws_subnet.public)[0] }
  domain   = "vpc"
  tags     = { Name = "${local.name}-eip-nat-${try(each.key, "a")}" }
}

resource "aws_nat_gateway" "nat" {
  for_each      = var.nat_per_az ? aws_subnet.public : { first = values(aws_subnet.public)[0] }
  subnet_id     = try(each.value.id, each.value.id)
  allocation_id = aws_eip.nat[each.key].id
  tags          = { Name = "${local.name}-nat-${try(each.key, "a")}" }
  depends_on    = [aws_internet_gateway.igw]
}

# Privada-app: salida a Internet por NAT (para bajar dependencias, ECR, etc.)
resource "aws_route_table" "private_app" {
  for_each = aws_subnet.private_app
  vpc_id   = aws_vpc.this.id
  tags     = { Name = "${local.name}-rt-private-app-${each.key}" }
}

resource "aws_route" "private_app_nat" {
  for_each               = aws_route_table.private_app
  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = var.nat_per_az ? aws_nat_gateway.nat[replace(each.key, "private_app", "public")].id : values(aws_nat_gateway.nat)[0].id
}

resource "aws_route_table_association" "private_app_assoc" {
  for_each       = aws_subnet.private_app
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_app[each.key].id
}

# Privada-data: Aislada (sin 0.0.0.0/0). Solo endpoints.
resource "aws_route_table" "private_data" {
  for_each = aws_subnet.private_data
  vpc_id   = aws_vpc.this.id
  tags     = { Name = "${local.name}-rt-private-data-${each.key}" }
}

resource "aws_route_table_association" "private_data_assoc" {
  for_each       = aws_subnet.private_data
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_data[each.key].id
}

#------------------ VPC ENDPOINTS ------------------
# Gateway endpoint para S3 (útil para data/backup sin salir a Internet)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat(
    [for rt in aws_route_table.private_app  : rt.id],
    [for rt in aws_route_table.private_data : rt.id]
  )
  tags = { Name = "${local.name}-vpce-s3" }
}

# Interface endpoints para servicios usados por contenedores/SageMaker/Logs/etc.
resource "aws_vpc_endpoint" "interface" {
  for_each          = toset(var.interface_endpoints)
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type = "Interface"
  subnet_ids        = [for s in aws_subnet.private_app : s.id] # en capa app
  security_group_ids = [aws_security_group.endpoints.id]
  private_dns_enabled = true
  tags = { Name = "${local.name}-vpce-${each.key}" }
}

#------------------ SECURITY GROUPS (base) ------------------
# ALB público
resource "aws_security_group" "alb" {
  name        = "${local.name}-sg-alb"
  description = "ALB publico"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name}-sg-alb" }
}

# Apps privadas (ECS on EC2/EKS/EC2) – recibe tráfico solo desde el ALB
resource "aws_security_group" "app" {
  name        = "${local.name}-sg-app"
  description = "Trafico desde ALB a aplicaciones"
  vpc_id      = aws_vpc.this.id

  ingress {
    description      = "App from ALB"
    from_port        = var.app_port
    to_port          = var.app_port
    protocol         = "tcp"
    security_groups  = [aws_security_group.alb.id]
  }

  # (Opcional) permitir de NLB del VPC Link si vas a usar API Gateway + VPC Link.
  # NLB no usa SG; si necesitas restringir, hazlo en SG del target (por puerto) y NACL.

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name}-sg-app" }
}

# Base de datos aislada – solo desde capa app
resource "aws_security_group" "db" {
  name        = "${local.name}-sg-db"
  description = "DB solo desde capa app"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "DB from app"
    from_port       = var.db_port
    to_port         = var.db_port
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name}-sg-db" }
}

# SG para endpoints interface (permite salidas desde app)
resource "aws_security_group" "endpoints" {
  name        = "${local.name}-sg-endpoints"
  description = "Permitir trafico desde apps hacia endpoints interface"
  vpc_id      = aws_vpc.this.id

  ingress { # desde apps a los ENI de los endpoints
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name}-sg-endpoints" }
}

# (Opcional) SG para SageMaker endpoint/notebook en subred privada-app
resource "aws_security_group" "sagemaker" {
  name        = "${local.name}-sg-sagemaker"
  description = "SageMaker dentro de la VPC"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "Invocacion desde apps"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name}-sg-sagemaker" }
}
