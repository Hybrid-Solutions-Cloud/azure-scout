@{
    ResourceTypes = @('AZSC/Governance/PimEligibility')
    ResourceTypeMatching = 'Grouped'
    AdditionalFilter = $null
    FilterPreamble = ''
    RowLoopVariable = '1'
    RowSource = @{
        Expression = 'foreach ($envelope in @($Resources | Where-Object { $_.TYPE -eq ''AZSC/Governance/PimEligibility'' })) { $envelope.PROPERTIES }'
    }
    Preamble = '$ResUCount = 1; $data = $1'
    AdditionalRowLoops = @()
    TagLoop = $null
    Fields = @(
        @{ Name = 'ID'; Expression = '$data.ID' }
        @{ Name = 'Subscription'; Expression = '$data.Subscription' }
        @{ Name = 'Scope'; Expression = '$data.Scope' }
        @{ Name = 'Principal ID'; Expression = '$data.''Principal ID''' }
        @{ Name = 'Principal Type'; Expression = '$data.''Principal Type''' }
        @{ Name = 'Role Definition ID'; Expression = '$data.''Role Definition ID''' }
        @{ Name = 'Member Type'; Expression = '$data.''Member Type''' }
        @{ Name = 'Start DateTime'; Expression = '$data.''Start DateTime''' }
        @{ Name = 'End DateTime'; Expression = '$data.''End DateTime''' }
        @{ Name = 'Status'; Expression = '$data.Status' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
    )
    Export = @{
        WorksheetName = 'Azure PIM Eligibility'
        TableNamePrefix = 'AzurePIMEligibility_'
        Columns = @('Subscription','Scope','Principal ID','Principal Type','Role Definition ID','Member Type','Start DateTime','End DateTime','Status','Resource U')
        TagColumns = @()
        TagColumnsBefore = $null
        NumberFormat = '0'
        ConditionalText = @()
    }
}
