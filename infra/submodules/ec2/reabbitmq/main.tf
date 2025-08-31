

resource "aws_iam_role" "ec2_ssm" {
  name = "${var.name}-ec2-ssm-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "${var.name}-ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm.name
}


resource "aws_security_group" "rabbit" {
  name        = "${var.name}-sg"
  description = "RabbitMQ access control"
  vpc_id      = var.vpc_id

  # Regla AMQP 5672 desde SG de apps (solo si viene)
  dynamic "ingress" {
    for_each = var.sg_app_id == "" ? [] : [var.sg_app_id]
    content {
      description     = "AMQP from app SG"
      from_port       = 5672
      to_port         = 5672
      protocol        = "tcp"
      security_groups = [ingress.value]  # <- ID sg-...
    }
  }

  # Consola 15672 desde IPs admin
  dynamic "ingress" {
    for_each = toset(var.allowed_admin_ips)
    content {
      description = "Mgmt UI from admin IP"
      from_port   = 15672
      to_port     = 15672
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

  tags = { Name = "${var.name}-sg" }
}

//resource "aws_security_group_rule" "mgmt_ips" {
//  for_each          = toset(var.allowed_admin_ips)
//  type              = "ingress"
//  from_port         = 15672
//  to_port           = 15672
//  protocol          = "tcp"
//  security_group_id = aws_security_group.rabbit.id
//  cidr_blocks       = [each.value]
//  description       = "Mgmt UI from admin IP"
//}

############################
# AMI Amazon Linux 2023
############################
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["137112412989"] # Amazon
  filter {
    name = "name"
    values = ["al2023-ami-*-x86_64"]
  } # usa *arm64 si usas t4g.*
}

############################
# EC2 con Docker + RabbitMQ
############################
resource "aws_instance" "rabbit" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id_private
  vpc_security_group_ids      = [aws_security_group.rabbit.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_ssm.name
  associate_public_ip_address = false

  # Volumen raíz (para Docker + datos)
  root_block_device {
    volume_size = var.ebs_size_gb
    volume_type = "gp3"
  }

  # Instala Docker y levanta RabbitMQ (management)
  user_data = <<-EOF
    #!/bin/bash
    set -eux

    echo 'ec2-user:MiPassFuerte1!' | chpasswd
    passwd -x 99999 ec2-user  # no expirar pronto

    dnf update -y
    dnf install -y docker
    systemctl enable --now docker

    # carpeta persistente
    mkdir -p /var/lib/rabbitmq
    chown ec2-user:ec2-user /var/lib/rabbitmq

    # levantar rabbitmq con plugin management
    docker run -d --name rabbitmq \
      -p 5672:5672 -p 15672:15672 \
      -v /var/lib/rabbitmq:/var/lib/rabbitmq \
      -e RABBITMQ_DEFAULT_USER=admin \
      -e RABBITMQ_DEFAULT_PASS=admin123 \
      --restart unless-stopped \
      rabbitmq:3.13-management
  EOF

  tags = {
    Name = "${var.name}-ec2"
  }
}

