#
# AB#7097. Authored by hand in the same shape scripts/ConvertTo-ScoutCollectorDefinition.ps1
# produces for the other Graph-backed Identity collectors (see AdminUnits.psd1, SecurityPolicies.psd1)
# -- there is no source .ps1 to convert from, this service never had one. Field expressions read
# the normalised envelope Start-ScoutEntraExtraction's Add-NormalizedResource produces for a
# SingleObject catalog entry: $1.id / $1.tenantId / $1.properties, exactly like every other
# entra/* collector in this category.
#
@{
    ResourceTypes = @(
        'entra/verifiedidconfiguration'
    )

    ResourceTypeMatching = 'Grouped'

    AdditionalFilter = $null

    FilterPreamble = ''

    RowLoopVariable = '1'

    Preamble = @'
$ResUCount = 1
            $data = $1.properties

            $excludeTargetCount = @($data.excludeTargets).Count
            $excludeTargetIds = if ($excludeTargetCount -gt 0) { [string](@($data.excludeTargets | ForEach-Object { $_.id }) -join ', ') } else { '' }
'@

    AdditionalRowLoops = @()

    TagLoop = $null

    Fields = @(
        @{
            Name = 'ID'
            Expression = '$1.id'
        }
        @{
            Name = 'Tenant ID'
            Expression = '$1.tenantId'
        }
        @{
            Name = 'State'
            Expression = '$data.state'
        }
        @{
            Name = 'Excluded Group Count'
            Expression = '[string]$excludeTargetCount'
        }
        @{
            Name = 'Excluded Group IDs'
            Expression = '$excludeTargetIds'
        }
        @{
            Name = 'Resource U'
            Expression = '$ResUCount'
        }
    )

    Export = @{
        WorksheetName = 'Verified ID Config'
        TableNamePrefix = 'VerifiedIDConfigTable_'
        Columns = @(
            'State'
            'Excluded Group Count'
            'Excluded Group IDs'
            'Resource U'
        )
        TagColumns = @()
        TagColumnsBefore = $null
        NumberFormat = '0'
        ConditionalText = @(
            'New-ConditionalText enabled -Range A:A -ConditionalType ContainsText -BackgroundColor LightGreen'
        )
    }

    SourceCollector = $null
}
