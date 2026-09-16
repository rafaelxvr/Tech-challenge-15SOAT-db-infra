variable "environment" {
  type = string
  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "An explicit staging or production environment is required."
  }
}
variable "vpc_id" {
  type = string
  validation {
    condition     = can(regex("^vpc-[0-9a-f]{8,17}$", var.vpc_id))
    error_message = "Use the reviewed foundation VPC ID."
  }
}
variable "database_subnet_ids" {
  type = set(string)
  validation {
    condition     = length(var.database_subnet_ids) >= 2 && alltrue([for s in var.database_subnet_ids : can(regex("^subnet-[0-9a-f]{8,17}$", s))])
    error_message = "Supply at least two isolated database subnets from the foundation receipt."
  }
}
variable "source_security_group_ids" {
  description = "Reviewed same-environment app, auth, notification and private bootstrap sources; no CIDRs."
  type        = object({ app = string, auth = string, notification = string, bootstrap = string })
  validation {
    condition     = alltrue([for s in values(var.source_security_group_ids) : can(regex("^sg-[0-9a-f]{8,17}$", s))])
    error_message = "Every source must be an explicit approved security group ID."
  }
}
