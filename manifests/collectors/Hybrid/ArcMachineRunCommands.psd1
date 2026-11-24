#
# Hand-authored collector (AB#9300): Run commands on Arc machines were discovered but not read. The script, its parameters and its output are never projected because they can carry secrets; only who-ran-what metadata is. Fields verified against live rows on 2026-11-24.
#
@{
    ResourceTypes = @('microsoft.hybridcompute/machines/runcommands')

    ResourceTypeMatching = 'Grouped'

    AdditionalFilter = $null

    FilterPreamble = ''

    RowLoopVariable = '1'

    Preamble = @'
$ResUCount = 1
$sub1 = $SUB | Where-Object { $_.id -eq $1.subscriptionId }
$data = $1.PROPERTIES
$Tags = if (![string]::IsNullOrEmpty($1.tags.psobject.properties)) { $1.tags.psobject.properties } else { '0' }
$machineName = ([string]$1.id -split '/')[-3]
'@

    AdditionalRowLoops = @()

    TagLoop = @{
        Variable = 'Tag'
        Source = '$Tags'
        Preamble = ''
    }

    Fields = @(
        @{ Name = 'ID'; Expression = '$1.id' }
        @{ Name = 'Subscription'; Expression = '(Get-AZSCSafeProperty -InputObject $sub1 -Path ''name'')' }
        @{ Name = 'Resource Group'; Expression = '$1.RESOURCEGROUP' }
        @{ Name = 'Name'; Expression = '$1.NAME' }
        @{ Name = 'Location'; Expression = '$1.LOCATION' }
        @{ Name = 'Machine'; Expression = '$machineName' }
        @{ Name = 'Execution State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''instanceView.executionState'')' }
        @{ Name = 'Exit Code'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''instanceView.exitCode'')' }
        @{ Name = 'Started'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''instanceView.startTime'')' }
        @{ Name = 'Ended'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''instanceView.endTime'')' }
        @{ Name = 'Timeout (s)'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''timeoutInSeconds'')' }
        @{ Name = 'Async'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''asyncExecution'')' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Arc Run Commands'
        TableNamePrefix = 'ArcRunCommands_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Machine'
            'Execution State'
            'Exit Code'
            'Started'
            'Ended'
            'Timeout (s)'
            'Async'
            'Provisioning State'
            'Resource U'
        )
        TagColumns = @(
            'Tag Name'
            'Tag Value'
        )
        TagColumnsBefore = 'Resource U'
        NumberFormat = '0'
        ConditionalText = @()
    }

    SourceCollector = 'manifests/collectors/Hybrid/ArcMachineRunCommands.psd1'

    ManualConversionReason = 'Run commands on Arc machines were discovered but not read. The script, its parameters and its output are never projected because they can carry secrets; only who-ran-what metadata is. Fields verified against live rows on 2026-11-24.'
}
