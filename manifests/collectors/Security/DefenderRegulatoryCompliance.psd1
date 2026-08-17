@{
    ResourceTypes = @('AZSC/Subscription/SecurityPolicySweep')
    ResourceTypeMatching = 'Grouped'
    AdditionalFilter = $null
    FilterPreamble = ''
    RowLoopVariable = '1'
    RowSource = @{
        Expression = @'
foreach ($sweep in @($Resources | Where-Object { $_.TYPE -eq 'AZSC/Subscription/SecurityPolicySweep' })) {
    foreach ($standard in @($sweep.PROPERTIES.DefenderRegulatoryStandards)) {
        $standard | Add-Member -NotePropertyName SubscriptionId -NotePropertyValue $sweep.subscriptionId -Force -PassThru
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
        @{ Name = 'Standard'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''Name''' }
        @{ Name = 'State'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''State''' }
        @{ Name = 'Passed Controls'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''PassedControls''' }
        @{ Name = 'Failed Controls'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''FailedControls''' }
        @{ Name = 'Skipped Controls'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''SkippedControls''' }
        @{ Name = 'Unsupported Controls'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''UnsupportedControls''' }
        @{ Name = 'Pass Percent'; Expression = '& { $passed = [double](Get-AZSCSafeProperty -InputObject $data -Path ''PassedControls''); $failed = [double](Get-AZSCSafeProperty -InputObject $data -Path ''FailedControls''); if (($passed + $failed) -gt 0) { [math]::Round(100 * $passed / ($passed + $failed), 2) } else { $null } }' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
    )
    Export = @{
        WorksheetName = 'Defender Compliance'
        TableNamePrefix = 'DefenderCompliance_'
        Columns = @('Subscription ID','Standard','State','Passed Controls','Failed Controls','Skipped Controls','Unsupported Controls','Pass Percent','Resource U')
        TagColumns = @()
        TagColumnsBefore = $null
        NumberFormat = '0'
        ConditionalText = @()
    }
}
