# APP bootstrap receipt V1/V2 consumer

`scripts/check-bootstrap-receipt.ps1` is this repository's APP bootstrap receipt consumer. It validates local reviewed files only; it does not read Secrets Manager, connect to PostgreSQL, generate a receipt or publish an artifact. V1 remains accepted under its existing exact-field contract. V2 is explicitly dispatched through [bootstrap.v2.json](../contracts/bootstrap.v2.json); unknown versions and mixed V1/V2 field sets fail.

| Version | Accepted output shape | Interpretation |
| --- | --- | --- |
| 1 | Original seven schema/view/ARN fields from [bootstrap.v1.json](../contracts/bootstrap.v1.json) | Legacy reference receipt; no immutable credential version is inferred. |
| 2 | V8/V5/V7 and four exact ARN + `VersionId` pairs | Version-preserving APP bootstrap receipt; no stage aliases or silent downgrade. |

For V2, the four ARN fields are `migrationSecretArn`, `appSecretArn`, `authLookupSecretArn`, `notificationLookupSecretArn`. Each has a sibling `...SecretVersionId`. The corresponding Secrets Manager paths must be exactly `oficina/ENVIRONMENT/migration-SUFFIX`, `app-SUFFIX`, `auth-SUFFIX` and `notification-SUFFIX`, where SUFFIX is the real six-character service suffix. They must share the independently supplied RDS-managed master's account in us-east-1 and the requested environment. Version IDs are 32–64-character alphanumeric/hyphen identifiers matching the APP producer; `AWSCURRENT`, `AWSPREVIOUS`, missing versions and structured/plaintext credentials are rejected. Version IDs are scoped to their ARN and need not differ across separate secrets; all four ARNs must differ.

Both paths preserve checks for expected APP source commit/environment, complete exact fields, distinct same-account/environment role references, master-secret exclusion, receipt hash and pinned CA hash. Duplicate JSON keys (including case variants), non-scalar references and unknown fields fail before any output. V2 additionally checks the exact role path, immutable version syntax and V8/V5/V7. No master reference, username, password or unknown field may appear in the receipt. The separately supplied `MasterSecretArn` exists only to validate exclusion/account binding; it is never added to validated output.

Validation command (all files/hashes must come from reviewed evidence):

```powershell
./scripts/check-bootstrap-receipt.ps1 `
  -ReceiptFile ./review/app-bootstrap.json -ExpectedSha256 REVIEWED_RECEIPT_SHA256 `
  -Environment staging -SourceCommit REVIEWED_APP_COMMIT `
  -MasterSecretArn REVIEWED_RDS_MANAGED_MASTER_ARN `
  -CaBundleFile ./review/rds-ca.pem -ExpectedCaSha256 REVIEWED_CA_SHA256 `
  -OutputFile ./review/validated-app-bootstrap.json
```

`OutputFile` is optional and must not exist. If supplied, the checker copies the **same byte snapshot** it hashed and validated; the output checksum therefore equals the reviewed receipt checksum. It never invents VersionIds, strips fields, transforms V2 into V1 or overwrites prior evidence. Invalid input creates no output. This optional local export is not an S3 publication or deployment attestation.

`scripts/export-outputs.ps1` retains its separate DB Terraform connection-output contract and allowlist. That receipt intentionally includes the managed-master ARN so APP's private bootstrap can consume it; it must never be confused with the APP runtime-reference receipt, where master is forbidden. The DB deployment's output publisher remains unchanged. Auditing the current K8S and FUN source found no APP bootstrap-receipt parser to upgrade: their infrastructure/output manifests use separate schemas. Do not add runtime credentials to platform allowlists or route a V2 bootstrap receipt into those unrelated exporters. Future consumers must validate V2 explicitly and preserve each ARN/version pair.

The APP producer has local PostgreSQL role tests; this checker only proves reference/packaging integrity. It cannot prove that an ARN/version exists, that SQL grants executed, or that its receipt is authorized beyond the supplied reviewed hashes. Staging still needs the actual bootstrap artifact, versioned secret references, private SQL/TLS proof, I6 bootstrap integration and reviewed publication/consumer wiring. No live receipt is supplied by this change.

Run `pwsh -File tests/outputs-bootstrap-contract.ps1`: it includes [V1/V2 compatibility and denial tests](../tests/bootstrap-v2-contract.ps1), old V1 safeguards and DB Terraform export tests. All fixtures are synthetic local test data; AWS calls are forbidden.
