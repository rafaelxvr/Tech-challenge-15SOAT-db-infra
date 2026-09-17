[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$temp=Join-Path ([IO.Path]::GetTempPath()) ('oficina-bootstrap-v2-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temp | Out-Null
function aws { throw 'Offline receipt tests forbid AWS.' }
$script:checks=0; $script:attempt=0
function Assert([bool]$Condition,[string]$Message) { if(-not $Condition){throw $Message}; $script:checks++ }
function Sha([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Reject([scriptblock]$Action) { $rejected=$false; try { & $Action | Out-Null } catch {$rejected=$true}; Assert $rejected 'Expected invalid receipt rejection.' }
$master='arn:aws:secretsmanager:us-east-1:123456789012:secret:rds!db-reviewed-AbCdEf'
$ca=Join-Path $temp 'ca.pem'; 'offline-public-ca-fixture' | Set-Content -LiteralPath $ca -NoNewline
$path=Join-Path $temp 'receipt.json'
function New-Fixture([int]$Version=2,[string]$Environment='staging') {
    $script:receipt=@{schemaVersion=$Version;environment=$Environment;sourceCommit=('a'*40);outputs=@{schemaVersion='V8';authViewVersion='V5';recipientViewVersion='V7'}}
    $roles=@{migrationSecret='migration';appSecret='app';authLookupSecret='auth';notificationLookupSecret='notification'}
    foreach($entry in $roles.GetEnumerator()) {
        $script:receipt.outputs[$entry.Key+'Arn']="arn:aws:secretsmanager:us-east-1:123456789012:secret:oficina/$Environment/$($entry.Value)-AbCdEf"
        # Version IDs need not be globally unique across distinct secrets; ARN+VersionId is the identity.
        if($Version -eq 2){$script:receipt.outputs[$entry.Key+'VersionId']='b'*32}
    }
    $script:check=@{ReceiptFile=$path;ExpectedSha256='';Environment=$Environment;SourceCommit=('a'*40);MasterSecretArn=$master;CaBundleFile=$ca;ExpectedCaSha256=(Sha $ca)}
}
function Save-Fixture {
    $script:receipt | ConvertTo-Json -Depth 10 -Compress | Set-Content -LiteralPath $path -NoNewline
    $script:check.ExpectedSha256=Sha $path
}
function Check-Fixture {
    Save-Fixture
    $script:attempt++
    $output=Join-Path $temp "verified-$script:attempt.json"
    & "$repo/scripts/check-bootstrap-receipt.ps1" @script:check -OutputFile $output | Out-Null
    Assert ((Sha $output) -ceq $script:check.ExpectedSha256) 'Verified export must preserve all exact reviewed bytes, schema and versions.'
    $doc=Get-Content -LiteralPath $output -Raw | ConvertFrom-Json
    Assert ($doc.schemaVersion -eq $script:receipt.schemaVersion) 'Never convert receipt versions implicitly.'
    Reject { & "$repo/scripts/check-bootstrap-receipt.ps1" @script:check -OutputFile $output }
}
try {
    foreach($environment in @('staging','production')) { foreach($version in @(1,2)) { New-Fixture $version $environment; Check-Fixture } }
    foreach($mutation in @(
        {$script:receipt.schemaVersion=3}, {$script:receipt.schemaVersion='2'},
        {$script:receipt.environment='production'}, {$script:receipt.sourceCommit='c'*40},
        {$script:receipt.password='must-not-export'}, {$script:receipt.outputs.password='must-not-export'},
        {$script:receipt.outputs.appSecretArn='plaintext-credential-value'},
        {$script:receipt.outputs.appSecretArn=$master},
        {$script:receipt.outputs.authLookupSecretArn=$script:receipt.outputs.appSecretArn},
        {$script:receipt.outputs.appSecretArn=$script:receipt.outputs.appSecretArn.Replace('/staging/','/production/')},
        {$script:receipt.outputs.appSecretArn=$script:receipt.outputs.appSecretArn.Replace('123456789012','999999999999')},
        {$script:receipt.outputs.appSecretArn=$script:receipt.outputs.appSecretArn.Replace(':us-east-1:',':us-west-2:')},
        {$script:receipt.outputs.appSecretArn=$script:receipt.outputs.appSecretArn.Replace('/app-','/migration-')},
        {$script:receipt.outputs.appSecretArn=@{password='must-not-export'}},
        {$script:receipt.outputs.appSecretVersionId='AWSCURRENT'},
        {$script:receipt.outputs.appSecretVersionId='AWSPREVIOUS'},
        {$script:receipt.outputs.appSecretVersionId='b'*31}, {$script:receipt.outputs.appSecretVersionId='b'*65},
        {$script:receipt.outputs.appSecretVersionId='arn:aws:secretsmanager:secret:value'},
        {$script:receipt.outputs.appSecretVersionId=@{value='b'*32}},
        {$script:receipt.outputs.Remove('appSecretVersionId')},
        {$script:receipt.outputs.schemaVersion='V4'}, {$script:receipt.outputs.authViewVersion='V4'}, {$script:receipt.outputs.recipientViewVersion='V6'},
        {$script:check.MasterSecretArn='arn:aws:secretsmanager:us-east-1:123456789012:secret:unmanaged-master'},
        {$script:check.ExpectedCaSha256='0'*64}
    )) {
        New-Fixture; & $mutation; Save-Fixture
        $badOutput=Join-Path $temp 'invalid-must-not-export.json'
        Reject { & "$repo/scripts/check-bootstrap-receipt.ps1" @script:check -OutputFile $badOutput }
        Assert (-not (Test-Path -LiteralPath $badOutput)) 'Invalid receipt must produce no artifact.'
    }
    # Schema mismatch cannot add implicit versions to V1 or downgrade a V2 receipt.
    New-Fixture 1; $script:receipt.outputs.appSecretVersionId='b'*32; Save-Fixture
    Reject { & "$repo/scripts/check-bootstrap-receipt.ps1" @script:check }
    New-Fixture 2; $script:receipt.schemaVersion=1; Save-Fixture
    Reject { & "$repo/scripts/check-bootstrap-receipt.ps1" @script:check }
    foreach($kind in @('top','nested','case')) {
        New-Fixture; Save-Fixture; $raw=Get-Content -LiteralPath $path -Raw
        $raw=switch($kind) {
            top {$raw.Replace('"schemaVersion":2','"schemaVersion":2,"schemaVersion":2')}
            nested {$raw.Replace('"appSecretVersionId":','"appSecretVersionId":"'+('c'*32)+'","appSecretVersionId":')}
            case {$raw.Replace('"schemaVersion":2','"SchemaVersion":2,"schemaVersion":2')}
        }
        $raw | Set-Content -LiteralPath $path -NoNewline; $script:check.ExpectedSha256=Sha $path
        Reject { & "$repo/scripts/check-bootstrap-receipt.ps1" @script:check }
    }
    New-Fixture; Save-Fixture; Add-Content -LiteralPath $path -Value ' '
    Reject { & "$repo/scripts/check-bootstrap-receipt.ps1" @script:check }
    Write-Output "Bootstrap receipt V1/V2 contracts: PASS ($script:checks assertions; no AWS calls)."
} finally {
    $resolved=[IO.Path]::GetFullPath($temp)
    if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -or -not [IO.Path]::GetFileName($resolved).StartsWith('oficina-bootstrap-v2-')){throw 'Unsafe test cleanup path.'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
