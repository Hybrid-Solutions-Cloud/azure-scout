#
# Hand-authored collector (AB#9300): VMM servers connected through Azure Arc-enabled System Center Virtual Machine Manager had no collector. Property paths from the Microsoft.ScVmm 2025-03-13 reference and SDK models.
#
@{
    ResourceTypes = @('microsoft.scvmm/vmmservers')

    ResourceTypeMatching = 'Grouped'

    AdditionalFilter = $null

    FilterPreamble = ''

    RowLoopVariable = '1'

    Preamble = @'
$ResUCount = 1
$sub1 = $SUB | Where-Object { $_.id -eq $1.subscriptionId }
$data = $1.PROPERTIES
$Tags = if (![string]::IsNullOrEmpty($1.tags.psobject.properties)) { $1.tags.psobject.properties } else { '0' }
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
        @{ Name = 'FQDN'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''fqdn'')' }
        @{ Name = 'Port'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''port'')' }
        @{ Name = 'Version'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''version'')' }
        @{ Name = 'Connection Status'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''connectionStatus'')' }
        @{ Name = 'Error'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''errorMessage'')' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Arc SCVMM Servers'
        TableNamePrefix = 'ArcSCVMMServers_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'FQDN'
            'Port'
            'Version'
            'Connection Status'
            'Error'
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

    SourceCollector = 'manifests/collectors/Hybrid/ArcSCVMMServers.psd1'

    ManualConversionReason = 'VMM servers connected through Azure Arc-enabled System Center Virtual Machine Manager had no collector. Property paths from the Microsoft.ScVmm 2025-03-13 reference and SDK models.'
}
