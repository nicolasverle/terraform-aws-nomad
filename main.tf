provider "aws" {
  region = var.vpc.region
}

locals {
  azs = ["${var.vpc.region}a", "${var.vpc.region}b", "${var.vpc.region}c"]
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = var.vpc.name
  cidr = var.vpc.cidr

  azs             = local.azs
  private_subnets = var.vpc.private_subnets
  public_subnets  = var.vpc.public_subnets

  enable_nat_gateway = true
  single_nat_gateway = true
  enable_vpn_gateway = false

  tags = {
    Environment = "dev"
  }
}

module "nomad_sg" {
  source = "terraform-aws-modules/security-group/aws"

  name        = "nomad_sg"
  vpc_id      = module.vpc.vpc_id

  egress_with_cidr_blocks = [
    {
      from_port = 0
      to_port = 0
      protocol = "-1"
      cidr_blocks = "0.0.0.0/0"
    }
  ]
  
  ingress_with_self = [
    {
      from_port   = 4646
      to_port     = 4648
      protocol    = "tcp"
      description = "nomad access port"
    },
    {
      from_port   = 8300
      to_port     = 8301
      protocol    = "tcp"
      description = "consul access port"
    },
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      description = "ssh access port"
    }
  ]

  ingress_with_cidr_blocks = [
    {
      from_port   = 4646
      to_port     = 4648
      protocol    = "tcp"
      description = "nomad access port"
      cidr_blocks = join(",", var.vpc.public_subnets)
    },
    {
      from_port   = 8300
      to_port     = 8301
      protocol    = "tcp"
      description = "consul access port"
      cidr_blocks = join(",", var.vpc.public_subnets)
    },
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      description = "ssh access port"
      cidr_blocks = join(",", var.vpc.public_subnets)
    }
  ]
}

resource "aws_iam_role" "ssm" {
  name = "${var.servers_asg.name}-role"

  assume_role_policy = <<-EOT
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Principal": {
          "Service": "ec2.amazonaws.com"
        },
        "Effect": "Allow",
        "Sid": ""
      }
    ]
  }
  EOT
}

resource "aws_iam_policy" "ssm-policy" {
  name = "${var.servers_asg.name}-policy"
  policy = <<-EOT
  {
    "Version": "2012-10-17",
    "Statement": [
      {
          "Sid": "",
          "Effect": "Allow",
          "Action": [
              "ec2:DescribeInstances",
              "autoscaling:DescribeAutoScalingGroups"
          ],
          "Resource": "*"
      }
    ]
  }
  EOT
}

resource "aws_iam_role_policy_attachment" "ssm-policy-attach" {
  role       = aws_iam_role.ssm.name
  policy_arn = aws_iam_policy.ssm-policy.arn
}

resource "aws_iam_instance_profile" "ssm" {
  name = "${var.servers_asg.name}-instance_profile"
  role = aws_iam_role.ssm.name
}

module "servers_asg" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "~> 4.0"

  # Autoscaling group
  name = var.servers_asg.name

  min_size                  = var.servers_asg.size
  max_size                  = var.servers_asg.size
  desired_capacity          = var.servers_asg.size
  wait_for_capacity_timeout = 0
  health_check_type         = "EC2"
  vpc_zone_identifier       = module.vpc.private_subnets

  instance_refresh = {
    strategy = "Rolling"
    preferences = {
      min_healthy_percentage = 50
    }
    triggers = ["tag"]
  }

  # Launch configuration
  lc_name                = var.servers_asg.launch_config.name
  description            = var.servers_asg.launch_config.description

  use_lc    = true
  create_lc = true

  image_id          = var.servers_asg.launch_config.ami
  instance_type     = var.servers_asg.launch_config.type
  ebs_optimized     = true
  enable_monitoring = true

  user_data = templatefile("setup.sh.tftpl", {
    servers_asg_name = var.servers_asg.name
    aws_region = var.vpc.region
    cluster_size = var.servers_asg.size
    is_server_node = true
  })

  security_groups = [module.nomad_sg.security_group_id]
  target_group_arns = module.alb.target_group_arns
  key_name = var.servers_asg.launch_config.key_name
  iam_instance_profile_name = aws_iam_instance_profile.ssm.name

  block_device_mappings = [
    {
      device_name = "/dev/sda1"
      no_device   = 0
      ebs = {
        delete_on_termination = true
        encrypted             = true
        volume_size           = 30
        volume_type           = "gp2"
      }
    }
  ]

  capacity_reservation_specification = {
    capacity_reservation_preference = "open"
  }

  credit_specification = {
    cpu_credits = "standard"
  }

  instance_market_options = {
    market_type = "spot"
  }

}

module "clients_asg" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "~> 4.0"

  # Autoscaling group
  name = var.clients_asg.name

  min_size                  = var.clients_asg.size
  max_size                  = var.clients_asg.size
  desired_capacity          = var.clients_asg.size
  wait_for_capacity_timeout = 0
  health_check_type         = "EC2"
  vpc_zone_identifier       = module.vpc.private_subnets

  instance_refresh = {
    strategy = "Rolling"
    preferences = {
      min_healthy_percentage = 50
    }
    triggers = ["tag"]
  }

  # Launch template
  lc_name                = var.clients_asg.launch_config.name
  description            = var.clients_asg.launch_config.description
  update_default_version = true

  use_lc    = true
  create_lc = true

  image_id          = var.clients_asg.launch_config.ami
  instance_type     = var.clients_asg.launch_config.type
  ebs_optimized     = true
  enable_monitoring = true

  user_data = templatefile("setup.sh.tftpl", {
    servers_asg_name = var.servers_asg.name
    aws_region = var.vpc.region
    cluster_size = var.servers_asg.size
    is_server_node = false
  })

  security_groups = [module.nomad_sg.security_group_id]
  target_group_arns = module.alb.target_group_arns
  key_name = var.clients_asg.launch_config.key_name
  iam_instance_profile_name = aws_iam_instance_profile.ssm.name

  block_device_mappings = [
    {
      device_name = "/dev/sda1"
      no_device   = 0
      ebs = {
        delete_on_termination = true
        encrypted             = true
        volume_size           = 30
        volume_type           = "gp2"
      }
    }
  ]

  capacity_reservation_specification = {
    capacity_reservation_preference = "open"
  }

  credit_specification = {
    cpu_credits = "standard"
  }

  instance_market_options = {
    market_type = "spot"
  }

}

module "alb_http_sg" {
  source  = "terraform-aws-modules/security-group/aws//modules/http-80"
  version = "~> 4.0"

  name        = "${var.lb.name}-alb-http"
  vpc_id      = module.vpc.vpc_id
  description = "Security group for ${var.lb.name}"

  ingress_cidr_blocks = ["0.0.0.0/0"]

}

module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 6.0"

  name = var.lb.name

  vpc_id          = module.vpc.vpc_id
  subnets         = module.vpc.public_subnets
  security_groups = [module.alb_http_sg.security_group_id]

  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "HTTP"
      target_group_index = 0
    }
  ]

  target_groups = [
    {
      name             = var.lb.name
      backend_protocol = "HTTP"
      backend_port     = 4646
      target_type      = "instance"
      deregistration_delay = 10
      health_check = {
        enabled = true
        path = "/v1/status/leader"
        protocol = "HTTP"
      }
    },
  ]

}

module "bastion_ssh_sg" {
  source  = "terraform-aws-modules/security-group/aws//modules/ssh"
  version = "~> 4.0"

  name        = "${var.bastion.name}-ssh"
  vpc_id      = module.vpc.vpc_id
  description = "Security group for ${var.bastion.name}"

  ingress_cidr_blocks = ["0.0.0.0/0"]

}

module "ec2_instance" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 3.0"

  name = var.bastion.name

  ami                    = var.bastion.ami
  instance_type          = var.bastion.type
  key_name               = var.bastion.key_name
  monitoring             = true
  vpc_security_group_ids = [module.bastion_ssh_sg.security_group_id]
  subnet_id              = module.vpc.public_subnets[0]

  tags = {
    Environment = "dev"
  }
}