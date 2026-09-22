@{
    ResourceTypes = @('AZSC/ARMChild/SentinelDataConnectors')
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
        @{ Name = 'Connector'; Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''name''' }
        @{ Name = 'Kind'; Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''kind''' }
        @{ Name = 'Tenant ID'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''tenantId''' }
        @{ Name = 'Subscription ID'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''subscriptionId''' }
        @{ Name = 'Data Types'; Expression = '& { $value=Get-AZSCSafeProperty -InputObject $data -Path ''dataTypes'';if($value){$value|ConvertTo-Json -Depth 20 -Compress}else{$null} }' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
    )
    Export = @{
        WorksheetName = 'Sentinel Connectors'
        TableNamePrefix = 'SentinelConnectors_'
        Columns = @('Workspace','Connector','Kind','Tenant ID','Subscription ID','Data Types','Resource U')
        TagColumns = @()
        TagColumnsBefore = $null
        NumberFormat = '0'
        ConditionalText = @()
    }
}
