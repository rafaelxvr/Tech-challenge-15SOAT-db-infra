# Database ownership and bootstrap contract

```mermaid
flowchart LR
  Foundation[Verified K8S foundation output] --> DB[DB Terraform]
  DB --> RDS[(Private managed PostgreSQL)]
  DB --> Refs[Versioned outputs.v1.json]
  Refs --> Job[APP private bootstrap job]
  Job --> Roles[Migration / app / auth / notification roles]
  Roles --> APP[APP migrations and views]
  APP --> Runtime[Restricted runtime access]
```

DB owns RDS, DB subnet/parameter/security groups and managed-master credential metadata. It never fetches secret values and does not own relational schema or runtime credential initialization. Exported fields are exactly `dbEndpoint`, `dbPort`, `dbName`, `masterSecretArn`, `databaseSecurityGroupId`. The endpoint is the hostname without port. A managed-secret ARN is an approved reference, not a password.

The source SG object names app/auth/notification/bootstrap explicitly. IDs come from reviewed same-environment platform references. Shared source IDs are deduplicated into one ingress rule; a shared worker/function SG alone cannot enforce namespace/environment isolation. Platform CNI/network policies and distinct credentials remain necessary. Subnets must be isolated across two AZs; reference validation here cannot prove route-table isolation without an actual foundation review.

## APP role bootstrap

The [V1/V2 handoff](bootstrap-receipts.md) has separate exact-field contracts. `scripts/check-bootstrap-receipt.ps1` checks the hash-bound APP receipt and pinned CA hash; V2 preserves all four ARN/immutable-VersionId pairs and V1 remains a distinct legacy format. DB does not substitute JSON validation for SQL permission tests.

The private APP bootstrap identity alone gets temporary `secretsmanager:GetSecretValue` for the exact managed-master ARN. Runtime identities get only their own secret ARN. RDS manages/rotates the master password; do not freeze it in tfvars, Terraform `secret_string`, output artifacts, command lines or logs.

APP performs idempotent role existence checks, reads externally provisioned credentials through exact reviewed secret versions, injects them through parameterized JDBC statements, and creates four separate non-superuser logins without CREATEDB/CREATEROLE. Migration owns the app schema and runs Flyway. App gets only required DML and sequence privileges. Auth gets schema USAGE and SELECT on `auth_cliente_snapshot`; notification gets SELECT on `notificacao_destinatario_snapshot`. Revoke PUBLIC CREATE/schema/default table privileges; new objects receive no automatic runtime grants.

APP's real PostgreSQL `DatabaseRolesTest` proves lookup-role base-table denial, runtime app DDL denial, and migration's owned-schema changes locally. Its standalone producer emits V2 schema/view versions and four distinct environment/account-scoped secret ARN/version pairs after runtime checks succeed. DB's checker rejects the master ARN, duplicate role references, another environment/account, unexpected fields and changed CA/receipt bytes. Actual staged bootstrap, external secret provisioning and runtime integration remain acceptance dependencies.

TLS clients use the actual RDS hostname, `sslmode=verify-full` and the SHA-256-pinned regional CA bundle from `https://truststore.pki.rds.amazonaws.com/us-east-1/us-east-1-bundle.pem`. The reviewed hash is recorded during APP packaging; no invented release digest is supplied. [AWS PostgreSQL TLS guidance](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/PostgreSQL.Concepts.General.SSL.html).

## Connection budget to measure at R4

App maximum is five connections per pod, including reports/publisher: staging 2 pods = 10; production 4 pods = 20. A temporary extra rollout pod adds 5 in its environment. Add migration/bootstrap sessions and at most one JDBC connection per Lambda execution environment, including warm-container churn; concurrency quotas do not bound retained idle connections. Measure each instance's `SHOW max_connections`, `pg_stat_activity` and reserved capacity under the actual rollout/churn scenario before acceptance. No RDS connection limit or timeout is claimed as measured.

Single-AZ DB, shared NAT and shared EKS are study limitations. A stop is not zero-cost teardown. Deletion needs a reviewed protection change and final-snapshot name review (the default final name cannot be reused if that snapshot exists).

## Technologies, Prerequisites and decision references

Technologies: PostgreSQL 16.15, Terraform 1.15.8 and AWS provider 5.100.0. Prerequisites: Terraform, PowerShell 7, reviewed foundation subnet/SG references and the RDS service-linked role prerequisite. This repository has no local API or Dockerfile; APP defines the [consumer API snapshot](../../Tech-challenge-15SOAT/docs/phase-3/api/contracts.md), [ER model](../../Tech-challenge-15SOAT/docs/phase-3/architecture/data-model.md) and migrations.

[PostgreSQL RFC 002](../../Tech-challenge-15SOAT/docs/rfcs/002-postgresql-model.md) chooses relational constraints/transactions over document or event-only storage. [ADR 005](../../Tech-challenge-15SOAT/docs/adrs/005-canonical-reporting.md) keeps canonical history authoritative rather than telemetry snapshots. Optimistic aggregate versions, current identity versions, actor checks and composite outbox/history FKs belong to APP migrations; provisioning RDS alone does not establish those invariants.

```mermaid
sequenceDiagram
  participant K as Foundation output publisher
  participant D as Protected DB executor
  participant R as Private RDS
  participant A as APP bootstrap owner
  K-->>D: Versioned hash-bound network references
  D->>D: Validate exact state and shared lock
  D->>R: Reviewed Terraform lifecycle
  D-->>A: Allowlisted endpoint and managed-secret ARN
  A->>R: Distinct roles and migrations after old-writer drain
  A->>R: Verify TLS and negative privilege tests
  A-->>A: Publish schema/view and runtime-secret references
```

The APP steps describe required orchestration; local adapter tests and receipt validation do not establish live bootstrap proof. Run `pwsh -File tests/verify.ps1` here. Follow [deployment prerequisites](deployment.md) and [requirement/evidence matrix](evidence/requirements.md); actual role grants, TLS and connection headroom remain staged acceptance work.
