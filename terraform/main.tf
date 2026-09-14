terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}

# --------------------------------------------------
# VPC
# --------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "three-tier-vpc"
  }
}

# --------------------------------------------------
# Public Subnets
# --------------------------------------------------

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = false

  tags = {
    Name = "public-a"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "ap-south-1b"
  map_public_ip_on_launch = false

  tags = {
    Name = "public-b"
  }
}

# --------------------------------------------------
# Internet Gateway
# --------------------------------------------------

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "three-tier-igw"
  }
}

# --------------------------------------------------
# Public Route Table
# --------------------------------------------------

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "public-route-table"
  }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# --------------------------------------------------
# Private App Subnets
# --------------------------------------------------

resource "aws_subnet" "app_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "ap-south-1a"

  tags = {
    Name = "private-app-a"
  }
}

resource "aws_subnet" "app_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.12.0/24"
  availability_zone = "ap-south-1b"

  tags = {
    Name = "private-app-b"
  }
}

# --------------------------------------------------
# Private DB Subnets
# --------------------------------------------------

resource "aws_subnet" "db_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.21.0/24"
  availability_zone = "ap-south-1a"

  tags = {
    Name = "private-db-a"
  }
}

resource "aws_subnet" "db_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.22.0/24"
  availability_zone = "ap-south-1b"

  tags = {
    Name = "private-db-b"
  }
}

# --------------------------------------------------
# Private App Route Table
# --------------------------------------------------

resource "aws_route_table" "private_app" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "private-app-route-table"
  }
}

resource "aws_route_table_association" "app_a" {
  subnet_id      = aws_subnet.app_a.id
  route_table_id = aws_route_table.private_app.id
}

resource "aws_route_table_association" "app_b" {
  subnet_id      = aws_subnet.app_b.id
  route_table_id = aws_route_table.private_app.id
}

# --------------------------------------------------
# Private DB Route Table
# --------------------------------------------------

resource "aws_route_table" "private_db" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "private-db-route-table"
  }
}

resource "aws_route_table_association" "db_a" {
  subnet_id      = aws_subnet.db_a.id
  route_table_id = aws_route_table.private_db.id
}

resource "aws_route_table_association" "db_b" {
  subnet_id      = aws_subnet.db_b.id
  route_table_id = aws_route_table.private_db.id
}

# --------------------------------------------------
# Security Groups
# --------------------------------------------------

resource "aws_security_group" "alb" {
  name        = "three-tier-alb-sg"
  description = "Security group for the public ALB"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "three-tier-alb-sg"
  }
}

resource "aws_security_group" "app" {
  name        = "three-tier-app-sg"
  description = "Security group for the application tier"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "three-tier-app-sg"
  }
}

resource "aws_security_group" "db" {
  name        = "three-tier-db-sg"
  description = "Security group for the database tier"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "three-tier-db-sg"
  }
}

# --------------------------------------------------
# Default Security Group
# --------------------------------------------------

resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "three-tier-default-sg"
  }
}

# --------------------------------------------------
# Security Group Rules
# --------------------------------------------------

# Intentional exception:
# The lab currently uses HTTP rather than HTTPS.
# This is a disposable learning environment, not a production endpoint.
#checkov:skip=CKV_AWS_260:HTTP is intentionally exposed for this disposable learning lab
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  #checkov:skip=CKV_AWS_260:HTTP is intentionally exposed for this disposable lab; HTTPS will be introduced in the production-hardening phase

  security_group_id = aws_security_group.alb.id

  description = "Allow HTTP from the internet to the public ALB"

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 80
  to_port     = 80
  ip_protocol = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id

  description = "Allow HTTPS from the internet to the public ALB"

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "app_http" {
  security_group_id = aws_security_group.app.id

  description = "Allow application traffic from the ALB"

  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "db_postgres" {
  security_group_id = aws_security_group.db.id

  description = "Allow PostgreSQL from the application tier"

  referenced_security_group_id = aws_security_group.app.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "app_all_outbound" {
  security_group_id = aws_security_group.app.id

  description = "Allow application instances to reach required destinations"

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id = aws_security_group.alb.id

  description = "Allow ALB to reach application instances on port 8080"

  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
}

# --------------------------------------------------
# Ubuntu AMI
# --------------------------------------------------

data "aws_ami" "ubuntu" {
  most_recent = true

  owners = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# --------------------------------------------------
# Launch Template
# --------------------------------------------------

resource "aws_launch_template" "app" {
  name = "three-tier-app-template"

  image_id      = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"

  vpc_security_group_ids = [
    aws_security_group.app.id
  ]

  # Enforce IMDSv2
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "three-tier-app"
    }
  }

  user_data = filebase64("${path.module}/user_data.sh")

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_ssm.name
  }
}

# --------------------------------------------------
# Auto Scaling Group
# --------------------------------------------------

resource "aws_autoscaling_group" "app" {
  name             = "three-tier-app-asg"
  min_size         = 2
  desired_capacity = 2
  max_size         = 4

  vpc_zone_identifier = [
    aws_subnet.app_a.id,
    aws_subnet.app_b.id
  ]

  target_group_arns = [
    aws_lb_target_group.app.arn
  ]

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "three-tier-app"
    propagate_at_launch = true
  }

  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 50
    }
  }
}

# --------------------------------------------------
# Application Target Group
# --------------------------------------------------

# Intentional exception:
# The application currently serves HTTP on port 8080.
# HTTPS between ALB and EC2 will be introduced in a later hardening step.
#checkov:skip=CKV_AWS_378:The backend application intentionally uses HTTP for this disposable lab
resource "aws_lb_target_group" "app" {
  #checkov:skip=CKV_AWS_378:HTTP between ALB and application is intentional for this disposable lab; backend TLS will be introduced in the production-hardening phase

  name     = "three-tier-app-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    port                = "8080"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
    timeout             = 5
  }

  tags = {
    Name = "three-tier-app-tg"
  }
}

# --------------------------------------------------
# Application Load Balancer
# --------------------------------------------------

# Intentional lab exceptions:
# - Deletion protection must remain disabled for ./lab.sh down.
# - Access logging is deferred for this cost-conscious lab.
# - HTTPS redirect is deferred because the current application uses HTTP.
# - WAF is deferred until we cover production edge protection.
#checkov:skip=CKV_AWS_150:Deletion protection is disabled so the disposable lab can be destroyed
#checkov:skip=CKV_AWS_91:ALB access logging is deferred for this cost-conscious disposable lab
#checkov:skip=CKV2_AWS_20:HTTPS redirect is deferred because this lab intentionally uses HTTP
#checkov:skip=CKV2_AWS_28:WAF is deferred because this is a disposable learning environment

resource "aws_lb" "app" {
#checkov:skip=CKV_AWS_150:Deletion protection is disabled to allow daily terraform destroy
#checkov:skip=CKV_AWS_91:ALB access logging is deferred for this disposable cost-conscious lab
#checkov:skip=CKV2_AWS_20:HTTP to HTTPS redirect is deferred until ACM certificate and HTTPS listener are introduced
  #checkov:skip=CKV2_AWS_28:AWS WAF is deferred for this disposable cost-conscious lab

  name               = "three-tier-app-alb"
  internal           = false
  load_balancer_type = "application"

  # Reject malformed HTTP headers
  drop_invalid_header_fields = true

  security_groups = [
    aws_security_group.alb.id
  ]

  subnets = [
    aws_subnet.public_a.id,
    aws_subnet.public_b.id
  ]

  tags = {
    Name = "three-tier-app-alb"
  }
}

# --------------------------------------------------
# ALB HTTP Listener
# --------------------------------------------------

# Intentional lab exceptions:
# HTTPS/TLS is deferred until we introduce ACM certificates
# and a production-style HTTPS listener.
#checkov:skip=CKV_AWS_2:HTTPS is intentionally deferred; this lab uses an HTTP listener
#checkov:skip=CKV_AWS_103:TLS is not applicable because the current lab listener is HTTP
resource "aws_lb_listener" "app_http" {
#checkov:skip=CKV_AWS_2:HTTP listener is intentional for this lab; HTTPS requires certificate setup
  #checkov:skip=CKV_AWS_103:TLS listener is deferred until ACM certificate and HTTPS listener are introduced

  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# --------------------------------------------------
# CodeBuild IAM Role
# --------------------------------------------------

resource "aws_iam_role" "codebuild" {
  name = "three-tier-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "codebuild.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}
