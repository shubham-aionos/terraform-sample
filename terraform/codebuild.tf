resource "aws_cloudwatch_log_group" "codebuild" {
  #checkov:skip=CKV_AWS_158:Customer-managed KMS encryption is deferred for this disposable lab
  #checkov:skip=CKV_AWS_338:One-day retention is intentional for this disposable lab
  name              = "/aws/codebuild/three-tier-terraform-ci"
  retention_in_days = 1
}

resource "aws_codebuild_project" "terraform_ci" {
  name         = "three-tier-terraform-ci"
  service_role = aws_iam_role.codebuild.arn

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec.yml"
  }

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = "ap-south-1"
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.codebuild.name
      stream_name = "build"
    }
  }
}

resource "aws_iam_role_policy" "codebuild_logs" {
  name = "three-tier-codebuild-logs"
  role = aws_iam_role.codebuild.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "WriteCodeBuildLogs"
        Effect = "Allow"

        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]

        Resource = "${aws_cloudwatch_log_group.codebuild.arn}:*"
      }
    ]
  })
}