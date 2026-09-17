[CmdletBinding()]
param([Parameter(Mandatory)][string]$TerraformVariablesFile)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$inputObject = Get-Content -LiteralPath $TerraformVariablesFile -Raw | ConvertFrom-Json
$expected = @('account_id', 'vpc_id', 'database_subnet_ids', 'source_security_group_ids')
if ((@($inputObject.PSObject.Properties.Name | Sort-Object) -join ',') -cne (@($expected | Sort-Object) -join ',')) { throw 'DB inputs require only reviewed account/network references; unknown fields or credential values are forbidden.' }
if ([string]$inputObject.account_id -notmatch '^[0-9]{12}$' -or [string]$inputObject.vpc_id -notmatch '^vpc-[a-f0-9]{8,17}$') { throw 'Verified account and VPC IDs are required.' }
$subnets = @($inputObject.database_subnet_ids)
if ($subnets.Count -lt 2 -or @($subnets | Sort-Object -Unique).Count -ne $subnets.Count -or @($subnets | Where-Object { $_ -notmatch '^subnet-[a-f0-9]{8,17}$' }).Count -gt 0) { throw 'At least two distinct isolated database subnet IDs are required.' }
$groups = $inputObject.source_security_group_ids
if ((@($groups.PSObject.Properties.Name | Sort-Object) -join ',') -cne 'app,auth,bootstrap,notification' -or @($groups.PSObject.Properties | Where-Object { [string]$_.Value -notmatch '^sg-[a-f0-9]{8,17}$' }).Count -gt 0) { throw 'Only explicit app/auth/notification/bootstrap source security groups are accepted.' }
Write-Output 'Database deployment inputs validated.'
