variable "project_name"        { type = string }
variable "vpc_id"              { type = string }
variable "public_subnet_ids"   { type = list(string) }
variable "instance_type"       { type = string }
variable "app_image"           { type = string }
variable "app_container_name"  { type = string }
variable "app_port"            { type = number }
variable "desired_count"       { type = number }
variable "allow_cidr_ingress"  { type = string }
variable "tags"                { type = map(string) }
variable "aws_region" {type = string}

resource "aws_security_group" "host_sg" {
  name        = "${var.project_name}-host-sg"
  description = "Allow HTTP to host"
  vpc_id      = var.vpc_id

  ingress {
    description = "App port"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = [var.allow_cidr_ingress]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.project_name}-host-sg" })
}

# IAM para instancias ECS
resource "aws_iam_role" "ecs_instance_role" {
  name = "${var.project_name}-ecsInstanceRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ecs_instance_managed" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "${var.project_name}-ecsInstanceProfile"
  role = aws_iam_role.ecs_instance_role.name
}

# Roles para tareas
resource "aws_iam_role" "task_execution" {
  name = "${var.project_name}-taskExecutionRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "task_exec_policy" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task_role" {
  name = "${var.project_name}-taskRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}

# Cluster ECS
resource "aws_ecs_cluster" "this" {
  name = "${var.project_name}-cluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
  tags = var.tags
}

# AMI ECS Optimized (ARM64/Graviton) AL2
data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/arm64/recommended/image_id"
}

# Launch Template
resource "aws_launch_template" "lt" {
  name_prefix   = "${var.project_name}-lt-"
  image_id      = data.aws_ssm_parameter.ecs_ami.value
  instance_type = var.instance_type
  iam_instance_profile { name = aws_iam_instance_profile.ecs_instance_profile.name }
  vpc_security_group_ids = [aws_security_group.host_sg.id]

  user_data = base64encode(templatefile("${path.module}/user_data.sh.tftpl", {
    cluster_name = aws_ecs_cluster.this.name
  }))

  metadata_options { http_tokens = "required" }

  tag_specifications {
    resource_type = "instance"
    tags          = var.tags
  }
}

# Auto Scaling Group (1 instancia para free-tier)
resource "aws_autoscaling_group" "asg" {
  name                = "${var.project_name}-asg"
  min_size            = 1
  max_size            = 1
  desired_capacity    = 1
  vpc_zone_identifier = var.public_subnet_ids
  health_check_type   = "EC2"

  launch_template {
    id      = aws_launch_template.lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-ecs"
    propagate_at_launch = true
  }
}

# Capacity Provider
resource "aws_ecs_capacity_provider" "cp" {
  name = "${var.project_name}-cp"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.asg.arn
    managed_termination_protection = "DISABLED"
    managed_scaling {
      status                    = "ENABLED"
      target_capacity           = 100
      minimum_scaling_step_size = 1
      maximum_scaling_step_size = 1
    }
  }
  tags = var.tags
}

resource "aws_ecs_cluster_capacity_providers" "attach" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = [aws_ecs_capacity_provider.cp.name]
  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.cp.name
    weight            = 1
  }
}

# ECR
resource "aws_ecr_repository" "repo" {
  name                 = var.project_name
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
  tags = var.tags
}

# Logs
resource "aws_cloudwatch_log_group" "lg" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 7
  tags = var.tags
}

# Task Definition (bridge mode, expone hostPort=app_port)
resource "aws_ecs_task_definition" "task" {
  family                   = "${var.project_name}-task"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task_role.arn

  container_definitions = jsonencode([{
    name      = var.app_container_name
    image     = var.app_image
    essential = true
    portMappings = [{
      containerPort = var.app_port
      hostPort      = var.app_port
      protocol      = "tcp"
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = "/ecs/${var.project_name}"
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "app"
      }
    }
    environment = [
      { name = "ENV", value = "dev" }
    ]
    cpu = 256
    memoryReservation = 256
    memory = 512
  }])

  tags = var.tags
}

# Servicio sin Load Balancer (para evitar costos)
resource "aws_ecs_service" "svc" {
  name            = "${var.project_name}-svc"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.task.arn
  desired_count   = var.desired_count
  launch_type     = "EC2"
  scheduling_strategy = "REPLICA"

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  depends_on = [aws_autoscaling_group.asg]
  tags = var.tags
}

# IP pública de la instancia (ayuda para acceder sin LB)
data "aws_instances" "ecs_instances" {
  instance_state_names = ["running"]
  filter {
    name   = "tag:Name"
    values = ["${var.project_name}-ecs"]
  }
}

data "aws_instance" "first" {
  instance_id = try(data.aws_instances.ecs_instances.ids[0], null)
}

output "instance_public_ip" {
  value = data.aws_instance.first.public_ip
}