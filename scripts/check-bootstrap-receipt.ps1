[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ReceiptFile,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedSha256,
    [Parameter(Mandatory)][ValidateSet('staging', 'production')][string]$Environment,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$SourceCommit,
    [Parameter(Mandatory)][string]$MasterSecretArn,
    [Parameter(Mandatory)][string]$CaBundleFile,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedCaSha256
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
foreach ($item in @(@($ReceiptFile, $ExpectedSha256), @($CaBundleFile, $ExpectedCaSha256))) {
    if ((Get-FileHash -LiteralPath $item[0] -Algorithm SHA256).Hash.ToLowerInvariant() -cne $item[1]) { throw 'Bootstrap receipt or pinned CA digest mismatch.' }
}
$r = Get-Content -LiteralPath $ReceiptFile -Raw | ConvertFrom-Json
$c = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../contracts/bootstrap.v1.json') -Raw | ConvertFrom-Json
if ($r.schemaVersion -ne 1 -or $r.environment -cne $Environment -or $r.sourceCommit -cne $SourceCommit) { throw 'Bootstrap receipt does not match the expected APP release/environment.' }
if ((@($r.PSObject.Properties.Name | Sort-Object) -join ',') -cne (@($c.requiredReceiptFields | Sort-Object) -join ',') -or
    (@($r.outputs.PSObject.Properties.Name | Sort-Object) -join ',') -cne (@($c.requiredOutputFields | Sort-Object) -join ',')) { throw 'Bootstrap receipt must contain only the complete schema/view/credential-reference contract.' }
foreach ($name in @('schemaVersion', 'authViewVersion', 'recipientViewVersion')) {
    if ([string]::IsNullOrWhiteSpace([string]$r.outputs.$name)) { throw "Bootstrap receipt lacks $name." }
}
if ($MasterSecretArn -notmatch '^arn:aws:secretsmanager:us-east-1:(?<account>[0-9]{12}):secret:.+$') { throw 'Expected RDS master secret ARN is invalid.' }
$account = $Matches.account
$arns = @('appSecretArn', 'migrationSecretArn', 'authLookupSecretArn', 'notificationLookupSecretArn') | ForEach-Object { [string]$r.outputs.$_ }
if (@($arns | Sort-Object -Unique).Count -ne 4 -or @($arns | Where-Object { $_ -ceq $MasterSecretArn -or $_ -notmatch "^arn:aws:secretsmanager:us-east-1:${account}:secret:oficina/$Environment/.+" }).Count -gt 0) { throw 'Runtime logins need four distinct same-environment credential references, excluding the master secret.' }
Write-Output 'APP bootstrap references and pinned CA verified; SQL permission proof remains APP-owned.'
