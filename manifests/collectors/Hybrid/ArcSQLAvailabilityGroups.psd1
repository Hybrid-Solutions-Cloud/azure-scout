#
# Hand-authored collector (AB#9300): Availability groups of Arc-enabled SQL Server instances were discovered but not read. Fields verified against live rows on 2026-11-24.
#
@{
    ResourceTypes = @('microsoft.azurearcdata/sqlserverinstances/availabilitygroups')

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
        @{ Name = 'Server'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''serverName'')' }
        @{ Name = 'Instance'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''instanceName'')' }
        @{ Name = 'Primary Replica'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''info.primaryReplica'')' }
        @{ Name = 'Synchronization Health'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''info.synchronizationHealthDescription'')' }
        @{ Name = 'Primary Recovery Health'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''info.primaryRecoveryHealthDescription'')' }
        @{ Name = 'Cluster Type'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''info.clusterTypeDescription'')' }
        @{ Name = 'Distributed'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''info.isDistributed'')' }
        @{ Name = 'Backup Preference'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''info.automatedBackupPreferenceDescription'')' }
        @{ Name = 'Collected'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''collectionTimestamp'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Arc SQL Availability Groups'
        TableNamePrefix = 'ArcSQLAGs_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Server'
            'Instance'
            'Primary Replica'
            'Synchronization Health'
            'Primary Recovery Health'
            'Cluster Type'
            'Distributed'
            'Backup Preference'
            'Collected'
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

    SourceCollector = 'manifests/collectors/Hybrid/ArcSQLAvailabilityGroups.psd1'

    ManualConversionReason = 'Availability groups of Arc-enabled SQL Server instances were discovered but not read. Fields verified against live rows on 2026-11-24.'
}
