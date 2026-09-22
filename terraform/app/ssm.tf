resource "aws_security_group" "ssm_endpoints" {
  name        = "three-tier-ssm-endpoints-sg"
  description = "Allow HTTPS from private app subnets to SSM VPC endpoints"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "three-tier-ssm-endpoints-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ssm_endpoints_https" {
  security_group_id            = aws_security_group.ssm_endpoints.id
  description                  = "Allow application instances to reach SSM VPC endpoints over HTTPS"
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.ap-south-1.ssm"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids = [
    aws_subnet.app_a.id,
    aws_subnet.app_b.id
  ]

  security_group_ids = [
    aws_security_group.ssm_endpoints.id
  ]

  tags = {
    Name = "three-tier-ssm"
  }
}

resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.ap-south-1.ssmmessages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids = [
    aws_subnet.app_a.id,
    aws_subnet.app_b.id
  ]

  security_group_ids = [
    aws_security_group.ssm_endpoints.id
  ]

  tags = {
    Name = "three-tier-ssmmessages"
  }
}

resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.ap-south-1.ec2messages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids = [
    aws_subnet.app_a.id,
    aws_subnet.app_b.id
  ]

  security_group_ids = [
    aws_security_group.ssm_endpoints.id
  ]

  tags = {
    Name = "three-tier-ec2messages"
  }
}



# S3 gateway endpoint: free private access from the application subnets to the
# CodePipeline artifact bucket used for the offline PostgreSQL driver bundle.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.ap-south-1.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table.private_app.id
  ]

  tags = {
    Name = "three-tier-s3"
  }
}

# Private Secrets Manager access so the application can retrieve the RDS-managed
# master secret without NAT or a public IP.
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.ap-south-1.secretsmanager"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids = [
    aws_subnet.app_a.id,
    aws_subnet.app_b.id
  ]

  security_group_ids = [
    aws_security_group.ssm_endpoints.id
  ]

  tags = {
    Name = "three-tier-secretsmanager"
  }
}
