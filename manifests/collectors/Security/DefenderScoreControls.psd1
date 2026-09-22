@{
    ResourceTypes = @('AZSC/Subscription/SecurityPolicySweep')
    ResourceTypeMatching = 'Grouped'
    AdditionalFilter = $null
    FilterPreamble = ''
    RowLoopVariable = '1'
    RowSource = @{
        Expression = @'
foreach ($sweep in @($Resources | Where-Object { $_.TYPE -eq 'AZSC/Subscription/SecurityPolicySweep' })) {
    foreach ($control in @($sweep.PROPERTIES.DefenderSecureScoreControls)) {
        $control | Add-Member -NotePropertyName SubscriptionId -NotePropertyValue $sweep.subscriptionId -Force -PassThru
    }
}
'@
    }
    Preamble = '$ResUCount = 1; $data = $1'
    AdditionalRowLoops = @()
    TagLoop = $null
    Fields = @(
        @{ Name = 'ID'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''Id''' }
        @{ Name = 'Subscription ID'; Expression = '$data.SubscriptionId' }
        @{ Name = 'Control'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''DisplayName''' }
        @{ Name = 'Current Score'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''Score.Current''' }
        @{ Name = 'Max Score'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''Score.Max''' }
        @{ Name = 'Percentage'; Expression = '& { $v = Get-AZSCSafeProperty -InputObject $data -Path ''Score.Percentage''; if ($null -ne $v) { [math]::Round(100 * [double]$v, 2) } else { $null } }' }
        @{ Name = 'Healthy Resources'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''HealthyResourceCount''' }
        @{ Name = 'Unhealthy Resources'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''UnhealthyResourceCount''' }
        @{ Name = 'Not Applicable'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''NotApplicableResourceCount''' }
        @{ Name = 'Weight'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''Weight''' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
    )
    Export = @{
        WorksheetName = 'Defender Score Controls'
        TableNamePrefix = 'DefenderScoreControls_'
        Columns = @('Subscription ID','Control','Current Score','Max Score','Percentage','Healthy Resources','Unhealthy Resources','Not Applicable','Weight','Resource U')
        TagColumns = @()
        TagColumnsBefore = $null
        NumberFormat = '0'
        ConditionalText = @()
    }
}
