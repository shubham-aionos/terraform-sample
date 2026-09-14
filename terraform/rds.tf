# --------------------------------------------------
# RDS Subnet Group
# --------------------------------------------------

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

# --------------------------------------------------
# RDS PostgreSQL
# --------------------------------------------------

resource "aws_db_instance" "postgres" {
  identifier = "three-tier-postgres"

  engine         = "postgres"
  engine_version = "17"

  instance_class        = "db.t3.micro"
  allocated_storage     = 20
  max_allocated_storage = 20
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

  multi_az = false

  backup_retention_period = 0

  skip_final_snapshot = true

  deletion_protection = false

  apply_immediately = true

  tags = {
    Name = "three-tier-postgres"
  }
}
