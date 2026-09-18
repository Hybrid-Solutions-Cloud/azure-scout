#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Import-ScoutReportInventory {
    <#
    .SYNOPSIS
        Attach every processed collector dataset to the report without changing rule inputs.
    .DESCRIPTION
        Collector rows can repeat resource identities (tags, disks, rules, and other children).
        Preserve all rows and report their unit separately from distinct resource identities.
        This is a local read of this run's cache, never an Azure collection or authentication.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Collect,
        [Parameter(Mandatory)] [string] $ReportCachePath
    )

    $datasets = [ordered]@{}
    foreach ($file in @(Get-ChildItem -LiteralPath $ReportCachePath -Filter '*.json' -File -ErrorAction Stop | Sort-Object Name)) {
        $cache = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -Depth 100 -ErrorAction Stop
        if ($file.BaseName -eq 'Discovery') {
            $Collect | Add-Member -NotePropertyName discovery -NotePropertyValue $cache -Force
            continue
        }
        foreach ($property in $cache.PSObject.Properties) {
            # Category cache files contain named arrays, including empty arrays. Metadata
            # objects are not datasets and should not turn into phantom inventory rows.
            if ($null -eq $property.Value -or $property.Value -isnot [System.Collections.IList]) { continue }
            $rows = @($property.Value)
            $ids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $identified = 0
            foreach ($row in $rows) {
                if ($null -eq $row) { continue }
                foreach ($name in @('id', 'ResourceId', 'Resource ID')) {
                    $value = $row.PSObject.Properties[$name]
                    if ($value -and -not [string]::IsNullOrWhiteSpace([string]$value.Value)) {
                        $null = $ids.Add([string]$value.Value)
                        $identified++
                        break
                    }
                }
            }
            $key = 'collected.{0}.{1}' -f $file.BaseName.ToLowerInvariant(), $property.Name
            $datasets[$key] = [ordered]@{
                label = '{0} → {1} (collected details)' -f $file.BaseName, ($property.Name -creplace '([a-z0-9])([A-Z])', '$1 $2')
                count = $rows.Count
                countUnit = 'evidence rows'
                resourceCount = if ($identified -eq $rows.Count) { $ids.Count } else { $null }
                rows = $rows
                truncated = $null
                source = '{0}/{1}' -f $file.Name, $property.Name
            }
        }
    }
    if ((Test-Path -LiteralPath (Join-Path $ReportCachePath 'Identity.json')) -and
        (Get-Command Get-ScoutEntraQueryCatalog -ErrorAction SilentlyContinue)) {
        $requirements = @(Get-ScoutEntraQueryCatalog | ForEach-Object {
            [pscustomobject]@{
                Dataset = $_.Name
                Endpoint = $_.Uri
                Permission = $_.Permission
                Licensing = if ($_.ContainsKey('LicensedProduct')) { $_.LicensedProduct } else { 'Check endpoint requirements' }
                CollectionEnabled = -not $_.ContainsKey('Collect') -or [bool]$_.Collect
                AccessNote = 'OAuth permission, directory role, tenant consent, guest restrictions and licensing are separate requirements. This matrix is not proof of granted access.'
            }
        })
        $datasets['collected.general.IdentityPermissionRequirements'] = [ordered]@{ label='Identity permission requirements'; count=$requirements.Count; rows=$requirements; truncated=$null; countUnit='dataset requirements'; resourceCount=$null; source='Entra query catalog' }
    }
    $Collect | Add-Member -NotePropertyName _reportInventory -NotePropertyValue $datasets -Force
    return $Collect
}
