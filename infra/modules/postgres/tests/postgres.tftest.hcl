mock_provider "aws" {}
variables {
  environment         = "staging"
  vpc_id              = "vpc-0123456789abcdef0"
  database_subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  source_security_group_ids = {
    app          = "sg-0123456789abcdef0"
    auth         = "sg-0123456789abcdef1"
    notification = "sg-0123456789abcdef2"
    bootstrap    = "sg-0123456789abcdef3"
  }
}
run "private_bounded_database" {
  command = plan
  assert {
    condition     = aws_db_instance.this.engine == "postgres" && aws_db_instance.this.engine_version == "16.15" && aws_db_instance.this.instance_class == "db.t4g.micro" && !aws_db_instance.this.multi_az
    error_message = "Only the approved PostgreSQL study profile is permitted."
  }
  assert {
    condition     = !aws_db_instance.this.publicly_accessible && aws_db_instance.this.storage_encrypted && aws_db_instance.this.allocated_storage == 20 && aws_db_instance.this.storage_type == "gp3" && aws_db_instance.this.max_allocated_storage == 0
    error_message = "Database storage must be private, encrypted and bounded to 20 GiB."
  }
  assert {
    condition     = aws_db_instance.this.manage_master_user_password && aws_db_instance.this.password == null && aws_db_instance.this.backup_retention_period == 1 && !aws_db_instance.this.auto_minor_version_upgrade
    error_message = "RDS owns the master credential; backups and engine upgrades remain reviewed."
  }
  assert {
    condition     = aws_db_instance.this.deletion_protection && !aws_db_instance.this.skip_final_snapshot && aws_db_instance.this.final_snapshot_identifier != null
    error_message = "Deletion requires a separately reviewed protection change and final snapshot."
  }
  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.postgres) == 4 && alltrue([for r in aws_vpc_security_group_ingress_rule.postgres : r.from_port == 5432 && r.to_port == 5432 && r.ip_protocol == "tcp" && r.cidr_ipv4 == null && r.cidr_ipv6 == null && contains(values(var.source_security_group_ids), r.referenced_security_group_id)])
    error_message = "Only approved app/function/bootstrap security groups can enter PostgreSQL."
  }
  assert {
    condition     = contains([for p in aws_db_parameter_group.this.parameter : "${p.name}=${p.value}"], "rds.force_ssl=1") && contains([for p in aws_db_parameter_group.this.parameter : "${p.name}=${p.value}"], "ssl_min_protocol_version=TLSv1.2")
    error_message = "TLS and certificate-verifying clients are required."
  }
}
run "reject_environment" {
  command = plan
  variables { environment = "development" }
  expect_failures = [var.environment]
}
run "reject_public_cidr_as_source" {
  command = plan
  variables {
    source_security_group_ids = {
      app          = "0.0.0.0/0"
      auth         = "sg-0123456789abcdef1"
      notification = "sg-0123456789abcdef2"
      bootstrap    = "sg-0123456789abcdef3"
    }
  }
  expect_failures = [var.source_security_group_ids]
}
run "reject_single_subnet" {
  command = plan
  variables { database_subnet_ids = ["subnet-0123456789abcdef0"] }
  expect_failures = [var.database_subnet_ids]
}
