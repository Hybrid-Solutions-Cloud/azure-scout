#
# HAND-AUTHORED -- AB#7085 (Story AB#7071, Feature AB#7069, Epic AB#7099). Azure Managed
# Applications has no legacy Modules/Public/InventoryModules/*.ps1 to convert from -- this codebase
# never collected it before. Authored directly against the ordinary ARG-indexed
# `microsoft.solutions/applications` resource type (the deployed managed-application INSTANCE, not
# the `applianceDefinitions`/`applicationDefinitions` catalogue entry a publisher authors).
#
@{
    ResourceTypes = @(
        'microsoft.solutions/applications'
    )

    ResourceTypeMatching = 'Grouped'

    AdditionalFilter = $null

    FilterPreamble = ''

    RowLoopVariable = '1'

    Preamble = @'
$ResUCount = 1
                $sub1 = $SUB | Where-Object { $_.Id -eq $1.subscriptionId }
                $data = $1.PROPERTIES
                $Tags = if(![string]::IsNullOrEmpty($1.tags.psobject.properties)){$1.tags.psobject.properties}else{'0'}

                $managedResourceGroup = if ($data.managedResourceGroupId) { (($data.managedResourceGroupId -split '/')[-1]) } else { 'N/A' }
                $definitionId = if ($data.applicationDefinitionId) { $data.applicationDefinitionId } else { 'N/A' }
                $provisioningState = if ($data.provisioningState) { $data.provisioningState } else { 'Unknown' }
                $managedBy = if ($1.managedBy) { $1.managedBy } else { 'N/A' }
                $planName = if ($1.PLAN.name) { $1.PLAN.name } else { 'N/A' }
                $planPublisher = if ($1.PLAN.publisher) { $1.PLAN.publisher } else { 'N/A' }
'@

    AdditionalRowLoops = @()

    TagLoop = @{
        Variable = 'Tag'
        Source = '$Tags'
        Preamble = ''
    }

    Fields = @(
        @{
            Name = 'ID'
            Expression = '$1.id'
        }
        @{
            Name = 'Subscription'
            Expression = '$sub1.Name'
        }
        @{
            Name = 'Resource Group'
            Expression = '$1.RESOURCEGROUP'
        }
        @{
            Name = 'Application Name'
            Expression = '$1.NAME'
        }
        @{
            Name = 'Location'
            Expression = '$1.LOCATION'
        }
        @{
            Name = 'Kind'
            Expression = '$1.KIND'
        }
        @{
            Name = 'Managed Resource Group'
            Expression = '$managedResourceGroup'
        }
        @{
            Name = 'Application Definition ID'
            Expression = '$definitionId'
        }
        @{
            Name = 'Managed By'
            Expression = '$managedBy'
        }
        @{
            Name = 'Plan Name'
            Expression = '$planName'
        }
        @{
            Name = 'Plan Publisher'
            Expression = '$planPublisher'
        }
        @{
            Name = 'Provisioning State'
            Expression = '$provisioningState'
        }
        @{
            Name = 'Resource U'
            Expression = '$ResUCount'
        }
        @{
            Name = 'Tag Name'
            Expression = '[string]$Tag.Name'
        }
        @{
            Name = 'Tag Value'
            Expression = '[string]$Tag.Value'
        }
    )

    Export = @{
        WorksheetName = 'Managed Applications'
        TableNamePrefix = 'ManagedAppTable_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Application Name'
            'Location'
            'Kind'
            'Managed Resource Group'
            'Application Definition ID'
            'Managed By'
            'Plan Name'
            'Plan Publisher'
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
}
