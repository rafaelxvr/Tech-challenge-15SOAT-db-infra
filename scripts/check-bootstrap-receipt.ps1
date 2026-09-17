[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ReceiptFile,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedSha256,
    [Parameter(Mandatory)][ValidateSet('staging', 'production')][string]$Environment,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$SourceCommit,
    [Parameter(Mandatory)][string]$MasterSecretArn,
    [Parameter(Mandatory)][string]$CaBundleFile,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedCaSha256,
    [string]$OutputFile
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
function Hash-Bytes([byte[]]$Bytes) {
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}
function Assert-UniqueProperties([System.Text.Json.JsonElement]$Element) {
    if ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
        $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($property in $Element.EnumerateObject()) {
            if (-not $names.Add($property.Name)) { throw 'Duplicate JSON property.' }
            Assert-UniqueProperties $property.Value
        }
    } elseif ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Array) {
        foreach ($item in $Element.EnumerateArray()) { Assert-UniqueProperties $item }
    }
}
function Assert-ReceiptShape([System.Text.Json.JsonElement]$Root) {
    # Check JSON kinds before PowerShell can enumerate arrays or coerce comparisons.
    if ($Root.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) { throw 'Receipt root must be an object.' }
    $version = $Root.GetProperty('schemaVersion')
    if ($version.ValueKind -ne [System.Text.Json.JsonValueKind]::Number -or $version.GetInt32() -notin @(1, 2)) { throw 'Receipt version must be integer 1 or 2.' }
    foreach ($name in @('environment', 'sourceCommit')) {
        $field = $Root.GetProperty($name)
        if ($field.ValueKind -ne [System.Text.Json.JsonValueKind]::String -or [string]::IsNullOrWhiteSpace($field.GetString())) { throw 'Receipt metadata must be non-empty scalar strings.' }
    }
    $outputs = $Root.GetProperty('outputs')
    if ($outputs.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) { throw 'Receipt outputs must be an object.' }
    foreach ($property in $outputs.EnumerateObject()) {
        if ($property.Value.ValueKind -ne [System.Text.Json.JsonValueKind]::String -or [string]::IsNullOrWhiteSpace($property.Value.GetString())) { throw 'Receipt output fields must be non-empty scalar strings.' }
    }
}
# Validate and optionally export the same byte snapshot: no hash/read/export race or schema downgrade.
$receiptBytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $ReceiptFile))
if ((Hash-Bytes $receiptBytes) -cne $ExpectedSha256 -or
    (Hash-Bytes ([IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $CaBundleFile)))) -cne $ExpectedCaSha256) { throw 'Bootstrap receipt or pinned CA digest mismatch.' }
$raw = [Text.Encoding]::UTF8.GetString($receiptBytes).TrimStart([char]0xfeff)
try {
    $options = [System.Text.Json.JsonDocumentOptions]::new(); $options.MaxDepth = 16
    $parsed = [System.Text.Json.JsonDocument]::Parse($raw, $options)
    try {
        Assert-UniqueProperties $parsed.RootElement
        Assert-ReceiptShape $parsed.RootElement
    } finally { $parsed.Dispose() }
    $r = $raw | ConvertFrom-Json
} catch { throw 'Bootstrap receipt must be a JSON object with object outputs, scalar fields and unique property names.' }
if (($r.schemaVersion -isnot [int] -and $r.schemaVersion -isnot [long]) -or $r.schemaVersion -notin @(1, 2) -or
    $r.environment -cne $Environment -or $r.sourceCommit -cne $SourceCommit) { throw 'Bootstrap receipt does not match the expected APP release/environment.' }
$c = Get-Content -LiteralPath (Join-Path $PSScriptRoot "../contracts/bootstrap.v$($r.schemaVersion).json") -Raw | ConvertFrom-Json
if ((@($r.PSObject.Properties.Name | Sort-Object) -join ',') -cne (@($c.requiredReceiptFields | Sort-Object) -join ',') -or
    (@($r.outputs.PSObject.Properties.Name | Sort-Object) -join ',') -cne (@($c.requiredOutputFields | Sort-Object) -join ',')) { throw 'Bootstrap receipt must contain only the complete schema/view/credential-reference contract.' }
foreach ($name in @('schemaVersion', 'authViewVersion', 'recipientViewVersion')) {
    if ($r.outputs.$name -isnot [string] -or [string]::IsNullOrWhiteSpace($r.outputs.$name)) { throw "Bootstrap receipt lacks $name." }
}
if ($MasterSecretArn -notmatch '^arn:aws:secretsmanager:us-east-1:(?<account>[0-9]{12}):secret:.+$') { throw 'Expected RDS master secret ARN is invalid.' }
$account = $Matches.account
$arnFields = @('appSecretArn', 'migrationSecretArn', 'authLookupSecretArn', 'notificationLookupSecretArn')
foreach ($name in $arnFields) { if ($r.outputs.$name -isnot [string]) { throw 'Credential references must be strings.' } }
$arns = @('appSecretArn', 'migrationSecretArn', 'authLookupSecretArn', 'notificationLookupSecretArn') | ForEach-Object { [string]$r.outputs.$_ }
if (@($arns | Sort-Object -Unique).Count -ne 4 -or @($arns | Where-Object { $_ -ceq $MasterSecretArn -or $_ -notmatch "^arn:aws:secretsmanager:us-east-1:${account}:secret:oficina/$Environment/.+" }).Count -gt 0) { throw 'Runtime logins need four distinct same-environment credential references, excluding the master secret.' }
if ($r.schemaVersion -eq 2) {
    if ($MasterSecretArn -cnotmatch "\Aarn:aws:secretsmanager:us-east-1:${account}:secret:rds!db-[A-Za-z0-9-]+\z") { throw 'V2 requires the explicit RDS-managed master reference for exclusion/account binding.' }
    foreach ($name in @('schemaVersion', 'authViewVersion', 'recipientViewVersion')) {
        if ($r.outputs.$name -cne $c.schemaVersions.$name) { throw 'Unreviewed V2 schema/view version.' }
    }
    foreach ($entry in $c.secretRoles.PSObject.Properties) {
        $arnName = $entry.Name + 'Arn'; $versionName = $entry.Name + 'VersionId'
        if ($r.outputs.$arnName -cnotmatch ("\Aarn:aws:secretsmanager:us-east-1:${account}:secret:oficina/$Environment/" + $entry.Value + '-[A-Za-z0-9]{6}\z') -or
            $r.outputs.$versionName -isnot [string] -or $r.outputs.$versionName -cnotmatch '\A[A-Za-z0-9-]{32,64}\z') { throw 'V2 requires exact role ARNs and immutable VersionIds; aliases/values are forbidden.' }
    }
}
if ($OutputFile) {
    # CREATE_NEW preserves prior evidence and cannot overwrite the input or a prior successful export.
    $destination = [IO.File]::Open([IO.Path]::GetFullPath($OutputFile), [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $destination.Write($receiptBytes, 0, $receiptBytes.Length) } finally { $destination.Dispose() }
}
Write-Output "APP bootstrap v$($r.schemaVersion) references and pinned CA verified; SQL permission proof remains APP-owned."
