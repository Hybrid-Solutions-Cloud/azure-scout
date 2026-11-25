#
# Hand-authored collector (AB#9300): Oracle Database@Azure autonomous databases, Exadata infrastructure and VM clusters had no collector. Admin passwords are never projected. Property paths from the Oracle.Database 2026-06-01 reference and SDK models.
#
@{
    ResourceTypes = @('oracle.database/autonomousdatabases', 'oracle.database/cloudexadatainfrastructures', 'oracle.database/cloudvmclusters')

    ResourceTypeMatching = 'Grouped'

    AdditionalFilter = $null

    FilterPreamble = ''

    RowLoopVariable = '1'

    Preamble = @'
$ResUCount = 1
$sub1 = $SUB | Where-Object { $_.id -eq $1.subscriptionId }
$data = $1.PROPERTIES
$Tags = if (![string]::IsNullOrEmpty($1.tags.psobject.properties)) { $1.tags.psobject.properties } else { '0' }
$kind = ([string]$1.type -split '/')[-1]
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
        @{ Name = 'Kind'; Expression = '$kind' }
        @{ Name = 'Version'; Expression = '& { $v = Get-AZSCSafeProperty -InputObject $data -Path ''dbVersion''; if ($null -eq $v) { $v = Get-AZSCSafeProperty -InputObject $data -Path ''giVersion'' }; $v }' }
        @{ Name = 'Workload'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''dbWorkload'')' }
        @{ Name = 'Shape'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''shape'')' }
        @{ Name = 'Compute'; Expression = '& { $v = Get-AZSCSafeProperty -InputObject $data -Path ''computeCount''; if ($null -eq $v) { $v = Get-AZSCSafeProperty -InputObject $data -Path ''cpuCoreCount'' }; $v }' }
        @{ Name = 'Storage (TB)'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''dataStorageSizeInTbs'')' }
        @{ Name = 'License Model'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''licenseModel'')' }
        @{ Name = 'Lifecycle State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''lifecycleState'')' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Oracle Database@Azure'
        TableNamePrefix = 'OracleDb_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Kind'
            'Version'
            'Workload'
            'Shape'
            'Compute'
            'Storage (TB)'
            'License Model'
            'Lifecycle State'
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

    SourceCollector = 'manifests/collectors/Databases/OracleDatabaseAtAzure.psd1'

    ManualConversionReason = 'Oracle Database@Azure autonomous databases, Exadata infrastructure and VM clusters had no collector. Admin passwords are never projected. Property paths from the Oracle.Database 2026-06-01 reference and SDK models.'
}
