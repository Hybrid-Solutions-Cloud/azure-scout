@{
    ResourceTypes = @('entra/organization','entra/domains','entra/domainfederationconfigurations')
    ResourceTypeMatching = 'Grouped'
    AdditionalFilter = $null
    FilterPreamble = ''
    RowLoopVariable = '1'
    Preamble = '$ResUCount = 1; $data = Get-AZSCSafeProperty -InputObject $1 -Path ''properties'''
    AdditionalRowLoops = @()
    TagLoop = $null
    Fields = @(
        @{ Name = 'ID'; Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''id''' }
        @{ Name = 'Evidence Type'; Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''TYPE''' }
        @{ Name = 'Name'; Expression = 'Get-AZSCSafeProperty -InputObject $1 -Path ''name''' }
        @{ Name = 'Authentication Type'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''authenticationType''' }
        @{ Name = 'On-Premises Sync Enabled'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''onPremisesSyncEnabled''' }
        @{ Name = 'Last Sync'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''onPremisesLastSyncDateTime''' }
        @{ Name = 'Issuer URI'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''issuerUri''' }
        @{ Name = 'Passive Sign-In URI'; Expression = 'Get-AZSCSafeProperty -InputObject $data -Path ''passiveSignInUri''' }
        @{ Name = 'Signing Certificate'; Expression = 'if (Get-AZSCSafeProperty -InputObject $data -Path ''signingCertificate'') { ''Present (value retained only in raw evidence)'' } else { $null }' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
    )
    Export = @{
        WorksheetName = 'Hybrid Identity'
        TableNamePrefix = 'HybridIdentity_'
        Columns = @('Evidence Type','Name','Authentication Type','On-Premises Sync Enabled','Last Sync','Issuer URI','Passive Sign-In URI','Signing Certificate','Resource U')
        TagColumns = @()
        TagColumnsBefore = $null
        NumberFormat = '0'
        ConditionalText = @()
    }
}
