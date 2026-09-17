[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('staging','production')][string]$Environment,
    [string]$EventName = $env:GITHUB_EVENT_NAME,
    [string]$BranchRef = $env:GITHUB_REF,
    [string]$DispatchApproval = $env:INPUT_CONFIRM_STAGING
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$expected = if ($Environment -ceq 'staging') { 'refs/heads/develop' } else { 'refs/heads/main' }
$automatic = $EventName -ceq 'push' -and $BranchRef -ceq $expected
$manualStaging = $Environment -ceq 'staging' -and $EventName -ceq 'workflow_dispatch' -and $BranchRef -ceq 'refs/heads/develop' -and $DispatchApproval -ceq 'STAGING_ONLY'
if (-not ($automatic -or $manualStaging)) { throw 'Deployment context must be a push to the exact protected environment branch; manual runs are limited to staging develop rehearsals.' }
if ($manualStaging) {
    Write-Output 'Manual staging rehearsal context validated; production remains push-only.'
}
else {
    Write-Output 'Protected branch mapping validated; external GitHub protection is still required.'
}
