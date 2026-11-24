#
# Hand-authored collector (AB#9300): Databases of Arc-enabled SQL Server instances were discovered but not read. Fields verified against live rows on 2026-11-24.
#
@{
    ResourceTypes = @('microsoft.azurearcdata/sqlserverinstances/databases')

    ResourceTypeMatching = 'Grouped'

    AdditionalFilter = $null

    FilterPreamble = ''

    RowLoopVariable = '1'

    Preamble = @'
$ResUCount = 1
$sub1 = $SUB | Where-Object { $_.id -eq $1.subscriptionId }
$data = $1.PROPERTIES
$Tags = if (![string]::IsNullOrEmpty($1.tags.psobject.properties)) { $1.tags.psobject.properties } else { '0' }
$instanceName = ([string]$1.id -split '/')[-3]
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
        @{ Name = 'SQL Instance'; Expression = '$instanceName' }
        @{ Name = 'State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''state'')' }
        @{ Name = 'Recovery Model'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''recoveryMode'')' }
        @{ Name = 'Compatibility Level'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''compatibilityLevel'')' }
        @{ Name = 'Size (MB)'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''sizeMB'')' }
        @{ Name = 'Data Files (MB)'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''dataFileSizeMB'')' }
        @{ Name = 'Log Files (MB)'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''logFileSizeMB'')' }
        @{ Name = 'Space Available (MB)'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''spaceAvailableMB'')' }
        @{ Name = 'Encrypted'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''databaseOptions.isEncrypted'')' }
        @{ Name = 'Read Only'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''isReadOnly'')' }
        @{ Name = 'Trustworthy'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''databaseOptions.isTrustworthyOn'')' }
        @{ Name = 'Auto Shrink'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''databaseOptions.isAutoShrinkOn'')' }
        @{ Name = 'Collation'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''collationName'')' }
        @{ Name = 'Created'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''databaseCreationDate'')' }
        @{ Name = 'Last Upload'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''lastDatabaseUploadTime'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Arc SQL Databases'
        TableNamePrefix = 'ArcSQLDatabases_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'SQL Instance'
            'State'
            'Recovery Model'
            'Compatibility Level'
            'Size (MB)'
            'Data Files (MB)'
            'Log Files (MB)'
            'Space Available (MB)'
            'Encrypted'
            'Read Only'
            'Trustworthy'
            'Auto Shrink'
            'Collation'
            'Created'
            'Last Upload'
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

    SourceCollector = 'manifests/collectors/Hybrid/ArcSQLDatabases.psd1'

    ManualConversionReason = 'Databases of Arc-enabled SQL Server instances were discovered but not read. Fields verified against live rows on 2026-11-24.'
}
