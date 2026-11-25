#
# Hand-authored collector (AB#9300): Deployment scripts had no collector. The script content, arguments and environment variables are never projected. Property paths from the Microsoft.Resources deploymentScripts reference.
#
@{
    ResourceTypes = @('microsoft.resources/deploymentscripts')

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
        @{ Name = 'Kind'; Expression = '$1.KIND' }
        @{ Name = 'Runtime Version'; Expression = '& { $v = Get-AZSCSafeProperty -InputObject $data -Path ''azPowerShellVersion''; if ($null -eq $v) { $v = Get-AZSCSafeProperty -InputObject $data -Path ''azCliVersion'' }; $v }' }
        @{ Name = 'Retention'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''retentionInterval'')' }
        @{ Name = 'Cleanup'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''cleanupPreference'')' }
        @{ Name = 'Timeout'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''timeout'')' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Deployment Scripts'
        TableNamePrefix = 'DeploymentScripts_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Kind'
            'Runtime Version'
            'Retention'
            'Cleanup'
            'Timeout'
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

    SourceCollector = 'manifests/collectors/Management/DeploymentScripts.psd1'

    ManualConversionReason = 'Deployment scripts had no collector. The script content, arguments and environment variables are never projected. Property paths from the Microsoft.Resources deploymentScripts reference.'
}
