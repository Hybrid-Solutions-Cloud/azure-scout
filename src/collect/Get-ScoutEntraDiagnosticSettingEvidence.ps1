#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ScoutEntraDiagnosticSettingEvidence {
    [CmdletBinding()]
    param()

    $uri = '/providers/microsoft.aadiam/diagnosticSettings?api-version=2017-04-01'
    $startedAt = Get-Date
    $rows = [System.Collections.Generic.List[object]]::new()
    try {
        $response = Invoke-AzRestMethod -Path $uri -Method GET -ErrorAction Stop
        if ($null -eq $response) { throw 'ARM returned no response.' }
        $statusProperty = $response.PSObject.Properties['StatusCode']
        if ($statusProperty -and ([int]$statusProperty.Value -lt 200 -or [int]$statusProperty.Value -ge 300)) {
            throw "ARM returned HTTP $($statusProperty.Value)."
        }
        $contentProperty = $response.PSObject.Properties['Content']
        $content = if ($contentProperty) { $contentProperty.Value } else { $null }
        if ($content -is [string] -and -not [string]::IsNullOrWhiteSpace($content)) { $content = $content | ConvertFrom-Json }
        [object[]]$items = @()
        if ($null -ne $content -and $content.PSObject.Properties['value']) {
            $items = @($content.value | Where-Object { $null -ne $_ })
        }
        $collectedAt = Get-Date
        foreach ($item in $items) {
            $id = if ($item.PSObject.Properties['id']) { [string]$item.id } else { "/providers/microsoft.aadiam/diagnosticSettings/$($rows.Count + 1)" }
            $name = if ($item.PSObject.Properties['name']) { [string]$item.name } else { "diagnostic-setting-$($rows.Count + 1)" }
            $rows.Add([pscustomobject][ordered]@{
                    id = "$id/providers/AzureScout/evidence"
                    name = $name
                    type = 'AZSC/Entra/DiagnosticSettings'
                    properties = [pscustomobject][ordered]@{ Raw = $item }
                    AZSC = [pscustomobject][ordered]@{
                        Source = 'Microsoft Entra control-plane API'
                        Dataset = 'EntraDiagnosticSettings'
                        Operation = 'GET'
                        Uri = $uri
                        ApiVersion = '2017-04-01'
                        CollectedAt = $collectedAt.ToString('o')
                    }
                })
        }
        return [pscustomobject]@{
            Resources = @($rows)
            SourceOperations = @([pscustomobject][ordered]@{
                    Source='Microsoft Entra control-plane API'; Dataset='EntraDiagnosticSettings'; Operation='GET'; Uri=$uri
                    ApiVersion='2017-04-01'; Status=if ($items.Count) {'Success'} else {'Empty'}; Count=$items.Count; Reason=$null
                    StartedAt=$startedAt.ToString('o'); CompletedAt=$collectedAt.ToString('o')
                })
            CollectionHealth = @()
        }
    }
    catch {
        $reason = $_.Exception.Message
        return [pscustomobject]@{
            Resources = @()
            SourceOperations = @([pscustomobject][ordered]@{
                    Source='Microsoft Entra control-plane API'; Dataset='EntraDiagnosticSettings'; Operation='GET'; Uri=$uri
                    ApiVersion='2017-04-01'; Status='Unavailable'; Count=0; Reason=$reason
                    StartedAt=$startedAt.ToString('o'); CompletedAt=(Get-Date).ToString('o')
                })
            CollectionHealth = @([pscustomobject]@{
                    Dataset='EntraDiagnosticSettings'; Operation='GET'; Status='Unavailable'; Reason=$reason
                    ResourceTypes=@('AZSC/Entra/DiagnosticSettings')
                })
        }
    }
}
