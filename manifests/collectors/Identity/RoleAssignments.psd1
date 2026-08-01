#
# AUTHORED AS DATA (AB#6780, Story AB#6779). There is no source collector script to drift from.
#
# Renders the role assignments src/collect/Get-ScoutGovernanceDataset.ps1 already collects. The
# rows arrive pre-flattened on an AZSC/Governance/RoleAssignment envelope (see
# src/collect/ConvertTo-ScoutGovernanceResource.ps1) because resolving a role GUID to its name,
# a scope to its subscription, and a scope string to its kind are lookups no field expression can
# express -- and because a nested read that is absent on one sparse payload throws under the
# declarative interpreter and costs the whole worksheet (AB#6839/AB#6844).
#
# This is the "who has Owner" sheet.
#
@{
    ResourceTypes = @(
        'AZSC/Governance/RoleAssignment'
    )

    ResourceTypeMatching = 'Grouped'

    AdditionalFilter = $null

    FilterPreamble = ''

    RowLoopVariable = '1'

    RowSource = @{
        Expression = @'
foreach ($envelope in @($Resources | Where-Object { $_.TYPE -eq 'AZSC/Governance/RoleAssignment' })) {
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
            Name = 'Scope'
            Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''Scope'''
        }
        @{
            Name = 'Role Name'
            Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''Role Name'''
        }
        @{
            Name = 'Role Type'
            Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''Role Type'''
        }
        @{
            Name = 'Principal ID'
            Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''Principal ID'''
        }
        @{
            Name = 'Principal Type'
            Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''Principal Type'''
        }
        @{
            Name = 'Condition'
            Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''Condition'''
        }
        @{
            Name = 'Description'
            Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''Description'''
        }
        @{
            Name = 'Created On'
            Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''Created On'''
        }
        @{
            Name = 'Assignment Name'
            Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''Assignment Name'''
        }
        @{
            Name = 'Role Definition ID'
            Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''Role Definition ID'''
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
        WorksheetName = 'Role Assignments'
        TableNamePrefix = 'RoleAssignmentsTable_'
        Columns = @(
            'Subscription'
            'Scope Type'
            'Scope'
            'Role Name'
            'Role Type'
            'Principal ID'
            'Principal Type'
            'Condition'
            'Description'
            'Created On'
            'Assignment Name'
            'Resource U'
        )
        TagColumns = @()
        TagColumnsBefore = $null
        NumberFormat = '0'
        ConditionalText = @()
    }
}
