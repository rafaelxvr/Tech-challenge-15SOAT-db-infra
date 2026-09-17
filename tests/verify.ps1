[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
& "$PSScriptRoot/workflow-context-contract.ps1"
& "$PSScriptRoot/source-package-contract.ps1"
& "$PSScriptRoot/cloud-window-tests.ps1"
& "$PSScriptRoot/pipeline-contract.ps1"
& "$PSScriptRoot/launcher-contract.ps1"
& "$PSScriptRoot/outputs-bootstrap-contract.ps1"
& terraform "-chdir=$repo" fmt -check -recursive
if ($LASTEXITCODE -ne 0) { throw 'Terraform formatting failed.' }
foreach ($relative in @('infra/modules/postgres', 'infra/environments/staging', 'infra/environments/production')) {
    $root = Join-Path $repo $relative
    & terraform "-chdir=$root" init -backend=false -input=false -lockfile=readonly
    if ($LASTEXITCODE -ne 0) { throw "Terraform init failed for $relative." }
    & terraform "-chdir=$root" validate -no-color
    if ($LASTEXITCODE -ne 0) { throw "Terraform validate failed for $relative." }
    & terraform "-chdir=$root" test -no-color
    if ($LASTEXITCODE -ne 0) { throw "Terraform mock tests failed for $relative." }
}
Write-Output 'I3 source verification passed. No AWS apply or real PostgreSQL permission test was performed.'
