#
# HAND-AUTHORED -- AB#7085 (Story AB#7071, Feature AB#7069, Epic AB#7099). Azure Resource Mover has
# no legacy Modules/Public/InventoryModules/*.ps1 to convert from -- this codebase never collected
# it before. Authored directly against the ordinary ARG-indexed `microsoft.migrate/movecollections`
# resource type -- the move collection container that groups resources being moved between regions
# (or from region to availability zone). Individual move resources inside a collection are a
# nested REST enumeration (like Site Recovery's replication protected items), not an ARG-indexed
# type -- out of scope for this pass, see docs/reference/service-coverage-gap.md.
#
@{
    ResourceTypes = @(
        'microsoft.migrate/movecollections'
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

                $sourceRegion = if ($data.sourceRegion) { $data.sourceRegion } else { 'N/A' }
                $targetRegion = if ($data.targetRegion) { $data.targetRegion } else { 'N/A' }
                $moveType = if ($data.moveType) { $data.moveType } else { 'RegionToRegion' }
                $identityType = if ($1.IDENTITY.type) { $1.IDENTITY.type } else { 'None' }
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
            Name = 'Move Collection'
            Expression = '$1.NAME'
        }
        @{
            Name = 'Location'
            Expression = '$1.LOCATION'
        }
        @{
            Name = 'Source Region'
            Expression = '$sourceRegion'
        }
        @{
            Name = 'Target Region'
            Expression = '$targetRegion'
        }
        @{
            Name = 'Move Type'
            Expression = '$moveType'
        }
        @{
            Name = 'Identity Type'
            Expression = '$identityType'
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
        WorksheetName = 'Resource Mover'
        TableNamePrefix = 'ResourceMoverTable_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Move Collection'
            'Location'
            'Source Region'
            'Target Region'
            'Move Type'
            'Identity Type'
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
