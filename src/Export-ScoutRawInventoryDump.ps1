#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Write every row the collection pass returned to a raw JSON artifact.

.DESCRIPTION
    AB#6764. Scout collects nearly everything and displays about 40% of it. The Resource Graph
    pass is unfiltered -- it pulls every resource type in the estate -- and the collector
    manifests then decide what reaches a worksheet. Everything else was discarded without being
    written anywhere, so a resource type no manifest claims left no trace that it had ever been
    seen.

    That is a display gap, not a collection gap, and dumping the raw rows eliminates it outright
    instead of reporting on it. Building a collector for every undisplayed type is a different
    and much larger job; this makes the data available today.

    Two properties matter and both are enforced by where this is called from:

      - It runs BEFORE the processing phase, so nothing has been filtered by a manifest yet.
      - It writes to the RUN folder alongside the other retained evidence. Invoke-AzureScout does
        not delete raw or processed discovery data when a scan completes.

.PARAMETER ExtractionData
    The object returned by `Start-AZSCExtractionOrchestration`.

.PARAMETER DefaultPath
    The run folder.

.PARAMETER FileName
    Artifact name. Defaults to `raw-inventory.json`.

.OUTPUTS
    [string] the path written, or $null if nothing was written.

.NOTES
    Tracks ADO AB#6764 (Feature AB#6743, Epic AB#6731). Format documented in docs/output.md.
#>
function Export-ScoutRawInventoryDump {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $ExtractionData,

        [Parameter(Mandatory)]
        [string] $DefaultPath,

        [string] $FileName = 'raw-inventory.json'
    )

    if ($null -eq $ExtractionData) {
        Write-Verbose 'Export-ScoutRawInventoryDump: nothing to dump — the extraction returned $null.'
        return $null
    }

    # Read element-wise. $ExtractionData's shape varies with -Scope and the -Skip* switches
    # (an EntraOnly run has no Resources at all), and under StrictMode dotting an absent
    # property throws rather than returning $null.
    function Get-Set {
        param($Object, [string] $Name)
        if ($Object.PSObject.Properties[$Name]) { @($Object.$Name) } else { @() }
    }

    $sets = [ordered]@{}
    foreach ($name in 'Resources', 'ResourceContainers', 'Advisories', 'Security', 'Retirements',
                      'EntraResources', 'Quotas', 'PolicyAssign', 'PolicyDef', 'PolicySetDef') {
        $sets[$name] = Get-Set -Object $ExtractionData -Name $name
    }

    # The type census is the point of the artifact, not decoration: it is the shortest answer to
    # "what did the estate contain that no worksheet showed?", and it is what makes the file
    # worth opening before scrolling through the rows.
    $typeCounts = @{}
    foreach ($row in @($sets['Resources'])) {
        if ($null -eq $row) { continue }
        $t = if ($row.PSObject.Properties['type'] -and $row.type) { [string] $row.type }
             elseif ($row.PSObject.Properties['TYPE'] -and $row.TYPE) { [string] $row.TYPE }
             else { '(untyped)' }
        if ($typeCounts.ContainsKey($t)) { $typeCounts[$t]++ } else { $typeCounts[$t] = 1 }
    }

    $path = Join-Path $DefaultPath $FileName
    if (-not $PSCmdlet.ShouldProcess($path, 'Write raw inventory dump')) { return $null }

    try {
        if (-not (Get-Command Write-ScoutJsonStream -ErrorAction SilentlyContinue)) {
            . (Join-Path $PSScriptRoot 'Write-ScoutJsonStream.ps1')
        }

        $payload = [ordered]@{
            Schema      = 'azure-scout/raw-inventory/v1'
            GeneratedAt = (Get-Date).ToString('o')
            Counts      = [ordered]@{}
            ResourceTypes = @(
                $typeCounts.GetEnumerator() | Sort-Object Name |
                    ForEach-Object { [PSCustomObject]@{ Type = $_.Key; Rows = $_.Value } }
            )
        }
        foreach ($name in $sets.Keys) { $payload.Counts[$name] = @($sets[$name]).Count }
        foreach ($name in $sets.Keys) { $payload[$name] = @($sets[$name]) }

        # Depth 100 matches what the assessment layer uses for collect.json. The `properties`
        # bag on a raw ARG row is arbitrarily nested and a shallower depth would silently
        # truncate it to a type name, which is the exact silent loss this artifact exists to end.
        # Stream each top-level collection row independently: ConvertTo-Json over the complete
        # payload duplicates the entire estate as one giant string and exhausted memory in a
        # 50,081-row operator run.
        Write-ScoutJsonStream -InputObject ([PSCustomObject]$payload) -Path $path -Depth 100 | Out-Null

        Write-Verbose "Export-ScoutRawInventoryDump: wrote $((@($sets['Resources'])).Count) resource rows across $($typeCounts.Count) types to '$path'."
        return $path
    }
    catch {
        # A dump failure must never cost the caller their report.
        Write-Warning "[AzureScout] Could not write the raw inventory dump to '$path': $($_.Exception.Message)"
        return $null
    }
}
