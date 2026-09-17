# DB requirement and evidence matrix

Source audit 2026-09-16 at `ed7f5df`; no AWS query or deployment evidence is added. [I3 source verification](i3-source-verification.md) and [historical R4 status](r4-local-status.json) retain their original meanings. The [central matrix](../../../Tech-challenge-15SOAT/docs/phase-3/evidence/requirements.md) tracks cross-owner gaps.

| Requirement | Source evidence | Acceptance gap |
| --- | --- | --- |
| Private encrypted managed DB | [Postgres module](../../infra/modules/postgres), [architecture](../architecture.md) | Current engine orderability, RDS service-linked role, subnet routes and real TLS/CA verification. |
| Separate environment lifecycle | [Environment roots](../../infra/environments), [verify script](../../tests/verify.ps1) | Reviewed plans and actual state/output receipts per environment. |
| Least-privilege schema/runtime roles | [Bootstrap contract](../../contracts/bootstrap.v1.json), [receipt checks](../../scripts/check-bootstrap-receipt.ps1) | APP-owned SQL/bootstrap execution and negative base-table/DDL privilege tests. |
| Safe output handoff | [Exporter](../../scripts/export-outputs.ps1), [output/bootstrap tests](../../tests/outputs-bootstrap-contract.ps1) | Versioned publication and consumer verification of the exact executed release. |
| CI/CD and operations | [Deployment runbook](../deployment.md), [pipeline tests](../../tests/pipeline-contract.ps1), [lock race contract](../../tests/deployment-lock-race-contract.ps1) | External branch/environment protection, updated executor digest, restore test and measured connection budget. |

The one-day backup retention and deletion protection are source settings, not a proven restore objective. Single-AZ is an accepted study tradeoff; do not call it high availability. Recovery/cleanup follows the [central runbook](../../../Tech-challenge-15SOAT/docs/phase-3/runbooks/release-operations.md) and requires explicit review of final snapshots and state preservation.
