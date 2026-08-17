@{
    ResourceTypes = @('AZSC/Billing/BillingRoleAssignments','AZSC/Billing/BillingRoleDefinitions','AZSC/Billing/SubscriptionCreationPermissions')
    ResourceTypeMatching = 'Grouped'; AdditionalFilter = $null; FilterPreamble = ''; RowLoopVariable = '1'
    Preamble = '$raw=Get-AZSCSafeProperty -InputObject $1 -Path ''properties.Raw'';$data=Get-AZSCSafeProperty -InputObject $raw -Path ''properties'''; AdditionalRowLoops = @(); TagLoop = $null
    Fields = @(
        @{ Name = 'ID'; Expression = 'Get-AZSCSafeProperty -InputObject $raw -Path ''id''' }
        @{ Name = 'Evidence Type'; Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''type''' }
        @{ Name = 'Role Name'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''roleName''' }
        @{ Name = 'Principal Type'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''principalType''' }
        @{ Name = 'Principal ID'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''principalId''' }
        @{ Name = 'Role Definition ID'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''roleDefinitionId''' }
        @{ Name = 'Scope'; Expression = '& { $value=Get-AZSCSafeProperty -InputObject $data -Path ''scope'';if($value){$value}else{Get-AZSCSafeProperty -InputObject $data -Path ''invoiceSectionId''} }' }
    )
    Export = @{ WorksheetName='Billing Roles'; TableNamePrefix='BillingRoles_'; Columns=@('Evidence Type','Role Name','Principal Type','Principal ID','Role Definition ID','Scope'); TagColumns=@(); TagColumnsBefore=$null; NumberFormat='0'; ConditionalText=@() }
    SourceCollector = 'src/collect/Get-ScoutBillingEvidence.ps1'
    ManualConversionReason = 'Hand-authored for AB#7441 against the billing evidence adapter; SourceCollector is provenance, not a legacy Standard-contract collector. Focused collection and renderer tests are the behavioural evidence.'
}
