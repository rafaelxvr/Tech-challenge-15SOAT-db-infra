[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$temp = Join-Path ([IO.Path]::GetTempPath()) ('oficina-db-outputs-test-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temp | Out-Null
function Sha($path) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Save($value, $name) { $p = Join-Path $temp $name; $value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $p -NoNewline; return $p }
function Reject([scriptblock]$action) { try { & $action } catch { return }; throw 'Expected invalid output/bootstrap reference to fail.' }
try {
    $master = 'arn:aws:secretsmanager:us-east-1:123456789012:secret:rds!db-fixture'
    $values = @{ db_endpoint = 'oficina.fixture.us-east-1.rds.amazonaws.com'; db_port = 5432; db_name = 'oficina'; master_secret_arn = $master; database_security_group_id = 'sg-0123456789abcdef0' }
    $outputs = @{}
    foreach ($k in $values.Keys) { $outputs[$k] = @{ value = $values[$k]; sensitive = $false; type = $(if ($k -eq 'db_port') { 'number' } else { 'string' }) } }
    $outputs.password = @{ value = 'must-not-export'; sensitive = $true; type = 'string' }
    $raw = Save $outputs 'raw.json'
    $published = Join-Path $temp 'outputs.json'
    $export = @{ Environment = 'staging'; SourceCommit = ('a' * 40); OutputFile = $published }
    & "$repo/scripts/export-outputs.ps1" @export -TerraformOutputFile $raw | Out-Null
    $doc = Get-Content -LiteralPath $published -Raw | ConvertFrom-Json
    if (@($doc.outputs.PSObject.Properties).Count -ne 5 -or $doc.outputs.masterSecretArn -cne $master -or (Get-Content -LiteralPath $published -Raw).Contains('must-not-export')) { throw 'Only the five approved references can leave DB.' }
    # Exercise actual native -chdir expansion for both path forms, without providers.
    $stateRoot = Join-Path $temp 'state with spaces'; New-Item -ItemType Directory -Path $stateRoot | Out-Null
    @{ version = 4; terraform_version = '1.15.8'; serial = 1; lineage = [guid]::NewGuid().ToString(); outputs = $outputs; resources = @() } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath "$stateRoot/terraform.tfstate" -NoNewline
    Push-Location -LiteralPath $temp
    try { foreach ($directory in @($stateRoot, './state with spaces')) { & "$repo/scripts/export-outputs.ps1" @export -TerraformDirectory $directory | Out-Null } } finally { Pop-Location }
    $outputs.master_secret_arn.sensitive = $true; $null = Save $outputs 'raw.json'
    Reject { & "$repo/scripts/export-outputs.ps1" @export -TerraformOutputFile $raw }
    $outputs.master_secret_arn.sensitive = $false; $outputs.Remove('db_endpoint'); $null = Save $outputs 'raw.json'
    Reject { & "$repo/scripts/export-outputs.ps1" @export -TerraformOutputFile $raw }
    $ca = Join-Path $temp 'test-ca.pem'; 'public CA fixture bytes' | Set-Content -LiteralPath $ca -NoNewline
    $receiptOutputs = @{ schemaVersion = 'V8'; authViewVersion = 'V5'; recipientViewVersion = 'V7'; appSecretArn = 'arn:aws:secretsmanager:us-east-1:123456789012:secret:oficina/staging/app-123'; migrationSecretArn = 'arn:aws:secretsmanager:us-east-1:123456789012:secret:oficina/staging/migration-123'; authLookupSecretArn = 'arn:aws:secretsmanager:us-east-1:123456789012:secret:oficina/staging/auth-123'; notificationLookupSecretArn = 'arn:aws:secretsmanager:us-east-1:123456789012:secret:oficina/staging/notification-123' }
    $receipt = @{ schemaVersion = 1; environment = 'staging'; sourceCommit = ('a' * 40); outputs = $receiptOutputs }
    $path = Save $receipt 'bootstrap.json'
    $check = @{ ReceiptFile = $path; ExpectedSha256 = (Sha $path); Environment = 'staging'; SourceCommit = ('a' * 40); MasterSecretArn = $master; CaBundleFile = $ca; ExpectedCaSha256 = (Sha $ca) }
    & "$repo/scripts/check-bootstrap-receipt.ps1" @check | Out-Null
    foreach ($badArn in @($master, $receiptOutputs.appSecretArn, 'arn:aws:secretsmanager:us-east-1:123456789012:secret:oficina/production/auth-123', 'arn:aws:secretsmanager:us-east-1:999999999999:secret:oficina/staging/auth-123')) {
        $receiptOutputs.authLookupSecretArn = $badArn; $null = Save $receipt 'bootstrap.json'; $check.ExpectedSha256 = Sha $path
        Reject { & "$repo/scripts/check-bootstrap-receipt.ps1" @check }
    }
    $receiptOutputs.authLookupSecretArn = 'arn:aws:secretsmanager:us-east-1:123456789012:secret:oficina/staging/auth-123'
    $null = Save $receipt 'bootstrap.json'; $check.ExpectedSha256 = Sha $path
    Add-Content -LiteralPath $ca -Value 'tampered'
    Reject { & "$repo/scripts/check-bootstrap-receipt.ps1" @check }
    Write-Output 'DB outputs/bootstrap contracts: PASS (filtering, real Terraform paths, role separation, environment/account binding and CA hash).'
} finally {
    $resolved = [IO.Path]::GetFullPath($temp)
    if (-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase) -or -not [IO.Path]::GetFileName($resolved).StartsWith('oficina-db-outputs-test-')) { throw 'Unsafe test cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
