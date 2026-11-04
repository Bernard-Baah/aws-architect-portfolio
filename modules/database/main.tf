# PostgreSQL on RDS, Multi-AZ, in private data subnets.
#
# The master password is never in Terraform code or state: RDS generates it and
# stores it in Secrets Manager (manage_master_user_password), with automatic
# rotation. The app reads it from Secrets Manager at runtime.

resource "aws_db_subnet_group" "this" {
  name        = "${var.name}-db"
  description = "Data-tier subnets for ${var.name}"
  subnet_ids  = var.subnet_ids

  tags = var.tags
}

resource "aws_db_instance" "this" {
  identifier = "${var.name}-db"

  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_name                     = var.db_name
  username                    = var.master_username
  manage_master_user_password = true

  # Storage: encrypted gp3 with autoscaling
  storage_type          = "gp3"
  allocated_storage     = var.allocated_storage_gb
  max_allocated_storage = var.max_allocated_storage_gb
  storage_encrypted     = true

  # Network: private only
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = var.security_group_ids
  publicly_accessible    = false
  port                   = 5432

  # Availability
  multi_az = var.multi_az

  # Backups and maintenance (UTC; overnight US Eastern)
  backup_retention_period    = var.backup_retention_days
  backup_window              = "07:00-08:00"
  maintenance_window         = "sun:08:30-sun:09:30"
  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true

  # Lab settings: easy teardown. Production: deletion_protection = true and
  # a final snapshot.
  deletion_protection = var.deletion_protection
  skip_final_snapshot = true
  apply_immediately   = true

  tags = var.tags
}
