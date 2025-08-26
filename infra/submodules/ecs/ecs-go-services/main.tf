# --------- AMI ECS Optimized ----------
data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/arm64/recommended/image_id"
}

locals {
  ecs_ami_id = var.ecs_ami_id != "" ? var.ecs_ami_id : data.aws_ssm_parameter.ecs_ami.value
}

# --------- SECURITY GROUPS ----------
# NLB no usa Security Groups. Filtramos en el SG de ECS.
resource "aws_security_group" "ecs" {
  name        = "${var.name}-ecs-sg"
  description = "Allow traffic from private app subnets to ECS"
  vpc_id      = var.vpc_id

  # Permite cada puerto desde las subredes privadas (donde estara NLB/VPC Link)
  ingress {
    from_port = var.movement_port
    to_port = var.movement_port
    protocol = "tcp"
    cidr_blocks = var.private_app_subnet_cidrs
  }
  ingress {
    from_port = var.stock_port
    to_port = var.stock_port
    protocol = "tcp"
    cidr_blocks = var.private_app_subnet_cidrs
  }
  ingress {
    from_port = var.client_port
    to_port = var.client_port
    protocol = "tcp"
    cidr_blocks = var.private_app_subnet_cidrs
  }
  ingress {
    from_port = var.notification_port
    to_port = var.notification_port
    protocol = "tcp"
    cidr_blocks = var.private_app_subnet_cidrs
  }

  egress  {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  } # p/ endpoints VPC (ECR/Logs/etc.)
  tags = {
    Name = "${var.name}-ecs-sg"
  }
}

# --------- NLB interno + TGs TCP + Listeners por puerto ----------
resource "aws_lb" "nlb" {
  name               = "${var.name}-nlb-int"
  internal           = true
  load_balancer_type = "network"
  subnets            = var.private_app_subnet_ids
  tags               = { Name = "${var.name}-nlb-int" }
}

# Puertos por API
locals {
  api_ports = {
    movement     = var.movement_port
    stock        = var.stock_port
    client       = var.client_port
    notification = var.notification_port
  }
}

# Target groups TCP (bridge -> target_type "instance")
resource "aws_lb_target_group" "api" {
  for_each    = local.api_ports
  name        = "${var.name}-tg-${each.key}"
  port        = each.value
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    protocol = "TCP"
    port     = each.value
  }
}

# Listeners TCP por puerto
resource "aws_lb_listener" "api" {
  for_each          = local.api_ports
  load_balancer_arn = aws_lb.nlb.arn
  port              = each.value
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api[each.key].arn
  }
}

# --------- ECS Cluster + Capacity (EC2) ----------
resource "aws_ecs_cluster" "this" {
  name = "${var.name}-cluster"
  setting {
    name = "containerInsights"
    value = "disabled"
  }
}

resource "aws_iam_role" "ecs_instance_role" {
  name = "${var.name}-ecs-instance-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_instance_attach" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs" {
  name = "${var.name}-ecs-instance-profile"
  role = aws_iam_role.ecs_instance_role.name
}

# --------- Launch Templates (On-Demand y Spot) ----------
resource "aws_launch_template" "ecs_od" {
  name_prefix   = "${var.name}-ecs-od-"
  image_id      = local.ecs_ami_id

  iam_instance_profile { name = aws_iam_instance_profile.ecs.name }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.ecs.id]
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              echo ECS_CLUSTER=${var.name}-cluster >> /etc/ecs/ecs.config
              EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = { Name = "${var.name}-ecs-od" }
  }
}

resource "aws_launch_template" "ecs_spot" {
  name_prefix   = "${var.name}-ecs-spot-"
  image_id      = local.ecs_ami_id

  iam_instance_profile { name = aws_iam_instance_profile.ecs.name }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.ecs.id]
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              echo ECS_CLUSTER=${var.name}-cluster >> /etc/ecs/ecs.config
              EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = { Name = "${var.name}-ecs-spot" }
  }
}

# --------- ASGs (On-Demand y Spot) ----------
resource "aws_autoscaling_group" "ecs_od" {
  name                = "${var.name}-ecs-asg-od"
  max_size            = 4
  min_size            = 1
  desired_capacity    = 1
  vpc_zone_identifier = var.private_app_subnet_ids
  health_check_type   = "EC2"

  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.ecs_od.id
        version            = "$Latest"
      }

      dynamic "override" {
        for_each = var.instance_type_od
        content {
          instance_type = override.value
        }
      }
    }

    instances_distribution {
      on_demand_base_capacity                  = 1
      on_demand_percentage_above_base_capacity = 100
    }
  }

  tag {
    key = "Name"
    value = "${var.name}-ecs-od"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_group" "ecs_spot" {
  name                = "${var.name}-ecs-asg-spot"
  max_size            = 1
  min_size            = 0
  desired_capacity    = 1
  vpc_zone_identifier = var.private_app_subnet_ids
  health_check_type   = "EC2"

  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.ecs_spot.id
        version            = "$Latest"
      }

      # ✅ overrides correctos (de tu lista var.instance_type_spot)
      dynamic "override" {
        for_each = var.instance_type_spot
        content {
          instance_type = override.value
        }
      }
    }

    # ✅ 100% Spot
    instances_distribution {
      on_demand_base_capacity                  = 0
      on_demand_percentage_above_base_capacity = 0
      spot_allocation_strategy                 = "capacity-optimized-prioritized"
    }
  }

  tag {
    key = "Name"
    value = "${var.name}-ecs-spot"
    propagate_at_launch = true
  }
}

# --------- Capacity Providers ----------
resource "aws_ecs_capacity_provider" "od" {
  name = "${var.name}-cp-od"
  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs_od.arn
    managed_termination_protection = "DISABLED"
    managed_scaling {
      status                    = "ENABLED"   # <- habilita scaling automático
      target_capacity           = 100         # <- % de utilización deseada
      minimum_scaling_step_size = 1
      maximum_scaling_step_size = 2
    }
  }
}

resource "aws_ecs_capacity_provider" "spot" {
  name = "${var.name}-cp-spot"
  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs_spot.arn
    managed_termination_protection = "DISABLED"
    managed_scaling { status = "DISABLED" }
  }
}

resource "aws_ecs_cluster_capacity_providers" "attach" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = [aws_ecs_capacity_provider.od.name, aws_ecs_capacity_provider.spot.name]
}

# --------- Task Execution Role (ECR/Logs) ----------
resource "aws_iam_role" "task_exec" {
  name = "${var.name}-task-exec-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "task_exec_attach" {
  role       = aws_iam_role.task_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# --------- 4 Task Definitions + Services (EC2 launch type, bridge) ----------
locals {
  services = {
    movement = {
      svc_name = "api-movement"
      image    = var.movement_image
      port     = var.movement_port
      tg_arn   = aws_lb_target_group.api["movement"].arn
      cp       = "od"
    }
    stock = {
      svc_name = "api-stock"
      image    = var.stock_image
      port     = var.stock_port
      tg_arn   = aws_lb_target_group.api["stock"].arn
      cp       = "od"
    }
    client = {
      svc_name = "api-client"
      image    = var.client_image
      port     = var.client_port
      tg_arn   = aws_lb_target_group.api["client"].arn
      cp       = "od"
    }
    notification = {
      svc_name = "api-notification"
      image    = var.notification_image
      port     = var.notification_port
      tg_arn   = aws_lb_target_group.api["notification"].arn
      cp       = "spot"   # ← esta va a Spot
    }
  }
}

resource "aws_cloudwatch_log_group" "logs" {
  for_each          = local.services
  name              = "/ecs/${var.name}/${each.value.svc_name}"
  retention_in_days = 7
}

resource "aws_ecs_task_definition" "td" {
  for_each                 = local.services
  family                   = "${var.name}-${each.value.svc_name}"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  cpu                      = "128"
  memory                   = "256"
  execution_role_arn       = aws_iam_role.task_exec.arn

  container_definitions = jsonencode([{
    name      = each.value.svc_name
    image     = each.value.image
    essential = true
    portMappings = [{
      containerPort = 80,                 # puerto DENTRO del contenedor (nginx)
      hostPort      = each.value.port,    # 8081..8084 en la instancia (bridge)
      protocol      = "tcp"
    }]
    logConfiguration = {
      logDriver = "awslogs",
      options = {
        awslogs-group         = aws_cloudwatch_log_group.logs[each.key].name,
        awslogs-region        = var.region,
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

# Importante: si usas capacity_provider_strategy NO pongas launch_type
resource "aws_ecs_service" "api" {
  for_each        = local.services
  name            = "${var.name}-${each.value.svc_name}"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.td[each.key].arn
  desired_count   = 1

  dynamic "capacity_provider_strategy" {
    for_each = [each.value.cp]
    content {
      capacity_provider = each.value.cp == "spot" ? aws_ecs_capacity_provider.spot.name : aws_ecs_capacity_provider.od.name
      weight            = 1
      base              = 0
    }
  }

  load_balancer {
    target_group_arn = each.value.tg_arn
    container_name   = each.value.svc_name
    container_port   = 80          # <-- debe coincidir con containerPort de la task
  }

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 200

  depends_on = [aws_lb_listener.api]
}

output "nlb_dns_name" {
  value = aws_lb.nlb.dns_name
}
