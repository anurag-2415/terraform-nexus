resource "aws_efs_file_system" "nexus" {
  creation_token = var.efs_name
  encrypted      = true
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
  tags = {
    Name = var.efs_name
  }
}

resource "aws_efs_mount_target" "nexus_az1" {
  file_system_id  = aws_efs_file_system.nexus.id
  subnet_id       = "subnet-00f1be2cc61fe155c"
  security_groups = ["sg-09f4b4a5801b31185"]
}

resource "aws_efs_mount_target" "nexus_az2" {
  file_system_id  = aws_efs_file_system.nexus.id
  subnet_id       = "subnet-0ca792222c939242e"
  security_groups = ["sg-09f4b4a5801b31185"]
}

resource "aws_efs_access_point" "nexus_data" {
  file_system_id = aws_efs_file_system.nexus.id

  posix_user {
    uid = 200
    gid = 200
  }

  root_directory {
    path = "/data"
    creation_info {
      owner_gid   = 200
      owner_uid   = 200
      permissions = "770"
    }
  }
}

resource "aws_efs_access_point" "nexus_logs" {
  file_system_id = aws_efs_file_system.nexus.id

  posix_user {
    uid = 200
    gid = 200
  }

  root_directory {
    path = "/logs"
    creation_info {
      owner_gid   = 200
      owner_uid   = 200
      permissions = "770"
    }
  }
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
  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role", "arn:aws:iam::aws:policy/AmazonElasticFileSystemClientReadWriteAccess", "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore", "arn:aws:iam::aws:policy/AdministratorAccess"]
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
  image_id      = data.aws_ami.ecs_optimized.id
  instance_type = "t2.large"
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
  cpu                      = "1524"
  memory                   = "4048"
  execution_role_arn       = "arn:aws:iam::296352766082:role/ecsTaskExecutionRole"
  task_role_arn            = "arn:aws:iam::296352766082:role/ecsTaskExecutionRole"

  container_definitions = jsonencode([
    {
      name      = "nexus"
      image     = "296352766082.dkr.ecr.us-west-1.amazonaws.com/nexus:3.76"
      essential = true
      cpu       = 1524
      memory    = 4048

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
      file_system_id     = aws_efs_file_system.nexus.id
      root_directory     = "/"
      transit_encryption = "ENABLED"

      authorization_config {
        access_point_id = aws_efs_access_point.nexus_data.id
        iam             = "DISABLED"
      }
    }
  }

  volume {
    name = "nexus-efs-logs"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.nexus.id
      root_directory     = "/"
      transit_encryption = "ENABLED"

      authorization_config {
        access_point_id = aws_efs_access_point.nexus_logs.id
        iam             = "DISABLED"
      }
    }
  }
}

resource "aws_ecs_service" "demo-service" {
  name            = "nexus-service"
  cluster         = aws_ecs_cluster.tst-cluster.id
  task_definition = aws_ecs_task_definition.nexus.arn
  desired_count   = 1
  load_balancer {
    target_group_arn = module.alb.arn
    container_name   = "nexus"
    container_port   = 8081
  }
}

module "alb" {
  source = "terraform-aws-modules/alb/aws"

  name    = "${terraform.workspace}-${var.alb-name}"
  vpc_id  = "vpc-00f2a9392ffd68490"
  subnets = ["subnet-0ca792222c939242e", "subnet-00f1be2cc61fe155c"]

  # Security Group
  security_group_ingress_rules = {
    all_http = {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      description = "HTTP web traffic"
      cidr_ipv4   = "0.0.0.0/0"
    }
    all_https = {
      from_port   = 443
      to_port     = 443
      ip_protocol = "tcp"
      description = "HTTPS web traffic"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }
  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "10.0.0.0/16"
    }
  }

  listeners = {
    ex-http-https-redirect = {
      port     = 8081
      protocol = "HTTP"
      redirect = {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
    ex-https = {
      port            = 443
      protocol        = "HTTPS"
      certificate_arn = "arn:aws:iam::123456789012:server-certificate/test_cert-123456789012"

      forward = {
        target_group_key = "ex-instance"
      }
    }
  }

  target_groups = {
    ex-instance = {
      name_prefix = "h1"
      protocol    = "HTTP"
      port        = 80
      target_type = "instance"
      target_id   = data.aws_instance.foo.private_ip
    }
  }

  tags = {
    Environment = "Development"
    Project     = "Example"
  }
}

output "alb-name" {
  value = module.alb.arn

}
