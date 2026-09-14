resource "aws_db_subnet_group" "main" {
  name = "three-tier-db-subnet-group"

  subnet_ids = [
    aws_subnet.db_a.id,
    aws_subnet.db_b.id
  ]

  tags = {
    Name = "three-tier-db-subnet-group"
  }
}

resource "aws_db_instance" "postgres" {
  #checkov:skip=CKV_AWS_353:Performance Insights is deferred for this disposable lab
  #checkov:skip=CKV_AWS_118:Enhanced Monitoring is deferred for this disposable lab
  #checkov:skip=CKV2_AWS_30:PostgreSQL query logging is deferred for this disposable lab
  identifier = "three-tier-postgres"

  engine         = "postgres"
  engine_version = "17"

  instance_class        = "db.t3.micro"
  allocated_storage     = 20
  max_allocated_storage = 50
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = "appdb"
  username = var.db_username
  password = var.db_password

  port = 5432

  db_subnet_group_name = aws_db_subnet_group.main.name
  vpc_security_group_ids = [
    aws_security_group.db.id
  ]

  publicly_accessible = false

  backup_retention_period = 0
  skip_final_snapshot     = true
  deletion_protection     = false

  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true

  enabled_cloudwatch_logs_exports = [
    "postgresql"
  ]

  #checkov:skip=CKV_AWS_161:IAM database authentication is intentionally disabled for this lab
  #checkov:skip=CKV_AWS_157:Multi-AZ is intentionally disabled to minimize lab cost
  #checkov:skip=CKV_AWS_293:Deletion protection is intentionally disabled for daily lab destroy
  #checkov:skip=CKV_AWS_133:Automated backups are intentionally disabled for this disposable lab

  tags = {
    Name = "three-tier-postgres"
  }
}
