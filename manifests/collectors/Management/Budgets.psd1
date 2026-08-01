#
# AUTHORED AS DATA (AB#6783, Story AB#6779). There is no source collector script to drift from.
#
# Renders the consumption budgets src/collect/Get-ScoutGovernanceDataset.ps1 already collects, on
# an AZSC/Governance/Budget envelope flattened by
# src/collect/ConvertTo-ScoutGovernanceResource.ps1.
#
# Filed under Management rather than a new Cost category deliberately: Cost Management sits under
# "Management and governance" in Microsoft's own service taxonomy, and Scout's category set is the
# published 18 (pinned by tests/CategoryFiltering.Tests.ps1). The audit's B4 line calls this
# 'Cost/Budgets'; the sheet is the same, the folder follows the taxonomy the rest of the tree does.
#
@{
    ResourceTypes = @(
        'AZSC/Governance/Budget'
    )

    ResourceTypeMatching = 'Grouped'

    AdditionalFilter = $null

    FilterPreamble = ''

    RowLoopVariable = '1'

    RowSource = @{
        Expression = @'
foreach ($envelope in @($Resources | Where-Object { $_.TYPE -eq 'AZSC/Governance/Budget' })) {
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
            Name = 'Name'
            Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''Name'''
        }
        @{
            Name = 'Category'
            Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''Category'''
        }
        @{
            Name = 'Amount'
            Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''Amount'''
        }
        @{
            Name = 'Currency'
            Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''Currency'''
        }
        @{
            Name = 'Time Grain'
            Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''Time Grain'''
        }
        @{
            Name = 'Start Date'
            Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''Start Date'''
        }
        @{
            Name = 'End Date'
            Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''End Date'''
        }
        @{
            Name = 'Current Spend'
            Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''Current Spend'''
        }
        @{
            Name = 'Forecast Spend'
            Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''Forecast Spend'''
        }
        @{
            Name = 'Budget Used %'
            Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''Budget Used %'''
        }
        @{
            Name = 'Alerts Configured'
            Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''Alerts Configured'''
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
        WorksheetName = 'Budgets'
        TableNamePrefix = 'BudgetsTable_'
        Columns = @(
            'Subscription'
            'Name'
            'Category'
            'Amount'
            'Currency'
            'Time Grain'
            'Start Date'
            'End Date'
            'Current Spend'
            'Forecast Spend'
            'Budget Used %'
            'Alerts Configured'
            'Resource U'
        )
        TagColumns = @()
        TagColumnsBefore = $null
        NumberFormat = '0'
        ConditionalText = @()
    }
}
