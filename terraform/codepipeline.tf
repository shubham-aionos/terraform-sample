resource "aws_codestarconnections_connection" "github" {
  name          = "three-tier-github"
  provider_type = "GitHub"
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

        Resource = aws_codestarconnections_connection.github.arn
      },
      {
        Sid    = "UseCodeBuild"
        Effect = "Allow"

        Action = [
          "codebuild:StartBuild",
          "codebuild:BatchGetBuilds"
        ]

        Resource = "arn:aws:codebuild:ap-south-1:812114845397:project/three-tier-terraform-ci"
      },
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

resource "aws_codepipeline" "three_tier" {
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
        ConnectionArn    = aws_codestarconnections_connection.github.arn
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
        ProjectName = "three-tier-terraform-ci"
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
