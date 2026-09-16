[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$temp = Join-Path ([IO.Path]::GetTempPath()) ('oficina-db-launcher-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temp | Out-Null
$global:DbLauncherFixture = @{ calls = [Collections.Generic.List[object]]::new(); mode = 'success' }

function aws {
    $a = @($args); $global:DbLauncherFixture.calls.Add($a); $global:LASTEXITCODE = 0
    switch ("$($a[0]) $($a[1])") {
        's3api put-object' {
            if ($global:DbLauncherFixture.mode -eq 'unversioned') { return '{}' }
            return '{"VersionId":"fixture-object-v"}'
        }
        'codebuild start-build' { return '{"build":{"id":"oficina-phase3-oficina-db-infra-staging-deploy:fixture"}}' }
        'codebuild batch-get-builds' {
            if ($global:DbLauncherFixture.mode -eq 'failed-build') { return '{"builds":[{"buildStatus":"FAILED"}]}' }
            return '{"builds":[{"buildStatus":"SUCCEEDED"}]}'
        }
        default { throw 'Unexpected AWS operation in offline launcher fixture.' }
    }
}
function Start-Sleep { param($Seconds) }
function Save($value, $name) { $p = Join-Path $temp $name; $value | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $p -NoNewline; return $p }
function Sha($path) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
try {
    $source = Join-Path $temp 'bundle.zip'; 'fixture' | Set-Content -LiteralPath $source -NoNewline
    $sha = Sha $source; $commit = 'a' * 40
    $manifest = Save @{ schemaVersion = 1; environment = 'staging'; sourceCommit = $commit; artifactSha256 = $sha; deployerImageDigest = ('sha256:' + ('b' * 64)); contractVersion = 'phase3-v2'; migrationVersion = 'database-infra-v1'; promotedFromStaging = $false } 'manifest.json'
    $tfvars = Save @{ account_id = '123456789012'; vpc_id = 'vpc-0123456789abcdef0'; database_subnet_ids = @('subnet-0123456789abcdef0','subnet-0123456789abcdef1'); source_security_group_ids = @{ app = 'sg-0123456789abcdef0'; auth = 'sg-0123456789abcdef1'; notification = 'sg-0123456789abcdef2'; bootstrap = 'sg-0123456789abcdef3' } } 'inputs.json'
    $now = [datetime]::UtcNow
    $window = Save @{ windowStartUtc = $now.AddMinutes(-1).ToString('o'); windowEndUtc = $now.AddMinutes(5).ToString('o'); recordedAtUtc = $now.ToString('o'); accountEvidenceReference = 'fixture'; projectAllowanceUsd = 80; reserveUsd = 20; currentEstimatedSpendUsd = 0 } 'window.json'
    $launch = @{ Environment = 'staging'; SourceZip = $source; ExpectedSha256 = $sha; ReleaseManifest = $manifest; ExpectedManifestSha256 = (Sha $manifest); Bucket = 'oficina-artifacts-test'; SourcePrefix = 'releases/database/staging'; ProjectName = 'oficina-phase3-oficina-db-infra-staging-deploy'; DeployerImageDigest = ('b' * 64); SourceCommit = $commit; CloudWindowEvidenceFile = $window; TerraformVariablesFile = $tfvars }
    foreach ($mode in @('success','failed-build','unversioned')) {
        $global:DbLauncherFixture.mode = $mode; $global:DbLauncherFixture.calls.Clear(); $failed = $false
        try { & "$repo/scripts/start-deploy.ps1" @launch | Out-Null } catch { if ($mode -eq 'success') { throw }; $failed = $true }
        if (($mode -eq 'success' -and $failed) -or ($mode -ne 'success' -and -not $failed)) { throw "Launcher did not propagate $mode outcome." }
        $starts = @($global:DbLauncherFixture.calls | Where-Object { $_[0] -eq 'codebuild' -and $_[1] -eq 'start-build' })
        if ($mode -eq 'unversioned') {
            if ($starts.Count -ne 0) { throw 'Unversioned source must stop before StartBuild.' }
        } else {
            if ($starts.Count -ne 1) { throw 'Exactly one reviewed build must launch.' }
            $start = $starts[0]; $versionIndex = [Array]::IndexOf($start, '--source-version')
            if ($versionIndex -lt 0 -or $start[$versionIndex+1] -cne 'fixture-object-v' -or $start -contains '--buildspec-override') { throw 'CodeBuild must consume the exact version through its platform-owned bootstrap.' }
            $promotions = @($global:DbLauncherFixture.calls | Where-Object { $_[0] -eq 's3api' -and ($_[([Array]::IndexOf($_, '--key'))+1]) -like '*/promotions/*' })
            if (($mode -eq 'success' -and $promotions.Count -ne 1) -or ($mode -eq 'failed-build' -and $promotions.Count -ne 0)) { throw 'Only SUCCEEDED builds can publish promotion evidence.' }
        }
    }
    Write-Output 'DB launcher lifecycle: PASS (version binding, terminal failure propagation, successful promotion only; AWS stubbed).'
} finally {
    $resolved = [IO.Path]::GetFullPath($temp)
    if (-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase) -or -not [IO.Path]::GetFileName($resolved).StartsWith('oficina-db-launcher-')) { throw 'Unsafe launcher fixture cleanup.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
