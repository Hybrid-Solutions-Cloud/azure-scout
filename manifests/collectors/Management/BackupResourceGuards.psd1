#
# Hand-authored collector (AB#9300): Resource guards (multi-user authorization for backup) had no collector. Property paths from the Microsoft.DataProtection SDK models.
#
@{
    ResourceTypes = @('microsoft.dataprotection/resourceguards')

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
        @{ Name = 'Protected Operations'; Expression = '((@(Get-AZSCSafeProperty -InputObject $data -Path ''resourceGuardOperations.vaultCriticalOperation'' -Enumerate) | Where-Object { $_ } | ForEach-Object { ([string]$_ -split ''/'')[-1] } | Sort-Object -Unique) -join '', '')' }
        @{ Name = 'Excluded Operations'; Expression = '((@(Get-AZSCSafeProperty -InputObject $data -Path ''vaultCriticalOperationExclusionList'' -Enumerate) | Where-Object { $_ } | ForEach-Object { ([string]$_ -split ''/'')[-1] } | Sort-Object -Unique) -join '', '')' }
        @{ Name = 'Auto Approvals'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''allowAutoApprovals'')' }
        @{ Name = 'Description'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''description'')' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Backup Resource Guards'
        TableNamePrefix = 'ResourceGuards_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Protected Operations'
            'Excluded Operations'
            'Auto Approvals'
            'Description'
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

    SourceCollector = 'manifests/collectors/Management/BackupResourceGuards.psd1'

    ManualConversionReason = 'Resource guards (multi-user authorization for backup) had no collector. Property paths from the Microsoft.DataProtection SDK models.'
}
