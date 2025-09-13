data "aws_ami" "aws1" {
  most_recent = true

  filter {
    name   = "name"
    values = ["al2023-ami-2023.8.20250818.0-kernel-6.1-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["137112412989"] # Canonical
}

resource "aws_iam_instance_profile" "instance-profile" {
  name = "demo-instance_profile"
  role = aws_iam_role.role.name
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "role" {
  name                = "demo-ecs_role"
  path                = "/"
  assume_role_policy  = data.aws_iam_policy_document.assume_role.json
  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"]
}


resource "aws_ecs_cluster" "tst-cluster" {
  name = "demo-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_launch_template" "foobar" {
  name_prefix   = "test-lt"
  image_id      = "ami-0bacd2d203828f784"
  instance_type = "t2.medium"
  iam_instance_profile {
    name = aws_iam_instance_profile.instance-profile.name
  }
  user_data = filebase64("${path.module}/user_data.sh")
}

resource "aws_autoscaling_group" "bar" {
  depends_on         = [aws_launch_template.foobar]
  availability_zones = ["us-west-1a"]
  desired_capacity   = 1
  max_size           = 1
  min_size           = 1

  launch_template {
    id      = aws_launch_template.foobar.id
    version = "$Latest"
  }
}

resource "aws_ecs_task_definition" "nexus" {
  family                   = "nexus-tdef"
  requires_compatibilities = ["EC2"]
  network_mode             = "bridge"
  cpu                      = "1024"
  memory                   = "2048"
  execution_role_arn       = "arn:aws:iam::296352766082:role/ecsTaskExecutionRole"
  task_role_arn            = "arn:aws:iam::296352766082:role/ecsTaskExecutionRole"

  container_definitions = jsonencode([
    {
      name      = "nexus"
      image     = "296352766082.dkr.ecr.us-east-1.amazonaws.com/nexus:3.76"
      essential = true
      cpu       = 1024
      memory    = 2048

      portMappings = [
        {
          containerPort = 8081
          hostPort      = 8081
          protocol      = "tcp"
        }
      ]

      mountPoints = [
        {
          sourceVolume  = "nexus-efs-data"
          containerPath = "/opt/nexus/data"
          readOnly      = false
        },
        {
          sourceVolume  = "nexus-efs-logs"
          containerPath = "/opt/nexus/logs"
          readOnly      = false
        }
      ]
    }
  ])
  volume {
    name = "nexus-efs-data"

    efs_volume_configuration {
      file_system_id     = "fs-014344ea414800be8"
      root_directory     = "/"
      transit_encryption = "ENABLED"

    }
  }
  volume {
    name = "nexus-efs-logs"

    efs_volume_configuration {
      file_system_id     = "fs-014344ea414800be8"
      root_directory     = "/"
      transit_encryption = "ENABLED"

    }
  }
}

resource "aws_ecs_service" "demo-service" {
  name            = "nexus-service"
  cluster         = aws_ecs_cluster.tst-cluster.id
  task_definition = aws_ecs_task_definition.nexus.arn
  desired_count   = 1
}
