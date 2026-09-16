[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TerraformDirectory,
    [Parameter(Mandatory)][ValidateSet('staging', 'production')][string]$Environment,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$SourceCommit,
    [Parameter(Mandatory)][ValidatePattern('^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$')][string]$ArtifactBucket
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$temp = Join-Path ([IO.Path]::GetTempPath()) ("oficina-db-outputs-" + [guid]::NewGuid() + '.json')
try {
    & (Join-Path $PSScriptRoot 'export-outputs.ps1') -TerraformDirectory $TerraformDirectory -Environment $Environment -SourceCommit $SourceCommit -OutputFile $temp | Out-Null
    $key = "releases/database/$Environment/outputs/$SourceCommit.json"
    $sha = (Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash.ToLowerInvariant()
    $uploaded = & aws s3api put-object --bucket $ArtifactBucket --key $key --body $temp --output json 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'DB output publication failed.' }
    $version = ($uploaded | ConvertFrom-Json).VersionId
    if ([string]::IsNullOrWhiteSpace($version)) { throw 'DB output publication requires S3 versioning.' }
    @{ schemaVersion = 1; kind = 'database-output'; environment = $Environment; sourceCommit = $SourceCommit; artifactBucket = $ArtifactBucket; artifactKey = $key; artifactVersionId = $version; artifactSha256 = $sha } | ConvertTo-Json -Compress
} finally { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
