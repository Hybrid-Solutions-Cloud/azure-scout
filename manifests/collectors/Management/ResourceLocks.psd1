#
# AUTHORED AS DATA (AB#6781, Story AB#6779). There is no source collector script to drift from.
#
# Renders the resource locks src/collect/Get-ScoutGovernanceDataset.ps1 already collects, on an
# AZSC/Governance/ResourceLock envelope flattened by
# src/collect/ConvertTo-ScoutGovernanceResource.ps1.
#
# `Protects` is the scope the lock applies to, not the lock's own ARM id -- "what is protected
# from deletion" is a question about the locked resource, and the lock id is only how you get
# there.
#
@{
    ResourceTypes = @(
        'AZSC/Governance/ResourceLock'
    )

    ResourceTypeMatching = 'Grouped'

    AdditionalFilter = $null

    FilterPreamble = ''

    RowLoopVariable = '1'

    RowSource = @{
        Expression = @'
foreach ($envelope in @($Resources | Where-Object { $_.TYPE -eq 'AZSC/Governance/ResourceLock' })) {
        @($envelope.PROPERTIES)
    }
'@
    }

    Preamble = @'
$ResUCount = 1
'@

    AdditionalRowLoops = @()

    TagLoop = $null

    Fields = @(
        @{
            Name = 'Subscription'
            Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''Subscription'''
        }
        @{
            Name = 'Scope Type'
            Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''Scope Type'''
        }
        @{
            Name = 'Protects'
            Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''Protects'''
        }
        @{
            Name = 'Lock Name'
            Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''Lock Name'''
        }
        @{
            Name = 'Lock Level'
            Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''Lock Level'''
        }
        @{
            Name = 'Notes'
            Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''Notes'''
        }
        @{
            Name = 'ID'
            Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''ID'''
        }
        @{
            Name = 'Resource U'
            Expression = '$ResUCount'
        }
    )

    Export = @{
        WorksheetName = 'Resource Locks'
        TableNamePrefix = 'ResourceLocksTable_'
        Columns = @(
            'Subscription'
            'Scope Type'
            'Protects'
            'Lock Name'
            'Lock Level'
            'Notes'
            'Resource U'
        )
        TagColumns = @()
        TagColumnsBefore = $null
        NumberFormat = '0'
        ConditionalText = @()
    }
}
