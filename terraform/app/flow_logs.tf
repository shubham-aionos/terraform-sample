resource "aws_cloudwatch_log_group" "vpc_flow_logs" {

  #checkov:skip=CKV_AWS_158:Customer-managed KMS encryption is deferred for this disposable lab
  #checkov:skip=CKV_AWS_338:One-day retention is intentional for this disposable lab

  name              = "/aws/vpc/three-tier-flow-logs"
  retention_in_days = 1
}

resource "aws_iam_role" "vpc_flow_logs" {
  name = "three-tier-vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}


resource "aws_iam_role_policy" "vpc_flow_logs" {
  #checkov:skip=CKV_AWS_355:CloudWatch Logs Describe APIs require wildcard resource scope

  name = "three-tier-vpc-flow-logs-policy"
  role = aws_iam_role.vpc_flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "DescribeLogs"
        Effect = "Allow"

        Action = [
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]

        Resource = "*"
      },
      {
        Sid    = "WriteFlowLogs"
        Effect = "Allow"

        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]

        Resource = aws_cloudwatch_log_group.vpc_flow_logs.arn
      }
    ]
  })
}

resource "aws_flow_log" "vpc" {
  vpc_id = aws_vpc.main.id

  traffic_type         = "ALL"
  iam_role_arn         = aws_iam_role.vpc_flow_logs.arn
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.vpc_flow_logs.arn

  tags = {
    Name = "three-tier-vpc-flow-logs"
  }
}
