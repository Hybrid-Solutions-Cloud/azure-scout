#
# Hand-authored collector (AB#9300): Backup vaults (Azure Backup for disks, blobs, AKS and databases) were read only as parents of backup instances; their security settings had no collector. Property paths from the Microsoft.DataProtection reference and SDK models.
#
@{
    ResourceTypes = @('microsoft.dataprotection/backupvaults')

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
        @{ Name = 'Storage Redundancy'; Expression = '((@(Get-AZSCSafeProperty -InputObject $data -Path ''storageSettings.type'' -Enumerate) | Where-Object { $_ } | ForEach-Object { [string]$_ } | Sort-Object -Unique) -join '', '')' }
        @{ Name = 'Immutability'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''securitySettings.immutabilitySettings.state'')' }
        @{ Name = 'Soft Delete'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''securitySettings.softDeleteSettings.state'')' }
        @{ Name = 'Soft Delete Retention (days)'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''securitySettings.softDeleteSettings.retentionDurationInDays'')' }
        @{ Name = 'Cross-Region Restore'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''featureSettings.crossRegionRestoreSettings.state'')' }
        @{ Name = 'Cross-Subscription Restore'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''featureSettings.crossSubscriptionRestoreSettings.state'')' }
        @{ Name = 'Job Failure Alerts'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''monitoringSettings.azureMonitorAlertSettings.alertsForAllJobFailures'')' }
        @{ Name = 'Protected by Resource Guard'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''isVaultProtectedByResourceGuard'')' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Backup Vaults'
        TableNamePrefix = 'BackupVaults_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Storage Redundancy'
            'Immutability'
            'Soft Delete'
            'Soft Delete Retention (days)'
            'Cross-Region Restore'
            'Cross-Subscription Restore'
            'Job Failure Alerts'
            'Protected by Resource Guard'
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

    SourceCollector = 'manifests/collectors/Management/BackupVaults.psd1'

    ManualConversionReason = 'Backup vaults (Azure Backup for disks, blobs, AKS and databases) were read only as parents of backup instances; their security settings had no collector. Property paths from the Microsoft.DataProtection reference and SDK models.'
}
