@{
    ResourceTypes = @('entra/breakglasscandidates')
    SourceDependencies = @('entra/conditionalaccesspolicies','entra/users','entra/authenticationmethodregistrations','entra/signins','entra/pimassignments')
    ResourceTypeMatching = 'Grouped'
    AdditionalFilter = $null
    FilterPreamble = ''
    RowLoopVariable = '1'
    Preamble = '$ResUCount = 1; $data = $1.properties'
    AdditionalRowLoops = @()
    TagLoop = $null
    Fields = @(
        @{ Name = 'ID'; Expression = '$1.id' }
        @{ Name = 'Masked User'; Expression = '$data.maskedUserPrincipalName' }
        @{ Name = 'Cloud Only'; Expression = '$data.cloudOnly' }
        @{ Name = 'Account Enabled'; Expression = '$data.accountEnabled' }
        @{ Name = 'Last Sign-in'; Expression = '$data.lastSignInDateTime' }
        @{ Name = 'MFA Registered'; Expression = '$data.isMfaRegistered' }
        @{ Name = 'Methods'; Expression = '@($data.methodsRegistered) -join '', ''' }
        @{ Name = 'Roles'; Expression = '@($data.assignedRoles) -join '', ''' }
        @{ Name = 'Enabled Policies Excluding User'; Expression = '$data.excludedFromEnabledPolicyCount' }
        @{ Name = 'Evidence Scope'; Expression = '$data.evidenceScope' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
    )
    Export = @{
        WorksheetName = 'Emergency Access'
        TableNamePrefix = 'EmergencyAccess_'
        Columns = @('Masked User','Cloud Only','Account Enabled','Last Sign-in','MFA Registered','Methods','Roles','Enabled Policies Excluding User','Evidence Scope','Resource U')
        TagColumns = @()
        TagColumnsBefore = $null
        NumberFormat = '0'
        ConditionalText = @()
    }
}
