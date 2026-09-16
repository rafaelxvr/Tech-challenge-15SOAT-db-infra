provider "aws" {
  region              = "us-east-1"
  allowed_account_ids = [var.account_id]
}
module "postgres" {
  source                    = "../../modules/postgres"
  environment               = "production"
  vpc_id                    = var.vpc_id
  database_subnet_ids       = var.database_subnet_ids
  source_security_group_ids = var.source_security_group_ids
}
