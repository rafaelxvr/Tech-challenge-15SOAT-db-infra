mock_provider "aws" {}
variables {
  account_id          = "123456789012"
  vpc_id              = "vpc-0123456789abcdef0"
  database_subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  source_security_group_ids = {
    app          = "sg-0123456789abcdef0"
    auth         = "sg-0123456789abcdef1"
    notification = "sg-0123456789abcdef2"
    bootstrap    = "sg-0123456789abcdef3"
  }
}
run "exports_only_connection_references" {
  command = plan
  assert {
    condition     = output.db_port == 5432 && output.db_name == "oficina"
    error_message = "Root must expose the managed database connection contract."
  }
}
run "reject_unverified_account" {
  command = plan
  variables { account_id = "root" }
  expect_failures = [var.account_id]
}
