#
# Hand-authored collector (AB#9300): Deployment stacks, whose deny settings protect the resources they manage, had no collector. Property paths from the Microsoft.Resources deploymentStacks 2025-07-01 reference.
#
@{
    ResourceTypes = @('microsoft.resources/deploymentstacks')

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
        @{ Name = 'Deny Mode'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''denySettings.mode'')' }
        @{ Name = 'Deny Applies to Children'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''denySettings.applyToChildScopes'')' }
        @{ Name = 'Excluded Principals'; Expression = '@(Get-AZSCSafeProperty -InputObject $data -Path ''denySettings.excludedPrincipals'' | Where-Object { $null -ne $_ }).Count' }
        @{ Name = 'On Unmanage (Resources)'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''actionOnUnmanage.resources'')' }
        @{ Name = 'Managed Resources'; Expression = '@(Get-AZSCSafeProperty -InputObject $data -Path ''resources'' | Where-Object { $null -ne $_ }).Count' }
        @{ Name = 'Failed Resources'; Expression = '@(Get-AZSCSafeProperty -InputObject $data -Path ''failedResources'' | Where-Object { $null -ne $_ }).Count' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Deployment Stacks'
        TableNamePrefix = 'DeploymentStacks_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Deny Mode'
            'Deny Applies to Children'
            'Excluded Principals'
            'On Unmanage (Resources)'
            'Managed Resources'
            'Failed Resources'
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

    SourceCollector = 'manifests/collectors/Management/DeploymentStacks.psd1'

    ManualConversionReason = 'Deployment stacks, whose deny settings protect the resources they manage, had no collector. Property paths from the Microsoft.Resources deploymentStacks 2025-07-01 reference.'
}
