
resource "aws_security_group" "rds_sg" {
  name        = var.name
  description = "Permite acceso a RDS PostgreSQL desde varias IPs"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.allowed_ips
    content {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "rds-postgres-sg"
  }
}

# ------------------------------
# DB Subnet Group
# ------------------------------
resource "aws_db_subnet_group" "rds" {
  name       = "rds-subnet-group"
  subnet_ids = var.db_subnets

  tags = {
    Name = "rds-subnet-group"
  }
}

# ------------------------------
# RDS PostgreSQL Instance
# ------------------------------
resource "aws_db_instance" "postgres" {
  identifier              = "rds-postgres-instance"
  engine                  = "postgres"
  instance_class          = "db.t3.micro"    # ✅ Free Tier
  allocated_storage       = 20               # ✅ Free Tier
  max_allocated_storage   = 20
  db_name                 = "appdb"
  network_type = "DUAL"
  multi_az = false
  username                = var.db_username
  password                = var.db_password
  db_subnet_group_name    = aws_db_subnet_group.rds.name
  vpc_security_group_ids  = [aws_security_group.rds_sg.id]
  publicly_accessible     = false             # ⚠️ cuidado, expone la DB (pero solo permite tu IP en el SG)
  skip_final_snapshot     = true             # ⚠️ en prod pon false
  deletion_protection     = false            # ⚠️ en prod pon true

  tags = {
    Name = "rds-postgres-instance"
  }
}