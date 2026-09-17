[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$check = Join-Path $PSScriptRoot '../scripts/check-workflow-context.ps1'
$count = 0
foreach ($environment in @('staging','production')) {
    $expected = if ($environment -eq 'staging') { 'refs/heads/develop' } else { 'refs/heads/main' }
    & $check -Environment $environment -EventName push -BranchRef $expected | Out-Null
    $count++
    foreach ($eventName in @('pull_request','pull_request_target','schedule')) {
        $rejected = $false
        try { & $check -Environment $environment -EventName $eventName -BranchRef $expected | Out-Null } catch { $rejected = $true }
        if (-not $rejected) { throw "Unexpected deploy context: $eventName/$environment" }; $count++
    }
    foreach ($branch in @('refs/heads/master','refs/heads/feature','refs/tags/main', $(if ($environment -eq 'staging') {'refs/heads/main'}else{'refs/heads/develop'}))) {
        $rejected = $false
        try { & $check -Environment $environment -EventName push -BranchRef $branch | Out-Null } catch { $rejected = $true }
        if (-not $rejected) { throw "Unexpected deploy branch: $branch/$environment" }; $count++
    }
}
$rejected = $false
try { & $check -Environment staging -EventName workflow_dispatch -BranchRef 'refs/heads/develop' -DispatchApproval 'STAGING_ONLY' | Out-Null } catch { $rejected = $true }
if ($rejected) { throw 'Approved manual staging rehearsal context was rejected.' }
foreach ($approval in @('', 'staging_only', 'STAGING_ONLY ')) {
    $rejected = $false
    try { & $check -Environment staging -EventName workflow_dispatch -BranchRef 'refs/heads/develop' -DispatchApproval $approval | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw "Unexpected manual staging approval: '$approval'" }
}
$rejected = $false
try { & $check -Environment production -EventName workflow_dispatch -BranchRef 'refs/heads/develop' -DispatchApproval 'STAGING_ONLY' | Out-Null } catch { $rejected = $true }
if (-not $rejected) { throw 'Manual production deployment context was accepted.' }
$repo = Split-Path -Parent $PSScriptRoot
$workflowPath = Join-Path $repo '.github/workflows/ci-cd.yml'
if (-not (Test-Path -LiteralPath $workflowPath)) { $workflowPath = Join-Path $repo '.github/workflows/ci.yml' }
$workflow = Get-Content -LiteralPath $workflowPath -Raw
if ($workflow -match 'pull_request_target|AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|refs/heads/master') { throw 'Workflow contains an unapproved event, branch or fixed deployment credential.' }
foreach ($required in @('workflow_dispatch:', 'confirm_staging:', 'STAGING_ONLY')) { if (-not $workflow.Contains($required)) { throw "Workflow lacks $required." } }
foreach ($job in ($workflow -split '(?m)(?=^  [a-z][a-z0-9-]+:\s*$)')) {
    if ($job -notmatch 'id-token: write|packages: write') { continue }
    if ($job -notmatch "github.event_name == 'push'") { throw 'A pull request could receive a publishing/deployment identity.' }
    if ($job -match 'id-token: write') {
        if ($job -notmatch 'cancel-in-progress: false|check-workflow-context.ps1') { throw 'Deployment needs non-cancelling concurrency and an explicit context guard.' }
        foreach ($required in @('cancel-in-progress: false','check-workflow-context.ps1','needs: verify')) {
            if (-not $job.Contains($required)) { throw "Deployment job lacks $required." }
        }
        if ($job -match 'environment: production' -and $job -notmatch "github.ref == 'refs/heads/main'") { throw 'Production job must require main.' }
        if ($job -match 'environment: production' -and $job -notmatch "vars.PRODUCTION_DEPLOYMENT_ENABLED == 'true'") { throw 'Production job must require the explicit activation flag.' }
        if ($job -match 'environment: staging') {
            if ($job -notmatch "github.ref == 'refs/heads/develop'") { throw 'Staging job must require develop.' }
            if ($job -notmatch "inputs.confirm_staging == 'STAGING_ONLY'") { throw 'Manual staging runs need the explicit STAGING_ONLY approval.' }
        }
        if ($job -match 'environment: production' -and $job -match 'workflow_dispatch') { throw 'Production must remain push-only.' }
    }
}
Write-Output "PASS: $count branch/event mapping contracts and workflow identity boundaries."
