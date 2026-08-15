#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Write a top-level JSON object without materialising the complete JSON document in memory.

.DESCRIPTION
    PowerShell's ConvertTo-Json returns one string containing the entire document. Large Scout
    estates can therefore hold the source objects, the serializer's object graph, and a second
    multi-hundred-megabyte string at the same time. This writer serializes top-level collections
    one element at a time and atomically replaces the destination only after the document closes.

    Individual resource rows still use ConvertTo-Json -Depth so PowerShell/JToken adaptation and
    the existing JSON contract remain unchanged. Peak serializer memory is bounded by the largest
    single row rather than the complete inventory.
#>
function Write-ScoutJsonStream {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $InputObject,

        [Parameter(Mandatory)]
        [string]$Path,

        [ValidateRange(1, 100)]
        [int]$Depth = 100
    )

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        $null = New-Item -Path $parent -ItemType Directory -Force
    }

    $temporaryPath = '{0}.{1}.tmp' -f $Path, [guid]::NewGuid().ToString('N')
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $writer = $null

    function ConvertTo-ScoutJsonFragment {
        param([AllowNull()]$Value)
        return ConvertTo-Json -InputObject $Value -Depth $Depth -Compress
    }

    function Test-ScoutJsonStreamCollection {
        param([AllowNull()]$Value)
        if ($null -eq $Value -or $Value -is [string] -or $Value -is [System.Collections.IDictionary]) {
            return $false
        }
        if ($Value -is [System.Management.Automation.PSCustomObject]) { return $false }
        if ($Value.GetType().FullName -eq 'Newtonsoft.Json.Linq.JObject') { return $false }
        return $Value -is [System.Collections.IEnumerable]
    }

    try {
        $writer = [System.IO.StreamWriter]::new($temporaryPath, $false, $utf8NoBom, 65536)
        $writer.WriteLine('{')

        $properties = @([System.Management.Automation.PSObject]::AsPSObject($InputObject).PSObject.Properties)
        for ($propertyIndex = 0; $propertyIndex -lt $properties.Count; $propertyIndex++) {
            $property = $properties[$propertyIndex]
            $nameJson = ConvertTo-ScoutJsonFragment -Value ([string]$property.Name)
            $writer.Write('  {0}: ' -f $nameJson)

            if (Test-ScoutJsonStreamCollection -Value $property.Value) {
                $writer.WriteLine('[')
                $itemIndex = 0
                foreach ($item in $property.Value) {
                    if ($itemIndex -gt 0) { $writer.WriteLine(',') }
                    $writer.Write('    ')
                    $writer.Write((ConvertTo-ScoutJsonFragment -Value $item))
                    $itemIndex++
                }
                if ($itemIndex -gt 0) { $writer.WriteLine() }
                $writer.Write('  ]')
            }
            else {
                $writer.Write((ConvertTo-ScoutJsonFragment -Value $property.Value))
            }

            if ($propertyIndex -lt ($properties.Count - 1)) { $writer.Write(',') }
            $writer.WriteLine()
        }

        $writer.WriteLine('}')
        $writer.Flush()
        $writer.Dispose()
        $writer = $null

        [System.IO.File]::Move($temporaryPath, $Path, $true)
        return $Path
    }
    catch {
        if ($null -ne $writer) { $writer.Dispose() }
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
        throw
    }
}
