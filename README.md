# Oficina database infrastructure

This repository owns the managed PostgreSQL infrastructure boundary for Oficina staging and production. Terraform roots and database validation workflows arrive in Phase 3 task I3; `infra/` is reserved for that versioned infrastructure code.

APP remains the owner of Flyway migrations and database view contracts. Remote owner, visibility, protected branches, environment credentials, and deployment targets are release prerequisites and are intentionally unset in this local bootstrap.
