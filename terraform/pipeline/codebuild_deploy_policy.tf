data "aws_caller_identity" "current" {}

resource "aws_iam_role_policy" "codebuild_deploy" {
  name = "three-tier-codebuild-deploy-policy"
  role = aws_iam_role.codebuild_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid      = "EC2AndNetworking"
        Effect   = "Allow"
        Action   = ["ec2:*"]
        Resource = "*"
      },
      {
        Sid      = "LoadBalancing"
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:*"]
        Resource = "*"
      },
      {
        Sid      = "AutoScaling"
        Effect   = "Allow"
        Action   = ["autoscaling:*"]
        Resource = "*"
      },
      {
        Sid      = "RDS"
        Effect   = "Allow"
        Action   = ["rds:*"]
        Resource = "*"
      },
      {
        Sid    = "RDSKMS"
        Effect = "Allow"
        Action = [
          "kms:DescribeKey"
        ]
        Resource = "arn:aws:kms:ap-south-1:${data.aws_caller_identity.current.account_id}:key/42921dbd-1273-4ac8-b2ad-bfaaf5d953dc"
      },
      {
        Sid    = "SecretsManagerKMS"
        Effect = "Allow"
        Action = [
          "kms:DescribeKey"
        ]
        Resource = "arn:aws:kms:ap-south-1:${data.aws_caller_identity.current.account_id}:key/d09559c0-02d8-4d28-beb6-e3f318e0c994"
      },
      {
        Sid      = "CloudWatchLogs"
        Effect   = "Allow"
        Action   = ["logs:*"]
        Resource = "*"
      },
      {
        Sid      = "SSMVerification"
        Effect   = "Allow"
        Action   = ["ssm:DescribeInstanceInformation"]
        Resource = "*"
      },
      {
        Sid      = "CodeBuild"
        Effect   = "Allow"
        Action   = ["codebuild:*"]
        Resource = "*"
      },
      {
        Sid      = "CodePipeline"
        Effect   = "Allow"
        Action   = ["codepipeline:*"]
        Resource = "*"
      },
      {
        Sid    = "CodeStarConnections"
        Effect = "Allow"
        Action = [
          "codestar-connections:GetConnection",
          "codestar-connections:ListConnections"
        ]
        Resource = "*"
      },
      {
        Sid    = "S3ArtifactBucket"
        Effect = "Allow"
        Action = ["s3:*"]
        Resource = [
          aws_s3_bucket.codepipeline_artifacts.arn,
          "${aws_s3_bucket.codepipeline_artifacts.arn}/*"
        ]
      },
      {
        Sid      = "TerraformIdentity"
        Effect   = "Allow"
        Action   = ["sts:GetCallerIdentity"]
        Resource = "*"
      },
      {
        Sid    = "TerraformStateBucket"
        Effect = "Allow"
        Action = [
          "s3:GetBucketLocation",
          "s3:GetBucketVersioning",
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.terraform_state.arn
      },
      {
        Sid    = "TerraformStateObjects"
        Effect = "Allow"
        Action = [
          "s3:DeleteObject",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.terraform_state.arn}/*"
      },
      {
        Sid    = "IAMRolesForLabResources"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:UpdateAssumeRolePolicy",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:GetRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:PassRole"
        ]
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/three-tier-ec2-ssm-role",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/three-tier-vpc-flow-logs-role",
          aws_iam_role.codebuild.arn,
          aws_iam_role.codepipeline.arn,
          aws_iam_role.codebuild_deploy.arn
        ]
      },
      {
        Sid    = "IAMInstanceProfilesForLabResources"
        Effect = "Allow"
        Action = [
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile"
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/three-tier-*"
      },
      {
        Sid    = "IAMListInstanceProfiles"
        Effect = "Allow"
        Action = [
          "iam:ListInstanceProfilesForRole"
        ]
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/three-tier-ec2-ssm-role",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/three-tier-vpc-flow-logs-role"
        ]
      },
      {
        Sid    = "IAMServiceLinkedRoles"
        Effect = "Allow"
        Action = [
          "iam:CreateServiceLinkedRole"
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/*"
      }
    ]
  })
}
