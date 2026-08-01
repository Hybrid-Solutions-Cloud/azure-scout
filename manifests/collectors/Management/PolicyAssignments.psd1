#
# AUTHORED AS DATA (AB#6782, Story AB#6779). There is no source collector script to drift from.
#
# Renders the policy assignments src/collect/Get-ScoutGovernanceDataset.ps1 already collects, on
# an AZSC/Governance/PolicyAssignment envelope flattened by
# src/collect/ConvertTo-ScoutGovernanceResource.ps1.
#
# Distinct from Management/PolicyDefinitions (what policies EXIST) and
# Management/PolicyComplianceStates (what the estate scored). This one answers which policies are
# actually applied, and where.
#
@{
    ResourceTypes = @(
        'AZSC/Governance/PolicyAssignment'
    )

    ResourceTypeMatching = 'Grouped'

    AdditionalFilter = $null

    FilterPreamble = ''

    RowLoopVariable = '1'

    RowSource = @{
        Expression = @'
foreach ($envelope in @($Resources | Where-Object { $_.TYPE -eq 'AZSC/Governance/PolicyAssignment' })) {
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
            Name = 'Assignment Name'
            Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''Assignment Name'''
        }
        @{
            Name = 'Display Name'
            Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''Display Name'''
        }
        @{
            Name = 'Assigned'
            Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''Assigned'''
        }
        @{
            Name = 'Definition'
            Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''Definition'''
        }
        @{
            Name = 'Enforcement Mode'
            Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''Enforcement Mode'''
        }
        @{
            Name = 'Excluded Scopes'
            Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''Excluded Scopes'''
        }
        @{
            Name = 'Parameters'
            Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''Parameters'''
        }
        @{
            Name = 'Description'
            Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''Description'''
        }
        @{
            Name = 'Definition ID'
            Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''Definition ID'''
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
        WorksheetName = 'Policy Assignments'
        TableNamePrefix = 'PolicyAssignmentsTable_'
        Columns = @(
            'Subscription'
            'Scope Type'
            'Scope'
            'Assignment Name'
            'Display Name'
            'Assigned'
            'Definition'
            'Enforcement Mode'
            'Excluded Scopes'
            'Parameters'
            'Description'
            'Resource U'
        )
        TagColumns = @()
        TagColumnsBefore = $null
        NumberFormat = '0'
        ConditionalText = @()
    }
}
