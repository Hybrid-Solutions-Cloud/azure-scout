#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Normalizes Resource Health outage descriptions into cross-platform collector envelopes.

.DESCRIPTION
    The legacy Outages collector used the Windows-only `HTMLFile` COM object merely to turn an
    incident description into text. This pure transform replaces that dependency before report
    processing: it retains the original Resource Graph row and adds the five incident narrative
    fields that the worksheet exposes. No Azure request is made here.

.OUTPUTS
    `AZSC/Monitor/Outage` envelopes with the original row in `properties.SourceResource` and
    the text fields in `properties.DescriptionSections`.
#>
function Get-ScoutOutageResource {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Resources
    )

    function Get-ScoutOutageValue {
        param($InputObject, [string[]] $Path)
        $value = $InputObject
        foreach ($segment in $Path) {
            if ($null -eq $value) { return $null }
            if ($value -is [System.Collections.IDictionary]) {
                if (-not $value.Contains($segment)) { return $null }
                $value = $value[$segment]
                continue
            }
            $property = $value.PSObject.Properties[$segment]
            if ($null -eq $property) { return $null }
            $value = $property.Value
        }
        return $value
    }

    function ConvertTo-ScoutOutageDescriptionSections {
        param([AllowNull()][string] $Description)

        $headings = @(
            'What happened?',
            'What went wrong and why?',
            'How did we respond?',
            'How are we making incidents like this less likely or less impactful?',
            'How can customers make incidents like this less impactful?'
        )
        $result = [ordered]@{}
        foreach ($heading in $headings) { $result[$heading.TrimEnd('?')] = $null }
        if ([string]::IsNullOrWhiteSpace($Description)) { return [pscustomobject] $result }

        # Preserve block boundaries before stripping tags; HTML decode is available on every
        # PowerShell 7 platform and avoids the Windows-only HTMLFile COM dependency.
        $text = $Description -replace '(?is)<(script|style)[^>]*>.*?</\1>', ''
        $text = $text -replace '(?i)<br\s*/?>', "`n"
        $text = $text -replace '(?i)</(?:p|div|li|h[1-6]|tr|section|article)>', "`n"
        $text = $text -replace '(?s)<[^>]+>', ''
        $text = [System.Net.WebUtility]::HtmlDecode($text) -replace "`r`n?", "`n"

        for ($index = 0; $index -lt $headings.Count; $index++) {
            $heading = $headings[$index]
            $start = $text.IndexOf($heading, [System.StringComparison]::OrdinalIgnoreCase)
            if ($start -lt 0) { continue }
            $contentStart = $start + $heading.Length
            $contentEnd = $text.Length
            foreach ($nextHeading in $headings) {
                $next = $text.IndexOf($nextHeading, $contentStart, [System.StringComparison]::OrdinalIgnoreCase)
                if ($next -ge 0 -and $next -lt $contentEnd) { $contentEnd = $next }
            }
            $lines = @($text.Substring($contentStart, $contentEnd - $contentStart) -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            if ($lines.Count -gt 0) { $result[$heading.TrimEnd('?')] = $lines[0] }
        }
        return [pscustomobject] $result
    }

    foreach ($resource in @($Resources)) {
        $type = [string](Get-ScoutOutageValue $resource @('type'))
        if ($type -ine 'Microsoft.ResourceHealth/events') { continue }
        $description = [string](Get-ScoutOutageValue $resource @('properties', 'description'))
        if ($description -notlike '*How can customers make incidents like this less impactful?*') { continue }

        [pscustomobject]@{
            id             = [string](Get-ScoutOutageValue $resource @('id'))
            name           = [string](Get-ScoutOutageValue $resource @('name'))
            type           = 'AZSC/Monitor/Outage'
            subscriptionId = [string](Get-ScoutOutageValue $resource @('subscriptionId'))
            properties     = [pscustomobject]@{
                SourceResource      = $resource
                DescriptionSections = ConvertTo-ScoutOutageDescriptionSections -Description $description
            }
        }
    }
}
