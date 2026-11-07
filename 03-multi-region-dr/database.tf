# Primary PostgreSQL in the primary region, cross-region read replica in the
# standby region.
#
# Why not Project 01's RDS-managed password: RDS doesn't allow read replicas of
# a DB whose master password it manages in Secrets Manager. So Terraform makes
# the password itself, as an *ephemeral* value: it's written to RDS and
# Secrets Manager through write-only attributes and never stored in state.
# The secret is replicated to the standby region, so the standby app can still
# read it while the primary region is down.

ephemeral "random_password" "db" {
  length           = 32
  override_special = "!#$%&*()-_=+[]{}<>:?" # RDS forbids / @ " and spaces
}

resource "aws_secretsmanager_secret" "db" {
  name        = "${var.name}/db-credentials"
  description = "Master credentials for the ${var.name} database (replicated for DR)"

  # Lab: allow immediate re-create with the same name after destroy.
  # Production: keep the default 7-30 day recovery window.
  recovery_window_in_days = 0

  replica {
    region = var.secondary_region
  }
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id                = aws_secretsmanager_secret.db.id
  secret_string_wo_version = var.db_password_version

  secret_string_wo = jsonencode({
    username = "appadmin"
    password = ephemeral.random_password.db.result
  })
}

locals {
  # A replicated secret keeps the same name and suffix; only the region in the ARN differs.
  db_secret_arn_secondary = replace(aws_secretsmanager_secret_version.db.arn, ":${var.primary_region}:", ":${var.secondary_region}:")
}

# ---------------------------------------------------------------- primary

resource "aws_db_subnet_group" "primary" {
  name       = "${var.name}-primary"
  subnet_ids = module.primary.data_subnet_ids
}

resource "aws_db_instance" "primary" {
  identifier     = "${var.name}-primary"
  engine         = "postgres"
  engine_version = "17"
  instance_class = "db.t4g.micro"

  db_name             = "app"
  username            = "appadmin"
  password_wo         = ephemeral.random_password.db.result
  password_wo_version = var.db_password_version

  storage_type      = "gp3"
  allocated_storage = 20
  storage_encrypted = true

  db_subnet_group_name   = aws_db_subnet_group.primary.name
  vpc_security_group_ids = [module.primary.db_security_group_id]
  publicly_accessible    = false
  multi_az               = var.primary_db_multi_az

  backup_retention_period = 1 # required for read replicas; 1 day keeps the lab cheap
  deletion_protection     = false
  skip_final_snapshot     = true
  apply_immediately       = true
}

# ---------------------------------------------------------------- cross-region replica

# Encrypted source => the replica must name a KMS key in its own region.
data "aws_kms_alias" "rds_secondary" {
  provider = aws.secondary
  name     = "alias/aws/rds"
}

resource "aws_db_subnet_group" "secondary" {
  provider = aws.secondary

  name       = "${var.name}-secondary"
  subnet_ids = module.secondary.data_subnet_ids
}

resource "aws_db_instance" "replica" {
  provider = aws.secondary

  identifier          = "${var.name}-replica"
  replicate_source_db = aws_db_instance.primary.arn
  instance_class      = "db.t4g.micro"

  storage_type      = "gp3"
  storage_encrypted = true
  kms_key_id        = data.aws_kms_alias.rds_secondary.target_key_arn

  db_subnet_group_name   = aws_db_subnet_group.secondary.name
  vpc_security_group_ids = [module.secondary.db_security_group_id]
  publicly_accessible    = false
  multi_az               = false

  deletion_protection = false
  skip_final_snapshot = true
  apply_immediately   = true

  lifecycle {
    # After a DR failover the replica is *promoted* (scripts/promote-standby.sh)
    # and stops having a source. Without this, the next plan would try to turn
    # the new primary back into a replica, or replace it.
    ignore_changes = [replicate_source_db]
  }
}
