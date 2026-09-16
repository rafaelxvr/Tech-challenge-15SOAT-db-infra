output "db_endpoint" { value = aws_db_instance.this.address }
output "db_port" { value = aws_db_instance.this.port }
output "db_name" { value = aws_db_instance.this.db_name }
# This is metadata only. Never read secret versions in Terraform.
output "master_secret_arn" { value = aws_db_instance.this.master_user_secret[0].secret_arn }
output "database_security_group_id" { value = aws_security_group.database.id }
