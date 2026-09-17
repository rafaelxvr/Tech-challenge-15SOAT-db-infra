# I3 source verification — 2026-09-16

Branch: `codex/i3-managed-postgres`. Scope: oficina-db-infra only. No AWS provisioning, secret retrieval/decryption or changes in other repositories.

RED: `terraform -chdir=infra/modules/postgres test -no-color` with only provider/test declarations failed on undeclared aws_db_instance/parameter/security resources (0 passed, 1 failed, 3 skipped). GREEN: after implementation the same command passed all 4 runs. Each environment root subsequently passed validate and 2 mock plans.

Checks are reproducible with `pwsh -NoProfile -File tests/verify.ps1`: cloud-window matrix; 34 pipeline assertions including both exact database state keys/source prefix, invalid credential inputs, wrong region/lock/project, promotion and network artifact tampering; output/bootstrap tests with real local Terraform output, absolute/relative paths with spaces, sensitive-output filtering and distinct-role references; launcher execution against AWS stubs proving S3 version binding and terminal failure propagation; Terraform fmt/validate and 8 mocked plans. No provider mock is counted as a live deployment or PostgreSQL SQL integration test.

AWS provider 5.100.0 is locked for Linux amd64 and Windows amd64 in all three test roots; Terraform is pinned to 1.15.8. SQL/role code remains in APP's approved ownership boundary. Its missing bootstrap job/scripts/DatabaseRolesTest are an explicit integration dependency; the DB receipt validator only validates references and packaging hash.

Self-review: fixed resource profile has no credential/capacity input; private ingress uses explicit SG references; master value is never read; output exporter accepts exactly five nonsensitive references; source promotion is byte-bound; native PowerShell arguments quote -chdir/-var-file/-out; release config contains no invented active AWS IDs; mock values exist only in tests. Current platform policies require the documented DB parameter/SG/managed-secret/output permissions before a live run. Verified source does not remove that dependency.

Existing `r4-local-status.json` is historical NOT_RUN evidence and is retained as such. No live R4 evidence was produced by I3.
