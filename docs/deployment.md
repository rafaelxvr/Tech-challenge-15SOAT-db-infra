# DB release controls and platform prerequisites

Authoring I3 never applies AWS resources. External deployment requires reviewed account/window/permissions and protected GitHub settings. No existing evidence file is proof of a current cloud window.

After APP bootstrap, follow the [explicit V1/V2 receipt validation and optional local export](bootstrap-receipts.md). V2 keeps exact credential ARN/VersionId pairs; the separate DB Terraform connection-output publisher remains unchanged. Receipt validation alone does not authorize SQL execution or publication.

| Environment | CodeBuild project | Source prefix | S3 state key | Trusted tfvars path |
|---|---|---|---|---|
| staging | oficina-phase3-oficina-db-infra-staging-deploy | releases/database/staging | database/staging.tfstate | /tmp/oficina/database_staging.tfvars.json |
| production | oficina-phase3-oficina-db-infra-production-deploy | releases/database/production | database/production.tfstate | /tmp/oficina/database_production.tfvars.json |

The platform-owned inline buildspec must select these paths and its pinned deployer image independently of StartBuild environment overrides. Its checksum guard downloads source, manifest and tfvars by immutable S3 VersionId before invoking this repository's `scripts/deploy.ps1`. The archive `buildspec.deploy.yml` is inert. The deploy adapter validates its exact state key and derived `.tflock`, acquires the shared foundation lock, initializes the committed provider lock, validates, plans and applies only that saved plan when the trusted executor supplies `-ApplyReviewedPlan`. All Terraform path/value arguments are quoted.

Before apply, the adapter rechecks orderability of 16.15/db.t4g.micro/encrypted 20 GiB gp3 in us-east-1 and fails if unavailable. It does not auto-select another engine. After successful apply it publishes only allowlisted connection references to `releases/database/{environment}/outputs/{sourceCommit}.json`, with S3 version and hash receipt. Publication failure fails the build.

## Protected configuration

GitHub staging accepts develop and production accepts main; enforce PR review/checks and restricted bypass externally. PR verification receives no OIDC deployment identity. Required per-environment variables are `AWS_LAUNCHER_ROLE_ARN`, `ARTIFACT_BUCKET`, `SOURCE_PREFIX`, `CODEBUILD_PROJECT`, `DEPLOYER_IMAGE_DIGEST` and `FOUNDATION_OUTPUT_RECEIPT_JSON`. Protected `TERRAFORM_TFVARS_JSON` contains only verified `account_id` and `source_security_group_ids`; the resolver supplies VPC and DB subnet IDs from the immutable foundation receipt. `CLOUD_WINDOW_EVIDENCE_JSON` must be fresh/open. Numeric-budget authorization and explicit billing acknowledgment are supported; acknowledgment authorizes only study staging, never production.

Production also needs `STAGING_PROMOTION_KEY`, `STAGING_PROMOTION_VERSION_ID` and `STAGING_PROMOTION_SHA256`. The verifier downloads and checks the named successful staging receipt and its named manifest. ZIPs use tree content and fixed timestamps, so unchanged trees remain byte-identical across merge commits; changed content must pass staging again. Launcher waits for terminal CodeBuild success before publishing promotion evidence; StartBuild alone is not success.

## Exact external permission dependencies

The platform owns executor/launcher policies. Its current DB profile must be reviewed for these required provider operations before live use; this repository does not grant them:

| Purpose | Required actions / scope |
|---|---|
| RDS | DescribeDBInstances, DescribeDBSubnetGroups, DescribeDBParameterGroups, DescribeDBParameters, DescribeOrderableDBInstanceOptions, DescribeDBEngineVersions, ListTagsForResource; supported describe calls use Resource * |
| Named DB resources | Create/Modify/Delete DBInstance, DBSubnetGroup and DBParameterGroup; Modify/ResetDBParameterGroup; AddTagsToResource/RemoveTagsFromResource; scope named `oficina-phase3-{environment}-postgres` ARNs and creation request tags where supported |
| DB SGs | Create/DeleteSecurityGroup, Authorize/RevokeSecurityGroupIngress, DescribeSecurityGroupRules, ModifySecurityGroupRules, CreateTags/DeleteTags; scope reviewed VPC/SG/request and resource tags as supported; describes use Resource * |
| Managed master secret | RDS documented Secrets Manager CreateSecret/TagResource and KMS DescribeKey integration permissions for RDS-managed credentials; ARN pattern is RDS-managed, not the runtime `oficina/{environment}` secret namespace; no GetSecretValue needed by Terraform |
| Artifacts / coordination | Read named source/manifest/config versions; PutObject only DB output prefix; Get/Put/Delete shared foundation lock with conditional-create ownership; Get/Put state and Get/Put/Delete exact state .tflock; never arbitrary state deletion |

Confirm the RDS service-linked role exists or arrange its one-time service-scoped bootstrap. Confirm provider-required calls against a reviewed plan/service authorization; the table is a dependency checklist, not a wildcard policy. IAM deny feedback must not be resolved with admin access.

Creation order: foundation/executors → DB RDS → APP schema/roles/views → functions → app rollout. DB does not read another repository's full Terraform state. The master secret is not a runtime connection credential.

## Local verification

Run `pwsh -NoProfile -File tests/verify.ps1`. It tests PowerShell contracts, native Terraform output argument handling, offline launcher terminal outcomes, and mock-provider plans for module plus both roots. Init uses backend=false/read-only provider locks. Refresh cross-platform checksums deliberately using `terraform providers lock -platform=windows_amd64 -platform=linux_amd64` in each root/module; review the lockfile diff.

R4 still must demonstrate live VPC isolation, engine availability, private TLS/CA validation, APP SQL permission tests, real connection counts, actual branch/environment protections, approved window, deployment/rollback and output handoff. No such outcome is implied by mocked tests.

## I7 source hardening

Before any OIDC request, each deployment job independently checks its exact push/branch/environment context with `check-workflow-context.ps1`. PRs, tags, manual dispatch and legacy master cannot pass that guard. Non-cancelling environment concurrency, named S3 object versions, checksum bootstrap, terminal CodeBuild polling and staging promotion receipt verification remain required.

`package-source.ps1` resolves the reviewed commit to its tree and uses a fixed archive timestamp. Tests prove that an unchanged merge preserves artifact bytes and a changed tree produces a different digest. Production still requires the successful immutable staging receipt; deterministic packaging does not waive that proof. The package helper never archives the mutable working directory.

Record actual repository visibility, immutable OIDC subject, branch ruleset/protection IDs, required checks/reviews and restricted bypass, plus develop-only staging and main-only production environment policies during external setup. Source changes neither configure those protections nor authorize production. The APP/FUN cloud adapters remain separately fail-closed pending their documented migration/ownership and execution prerequisites; I7 across all four owners is therefore partial, not evidence of eight successful cloud deployments.

Run `tests/source-package-contract.ps1`, `tests/workflow-context-contract.ps1` and the existing pipeline contract suite. Output tests reject sensitive allowlisted fields in addition to filtering unknown credentials/state fields. No AWS API call or cloud deployment is needed for these local proofs.

Lock release checks the owner and observed ETag from the same HEAD, then sends `DeleteObject --if-match` with that exact ETag. A replacement owner changes the lock payload; S3 rejects the stale conditional delete. Missing/wildcard ETags and every delete failure stop release without retrying unconditionally. No specific object version is permanently deleted. The executor AWS CLI must support [S3 DeleteObject If-Match](https://docs.aws.amazon.com/cli/latest/reference/s3api/delete-object.html); an older CLI fails closed and must be updated in its separate reviewed image release. Offline lock mutations use a shared named mutex around owner comparison/deletion. `tests/deployment-lock-race-contract.ps1` deterministically replaces owner A with B between HEAD and DELETE and proves B survives; the old implementation fails this test. AWS calls in this proof are mocked.
