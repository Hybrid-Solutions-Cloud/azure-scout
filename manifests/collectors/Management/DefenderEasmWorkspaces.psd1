#
# HAND-AUTHORED -- AB#7085 (Story AB#7071, Feature AB#7069, Epic AB#7099). Defender External Attack
# Surface Management has no legacy Modules/Public/InventoryModules/*.ps1 to convert from -- this
# codebase never collected it before. Authored directly against the ordinary ARG-indexed
# `microsoft.easm/workspaces` resource type -- the EASM workspace resource itself (the discovered
# internet-facing asset inventory it produces lives behind the workspace's own data-plane endpoint,
# not in ARM/ARG, and is out of scope here the same way Get-ScoutCostInventory.ps1's data lives
# behind a separate API rather than a manifests/collectors definition).
#
@{
    ResourceTypes = @(
        'microsoft.easm/workspaces'
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

                $dataPlaneEndpoint = if ($data.dataPlaneEndpoint) { $data.dataPlaneEndpoint } else { 'N/A' }
                $provisioningState = if ($data.provisioningState) { $data.provisioningState } else { 'Unknown' }
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
            Name = 'Workspace Name'
            Expression = '$1.NAME'
        }
        @{
            Name = 'Location'
            Expression = '$1.LOCATION'
        }
        @{
            Name = 'Data Plane Endpoint'
            Expression = '$dataPlaneEndpoint'
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
        WorksheetName = 'Defender EASM'
        TableNamePrefix = 'EasmTable_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Workspace Name'
            'Location'
            'Data Plane Endpoint'
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
