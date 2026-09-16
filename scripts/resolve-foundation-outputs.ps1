[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ArtifactBucket,
    [Parameter(Mandatory)][string]$ReceiptFile,
    [Parameter(Mandatory)][string]$BaseTerraformVariablesFile,
    [Parameter(Mandatory)][string]$OutputTerraformVariablesFile,
    [string]$ArtifactFileForTest
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$r = Get-Content -LiteralPath $ReceiptFile -Raw | ConvertFrom-Json
$b = Get-Content -LiteralPath $BaseTerraformVariablesFile -Raw | ConvertFrom-Json
if ($r.schemaVersion -ne 1 -or $r.kind -cne 'foundation-output' -or $r.environment -cne 'foundation' -or $r.artifactBucket -cne $ArtifactBucket -or $r.sourceCommit -notmatch '^[a-f0-9]{40}$' -or $r.artifactKey -cne "releases/k8s/foundation/outputs/$($r.sourceCommit).json" -or [string]::IsNullOrWhiteSpace($r.artifactVersionId) -or $r.artifactSha256 -notmatch '^[a-f0-9]{64}$') { throw 'A reviewed immutable foundation output receipt is required.' }
if ($b.PSObject.Properties['vpc_id'] -or $b.PSObject.Properties['database_subnet_ids']) { throw 'Base DB configuration cannot override foundation network outputs.' }
$temp = Join-Path ([IO.Path]::GetTempPath()) ("oficina-db-foundation-" + [guid]::NewGuid() + '.json')
try {
    if ($ArtifactFileForTest) { Copy-Item -LiteralPath $ArtifactFileForTest -Destination $temp }
    else {
        & aws s3api get-object --bucket $ArtifactBucket --key $r.artifactKey --version-id $r.artifactVersionId $temp 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Versioned foundation output download failed.' }
    }
    if ((Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash.ToLowerInvariant() -cne $r.artifactSha256) { throw 'Foundation output digest mismatch.' }
    $a = Get-Content -LiteralPath $temp -Raw | ConvertFrom-Json
    if ($a.schemaVersion -ne 1 -or $a.environment -cne 'foundation' -or $a.sourceCommit -cne $r.sourceCommit) { throw 'Foundation output envelope mismatch.' }
    $b | Add-Member -NotePropertyName vpc_id -NotePropertyValue $a.outputs.vpcId
    $b | Add-Member -NotePropertyName database_subnet_ids -NotePropertyValue $a.outputs.databaseSubnetIds
    $b | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputTerraformVariablesFile -NoNewline
    & (Join-Path $PSScriptRoot 'check-database-inputs.ps1') -TerraformVariablesFile $OutputTerraformVariablesFile | Out-Null
    Write-Output 'DB inputs bound to verified foundation output version.'
} finally { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
