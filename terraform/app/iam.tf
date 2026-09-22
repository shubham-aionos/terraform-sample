resource "aws_iam_role" "ec2_ssm" {
  name = "three-tier-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "three-tier-ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm.name
}


resource "aws_iam_role_policy" "ec2_app_runtime" {
  name = "three-tier-ec2-app-runtime"
  role = aws_iam_role.ec2_ssm.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadDatabaseSecret"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_db_instance.postgres.master_user_secret[0].secret_arn
      },
      {
        Sid    = "ReadApplicationRuntimeArtifact"
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "arn:aws:s3:::three-tier-codepipeline-artifacts-${data.aws_caller_identity.current.account_id}/runtime/psycopg-runtime.zip"
      }
    ]
  })
}

data "aws_caller_identity" "current" {}
