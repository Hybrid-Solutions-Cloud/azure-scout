@{
    ResourceTypes = @('AZSC/Billing/BillingProfiles','AZSC/Billing/InvoiceSections','AZSC/Billing/Departments','AZSC/Billing/EnrollmentAccounts')
    ResourceTypeMatching = 'Grouped'; AdditionalFilter = $null; FilterPreamble = ''; RowLoopVariable = '1'
    Preamble = '$raw=Get-AZSCSafeProperty -InputObject $1 -Path ''properties.Raw'';$data=Get-AZSCSafeProperty -InputObject $raw -Path ''properties'''; AdditionalRowLoops = @(); TagLoop = $null
    Fields = @(
        @{ Name = 'ID'; Expression = 'Get-AZSCSafeProperty -InputObject $raw -Path ''id''' }
        @{ Name = 'Hierarchy Type'; Expression = 'Get-AZSCSafeProperty -InputObject $raw -Path ''type''' }
        @{ Name = 'Name'; Expression = '& { $value=Get-AZSCSafeProperty -InputObject $data -Path ''displayName'';if($value){$value}else{Get-AZSCSafeProperty -InputObject $raw -Path ''name''} }' }
        @{ Name = 'Status'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''status''' }
        @{ Name = 'Parent Department'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''departmentDisplayName''' }
        @{ Name = 'Cost Center'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''costCenter''' }
        @{ Name = 'Invoice Email Enabled'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''invoiceEmailOptIn''' }
    )
    Export = @{ WorksheetName='Billing Hierarchy'; TableNamePrefix='BillingHierarchy_'; Columns=@('Hierarchy Type','Name','Status','Parent Department','Cost Center','Invoice Email Enabled'); TagColumns=@(); TagColumnsBefore=$null; NumberFormat='0'; ConditionalText=@() }
    SourceCollector = 'src/collect/Get-ScoutBillingEvidence.ps1'
    ManualConversionReason = 'Hand-authored for AB#7441 against the billing evidence adapter; SourceCollector is provenance, not a legacy Standard-contract collector. Focused collection and renderer tests are the behavioural evidence.'
}
