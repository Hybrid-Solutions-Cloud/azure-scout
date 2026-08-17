@{
    ResourceTypes = @('entra/accessreviewdefinitions')
    ResourceTypeMatching = 'Grouped'
    AdditionalFilter = $null
    FilterPreamble = ''
    RowLoopVariable = '1'
    Preamble = @'
$ResUCount = 1
$data = Get-AZSCSafeProperty -InputObject $1 -Path 'properties'
$instances = @(Get-AZSCSafeProperty -InputObject $data -Path 'instances')
$lastInstance = @($instances | Sort-Object endDateTime -Descending | Select-Object -First 1)
'@
    AdditionalRowLoops = @()
    TagLoop = $null
    Fields = @(
        @{ Name = 'ID'; Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''id''' }
        @{ Name = 'Display Name'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''displayName''' }
        @{ Name = 'Status'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''status''' }
        @{ Name = 'Scope'; Expression = '& { $value=Get-AZSCSafeProperty -InputObject $data -Path ''scope''; if ($value) { $value | ConvertTo-Json -Depth 20 -Compress } else { $null } }' }
        @{ Name = 'Recurrence'; Expression = '& { $value=Get-AZSCSafeProperty -InputObject $data -Path ''settings.recurrence''; if ($value) { $value | ConvertTo-Json -Depth 20 -Compress } else { $null } }' }
        @{ Name = 'Last Completed'; Expression = 'if ($lastInstance.Count -gt 0) { Get-AZSCSafeProperty -InputObject $lastInstance[0] -Path ''endDateTime'' } else { $null }' }
        @{ Name = 'Instance Count'; Expression = '$instances.Count' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
    )
    Export = @{
        WorksheetName = 'Access Reviews'
        TableNamePrefix = 'AccessReviews_'
        Columns = @('Display Name','Status','Scope','Recurrence','Last Completed','Instance Count','Resource U')
        TagColumns = @()
        TagColumnsBefore = $null
        NumberFormat = '0'
        ConditionalText = @()
    }
}
