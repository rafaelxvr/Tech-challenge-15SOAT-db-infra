locals {
  name = "oficina-phase3-${var.environment}-postgres"
  tags = { project = "oficina-phase3", environment = var.environment, owner = "oficina-db-infra" }
}
resource "aws_db_subnet_group" "this" {
  name       = local.name
  subnet_ids = var.database_subnet_ids
  tags       = local.tags
}
resource "aws_security_group" "database" {
  name        = local.name
  description = "Private PostgreSQL ingress from reviewed workload/bootstrap groups"
  vpc_id      = var.vpc_id
  # No outbound initiation is required; SG state tracking permits replies.
  tags = local.tags
}
resource "aws_vpc_security_group_ingress_rule" "postgres" {
  for_each                     = toset(values(var.source_security_group_ids))
  security_group_id            = aws_security_group.database.id
  referenced_security_group_id = each.value
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "Reviewed same-environment PostgreSQL client"
  tags                         = local.tags
}
resource "aws_db_parameter_group" "this" {
  name   = local.name
  family = "postgres16"
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }
  parameter {
    name         = "ssl_min_protocol_version"
    value        = "TLSv1.2"
    apply_method = "pending-reboot"
  }
  tags = local.tags
}
resource "aws_db_instance" "this" {
  identifier                   = local.name
  engine                       = "postgres"
  engine_version               = "16.15"
  instance_class               = "db.t4g.micro"
  allocated_storage            = 20
  max_allocated_storage        = 0
  storage_type                 = "gp3"
  storage_encrypted            = true
  multi_az                     = false
  publicly_accessible          = false
  port                         = 5432
  db_name                      = "oficina"
  username                     = "oficina_bootstrap"
  manage_master_user_password  = true
  db_subnet_group_name         = aws_db_subnet_group.this.name
  vpc_security_group_ids       = [aws_security_group.database.id]
  parameter_group_name         = aws_db_parameter_group.this.name
  ca_cert_identifier           = "rds-ca-rsa2048-g1"
  backup_retention_period      = 1
  backup_window                = "03:00-04:00"
  maintenance_window           = "sun:04:30-sun:05:30"
  auto_minor_version_upgrade   = false
  allow_major_version_upgrade  = false
  apply_immediately            = false
  deletion_protection          = true
  skip_final_snapshot          = false
  final_snapshot_identifier    = "${local.name}-final"
  copy_tags_to_snapshot        = true
  performance_insights_enabled = false
  monitoring_interval          = 0
  tags                         = local.tags
}
