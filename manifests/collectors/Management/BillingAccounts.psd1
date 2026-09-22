@{
    ResourceTypes = @('AZSC/Billing/BillingAccounts')
    ResourceTypeMatching = 'Grouped'; AdditionalFilter = $null; FilterPreamble = ''; RowLoopVariable = '1'
    Preamble = '$raw=Get-AZSCSafeProperty -InputObject $1 -Path ''properties.Raw'';$data=Get-AZSCSafeProperty -InputObject $raw -Path ''properties'''; AdditionalRowLoops = @(); TagLoop = $null
    Fields = @(
        @{ Name = 'ID'; Expression = 'Get-AZSCSafeProperty -InputObject $raw -Path ''id''' }
        @{ Name = 'Name'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''displayName''' }
        @{ Name = 'Agreement Type'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''agreementType''' }
        @{ Name = 'Account Type'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''accountType''' }
        @{ Name = 'Account Subtype'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''accountSubType''' }
        @{ Name = 'Status'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''accountStatus''' }
        @{ Name = 'Has Read Access'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''hasReadAccess''' }
        @{ Name = 'Notification Contact Configured'; Expression = '-not [string]::IsNullOrWhiteSpace([string](Get-AZSCSafeProperty -InputObject $data -Path ''notificationEmailAddress''))' }
    )
    Export = @{ WorksheetName = 'Billing Accounts'; TableNamePrefix = 'BillingAccounts_'; Columns = @('Name','Agreement Type','Account Type','Account Subtype','Status','Has Read Access','Notification Contact Configured'); TagColumns=@(); TagColumnsBefore=$null; NumberFormat='0'; ConditionalText=@() }
    SourceCollector = 'src/collect/Get-ScoutBillingEvidence.ps1'
    ManualConversionReason = 'Hand-authored for AB#7441 against the billing evidence adapter; SourceCollector is provenance, not a legacy Standard-contract collector. Focused collection and renderer tests are the behavioural evidence.'
}
