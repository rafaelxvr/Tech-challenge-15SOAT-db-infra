[CmdletBinding(DefaultParameterSetName = 'File')]
param(
    [Parameter(Mandatory, ParameterSetName = 'File')][string]$TerraformOutputFile,
    [Parameter(Mandatory, ParameterSetName = 'Terraform')][string]$TerraformDirectory,
    [Parameter(Mandatory)][ValidateSet('staging', 'production')][string]$Environment,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$SourceCommit,
    [Parameter(Mandatory)][string]$OutputFile
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($PSCmdlet.ParameterSetName -eq 'Terraform') {
    if (-not (Test-Path -LiteralPath $TerraformDirectory -PathType Container)) { throw 'Terraform directory does not exist.' }
    $raw = & terraform "-chdir=$TerraformDirectory" output -json
    if ($LASTEXITCODE -ne 0) { throw 'Terraform output failed.' }
} else { $raw = Get-Content -LiteralPath $TerraformOutputFile -Raw }
$source = $raw | ConvertFrom-Json
$allowlist = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../contracts/outputs-allowlist.json') -Raw | ConvertFrom-Json
$published = [ordered]@{}
foreach ($mapping in $allowlist.outputs.PSObject.Properties) {
    $entry = $source.PSObject.Properties[$mapping.Value]
    if ($null -eq $entry -or $null -eq $entry.Value.value -or $entry.Value.sensitive -ne $false) { throw "Missing or sensitive DB output: $($mapping.Name)." }
    $published[$mapping.Name] = $entry.Value.value
}
if ([string]$published.dbEndpoint -notmatch '^[a-zA-Z0-9.-]+\.us-east-1\.rds\.amazonaws\.com$' -or $published.dbPort -ne 5432 -or $published.dbName -cne 'oficina' -or [string]$published.databaseSecurityGroupId -notmatch '^sg-[a-f0-9]{8,17}$' -or [string]$published.masterSecretArn -notmatch '^arn:aws:secretsmanager:us-east-1:[0-9]{12}:secret:.+$') { throw 'DB output references do not satisfy the reviewed connection contract.' }
# masterSecretArn is the one explicitly approved credential reference; never its value.
@{ schemaVersion = 1; environment = $Environment; sourceCommit = $SourceCommit; outputs = $published } |
    ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputFile -NoNewline
Write-Output 'Only approved DB connection references were exported.'
