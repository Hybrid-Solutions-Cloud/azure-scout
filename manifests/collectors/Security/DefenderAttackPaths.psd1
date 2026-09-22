@{
    ResourceTypes = @('microsoft.security/attackpaths')
    ResourceTypeMatching = 'Grouped'
    AdditionalFilter = $null
    FilterPreamble = ''
    RowLoopVariable = '1'
    Preamble = '$ResUCount = 1; $data = Get-AZSCSafeProperty -InputObject $1 -Path ''properties'''
    AdditionalRowLoops = @()
    TagLoop = $null
    Fields = @(
        @{ Name = 'ID'; Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''id''' }
        @{ Name = 'Subscription ID'; Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''subscriptionId''' }
        @{ Name = 'Display Name'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''displayName''' }
        @{ Name = 'Attack Path Type'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''attackPathType''' }
        @{ Name = 'Description'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''description''' }
        @{ Name = 'Potential Impact'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''potentialImpact''' }
        @{ Name = 'Risk Categories'; Expression = '@(Get-AZSCSafeProperty -InputObject $data -Path ''riskCategories'') -join '', ''' }
        @{ Name = 'Entry Point'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''entryPointEntityInternalID''' }
        @{ Name = 'Target'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''targetEntityInternalID''' }
        @{ Name = 'Graph Components'; Expression = '@(Get-AZSCSafeProperty -InputObject $data -Path ''graphComponent'').Count' }
        @{ Name = 'Remediation'; Expression = '@(Get-AZSCSafeProperty -InputObject $data -Path ''manualRemediationSteps'') -join '' | ''' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
    )
    Export = @{
        WorksheetName = 'Defender Attack Paths'
        TableNamePrefix = 'DefenderAttackPaths_'
        Columns = @('Subscription ID','Display Name','Attack Path Type','Description','Potential Impact','Risk Categories','Entry Point','Target','Graph Components','Remediation','Resource U')
        TagColumns = @()
        TagColumnsBefore = $null
        NumberFormat = '0'
        ConditionalText = @()
    }
}
