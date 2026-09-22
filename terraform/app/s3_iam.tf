resource "aws_iam_role_policy" "ec2_s3_artifact" {
  name = "three-tier-read-application-artifact"
  role = aws_iam_role.ec2_ssm.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "ReadApplicationArtifact"
        Effect = "Allow"

        Action = [
          "s3:GetObject"
        ]

        Resource = "arn:aws:s3:::three-tier-codepipeline-artifacts-812114845397/applications/*"
      }
    ]
  })
}
