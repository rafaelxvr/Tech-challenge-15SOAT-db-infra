# Staging database platform acceptance — 2026-09-17

Generated from the successful staging rehearsal for `oficina-db-infra`. This record contains identifiers and operational metadata only; no secret values were retrieved or recorded.

## Rehearsal evidence

| Item | Evidence |
|---|---|
| GitHub workflow | [`ci-cd` run 35288193611](https://github.com/rafaelxvr/Tech-challenge-15SOAT-db-infra/actions/runs/35288193611) |
| Source branch / commit | `develop` / `ef80c09e60302ec3d554c12fbba573bfe689b72f` |
| Local-contracts job | `success` |
| Staging deployment job | `success` |
| Production deployment job | `skipped` |
| Private executor | `oficina-phase3-oficina-db-infra-staging-deploy:f426eb8b-f880-41a5-9981-ee2967768a4b` |
| CodeBuild result | `SUCCEEDED` |
| CodeBuild source version | `6ZcYF335Cmk62pX1YAQw68Vj39l9Fg6V` |

## Immutable handoff records

| Record | S3 key | Version ID |
|---|---|---|
| Terraform outputs | `releases/database/staging/outputs/ef80c09e60302ec3d554c12fbba573bfe689b72f.json` | `.7yzVzz2BxyShD2vXRRReXhPtVEUC_VY` |
| Staging promotion | `releases/database/staging/promotions/ef80c09e60302ec3d554c12fbba573bfe689b72f.json` | `qPHn1vzaLLrLXLHlMtNK6g89nMCMMRLt` |
| Release manifest | `releases/database/staging/manifests/ef80c09e60302ec3d554c12fbba573bfe689b72f.json` | `0YZRqDDPSVGZBMDGvTKboTVeARdjhC.2` |
| Terraform state | `database/staging.tfstate` in `oficina-phase3-state-16225b7358` | `rCugY5f8mt4Xxi_PngEpZ382NZe5nmvU` |

The promotion receipt binds the staging source commit, artifact digest `89eff261b30741671650490d1aca5328115dd4baa12d60fed18b5d1f4832dc6e`, successful CodeBuild status, and the private executor build identity. The output receipt exposes the allowlisted connection-reference fields `dbEndpoint`, `dbPort`, `dbName`, `masterSecretArn`, and `databaseSecurityGroupId`; only the nonsecret endpoint metadata is repeated below.

## RDS staging metadata

| Field | Observed value |
|---|---|
| Instance | `oficina-phase3-staging-postgres` |
| Status | `available` |
| Engine | `postgres` `16.15` |
| Endpoint | `oficina-phase3-staging-postgres.cgbomcuoit0y.us-east-1.rds.amazonaws.com` |
| Port / database | `5432` / `oficina` |
| Instance class / storage | `db.t4g.micro` / `20 GiB` |
| Availability zone | `us-east-1b` |
| Encryption | `true` |
| Publicly accessible | `false` |

## Acceptance boundary

**DB infrastructure acceptance: PASS.** The reviewed `develop` workflow completed local contracts, launched the reviewed private staging executor, completed the Terraform deployment, published immutable output and promotion records, and the resulting managed RDS instance is available with the expected private PostgreSQL profile.

The following remain **NOT_RUN** in this record because this rehearsal did not directly evidence them:

- SQL migrations, role grants, and read-view permissions;
- APP bootstrap and application integration;
- Lambda/function notification behavior;
- application runtime health, API requests, or end-to-end order processing;
- TLS client verification and measured connection-budget behavior.

This evidence does not claim production deployment or production acceptance. Production was skipped by the workflow guard.
