resource "aws_codebuild_project" "terraform_deploy" {
  #checkov:skip=CKV_AWS_147:Customer-managed KMS encryption is deferred for this disposable lab; CodeBuild service encryption remains enabled
  name         = "three-tier-terraform-deploy"
  service_role = aws_iam_role.codebuild_deploy.arn

  source {
    type      = "CODEPIPELINE"
    buildspec = "deployspec.yml"
  }

  artifacts {
    type = "CODEPIPELINE"
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.codebuild.name
      stream_name = "deploy"
    }
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
}
