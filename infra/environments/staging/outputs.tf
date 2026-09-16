output "db_endpoint" { value = module.postgres.db_endpoint }
output "db_port" { value = module.postgres.db_port }
output "db_name" { value = module.postgres.db_name }
# This is metadata only. Never read secret versions in Terraform.
output "master_secret_arn" { value = module.postgres.master_secret_arn }
output "database_security_group_id" { value = module.postgres.database_security_group_id }
