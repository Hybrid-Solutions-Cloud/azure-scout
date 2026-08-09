#
# HAND-AUTHORED -- AB#7085 (Story AB#7071, Feature AB#7069, Epic AB#7099). Azure Automanage has no
# legacy Modules/Public/InventoryModules/*.ps1 to convert from -- this codebase never collected it
# before. Authored directly against the ordinary ARG-indexed
# `microsoft.automanage/configurationprofiles` resource type -- the reusable best-practice profile
# a subscription/VM assignment (`Microsoft.Automanage/configurationProfileAssignments`) points at.
# Assignments themselves are extension resources scoped under an arbitrary VM/ARC machine rather
# than a standalone resource-group-scoped resource, the same fan-out cost class as diagnostic
# settings (see Get-ScoutArmChildResource.ps1's header) -- deliberately deferred rather than forced
# into this pass; see docs/reference/service-coverage-gap.md's Automanage row.
#
@{
    ResourceTypes = @(
        'microsoft.automanage/configurationprofiles'
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

                $overrideCount = if ($data.overrides) { @($data.overrides).Count } else { 0 }
                $antimalware = if ($data.configuration.Antimalware) { 'Configured' } else { 'Not Configured' }
                $backup = if ($data.configuration.Backup) { 'Configured' } else { 'Not Configured' }
                $updateManagement = if ($data.configuration.WindowsPatchSettings -or $data.configuration.LinuxPatchSettings) { 'Configured' } else { 'Not Configured' }
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
            Name = 'Configuration Profile'
            Expression = '$1.NAME'
        }
        @{
            Name = 'Location'
            Expression = '$1.LOCATION'
        }
        @{
            Name = 'Antimalware'
            Expression = '$antimalware'
        }
        @{
            Name = 'Backup'
            Expression = '$backup'
        }
        @{
            Name = 'Update Management'
            Expression = '$updateManagement'
        }
        @{
            Name = 'Override Count'
            Expression = '$overrideCount'
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
        WorksheetName = 'Automanage Profiles'
        TableNamePrefix = 'AutomanageTable_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Configuration Profile'
            'Location'
            'Antimalware'
            'Backup'
            'Update Management'
            'Override Count'
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
