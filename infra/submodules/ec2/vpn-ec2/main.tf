resource "aws_security_group" "pritunl" {
  name        = "${var.project_name}-pritunl-sg"
  description = "Acceso a Pritunl VPN"
  vpc_id      = var.aws_vpc_id

  # HTTPS para panel y/o túnel TCP
  ingress {
    description      = "Pritunl HTTPS"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  # OpenVPN UDP (puerto por defecto)
  ingress {
    description      = "OpenVPN UDP"
    from_port        = 1194
    to_port          = 1194
    protocol         = "udp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  # SSH (opcional). Si usarás SSM, puedes borrar este bloque.
  dynamic "ingress" {
    for_each = var.ssh_key_name == null ? [] : [1]
    content {
      description = "SSH"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [var.ssh_cidr]
    }
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = { Name = "${var.project_name}-pritunl-sg" }
}


data "aws_iam_policy_document" "ssm_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "pritunl_ssm_role" {
  name               = "${var.project_name}-pritunl-ssm-role"
  assume_role_policy = data.aws_iam_policy_document.ssm_assume.json
}

resource "aws_iam_role_policy_attachment" "pritunl_ssm_attach" {
  role       = aws_iam_role.pritunl_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "pritunl_ssm_profile" {
  name = "${var.project_name}-pritunl-ssm-profile"
  role = aws_iam_role.pritunl_ssm_role.name
}

# Elastic IP fija (gratis mientras la instancia esté encendida)
resource "aws_eip" "pritunl" {
  vpc  = true
  tags = { Name = "${var.project_name}-pritunl-eip" }
}

resource "aws_instance" "pritunl" {
  ami                         = data.aws_ami.ubuntu_jammy.id
  instance_type               = "t3.micro"
  subnet_id                   = var.public_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.pritunl.id]
  key_name                    = var.ssh_key_name
  iam_instance_profile        = aws_iam_instance_profile.pritunl_ssm_profile.name
  associate_public_ip_address = false
  source_dest_check           = false

 #user_data = <<EOF
 ##!/bin/bash
 #set -euxo pipefail
 #exec > >(tee -a /var/log/pritunl-bootstrap.log | logger -t user-data) 2>&1
 #export DEBIAN_FRONTEND=noninteractive
 #
 ## Forzar IPv4 para APT (evita issues con IPv6/DNS)
 #printf 'Acquire::ForceIPv4 "true";\n' >/etc/apt/apt.conf.d/99force-ipv4
 #
 #apt-get update -y
 #apt-get install -y ca-certificates curl gnupg lsb-release software-properties-common
 #
 ## SSM Agent
 #snap install amazon-ssm-agent --classic || true
 #systemctl enable --now snap.amazon-ssm-agent.amazon-ssm-agent.service || \
 # (apt-get install -y amazon-ssm-agent && systemctl enable --now amazon-ssm-agent) || true
 #
 ## Pritunl (Cloudsmith - endpoints config)
 #curl -1sLf 'https://dl.cloudsmith.io/public/pritunl/pritunl/config.keyring' \
 #  -o /usr/share/keyrings/pritunl-keyring.gpg
 #curl -1sLf 'https://dl.cloudsmith.io/public/pritunl/pritunl/config.deb.txt' \
 #  -o /etc/apt/sources.list.d/pritunl.list
 #
 ## MongoDB 6.0
 #curl -fsSL https://pgp.mongodb.com/server-6.0.asc | gpg --dearmor \
 #  -o /usr/share/keyrings/mongodb-org-6.0.gpg
 #cat >/etc/apt/sources.list.d/mongodb-org-6.0.list <<'EOF'
 #deb [signed-by=/usr/share/keyrings/mongodb-org-6.0.gpg] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse
 #EOF
 #
 #  apt-get update -y
 #apt-get install -y pritunl mongodb-org
 #
 ## Enable IP forwarding (por si NAT sobre la VPN)
 #sysctl -w net.ipv4.ip_forward=1
 #sed -i 's/^#\?net.ipv4.ip_forward.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf
 #sysctl -w net.ipv6.conf.all.forwarding=1
 #sed -i 's/^#\?net.ipv6.conf.all.forwarding.*/net.ipv6.conf.all.forwarding=1/' /etc/sysctl.conf
 #
 #systemctl enable --now mongod
 #systemctl enable --now pritunl
 #
 #echo "SETUP KEY: $(pritunl setup-key)"
 #echo "DEFAULT ADMIN PASS:"
 #pritunl default-password || true
 #EOF



tags = { Name = "${var.project_name}-pritunl" }
}


# Asociar la EIP a la instancia
resource "aws_eip_association" "pritunl" {
  allocation_id = aws_eip.pritunl.id
  instance_id   = aws_instance.pritunl.id
}

output "pritunl_public_ip" {
  value = aws_eip.pritunl.public_ip
}

output "pritunl_admin_urls" {
  value = {
    https  = "https://${aws_eip.pritunl.public_ip}/"
    http   = "http://${aws_eip.pritunl.public_ip}/"
    ssm    = "Use AWS Systems Manager > Fleet Manager / Session Manager"
  }
}

resource "aws_ssm_document" "session_manager_run_as_root" {
  name          = "SSM-SessionManagerRunAs"
  document_type = "Session"
  content = jsonencode({
    schemaVersion = "1.0",
    description   = "Session Manager preferences",
    sessionType   = "Standard_Stream",
    inputs = {
      idleSessionTimeout     = "20"
      cloudWatchLogGroupName = ""
      s3BucketName           = ""
      kmsKeyId               = ""
      runAsEnabled           = true
      runAsDefaultUser       = "root"
      shellProfile = {
        linux = "bash"
      }
    }
  })
}
