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
  map_public_ip_on_launch = true

  tags = {
    Name = "public-a"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "ap-south-1b"
  map_public_ip_on_launch = true

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
# Security Group Rules
# --------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 80
  to_port     = 80
  ip_protocol = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "app_http" {
  security_group_id = aws_security_group.app.id

  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "db_postgres" {
  security_group_id = aws_security_group.db.id

  referenced_security_group_id = aws_security_group.app.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
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

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "three-tier-app"
    }
  }
  user_data = base64encode(<<-EOF
    #!/bin/bash

    exec > /var/log/user-data.log 2>&1
    set -x

    echo "=== USER DATA STARTED ==="

    mkdir -p /var/www/app

    cat > /var/www/app/index.html <<'HTML'
    <html>
      <head>
        <title>Three Tier AWS App</title>
      </head>
      <body>
        <h1>Hello from the AWS Three-Tier Architecture!</h1>
        <p>This page is running on an EC2 instance in a private subnet.</p>
      </body>
    </html>
    HTML

    echo "=== CHECKING PYTHON ==="
    which python3
    python3 --version

    echo "=== STARTING APPLICATION ==="
    cd /var/www/app
nohup python3 -m http.server 8080 --bind 0.0.0.0 > /var/log/app-server.log 2>&1 &

sleep 2

echo "=== CHECKING LOCAL APPLICATION ==="
curl -v http://127.0.0.1:8080/ || true

echo "=== CHECKING PORT 8080 ==="
ss -lntp | grep 8080 || true
    echo "=== USER DATA FINISHED ==="
  EOF
  )

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

resource "aws_lb_target_group" "app" {
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

resource "aws_lb" "app" {
  name               = "three-tier-app-alb"
  internal           = false
  load_balancer_type = "application"

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

resource "aws_lb_listener" "app_http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_vpc_security_group_egress_rule" "app_all_outbound" {
  security_group_id = aws_security_group.app.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}
resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
}
