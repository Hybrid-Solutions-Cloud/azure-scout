@{
    ResourceTypes = @('AZSC/ARMChild/LAWorkspaceTables')
    ResourceTypeMatching = 'Grouped'
    AdditionalFilter = $null
    FilterPreamble = ''
    RowLoopVariable = '1'
    Preamble = '$ResUCount = 1; $data = Get-AZSCSafeProperty -InputObject $1 -Path ''properties'''
    AdditionalRowLoops = @()
    TagLoop = $null
    Fields = @(
        @{ Name = 'ID'; Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''id''' }
        @{ Name = 'Workspace'; Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''PARENTNAME''' }
        @{ Name = 'Table'; Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''name''' }
        @{ Name = 'Plan'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''plan''' }
        @{ Name = 'Retention Days'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''retentionInDays''' }
        @{ Name = 'Total Retention Days'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''totalRetentionInDays''' }
        @{ Name = 'Archive Retention Days'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''archiveRetentionInDays''' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
    )
    Export = @{
        WorksheetName = 'Workspace Table Retention'
        TableNamePrefix = 'WorkspaceRetention_'
        Columns = @('Workspace','Table','Plan','Retention Days','Total Retention Days','Archive Retention Days','Resource U')
        TagColumns = @()
        TagColumnsBefore = $null
        NumberFormat = '0'
        ConditionalText = @()
    }
}
