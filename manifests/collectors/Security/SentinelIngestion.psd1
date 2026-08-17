@{
    ResourceTypes = @('AZSC/ARMChild/SentinelIngestion')
    ResourceTypeMatching = 'Grouped'
    AdditionalFilter = $null
    FilterPreamble = ''
    RowLoopVariable = '1'
    Preamble = '$ResUCount = 1'
    AdditionalRowLoops = @()
    TagLoop = $null
    Fields = @(
        @{ Name = 'ID'; Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''id''' }
        @{ Name = 'Workspace'; Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''PARENTNAME''' }
        @{ Name = 'Table'; Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''TableName''' }
        @{ Name = 'Last Record'; Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''LastRecord''' }
        @{ Name = 'Record Count 30 Days'; Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''Count''' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
    )
    Export = @{
        WorksheetName = 'Sentinel Ingestion'
        TableNamePrefix = 'SentinelIngestion_'
        Columns = @('Workspace','Table','Last Record','Record Count 30 Days','Resource U')
        TagColumns = @()
        TagColumnsBefore = $null
        NumberFormat = '0'
        ConditionalText = @()
    }
}
