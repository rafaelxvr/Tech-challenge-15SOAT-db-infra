[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'deployment-lock-race-contract.ps1')
$repo = Split-Path -Parent $PSScriptRoot
$temp = Join-Path ([IO.Path]::GetTempPath()) ('oficina-db-contract-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temp | Out-Null
$script:checks = 0
function Assert($condition, $message) { $script:checks++; if (-not $condition) { throw "ASSERTION FAILED: $message" } }
function Reject([scriptblock]$action, $message) { $script:checks++; try { & $action } catch { return }; throw "Expected rejection: $message" }
function Save($value, $name) { $path = Join-Path $temp $name; $value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -NoNewline; return $path }
function Sha($path) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
# Any unexpected AWS call fails immediately; all these tests are credential-free.
function aws { throw 'Offline tests must never contact AWS.' }
try {
    $commit = 'a' * 40
    $groups = @{ app = 'sg-0123456789abcdef0'; auth = 'sg-0123456789abcdef1'; notification = 'sg-0123456789abcdef2'; bootstrap = 'sg-0123456789abcdef3' }
    $inputs = @{ account_id = '123456789012'; vpc_id = 'vpc-0123456789abcdef0'; database_subnet_ids = @('subnet-0123456789abcdef0','subnet-0123456789abcdef1'); source_security_group_ids = $groups }
    $tfvars = Save $inputs 'reviewed inputs.json'
    & "$repo/scripts/check-database-inputs.ps1" -TerraformVariablesFile $tfvars | Out-Null
    $inputs.password = 'forbidden-fixture'
    $badInputs = Save $inputs 'bad-inputs.json'
    Reject { & "$repo/scripts/check-database-inputs.ps1" -TerraformVariablesFile $badInputs } 'credential input'
    $inputs.Remove('password')
    $bundle = Join-Path $temp 'bundle.zip'; 'source fixture' | Set-Content -LiteralPath $bundle -NoNewline
    $digest = Sha $bundle
    $now = [datetime]::UtcNow
    $evidenceObject = @{ windowStartUtc = $now.AddMinutes(-2).ToString('o'); windowEndUtc = $now.AddMinutes(30).ToString('o'); recordedAtUtc = $now.ToString('o'); accountEvidenceReference = 'test-only'; costAuthorization = 'billing-acknowledgment'; environment = 'staging'; scope = 'study-staging'; billingBeyondFreeCreditsAcknowledged = $true; approvalReference = 'test-only-approval' }
    $evidence = Save $evidenceObject 'window.json'
    $manifestObject = @{ schemaVersion = 1; environment = 'staging'; sourceCommit = $commit; artifactSha256 = $digest; deployerImageDigest = ('sha256:' + ('b' * 64)); contractVersion = 'phase3-v2'; migrationVersion = 'database-infra-v1'; promotedFromStaging = $false }
    $manifest = Save $manifestObject 'manifest.json'
    $launch = @{ Environment = 'staging'; SourceZip = $bundle; ExpectedSha256 = $digest; ReleaseManifest = $manifest; ExpectedManifestSha256 = (Sha $manifest); Bucket = 'oficina-artifacts-test'; SourcePrefix = 'releases/database/staging'; ProjectName = 'oficina-phase3-oficina-db-infra-staging-deploy'; DeployerImageDigest = ('b' * 64); SourceCommit = $commit; CloudWindowEvidenceFile = $evidence; TerraformVariablesFile = $tfvars; DryRun = $true }
    & "$repo/scripts/start-deploy.ps1" @launch | Out-Null
    foreach ($entry in @(@('SourcePrefix','releases/db/staging'), @('ProjectName','oficina-phase3-oficina-db-infra-production-deploy'), @('ExpectedSha256',('c' * 64)), @('ExpectedManifestSha256',('d' * 64)))) {
        $bad = $launch.Clone(); $bad[$entry[0]] = $entry[1]
        Reject { & "$repo/scripts/start-deploy.ps1" @bad } "launcher $($entry[0])"
    }
    $evidenceObject.windowEndUtc = $now.AddMinutes(-1).ToString('o')
    $null = Save $evidenceObject 'window.json'
    Reject { & "$repo/scripts/start-deploy.ps1" @launch } 'closed window'
    $evidenceObject.windowEndUtc = $now.AddMinutes(30).ToString('o')
    $null = Save $evidenceObject 'window.json'
    foreach ($environment in @('staging','production')) {
        $m = $manifestObject.Clone(); $m.environment = $environment
        if ($environment -eq 'production') {
            $m.promotedFromStaging = $true; $m.stagingManifestSha256 = 'c' * 64; $m.stagingArtifactSha256 = $digest; $m.stagingPromotionSha256 = 'd' * 64
            $m.stagingPromotionKey = "releases/database/staging/promotions/$commit.json"; $m.stagingPromotionVersionId = 'fixture-version'
        }
        $path = Save $m "$environment-manifest.json"
        $deploy = @{ Environment = $environment; ReleaseManifest = $path; ExpectedSourceSha256 = $digest; ExpectedManifestSha256 = (Sha $path); SourceCommit = $commit; ExpectedDeployerImageDigest = $m.deployerImageDigest; TerraformVariablesFile = $tfvars; TerraformBackendBucket = 'oficina-state-test'; TerraformBackendKey = "database/$environment.tfstate"; TerraformBackendLockKey = "database/$environment.tfstate.tflock"; TerraformBackendRegion = 'us-east-1'; DryRun = $true }
        & "$repo/scripts/deploy.ps1" @deploy | Out-Null
        foreach ($key in @("db/$environment.tfstate", 'environments/staging.tfstate', "database/$(if($environment -eq 'staging'){'production'}else{'staging'}).tfstate")) {
            $bad = $deploy.Clone(); $bad.TerraformBackendKey = $key
            Reject { & "$repo/scripts/deploy.ps1" @bad } 'wrong state key'
        }
        $bad = $deploy.Clone(); $bad.TerraformBackendLockKey = 'database/other.tfstate.tflock'
        Reject { & "$repo/scripts/deploy.ps1" @bad } 'wrong lock key'
        $bad = $deploy.Clone(); $bad.TerraformBackendRegion = 'eu-west-1'
        Reject { & "$repo/scripts/deploy.ps1" @bad } 'wrong region'
    }
    # Promotion is bound to named immutable receipt AND staging manifest contents.
    $promotion = @{ schemaVersion = 1; environment = 'staging'; sourceCommit = $commit; artifactSha256 = $digest; buildStatus = 'SUCCEEDED'; codeBuildProjectName = $launch.ProjectName; codeBuildBuildId = "$($launch.ProjectName):fixture-build"; releaseManifestKey = "releases/database/staging/manifests/$commit.json"; releaseManifestVersionId = 'fixture-manifest-v'; releaseManifestSha256 = (Sha $manifest) }
    $promotionPath = Save $promotion 'promotion.json'
    $verifyPromotion = @{ Bucket = $launch.Bucket; PromotionKey = "releases/database/staging/promotions/$commit.json"; PromotionVersionId = 'fixture-v'; ExpectedPromotionSha256 = (Sha $promotionPath); ExpectedArtifactSha256 = $digest; OutputFile = (Join-Path $temp 'verified.json'); PromotionFileForTest = $promotionPath; StagingManifestFileForTest = $manifest }
    & "$repo/scripts/verify-staging-promotion.ps1" @verifyPromotion | Out-Null
    $promotion.buildStatus = 'FAILED'; $null = Save $promotion 'promotion.json'; $verifyPromotion.ExpectedPromotionSha256 = Sha $promotionPath
    Reject { & "$repo/scripts/verify-staging-promotion.ps1" @verifyPromotion } 'unsuccessful staging promotion'
    $foundation = Save @{ schemaVersion = 1; environment = 'foundation'; sourceCommit = $commit; outputs = @{ vpcId = $inputs.vpc_id; databaseSubnetIds = $inputs.database_subnet_ids } } 'foundation.json'
    $receipt = Save @{ schemaVersion = 1; kind = 'foundation-output'; environment = 'foundation'; sourceCommit = $commit; artifactBucket = $launch.Bucket; artifactKey = "releases/k8s/foundation/outputs/$commit.json"; artifactVersionId = 'foundation-v'; artifactSha256 = (Sha $foundation) } 'foundation-receipt.json'
    $base = Save @{ account_id = $inputs.account_id; source_security_group_ids = $groups } 'base.json'
    $resolve = @{ ArtifactBucket = $launch.Bucket; ReceiptFile = $receipt; BaseTerraformVariablesFile = $base; OutputTerraformVariablesFile = (Join-Path $temp 'resolved.json'); ArtifactFileForTest = $foundation }
    & "$repo/scripts/resolve-foundation-outputs.ps1" @resolve | Out-Null
    $resolve.BaseTerraformVariablesFile = $tfvars
    Reject { & "$repo/scripts/resolve-foundation-outputs.ps1" @resolve } 'network override'
    $resolve.BaseTerraformVariablesFile = $base
    Add-Content -LiteralPath $foundation -Value 'tampered'
    Reject { & "$repo/scripts/resolve-foundation-outputs.ps1" @resolve } 'foundation digest tampering'
    $lock = "$repo/scripts/deployment-lock.ps1"; $lockDir = Join-Path $temp 'locks'
    $owner = [guid]::NewGuid().ToString(); $other = [guid]::NewGuid().ToString()
    & $lock -Action Acquire -StateBucket 'oficina-state-test' -OwnerToken $owner -Offline -OfflineDirectory $lockDir | Out-Null
    Reject { & $lock -Action Acquire -StateBucket 'oficina-state-test' -OwnerToken $other -Offline -OfflineDirectory $lockDir } 'concurrent mutation'
    Reject { & $lock -Action Release -StateBucket 'oficina-state-test' -OwnerToken $other -Offline -OfflineDirectory $lockDir } 'foreign release'
    & $lock -Action Release -StateBucket 'oficina-state-test' -OwnerToken $owner -Offline -OfflineDirectory $lockDir | Out-Null
    $workflow = Get-Content -LiteralPath "$repo/.github/workflows/ci-cd.yml" -Raw
    foreach ($required in @("refs/heads/develop", "refs/heads/main", 'environment: staging', 'environment: production', 'cancel-in-progress: false', 'id-token: write', 'verify-staging-promotion.ps1', 'resolve-foundation-outputs.ps1', 'terraform_version: 1.15.8', './scripts/package-source.ps1', './scripts/check-workflow-context.ps1')) { Assert ($workflow.Contains($required)) "workflow needs $required" }
    $verifyJob = ($workflow -split '  deploy-staging:')[0]
    Assert (-not $verifyJob.Contains('id-token: write') -and -not $verifyJob.Contains('configure-aws-credentials')) 'PR verification has no deployment identity'
    foreach ($script in @('deploy.ps1','start-deploy.ps1')) {
        $source = Get-Content -LiteralPath "$repo/scripts/$script" -Raw
        Assert (-not $source.Contains('releases/db/') -and -not $source.Contains('"db/$Environment.tfstate"')) 'exact platform executor contract'
    }
    Write-Output "DB pipeline contracts: PASS ($script:checks assertions; no AWS calls)."
} finally {
    $resolved = [IO.Path]::GetFullPath($temp)
    if (-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase) -or -not [IO.Path]::GetFileName($resolved).StartsWith('oficina-db-contract-')) { throw 'Unsafe test cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
