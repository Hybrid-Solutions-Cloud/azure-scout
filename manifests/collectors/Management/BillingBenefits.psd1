@{
    ResourceTypes = @('AZSC/Billing/ReservationOrders','AZSC/Billing/SavingsPlanOrders')
    ResourceTypeMatching = 'Grouped'; AdditionalFilter = $null; FilterPreamble = ''; RowLoopVariable = '1'
    Preamble = '$raw=Get-AZSCSafeProperty -InputObject $1 -Path ''properties.Raw'';$data=Get-AZSCSafeProperty -InputObject $raw -Path ''properties'''; AdditionalRowLoops = @(); TagLoop = $null
    Fields = @(
        @{ Name = 'ID'; Expression = 'Get-AZSCSafeProperty -InputObject $raw -Path ''id''' }
        @{ Name = 'Benefit Type'; Expression = 'Get-AZSCSafeProperty -InputObject $raw -Path ''type''' }
        @{ Name = 'Name'; Expression = '& { $value=Get-AZSCSafeProperty -InputObject $data -Path ''displayName'';if($value){$value}else{Get-AZSCSafeProperty -InputObject $raw -Path ''name''} }' }
        @{ Name = 'State'; Expression = '& { $value=Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'';if($value){$value}else{Get-AZSCSafeProperty -InputObject $data -Path ''status''} }' }
        @{ Name = 'Term'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''term''' }
        @{ Name = 'Expiry'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''expiryDateTime''' }
        @{ Name = 'Billing Scope'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''billingScopeId''' }
    )
    Export = @{ WorksheetName='Billing Benefits'; TableNamePrefix='BillingBenefits_'; Columns=@('Benefit Type','Name','State','Term','Expiry','Billing Scope'); TagColumns=@(); TagColumnsBefore=$null; NumberFormat='0'; ConditionalText=@() }
    SourceCollector = 'src/collect/Get-ScoutBillingEvidence.ps1'
    ManualConversionReason = 'Hand-authored for AB#7441 against the billing evidence adapter; SourceCollector is provenance, not a legacy Standard-contract collector. Focused collection and renderer tests are the behavioural evidence.'
}
