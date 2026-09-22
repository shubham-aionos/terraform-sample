resource "aws_secretsmanager_secret" "db" {
  name = "three-tier/database"

  tags = {
    Name = "three-tier-database-secret"
  }
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id

  secret_string = jsonencode({
    username = "postgres"
    password = random_password.db.result
    database = "appdb"
    port     = 5432
    host     = aws_db_instance.postgres.address
  })
}

resource "aws_iam_role_policy" "ec2_secrets" {
  name = "three-tier-read-db-secret"
  role = aws_iam_role.ec2_ssm.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "secretsmanager:GetSecretValue"
        ]

        Resource = aws_secretsmanager_secret.db.arn
      }
    ]
  })
}
