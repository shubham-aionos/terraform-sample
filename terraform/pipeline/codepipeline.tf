data "aws_codestarconnections_connection" "github" {
  arn = "arn:aws:codestar-connections:ap-south-1:812114845397:connection/55c323f8-bfb5-4e6c-9117-eed1fd87e421"
}

resource "aws_iam_role" "codepipeline" {
  name = "three-tier-codepipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "codepipeline.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}
resource "aws_iam_role_policy" "codepipeline" {
  name = "three-tier-codepipeline-policy"
  role = aws_iam_role.codepipeline.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "UseGitHubConnection"
        Effect = "Allow"

        Action = [
          "codestar-connections:UseConnection"
        ]

        Resource = data.aws_codestarconnections_connection.github.arn
      },
      {
        Sid    = "UseCodeBuild"
        Effect = "Allow"

        Action = [
          "codebuild:StartBuild",
          "codebuild:BatchGetBuilds"
        ]

        Resource = [
          aws_codebuild_project.terraform_ci.arn,
          aws_codebuild_project.terraform_deploy.arn
      ] },
      {
        Sid    = "UseArtifactBucket"
        Effect = "Allow"

        Action = [
          "s3:GetBucketVersioning",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject"
        ]

        Resource = [
          aws_s3_bucket.codepipeline_artifacts.arn,
          "${aws_s3_bucket.codepipeline_artifacts.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_s3_bucket" "codepipeline_artifacts" {
  #checkov:skip=CKV_AWS_18:S3 access logging is deferred for this disposable lab

  #checkov:skip=CKV_AWS_144:Cross-region replication is unnecessary for this disposable single-region lab

  #checkov:skip=CKV_AWS_145:SSE-S3 encryption is sufficient for this disposable lab; customer-managed KMS is deferred

  #checkov:skip=CKV2_AWS_62:Event notifications are unnecessary for the CodePipeline artifact bucket
  bucket        = "three-tier-codepipeline-artifacts-812114845397"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "codepipeline_artifacts" {
  bucket = aws_s3_bucket.codepipeline_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "codepipeline_artifacts" {
  bucket = aws_s3_bucket.codepipeline_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "codepipeline_artifacts" {
  bucket = aws_s3_bucket.codepipeline_artifacts.id

  versioning_configuration {
    status = "Enabled"
  }

}

resource "aws_s3_bucket_lifecycle_configuration" "codepipeline_artifacts" {
  bucket = aws_s3_bucket.codepipeline_artifacts.id

  rule {
    id     = "expire-old-artifacts"
    status = "Enabled"

    filter {}

    expiration {
      days = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_codepipeline" "three_tier" {
  #checkov:skip=CKV_AWS_219:Customer-managed KMS encryption for the CodePipeline artifact store is deferred for this disposable lab
  name     = "three-tier-terraform-pipeline"
  role_arn = aws_iam_role.codepipeline.arn

  artifact_store {
    location = aws_s3_bucket.codepipeline_artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "GitHub"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn    = data.aws_codestarconnections_connection.github.arn
        FullRepositoryId = "shubham-aionos/terraform-sample"
        BranchName       = "main"
        DetectChanges    = "true"
      }
    }
  }

  stage {
    name = "Validate"

    action {
      name            = "TerraformCheckov"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["source_output"]

      configuration = {
        ProjectName = aws_codebuild_project.terraform_ci.name
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "DeployAndVerify"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["source_output"]

      configuration = {
        ProjectName = aws_codebuild_project.terraform_deploy.name
      }
    }
  }
}

resource "aws_iam_role_policy" "codebuild_artifacts" {
  name = "three-tier-codebuild-artifacts"
  role = aws_iam_role.codebuild.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadCodePipelineArtifacts"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = "${aws_s3_bucket.codepipeline_artifacts.arn}/*"
      },
      {
        Sid    = "InspectCodePipelineArtifactBucket"
        Effect = "Allow"
        Action = [
          "s3:GetBucketVersioning"
        ]
        Resource = aws_s3_bucket.codepipeline_artifacts.arn
      }
    ]
  })
}
