resource "aws_iam_role" "codebuild_deploy" {
  name = "three-tier-codebuild-deploy-role"

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
